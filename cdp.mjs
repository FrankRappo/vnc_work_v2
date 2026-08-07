/**
 * cdp.mjs — CDP-движок для vnc_work. Подключается к уже запущенному chromium
 * (--remote-debugging-port=PORT) и выполняет действия на странице ЧЕРЕЗ DevTools
 * Protocol (реальные мышь/клавиатура, UTF-8/кириллица — без проблем).
 *
 * Запуск (через vnc.sh, но можно и напрямую):
 *   NODE_PATH=/home/hgff/node_modules node cdp.mjs <PORT> <cmd> [args...]
 *
 * Команды:
 *   url                      — URL активной вкладки
 *   go <URL>                 — навигация
 *   text [maxChars]          — innerText страницы (для «прочитать глазами модели»)
 *   eval '<js>'              — выполнить JS в странице, напечатать результат (JSON)
 *   find '<regex>'           — список кликабельных/инпутов, чей текст матчит regex (поиск селектора)
 *   click '<text|regex>'     — клик по элементу с видимым текстом (button/a/role/label/submit)
 *   clicksel '<css>'         — клик по CSS-селектору
 *   type '<css>' '<value>'   — фокус + очистить + впечатать значение (UTF-8 ок). Для кириллицы тоже.
 *   press '<Key>'            — клавиша (Enter, Escape, Tab, ArrowDown…)
 *   wait '<css>' [ms]        — дождаться селектора
 *   bbox '<css|text>'        — НАТИВНЫЕ экранные координаты центра элемента "x y"
 *                              (для xdotool-кликов по canvas/картам; DOM лучше кликать click/clicksel)
 *   mclick <x> <y>           — клик по VIEWPORT-координатам через CDP-мышь (надёжно, мимо offset хрома)
 *   tap '<text|regex>' [name]— 🟢 НАДЁЖНЫЙ клик по видимому тексту: scrollIntoView → (если ниже фолда → zoom)
 *                              → CDP-мышь в центр → ПРОВЕРКА что клик долетел (elementFromPoint) →
 *                              авто-отчёт POST/PUT-ответов 4с + ЗАПОМИНАЕТ элемент в память координат.
 *   zoom <factor>            — body.style.zoom (0.8 поднимает фикс-футер в зону видимости)
 *   ── ПАМЯТЬ КООРДИНАТ (coords_memory.json, per-URL) — чтобы легче писать скрипты ──
 *   remember '<text>' [name] — запомнить элемент по тексту БЕЗ клика (локатор+коорд)
 *   recall <name|text>       — достать из памяти для текущего URL, пере-найти вживую → печатает "x y"
 *   mem                      — показать все запомненные элементы текущего URL
 *   forget <name|--page>     — удалить запись/всю страницу
 *   grant <origin> <perm..>  — выдать разрешения (geolocation, notifications…) чтобы не было попапов
 *
 * 🔴 КООРДИНАТНЫЕ ПРАВИЛА (чтобы НЕ МАЗАТЬ) — уроки реальных production-like VNC/CDP сессий:
 *   1. Кликать ВСЕГДА по VIEWPORT-координатам через CDP-мышь (mclick/tap), НЕ xdotool по нативным:
 *      нативный scrot=1920×1080, а viewport CDP=1903×1040; native ≈ viewport + (8, 120) [хром сверху].
 *   2. Координаты брать из DOM (getBoundingClientRect = viewport), НЕ на глаз со скрина (jpg в др. масштабе).
 *   3. Чужой puppeteer.connect() без defaultViewport:null оставляет вьюпорт 800×600 → верстка в «узкую
 *      колонку», ВСЕ координаты едут. Лечится setViewport (делается на connect ниже).
 *   4. Кнопки фикс-футера на viewport y>~960 — НИЖЕ физического экрана 1080 → xdotool не достанет;
 *      mclick долетит, но надёжнее zoom 0.8 (поднять в вид) и кликнуть. `map` помечает такие ⬇below-fold.
 *   5. Проверять заполнение поля по input.value, НЕ по innerText/textContent (значений инпутов там нет).
 *   6. После важного клика — смотреть POST/PUT ответ (tap это делает), а не только UI: ошибка может быть
 *      400 в сети при «успешном» на вид экране.
 *
 * Возврат: печатает результат в stdout. Код выхода 0 ок, 2 — элемент не найден.
 */
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const require = createRequire("/home/hgff/index.js");
const puppeteer = require("puppeteer");

