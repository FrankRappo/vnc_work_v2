/**
 * diadoc_submit.mjs — заполнить форму "Add settlement account" для ООО ОРВЕЛИКС
 * и отправить запрос в ЭДО Diadoc (Контур), С ПЕРЕХВАТОМ СЕТИ (видеть, ушёл ли POST).
 * Координатные клики через CDP-мышь (page.mouse.click) — по viewport-координатам из DOM.
 *
 *   NODE_PATH=/home/hgff/node_modules node diadoc_submit.mjs
 */
import { createRequire } from "node:module";
const require = createRequire("/home/hgff/index.js");
const puppeteer = require("puppeteer");

const INN = "5610260464", RS = "40702810210002133541", BIK = "044525974";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const { webSocketDebuggerUrl } = await (await fetch("http://127.0.0.1:9334/json/version")).json();
  const browser = await puppeteer.connect({ browserWSEndpoint: webSocketDebuggerUrl, defaultViewport: null });
  const pages = await browser.pages();
  const page = pages.filter((p) => /dostavka\.yandex/.test(p.url())).pop() || pages.pop();
  await page.setViewport({ width: 1903, height: 1040 });

  // ── перехват сети: все НЕ-GET ответы (POST/PUT) ──
  const net = [];
  page.on("response", async (resp) => {
    try {
      const req = resp.request();
      if (req.method() === "GET") return;
      let body = "";
      try { body = (await resp.text()).slice(0, 300); } catch {}
      net.push(`${resp.status()} ${req.method()} ${resp.url().slice(0, 90)}  ${body.replace(/\s+/g, " ")}`);
    } catch {}
  });

  const center = async (finder) => {
    const r = await page.evaluate(finder);
    return r;
  };
  const clickXY = async (x, y) => { await page.mouse.click(x, y); };

  console.log("→ navigate add-balance");
  await page.goto("https://dostavka.yandex.ru/account/profile/add-balance", { waitUntil: "domcontentloaded" });
  await sleep(3500);

  // STEP 1: ИНН → выбрать ООО из саджеста
  console.log("→ step1: ИНН");
  await clickXY(1072, 174);
  await page.keyboard.type(INN, { delay: 30 });
  await sleep(3000);
  // координаты пункта саджеста (по тексту 'Промыслов' + ОРВЕЛИКС)
  const sugg = await page.evaluate(() => {
    const c = [...document.querySelectorAll("*")].filter((e) => {
      const t = e.textContent || ""; const r = e.getBoundingClientRect();
      return /Промыслов/.test(t) && /ОРВЕЛИКС/.test(t) && r.height > 20 && r.height < 120;
    });
    c.sort((a, b) => a.getBoundingClientRect().height - b.getBoundingClientRect().height);
    if (!c.length) return null;
    const r = c[0].getBoundingClientRect();
    return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
  });
  if (!sugg) { console.log("✗ саджест ООО не найден"); console.log(net.join("\n")); process.exit(2); }
  await clickXY(sugg.x, sugg.y);
  await sleep(1500);
  const v1 = await page.evaluate(() => document.querySelector("input")?.value || "");
  console.log("  company field:", v1);

  // Next → step2
  const nextXY = async () => page.evaluate(() => {
    const b = [...document.querySelectorAll("button")].find((e) => /^Next/.test((e.innerText || "").trim()));
    if (!b) return null; const r = b.getBoundingClientRect();
    return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
  });
  let nx = await nextXY(); if (nx) await clickXY(nx.x, nx.y); await sleep(2500);
  console.log("→ step2 done (address auto)");
  nx = await nextXY(); if (nx) await clickXY(nx.x, nx.y); await sleep(2500);

  // STEP 3: банк
  console.log("→ step3: банк");
  const fields = await page.evaluate(() => [...document.querySelectorAll("input")].map((i) => {
    const r = i.getBoundingClientRect(); return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2), val: i.value };
  }));
  // [0]=email,[1]=р/с,[2]=БИК
  await clickXY(fields[1].x, fields[1].y); await page.keyboard.type(RS, { delay: 25 });
  await clickXY(fields[2].x, fields[2].y); await page.keyboard.type(BIK, { delay: 25 });
  await sleep(1500);
  nx = await nextXY(); if (nx) await clickXY(nx.x, nx.y); await sleep(2500);

  // STEP 4: оферта + Use Diadoc
  console.log("→ step4: оферта + Use Diadoc");
  const cb = await page.evaluate(() => {
    const c = document.querySelector('input[type=checkbox],[role=checkbox]'); if (!c) return null;
    const r = c.getBoundingClientRect(); return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
  });
  if (cb) { await clickXY(cb.x, cb.y); await sleep(800); }
  const checked = await page.evaluate(() => { const c = document.querySelector('input[type=checkbox],[role=checkbox]'); return c?.checked ?? c?.getAttribute("aria-checked"); });
  console.log("  offer checked:", checked);

  // поднять футер в зону видимости + точные координаты Use Diadoc
  await page.evaluate(() => { document.body.style.zoom = "0.8"; });
  await sleep(800);
  const dia = await page.evaluate(() => {
    const b = [...document.querySelectorAll("button")].find((e) => /Use Diadoc/i.test(e.textContent || ""));
    if (!b) return null; const r = b.getBoundingClientRect();
    return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
  });
  console.log("  Use Diadoc @", dia);
  net.length = 0; // очистить — слушаем только то, что после клика
  if (dia) await clickXY(dia.x, dia.y);
  await sleep(5000);

  console.log("\n=== СЕТЕВЫЕ ОТВЕТЫ ПОСЛЕ 'Use Diadoc' (POST/PUT) ===");
  console.log(net.length ? net.join("\n") : "(нет POST/PUT — запрос не ушёл!)");
  await page.evaluate(() => { document.body.style.zoom = "1"; }).catch(() => {});
  process.exit(0);
})().catch((e) => { console.error("ERR:", e.message); process.exit(1); });