// ─── ПАМЯТЬ КООРДИНАТ ─────────────────────────────────────────────────────────
// Запоминает успешные клики/элементы per-URL, чтобы потом легче писать скрипты.
// Локатор = текст+роль+тег (стабильно у SPA с хеш-классами), координаты — подсказка.
const HERE = path.dirname(fileURLToPath(import.meta.url));
const MEM = path.join(HERE, "coords_memory.json");
const loadMem = () => { try { return JSON.parse(fs.readFileSync(MEM, "utf8")); } catch { return { version: 1, pages: {} }; } };
const saveMem = (m) => { try { fs.writeFileSync(MEM, JSON.stringify(m, null, 1)); } catch {} };
const normUrl = (u) => { try { const x = new URL(u); return (x.host + x.pathname).toLowerCase().replace(/\/+$/, "") || x.host; } catch { return u; } };
const slug = (t) => (t || "").toLowerCase().replace(/[^a-z0-9а-яё]+/gi, "-").replace(/^-+|-+$/g, "").slice(0, 40) || "el";
function record(url, name, desc) {
  const m = loadMem(), key = normUrl(url);
  m.pages[key] = m.pages[key] || { elements: {} };
  const nm = name || slug(desc.text) || slug(desc.ariaLabel);
  const prev = m.pages[key].elements[nm] || {};
  m.pages[key].elements[nm] = { ...desc, hits: (prev.hits || 0) + 1, lastTs: new Date().toISOString() };
  saveMem(m);
  return { key, nm };
}
// описать элемент для памяти (выполняется через page.evaluate, передаём как строку функции)
const DESCRIBE = `(el)=>{const r=el.getBoundingClientRect();return{
  text:(el.innerText||el.value||el.getAttribute('aria-label')||'').trim().replace(/\\s+/g,' ').slice(0,60),
  tag:el.tagName.toLowerCase(), role:el.getAttribute('role')||null,
  ariaLabel:el.getAttribute('aria-label')||null, id:el.id||null,
  x:Math.round(r.left+r.width/2), y:Math.round(r.top+r.height/2), w:Math.round(r.width), h:Math.round(r.height)};}`;

const [PORT, CMD, ...ARGS] = process.argv.slice(2);
if (!PORT || !CMD) { console.error("usage: node cdp.mjs <port> <cmd> [args]"); process.exit(64); }

const CLICKABLE = 'button,a,[role="button"],[role="menuitem"],[role="tab"],input[type=submit],input[type=button],label,[onclick]';

async function activePage(browser) {
  const pages = await browser.pages();
  // последняя «настоящая» вкладка (не devtools/extension)
  const real = pages.filter(p => /^https?:|^about:blank/.test(p.url()));
  return (real.length ? real : pages)[ (real.length ? real : pages).length - 1 ];
}

function findInPageFn(re) {
  // выполняется В СТРАНИЦЕ. Возвращает ЛУЧШИЙ элемент или null.
  // Ранжирование (фикс неоднозначности: 'ORVELIX' не должен цеплять ссылку 'orvelix.ru'):
  //   точное совпадение текста > по границе слова > startsWith > подстрока;
  //   +бонус button/role=tab|button, −штраф <a> на ДРУГОЙ origin (уводит со страницы),
  //   −штраф за «лишний» текст; берём только видимые.
  const rx = new RegExp(re, "i");
  const sels = 'button,a,[role="button"],[role="menuitem"],[role="tab"],input[type=submit],input[type=button],label,[onclick]';
  const txt = (e) => ((e.innerText || e.value || e.getAttribute("aria-label") || "")).trim();
  const vis = (e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && e.offsetParent !== null; };
  const cands = [...document.querySelectorAll(sels)].filter((e) => rx.test(txt(e)) && vis(e));
  if (!cands.length) return null;
  if (cands.length === 1) return cands[0];
  const needle = re.replace(/[.*+?^${}()|[\]\\]/g, "").trim().toLowerCase();
  let wb = null; try { wb = new RegExp("\\b" + needle + "\\b", "i"); } catch {}
  const score = (e) => {
    const t = txt(e).toLowerCase(); let s = 0;
    if (t === needle) s += 100;
    else if (wb && wb.test(t)) s += 50;
    else if (t.startsWith(needle)) s += 20;
    if (e.tagName === "BUTTON" || /^(button|tab|menuitem)$/.test(e.getAttribute("role") || "")) s += 10;
    if (e.tagName === "A") { const h = e.getAttribute("href") || "";
      try { if (h && new URL(h, location.href).origin !== location.origin) s -= 30; } catch {} }
    s -= Math.max(0, t.length - needle.length) * 0.1;
    return s;
  };
  return cands.slice().sort((a, b) => score(b) - score(a))[0];
}

function rankInPageFn(re) {
  // как findInPageFn, но возвращает ВСЕХ видимых кандидатов со скорингом (для guard'а).
  const rx = new RegExp(re, "i");
  const sels = 'button,a,[role="button"],[role="menuitem"],[role="tab"],input[type=submit],input[type=button],label,[onclick]';
  const txt = (e) => ((e.innerText || e.value || e.getAttribute("aria-label") || "")).trim();
  const vis = (e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && e.offsetParent !== null; };
  const cands = [...document.querySelectorAll(sels)].filter((e) => rx.test(txt(e)) && vis(e));
  const needle = re.replace(/[.*+?^${}()|[\]\\]/g, "").trim().toLowerCase();
  let wb = null; try { wb = new RegExp("\\b" + needle + "\\b", "i"); } catch {}
  const desc = (e) => {
    const t = txt(e), tl = t.toLowerCase(); let s = 0;
    if (tl === needle) s += 100; else if (wb && wb.test(tl)) s += 50; else if (tl.startsWith(needle)) s += 20;
    const role = e.getAttribute("role") || "";
    if (e.tagName === "BUTTON" || /^(button|tab|menuitem)$/.test(role)) s += 10;
    let crossOrigin = false;
    if (e.tagName === "A") { const h = e.getAttribute("href") || "";
      try { if (h && new URL(h, location.href).origin !== location.origin) { s -= 30; crossOrigin = true; } } catch {} }
    s -= Math.max(0, t.length - needle.length) * 0.1;
    const aid = e.getAttribute("automation-id");
    const sel = e.id ? "#" + e.id : (aid ? '[automation-id="' + aid + '"]' : "");
    return { text: t.slice(0, 45), tag: e.tagName.toLowerCase(), role, href: (e.getAttribute("href") || ""), crossOrigin, sel, score: +s.toFixed(1) };
  };
  return cands.map(desc).sort((a, b) => b.score - a.score);
}

// guard неоднозначности: кликать молча можно только если выбор однозначен и безопасен.
function decideTarget(cands) {
  if (!cands.length) return { notFound: true };
  const top = cands[0];
  const exactUnique = top.score >= 100 && (cands.length < 2 || cands[1].score < 100);
  const risky = (!exactUnique && cands.length >= 2) || top.crossOrigin;
  if (risky && process.env.CDP_FORCE !== "1") {
    console.log(`AMBIGUOUS: ${cands.length} вариант(ов) — НЕ кликаю (CDP_FORCE=1 чтобы взять верхний):`);
    cands.slice(0, 8).forEach((c, i) => console.log(
      `  [${i}] ${c.tag}${c.role ? "(" + c.role + ")" : ""} "${c.text}"` +
      `${c.crossOrigin ? " ⚠cross-origin→" + c.href : ""}${c.sel ? "  sel=" + c.sel : ""}  score=${c.score}`));
    console.log("→ уточни: clicksel '<css>' (sel выше) или более точный текст");
    return { ambiguous: true };
  }
  return { act: true };
}

(async () => {
  const { webSocketDebuggerUrl } = await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json();
  const browser = await puppeteer.connect({ browserWSEndpoint: webSocketDebuggerUrl, defaultViewport: null });
  const page = await activePage(browser);
  // 🔴 КРИТИЧНО: чужой puppeteer.connect() без defaultViewport:null оставляет вьюпорт 800×600 →
  // верстка «в узкую колонку», координаты едут. clearDeviceMetricsOverride НЕ помогает —
  // принудительно задаём полный размер окна (идемпотентно, persists на target'е).
  try { await page.setViewport({ width: 1903, height: 1040 }); } catch {}
  let code = 0;
  try {
    switch (CMD) {
      case "url": {
        const pages = await browser.pages();
        console.log(pages.filter(p=>/^https?:/.test(p.url())).map(p=>p.url()).join("\n"));
        break;
      }
      case "go": {
        await page.goto(ARGS[0], { waitUntil: "domcontentloaded", timeout: 60000 }).catch(e => console.log("nav:", e.message));
        console.log("OK", page.url());
        break;
      }
      case "text": {
        const max = parseInt(ARGS[0] || "4000", 10);
        const t = await page.evaluate(() => document.body.innerText.replace(/\n{2,}/g, "\n"));
        console.log(t.slice(0, max));
        break;
      }
      case "eval": {
        const r = await page.evaluate((js) => {
          // eslint-disable-next-line no-eval
          const out = eval(js);
          return typeof out === "object" ? JSON.stringify(out) : String(out);
        }, ARGS[0]);
        console.log(r);
        break;
      }
      case "find": {
        const re = ARGS[0] || ".";
        const list = await page.evaluate((re) => {
          const rx = new RegExp(re, "i");
          const sels = 'button,a,[role="button"],[role="menuitem"],[role="tab"],input,select,textarea,label';
          return [...document.querySelectorAll(sels)].map(e => {
            const txt = (e.innerText || e.value || e.placeholder || e.getAttribute("aria-label") || "").trim().slice(0, 40);
            const id = e.id ? "#" + e.id : "";
            const cls = (typeof e.className === "string" && e.className) ? "." + e.className.trim().split(/\s+/).slice(0,2).join(".") : "";
            return { tag: e.tagName.toLowerCase(), txt, sel: id || (e.tagName.toLowerCase() + cls), href: e.getAttribute && e.getAttribute("href") || "" };
          }).filter(o => rx.test(o.txt + " " + o.sel + " " + o.href)).slice(0, 40);
        }, re);
        list.forEach(o => console.log(`${o.tag.padEnd(8)} | ${o.txt.padEnd(40)} | ${o.sel} ${o.href}`));
        if (!list.length) { console.log("(ничего не найдено по /" + re + "/)"); }
        break;
      }
      case "click": {
        const cands = await page.evaluate(rankInPageFn, ARGS[0]);
        const d = decideTarget(cands);
        if (d.notFound) { console.log("NOT FOUND:", ARGS[0]); code = 2; break; }
        if (d.ambiguous) { code = 3; break; }
        const handle = await page.evaluateHandle(findInPageFn, ARGS[0]);
        const el = handle.asElement();
        if (!el) { console.log("NOT FOUND:", ARGS[0]); code = 2; break; }
        const label = await page.evaluate(e => (e.innerText || e.value || "").trim().slice(0, 50), el);
        await el.click().catch(async () => { await page.evaluate(e => e.click(), el); });
        console.log("clicked:", label || "(empty)");
        break;
      }
      case "clicksel": {
        await page.waitForSelector(ARGS[0], { timeout: 8000 });
        await page.click(ARGS[0]);
        console.log("clicked sel:", ARGS[0]);
        break;
      }
      case "upload": {   // загрузка файла в <input type=file> (в т.ч. скрытый): upload <filepath> [css]
        const file = ARGS[0];
        const sel = ARGS[1] || "input[type=file]";
        if (!file) { console.log("usage: upload <filepath> [css]"); code = 2; break; }
        let input = await page.$(sel);
        if (!input) input = await page.waitForSelector(sel, { timeout: 6000 }).catch(() => null);
        if (!input) { console.log("NO file input:", sel); code = 2; break; }
        // лог сетевых ответов аплоада (многие формы грузят файл async по change)
        const ulog = [];
        page.on("response", r => { try { if (/upload/i.test(r.url())) ulog.push(r.status() + " " + r.url().slice(0, 70)); } catch {} });
        await input.uploadFile(file);
        // держим соединение, пока async-загрузка отработает (иначе disconnect рвёт XHR)
        await new Promise(r => setTimeout(r, 4000));
        console.log("uploaded:", file, "->", sel);
        if (ulog.length) console.log("upload-net:", ulog.join(" | "));
        break;
      }
      case "type": {
        const sel = ARGS[0], val = ARGS[1] ?? "";
        await page.waitForSelector(sel, { timeout: 8000 });
        await page.click(sel);
        await page.evaluate(s => { const el = document.querySelector(s); if (el) { el.focus(); if ("value" in el) el.value = ""; } }, sel);
        await page.type(sel, val, { delay: 25 });   // UTF-8/кириллица ок
        console.log("typed into", sel, "(", val.length, "chars )");
        break;
      }
      case "press": {
        await page.keyboard.press(ARGS[0]);
        console.log("pressed", ARGS[0]);
        break;
      }
      case "mclick": {   // точный клик по VIEWPORT-координатам через CDP-мышь (идёт в рендерер, мимо OS-offset)
        const x = parseInt(ARGS[0], 10), y = parseInt(ARGS[1], 10);
        await page.mouse.click(x, y);
        console.log("mclick", x, y);
        break;
      }
      case "keytype": {  // ввод в СФОКУСИРОВАННОЕ поле через CDP-клавиатуру (UTF-8; для react-aria/сегментных полей)
        await page.keyboard.type(ARGS[0] ?? "", { delay: 30 });
        console.log("keytyped", (ARGS[0] || "").length, "chars");
        break;
      }
      case "zoom": {     // body zoom (0.8 поднимает фикс-футер в зону видимости экрана 1080)
        const f = ARGS[0] || "1";
        await page.evaluate((f) => { document.body.style.zoom = f; }, f);
        console.log("zoom", f);
        break;
      }
      case "tap": {      // 🟢 надёжный клик по видимому тексту + проверка попадания + отчёт сети
        const re = ARGS[0] || ".";
        // сетевой слушатель ДО клика — ловим POST/PUT ответы
        const net = [];
        page.on("response", async (resp) => {
          try { const rq = resp.request(); if (rq.method() === "GET") return;
            let b = ""; try { b = (await resp.text()).slice(0, 200); } catch {}
            if (/yandex\.ru\/(watch|clck)|mc\.yandex/.test(resp.url())) return; // отсечь аналитику
            net.push(`${resp.status()} ${rq.method()} ${resp.url().slice(0, 80)}  ${b.replace(/\s+/g, " ")}`);
          } catch {}
        });
        // guard неоднозначности (как у click) — не угадывать молча
        const tcands = await page.evaluate(rankInPageFn, re);
        const td = decideTarget(tcands);
        if (td.notFound) { console.log("NOT FOUND:", re); code = 2; break; }
        if (td.ambiguous) { code = 3; break; }
        // лучший элемент (ранжированный топ), проскроллить в центр, при необходимости — zoom 0.8
        const tHandle = await page.evaluateHandle(findInPageFn, re);
        const tEl = tHandle.asElement();
        if (!tEl) { console.log("NOT FOUND:", re); code = 2; break; }
        const loc = await page.evaluate((el, DESCRIBE) => {
          el.scrollIntoView({ block: "center", inline: "center" });
          if (el.getBoundingClientRect().bottom > 960) document.body.style.zoom = "0.8"; // поднять из-под фолда
          const d = eval(DESCRIBE)(el);
          d.zoomed = document.body.style.zoom && document.body.style.zoom !== "1" ? document.body.style.zoom : null;
          return d;
        }, tEl, DESCRIBE);
        if (!loc) { console.log("NOT FOUND:", re); code = 2; break; }
        // вооружить проверку попадания
        await page.evaluate((x, y) => { window.__tapHit = false;
          const el = document.elementFromPoint(x, y);
          if (el) { el.addEventListener("click", () => { window.__tapHit = true; }, { once: true, capture: true }); }
        }, loc.x, loc.y);
        await page.mouse.click(loc.x, loc.y);
        await new Promise(r => setTimeout(r, 600));
        const hit = await page.evaluate(() => window.__tapHit === true);
        await new Promise(r => setTimeout(r, 3500)); // дождаться сетевых ответов
        // ЗАПОМНИТЬ успешный клик (имя = ARGS[1] или из текста)
        let memInfo = "";
        if (hit) { const { key, nm } = record(page.url(), ARGS[1], loc); memInfo = `  → memory[${key}].${nm}`; }
        console.log(`tap "${loc.text}" @ ${loc.x},${loc.y}${loc.zoomed ? " (zoom" + loc.zoomed + ")" : ""}  landed=${hit}${memInfo}`);
        if (net.length) { console.log("— сеть после клика:"); net.forEach(n => console.log("  " + n)); }
        else console.log("— сеть: (без POST/PUT)");
        break;
      }
      case "remember": {  // запомнить элемент по тексту БЕЗ клика. remember '<text>' [name]
        const loc = await page.evaluate((re, DESCRIBE) => {
          const rx = new RegExp(re, "i");
          const sels = 'button,a,[role="button"],[role="menuitem"],[role="tab"],input,select,textarea,label,[onclick]';
          const el = [...document.querySelectorAll(sels)].find(e => rx.test(((e.innerText || e.value || e.placeholder || e.getAttribute("aria-label") || "")).trim()));
          return el ? eval(DESCRIBE)(el) : null;
        }, ARGS[0], DESCRIBE);
        if (!loc) { console.log("NOT FOUND:", ARGS[0]); code = 2; break; }
        const { key, nm } = record(page.url(), ARGS[1], loc);
        console.log(`remembered memory[${key}].${nm} = "${loc.text}" @ ${loc.x},${loc.y} (${loc.tag})`);
        break;
      }
      case "recall": {    // достать из памяти для ТЕКУЩЕГО url; пере-найти вживую (свежие коорд). recall <name|text>
        const m = loadMem(), key = normUrl(page.url());
        const els = (m.pages[key] && m.pages[key].elements) || {};
        const q = ARGS[0] || "";
        let rec = els[q] || els[slug(q)];
        if (!rec) { const hit = Object.entries(els).find(([n, e]) => new RegExp(q, "i").test(n + " " + (e.text || ""))); if (hit) rec = hit[1]; }
        if (!rec) { console.log(`в памяти нет "${q}" для ${key}. Известно: ${Object.keys(els).join(", ") || "(пусто)"}`); code = 2; break; }
        // пере-найти вживую по сохранённому тексту → свежие координаты
        const live = await page.evaluate((txt, DESCRIBE) => {
          const sels = 'button,a,[role="button"],[role="menuitem"],[role="tab"],input,select,textarea,label,[onclick]';
          const el = [...document.querySelectorAll(sels)].find(e => ((e.innerText || e.value || e.getAttribute("aria-label") || "").trim()) === txt);
          return el ? eval(DESCRIBE)(el) : null;
        }, rec.text, DESCRIBE);
        if (live) console.log(`${live.x} ${live.y}\t(live "${live.text}") [stored ${rec.x},${rec.y}]`);
        else console.log(`${rec.x} ${rec.y}\t(stored "${rec.text}" — вживую не найден, координаты могут устареть)`);
        break;
      }
      case "mem": {       // показать всё, что запомнено для ТЕКУЩЕГО url
        const m = loadMem(), key = normUrl(page.url());
        const els = (m.pages[key] && m.pages[key].elements) || {};
        const keys = Object.keys(els);
        if (!keys.length) { console.log(`память пуста для ${key}`); break; }
        console.log(`memory[${key}] — ${keys.length} элем.:`);
        keys.forEach(n => { const e = els[n]; console.log(`  ${n.padEnd(22)} ${String(e.x).padStart(4)},${String(e.y).padStart(4)} ${e.tag.padEnd(7)} "${e.text}" (hits ${e.hits})`); });
        break;
      }
      case "forget": {    // удалить запись. forget <name>  |  forget --page (всю страницу)
        const m = loadMem(), key = normUrl(page.url());
        if (ARGS[0] === "--page") { delete m.pages[key]; saveMem(m); console.log("forgot page", key); break; }
        if (m.pages[key] && m.pages[key].elements[ARGS[0]]) { delete m.pages[key].elements[ARGS[0]]; saveMem(m); console.log("forgot", ARGS[0]); }
        else console.log("нет такой записи:", ARGS[0]);
        break;
      }
      case "wait": {
        await page.waitForSelector(ARGS[0], { timeout: parseInt(ARGS[1] || "15000", 10) });
        console.log("present:", ARGS[0]);
        break;
      }
      case "bbox": {
        const r = await page.evaluate((arg) => {
          let el = document.querySelector(arg);
          if (!el) {
            const rx = new RegExp(arg, "i");
            const sels = 'button,a,[role="button"],input,label,div,span';
            el = [...document.querySelectorAll(sels)].find(e => rx.test(((e.innerText || e.value || "")).trim()));
          }
          if (!el) return null;
          const b = el.getBoundingClientRect();
          return { x: b.left + b.width / 2, y: b.top + b.height / 2,
                   sx: window.screenX, sy: window.screenY,
                   oh: window.outerHeight, ih: window.innerHeight,
                   ow: window.outerWidth, iw: window.innerWidth, dpr: window.devicePixelRatio };
        }, ARGS[0]);
        if (!r) { console.log("NOT FOUND:", ARGS[0]); code = 2; break; }
        // viewport top within window = outerHeight - innerHeight (toolbar+infobar). left ≈ (ow-iw)/2.
        const nx = Math.round(r.sx + (r.ow - r.iw) / 2 + r.x * r.dpr);
        const ny = Math.round(r.sy + (r.oh - r.ih) + r.y * r.dpr);
        console.log(`${nx} ${ny}`);
        break;
      }
      case "grant": {
        const ctx = browser.defaultBrowserContext();
        await ctx.overridePermissions(ARGS[0], ARGS.slice(1));
        console.log("granted", ARGS.slice(1).join(","), "for", ARGS[0]);
        break;
      }
      case "map": {
        // КАРТА кликабельных: точные НАТИВНЫЕ координаты центра (x y) + label + контекст-текст.
        // Для иконок без подписи (как «+») — берём по контексту строки, потом xclick x y.
        const re = ARGS[0] || ".";
        const list = await page.evaluate((re) => {
          const rx = new RegExp(re, "i");
          const sels = 'button,a,[role="button"],[role="menuitem"],[role="tab"],input[type=submit],input[type=button],[onclick],svg';
          const seen = new Set();
          return [...document.querySelectorAll(sels)].map((e) => {
            const b = e.getBoundingClientRect();           // СОБСТВЕННЫЙ rect (центр самой иконки/кнопки)
            if (b.width === 0 || b.height === 0 || b.width > 600) return null; // отсекаем огромные обёртки-строки
            const x = Math.round(b.left + b.width / 2);     // VIEWPORT-координаты (для mclick через CDP-мышь)
            const y = Math.round(b.top + b.height / 2);
            const key = x + ":" + y; if (seen.has(key)) return null; seen.add(key);
            const label = (e.innerText || e.value || e.getAttribute("aria-label") || "").trim().replace(/\s+/g, " ").slice(0, 24);
            let ctx = "", n = e;            // контекст-текст — поднимаясь к строке (для иконок без подписи)
            for (let k = 0; k < 6 && n; k++) { const t = (n.textContent || "").trim(); if (t && t.length > 1 && t.length <= 90) { ctx = t.replace(/\s+/g, " ").slice(0, 50); break; } n = n.parentElement; }
            return { x, y, tag: e.tagName.toLowerCase(), label, ctx };
          }).filter(Boolean).filter(o => rx.test(o.label + " " + o.ctx)).slice(0, 50);
        }, re);
        list.forEach(o => console.log(`${o.x}\t${o.y}\t${o.tag.padEnd(6)} ${(o.label || "·").padEnd(24)} | ${o.ctx}${o.y > 960 ? "  ⬇below-fold(zoom/tap)" : ""}`));
        if (!list.length) console.log("(пусто по /" + re + "/)");
        break;
      }
      default:
        console.error("unknown cmd:", CMD); code = 64;
    }
  } catch (e) {
    console.log("ERR:", e.message); code = 1;
  } finally {
    browser.disconnect();
    process.exit(code);
  }
})();
