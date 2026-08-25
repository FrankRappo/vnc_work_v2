#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""modal1c.py — модальные окна 1С: опознать и нажать кнопку ВОСПРОИЗВОДИМО.

🔴 ЗАЧЕМ ЭТОТ МОДУЛЬ СУЩЕСТВУЕТ (две задачи подряд встали ровно здесь).
T232 §4.1 и T246 §8 не смогли нажать «Да» в вопросе 1С «Предварительно необходимо рассчитать
скидки (наценки). Выполнить расчет?». Перепробовано было четыре способа: клик по координатам из
OCR, клик по якорю от соседнего слова, Enter после фокуса на тексте, Left+Enter. Человек рядом
жмёт эту кнопку мышью за секунду — значит дыра была в драйвере, а не в 1С.

🔴 ПОЧЕМУ НЕ ПОЛУЧАЛОСЬ (измерено на живой форме РМК копии 12.08.2026).
Подпись кнопки в веб-клиенте 1С — это ТЕКСТОВЫЙ УЗЕЛ, лежащий РЯДОМ с элементом-соседом
(подсказка горячей клавиши). Поэтому:
  * поиск «по видимому тексту» среди ЛИСТЬЕВ DOM (`children.length === 0`) кнопку НЕ находит:
    у ближайшего элемента-контейнера `children.length === 1`, и обычный обход его пропускает.
    Так `find «Штрихкод»` возвращал пустой список при том, что слово на экране есть;
  * у самого текстового узла `getBoundingClientRect()` = 0×0 — кликать надо предка `.pressBox`
    (это уже было записано в память как гоча T224, но искать-то по тексту всё равно нечем).
Дальше в ход шли OCR и «клик по якорю» — то есть угадывание координат, которое и промахивалось.

🔴 ЧТО ОКАЗАЛОСЬ ПРАВДОЙ. Модальное окно веб-клиента 1С опознаётся ДЕТЕРМИНИРОВАННО, без
картинки и без OCR:
  * `#modalSurface.surfaceBlack` (z-index 9000) — затемняющая подложка. Есть подложка = экран
    модально заблокирован;
  * `div[id^=ps][id$=win]` (`ps0win`, `ps1win`, …, z-index 9004+) — само окно; вложенные
    модалки нумеруются по порядку, верхняя = с наибольшим z-index;
  * каждое окно 1С раскладывает свои элементы с ПРЕФИКСОМ `form<N>_`, а имена — из метаданных
    формы (`form3_OK`, `form3_Cancel`, `form2_ОплатитьНаличными`). Это стабильный адрес, он не
    зависит ни от разрешения экрана, ни от темы.

Отсюда приём: НАЙТИ верхнее модальное окно → перечислить в нём кнопки (`a.press` с ненулевым
rect) → взять ту, чья подпись совпала → кликнуть её центр ДОВЕРЕННЫМ событием мыши → УБЕДИТЬСЯ,
что окно исчезло. Последнее — не «диф картинки», а проверка по DOM: модалка либо ушла, либо нет.

🔴 ВЕБ-КЛИЕНТ И ТОНКИЙ КЛИЕНТ — РАЗНЫЕ СЛУЧАИ, И ЭТО ГЛАВНОЕ РАЗЛИЧЕНИЕ.
  * ВЕБ-КЛИЕНТ (этот модуль): окно 1С — это DOM в браузере. Есть CDP → есть точные координаты,
    подписи и проверка результата. Картинка не нужна вовсе, токенов на зрение ноль.
  * ТОНКИЙ КЛИЕНТ (1cv8c.exe на удалённой машине, канал RustDesk/AnyDesk): DOM не существует,
    внутрь окна заглянуть нечем. Там остаётся ТОЛЬКО картинка: эталон кнопки из `templates/` +
    template-match + клик в НАТИВНЫХ пикселях + контрольный кадр. Команда для этого случая —
    `rc.sh modal-click --tmpl <эталон>`; она не требует CDP.
  Путать их нельзя: приём, отлаженный на веб-клиенте через DOM, на тонком клиенте не применим,
  а эталон, снятый с веб-клиента, не совпадёт с отрисовкой тонкого (другой движок, другие
  шрифты). Эталоны тонкого клиента режутся с кадров ТОГО ЖЕ клиента.

Координаты. `bounding rect` даёт координаты в CSS-пикселях страницы. Экранный пиксель =
rect + (screenX, screenY + (outerHeight - innerHeight)) при devicePixelRatio = 1; смещение
считается тут же и отдаётся наверх как `screen_offset`, чтобы клик xdotool шёл в НАТИВНЫХ
пикселях (грабля FIELD_NOTES «gui-coords-native-pixels»).

Команды:
    modal1c.py scan  [--json]                  что за модальное окно сейчас
    modal1c.py click <подпись> [--via cdp|x]   нажать кнопку по подписи (с проверкой)
    modal1c.py fill  <текст>                   ввести текст в поле верхнего модального окна
    modal1c.py keys  <Enter|Escape|…>          клавиша в верхнее модальное окно
"""
import argparse
import socket
from urllib.error import URLError
import importlib.util
import json
import os
import re
import subprocess
import sys
import time

CDP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'cdp')
_spec = importlib.util.spec_from_file_location('cdp_linux', os.path.join(CDP_DIR, 'cdp_linux.py'))
cdp_linux = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cdp_linux)


# ── JS: разведка модального окна ────────────────────────────────────────────────────────────
# 🔴 Кнопки собираются по классу `press` (a.press / a.pressButton / a.pressCommand), а НЕ по
# «элемент без детей с нужным текстом»: см. шапку — подпись лежит текстовым узлом рядом с
# элементом-соседом, и листовой обход её не видит.
JS_SCAN = r"""
(function(){
  function vis(e){
    if(!e) return false;
    var b = e.getBoundingClientRect();
    if(b.width < 1 || b.height < 1) return false;
    var cs = getComputedStyle(e);
    return cs.display !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0';
  }
  function rect(e){
    var b = e.getBoundingClientRect();
    return {x: Math.round(b.left + b.width/2), y: Math.round(b.top + b.height/2),
            left: Math.round(b.left), top: Math.round(b.top),
            w: Math.round(b.width), h: Math.round(b.height)};
  }
  // 🔴 ТОЧКА, В КОТОРУЮ КЛИК ДЕЙСТВИТЕЛЬНО ПОПАДЁТ ПО КНОПКЕ.
  // Замерено 12.08.2026 на мастере «Считать карту лояльности»: у кнопки «Готово» прямоугольник
  // [956,590,71x27], центр (992,604) — и `elementFromPoint(992,604)` возвращает НЕ кнопку, а
  // `div.messagesHeader`: панель «Сообщения» лежит ПОВЕРХ командной панели окна. Клик по центру
  // (и CDP-событием, и настоящим указателем) уходит в панель сообщений, кнопка не нажимается,
  // и внешне это неотличимо от «клик не доходит вообще» — ровно тот тупик, в котором T232
  // перебрал четыре способа нажатия. Поэтому: проверяем попадание hit-тестом и, если центр
  // перекрыт, ищем свободную точку внутри самого прямоугольника кнопки.
  function hitPoint(e){
    var b = e.getBoundingClientRect();
    var fx = [0.5, 0.25, 0.75, 0.12, 0.88];
    var fy = [0.5, 0.28, 0.72, 0.15, 0.85];
    var first = null, blocker = null;
    for (var j = 0; j < fy.length; j++){
      for (var i = 0; i < fx.length; i++){
        var px = b.left + b.width * fx[i], py = b.top + b.height * fy[j];
        if (px < 0 || py < 0) continue;
        var el = document.elementFromPoint(px, py);
        if (!first){ first = el; }
        if (el && (el === e || e.contains(el) || el.contains(e))){
          return {x: Math.round(px), y: Math.round(py),
                  obstructed: (i !== 0 || j !== 0),
                  blocker: (i === 0 && j === 0) ? '' :
                     ((first ? (first.tagName + '.' + String(first.className || '').slice(0,28)) : '?'))};
        }
        if (!blocker && el) blocker = el.tagName + '.' + String(el.className || '').slice(0,28);
      }
    }
    return {x: Math.round(b.left + b.width/2), y: Math.round(b.top + b.height/2),
            obstructed: true, blocker: blocker || 'неизвестно', unreachable: true};
  }
  // подпись кнопки: собственный текст, схлопнутые пробелы, без хвоста горячей клавиши
  function caption(e){
    var t = (e.textContent || '').replace(/\s+/g, ' ').trim();
    t = t.replace(/\s*\((F\d+|Ctrl[^)]*|Alt[^)]*|Shift[^)]*)\)\s*$/i, '');
    t = t.replace(/\s*(Ctrl|Alt|Shift)\+\S+$/i, '');
    return t.trim();
  }
  // 🔴 Горячая клавиша кнопки — НЕ мусор в подписи, а ЗАПАСНОЙ ВХОД. Когда кнопка перекрыта
  // панелью «Сообщения» (см. hitPoint), нажать её мышью нельзя вообще ничем, и человек за
  // экраном делает ровно это: жмёт Ctrl+Enter. Подпись 1С сама несёт подсказку («ГотовоCtrl+Enter»).
  function hotkey(e, cap, scope){
    var re = /((?:Ctrl|Alt|Shift)(?:\+(?:Ctrl|Alt|Shift))*\+[A-Za-zА-Яа-я0-9]+|F\d{1,2})\s*$/;
    var t = (e.textContent || '').replace(/\s+/g, ' ').trim();
    var m = re.exec(t);
    if (m) return m[1];
    // 🔴 У видимой кнопки в подписи горячей клавиши обычно НЕТ — она есть у её двойника в
    // меню «Еще» (`div.submenuBlock`, текст вида «ГотовоCtrl+Enter»). Ищем двойника по подписи.
    var subs = scope.querySelectorAll('.submenuBlock, [id*="popup_"]');
    for (var i = 0; i < subs.length; i++){
      var st = (subs[i].textContent || '').replace(/\s+/g, ' ').trim();
      if (st.indexOf(cap) !== 0) continue;
      var m2 = re.exec(st);
      if (m2) return m2[1];
    }
    return '';
  }
  var surface = document.querySelector('#modalSurface');
  var blocked = vis(surface);
  // 🔴 Окна платформы называются НЕ ОДИНАКОВО, и на этом легко потерять окно целиком:
  //   * простой вопрос/поле ввода   -> `ps0win`, `ps1win`, …            (z ≈ 9004, поверх подложки)
  //   * форма, открытая внутри вкладки -> `VW_page2ps0win`, …           (z ≈ 1004)
  // Селектор `div[id^=ps][id$=win]` (первая версия) второй вид НЕ находил: окно на экране есть,
  // разведка отвечает «модального окна нет». Ловим по ХВОСТУ id + классу `cloud`.
  var wins = [];
  var cand = document.querySelectorAll('div[id$="win"]');
  for (var i = 0; i < cand.length; i++){
    if (!/(^|\s)cloud(\s|$)/.test(cand[i].className || '')) continue;
    if (!vis(cand[i])) continue;
    var z = parseInt(getComputedStyle(cand[i]).zIndex) || 0;
    wins.push({el: cand[i], z: z});
  }
  wins.sort(function(a,b){ return a.z - b.z; });
  var out = {modal: blocked, windows: wins.length, screen_offset: [
      window.screenX, window.screenY + (window.outerHeight - window.innerHeight)],
      dpr: window.devicePixelRatio, view: [window.innerWidth, window.innerHeight]};
  if (!wins.length){ out.title = ''; out.text = ''; out.buttons = []; out.inputs = []; return JSON.stringify(out); }
  var top = wins[wins.length-1].el;
  out.window_id = top.id;
  out.window_rect = rect(top);
  out.z = wins[wins.length-1].z;
  // префикс формы внутри окна (form3_…) — стабильный адрес элементов
  var any = top.querySelector('[id*="_"]');
  var pref = '';
  if (any){ var m = /^(form\d+)_/.exec(any.id); if (m) pref = m[1]; }
  if (!pref){
    var all = top.querySelectorAll('[id^="form"]');
    for (var k = 0; k < all.length; k++){ var mm = /^(form\d+)_/.exec(all[k].id); if (mm){ pref = mm[1]; break; } }
  }
  out.form = pref;
  // заголовок окна платформы
  var ttl = top.querySelector('[id$="_title"], .toplineBoxTitle, .windowTitle');
  out.title = ttl ? (ttl.textContent||'').replace(/\s+/g,' ').trim().slice(0,120) : '';
  out.text = (top.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 400);
  var btns = [], seen = {};
  var press = top.querySelectorAll('a.press, .pressButton, .pressCommand');
  for (var j = 0; j < press.length; j++){
    var e = press[j];
    if (!vis(e)) continue;
    var c = caption(e);
    if (!c) continue;
    if (seen[c]) continue;
    seen[c] = 1;
    var r = rect(e);
    r.caption = c;
    r.id = e.id || '';
    r.def = /pressDefault/.test(e.className || '');
    var hp = hitPoint(e);
    r.hx = hp.x; r.hy = hp.y;                    // куда бить на самом деле
    r.obstructed = !!hp.obstructed;
    r.blocker = hp.blocker || '';
    r.unreachable = !!hp.unreachable;
    r.hotkey = hotkey(e, c, top);
    btns.push(r);
  }
  out.buttons = btns;
  // 🔴 Куда кликнуть, чтобы окно 1С взяло КЛАВИАТУРНЫЙ ФОКУС, ничего при этом не нажав.
  // Без такого клика клавиши уходят в никуда (то же полевое открытие 1 из FIELD_NOTES, только
  // для окна веб-клиента): проверено — Escape в меню РМК не срабатывал, пока в окно не кликнули.
  var wr = top.getBoundingClientRect(), fp = null;
  for (var dy = 4; dy <= 24 && !fp; dy += 4){
    for (var fxx = 0.5; fxx > 0.04; fxx -= 0.08){
      var px = wr.left + wr.width * fxx, py = wr.top + dy;
      var el = document.elementFromPoint(px, py);
      if (!el || !top.contains(el)) continue;
      if (el.closest && (el.closest('a.press') || el.closest('input') || el.closest('label.field'))) continue;
      fp = {x: Math.round(px), y: Math.round(py)}; break;
    }
  }
  out.focus_point = fp;
  var ins = [], inp = top.querySelectorAll('input.editInput, input[type=text], textarea');
  for (var q = 0; q < inp.length; q++){
    if (!vis(inp[q])) continue;
    var ri = rect(inp[q]); ri.id = inp[q].id || ''; ri.value = String(inp[q].value || '').slice(0,60);
    ins.push(ri);
  }
  out.inputs = ins;
  return JSON.stringify(out);
})()
"""


def attach(timeout=15.0):
    """Своя CDP-сессия БЕЗ Emulation.*: подмена размеров рассинхронизировала бы DOM и пиксели."""
    tabs = [t for t in cdp_linux.http_json('/json/list') if t.get('type') == 'page']
    if not tabs:
        raise RuntimeError('нет вкладки-страницы (браузер не поднят?)')
    return cdp_linux.CDP(tabs[0]['webSocketDebuggerUrl'], timeout=timeout)


def probe_scan(timeout=3.0):
    """Разведка модалки с КОРОТКИМ таймаутом и ОДНОРАЗОВЫМ сокетом.

    🔴 РАДИ ЧЕГО ЭТО НАПИСАНО — здесь корень всей истории T232/T246.
    Нажатие кнопки в 1С почти всегда запускает СИНХРОННЫЙ серверный вызов. Пока он идёт,
    главный поток страницы стоит и `Runtime.evaluate` не выполняется ВООБЩЕ. Наивная проверка
    «а закрылось ли окно?» в этот момент получает таймаут, молча берёт прошлый ответ и печатает
    «окно на месте — клик НЕ дошёл». Это ЛОЖЬ, и именно она стоила двух статусов подряд:
    12.08.2026 замерено — клик xdotool по «OK» ДОШЁЛ (товар оказался в чеке), а драйвер в ту же
    секунду отрапортовал, что не дошёл. Дальше оператор пробовал ещё три способа и жал Escape,
    который сбрасывает уже посчитанную скидку.
    Поэтому: свой сокет на каждую пробу (зависший выбрасывается целиком и не отравляет
    следующую), короткий таймаут и ЧЕСТНЫЙ ответ 'BUSY' — который сам по себе является
    доказательством, что клик дошёл: страница занята именно из-за него.
    Возврат: (данные|None, 'OK'|'BUSY'|'ОШИБКА …')
    """
    c = None
    try:
        c = attach(timeout=timeout)
        val, err = c.evaluate(JS_SCAN)
        if err:
            return None, 'ОШИБКА JS: %s' % str(err)[:150]
        return json.loads(val), 'OK'
    except Exception as e:
        # таймаут сокета = рендерер занят серверным вызовом 1С
        return None, 'BUSY' if 'timed out' in str(e).lower() or isinstance(e, OSError) else 'ОШИБКА: %s' % str(e)[:150]
    finally:
        if c is not None:
            try:
                c.ws.sock.close()
            except Exception:
                pass


def wait_verdict(before, wait, probe_timeout=3.0):
    """Дождаться исхода клика. Возврат: (код, текст).

    код: 0 — окно ушло/сменилось (клик дошёл); 2 — окно на месте (клик не дошёл);
         1 — страница так и осталась занятой (клик дошёл, но исход не дочитан)."""
    deadline = time.time() + wait
    busy_seen = 0
    last = before
    while time.time() < deadline:
        d, st = probe_scan(probe_timeout)
        if st == 'BUSY':
            busy_seen += 1
            continue
        if st != 'OK':
            time.sleep(0.4)
            continue
        last = d
        if not d.get('windows'):
            return 0, ('ПРОВЕРКА: модальное окно закрылось — клик дошёл'
                       + (' (страница была занята серверным вызовом %d проб)' % busy_seen if busy_seen else ''))
        if d.get('window_id') != before.get('window_id') or d.get('form') != before.get('form'):
            return 0, ('ПРОВЕРКА: окно сменилось (%s/%s -> %s/%s) — клик дошёл'
                       % (before.get('window_id'), before.get('form'), d.get('window_id'), d.get('form')))
        # 🔴 Окно осталось, но ИЗМЕНИЛОСЬ — это тоже «клик дошёл», и это не редкость: 1С не
        # закрывает окно, когда действие отбито проверкой, а дописывает в него сообщение
        # («Карта со штрихкодом … не зарегистрирована»). Первая версия вердикта считала такое
        # «клик НЕ дошёл» и отправляла оператора чинить исправный ввод — измерено 12.08.2026.
        if d.get('text') != before.get('text'):
            return 0, ('ПРОВЕРКА: окно осталось, но его содержимое изменилось — клик дошёл, '
                       'действие отработало. Стало: «%s»'
                       % (d.get('text') or '')[-220:])
        time.sleep(0.4)
    if busy_seen and (last is before or last.get('window_id') == before.get('window_id')):
        return 1, ('ПРОВЕРКА: страница %d раз отвечала «занята» — клик ДОШЁЛ и запустил серверный '
                   'вызов 1С, но за %.0f с исход не дочитан. Это НЕ «клик не дошёл»: повторно жать '
                   'НЕЛЬЗЯ, надо ждать.' % (busy_seen, wait))
    return 2, ('ПРОВЕРКА: окно %s на месте спустя %.0f с и страница отвечала — клик НЕ дошёл'
               % (before.get('window_id'), wait))


def scan(cdp=None):
    own = cdp is None
    if own:
        cdp = attach()
    try:
        val, err = cdp.evaluate(JS_SCAN)
        if err:
            raise RuntimeError('JS: %s' % str(err)[:200])
        return json.loads(val)
    finally:
        if own:
            try:
                cdp.ws.sock.close()
            except Exception:
                pass


def _norm(s):
    return re.sub(r'\s+', ' ', (s or '')).strip().lower().replace('ё', 'е')


def pick(buttons, needle):
    """Кнопка по подписи: сначала точное совпадение, потом вхождение. Регистр и «ё» не важны."""
    n = _norm(needle)
    for b in buttons:
        if _norm(b['caption']) == n:
            return b
    for b in buttons:
        if n in _norm(b['caption']):
            return b
    return None


def xdo(display, *args):
    return subprocess.run(['xdotool'] + list(args),
                          env=dict(os.environ, DISPLAY=display),
                          capture_output=True, text=True)


def cmd_scan(a):
    d = scan()
    if a.json:
        print(json.dumps(d, ensure_ascii=False))
        return 0
    if not d.get('windows'):
        print('МОДАЛЬНОГО ОКНА 1С НЕТ (modalSurface=%s)' % d.get('modal'))
        return 1
    print('ОКНО 1С: %s (форма %s, z=%s), экран заблокирован: %s'
          % (d.get('window_id'), d.get('form'), d.get('z'), d.get('modal')))
    print('заголовок: %s' % (d.get('title') or '—'))
    print('текст: %s' % (d.get('text') or '—')[:300])
    print('смещение окна браузера на экране: %s (нативные пиксели, dpr=%s)'
          % (d.get('screen_offset'), d.get('dpr')))
    for b in d.get('buttons', []):
        ox, oy = d['screen_offset']
        print('  кнопка «%s» id=%s центр DOM %d,%d -> ЭКРАН %d,%d%s'
              % (b['caption'], b['id'], b['x'], b['y'], b['x'] + ox, b['y'] + oy,
                 '  [по умолчанию]' if b.get('def') else ''))
    for i in d.get('inputs', []):
        ox, oy = d['screen_offset']
        print('  поле id=%s центр DOM %d,%d -> ЭКРАН %d,%d значение «%s»'
              % (i['id'], i['x'], i['y'], i['x'] + ox, i['y'] + oy, i['value']))
    return 0


def cmd_click(a):
    cdp = attach()
    try:
        before = scan(cdp)
        if not before.get('windows'):
            print('НЕТ МОДАЛЬНОГО ОКНА — нажимать нечего')
            return 1
        b = pick(before.get('buttons', []), a.caption)
        if b is None:
            print('КНОПКА «%s» НЕ НАЙДЕНА. Есть: %s'
                  % (a.caption, ', '.join('«%s»' % x['caption'] for x in before.get('buttons', []))))
            return 3
        ox, oy = before['screen_offset']
        # 🔴 Бьём в ПРОВЕРЕННУЮ hit-тестом точку (hx,hy), а не в геометрический центр:
        # центр кнопки бывает перекрыт панелью «Сообщения» — см. hitPoint() в JS_SCAN.
        cx, cy = b.get('hx', b['x']), b.get('hy', b['y'])
        sx, sy = cx + ox, cy + oy
        if b.get('unreachable'):
            print('🔴 КНОПКА «%s» ПЕРЕКРЫТА ЦЕЛИКОМ (сверху «%s») — свободной точки внутри неё нет. '
                  'Клик по её координатам уйдёт в чужой элемент; это НЕ «кнопка не нажимается».'
                  % (b['caption'], b.get('blocker')))
            hk = b.get('hotkey') or ''
            if not hk:
                print('   горячей клавиши у кнопки тоже нет — нажать её сейчас нечем. '
                      'Убери перекрытие (свернуть панель «Сообщения» / изменить размер окна) и повтори.')
                return 4
            # 🔴 ЗАПАСНОЙ ВХОД: горячая клавиша самой кнопки. Именно так эту кнопку жмёт человек,
            # когда панель сообщений закрыла командную строку окна. Клавиша уйдёт в никуда, если
            # окно 1С не получило фокус РЕАЛЬНЫМ кликом — поэтому сначала клик в свободную точку
            # окна (focus_point), и только потом клавиша.
            print('   у кнопки есть горячая клавиша «%s» — жму её (сначала клик-фокус в окно)' % hk)
            fp = before.get('focus_point')
            if fp:
                fsx, fsy = fp['x'] + ox, fp['y'] + oy
                if a.via == 'x':
                    xdo(a.display, 'mousemove', str(fsx), str(fsy), 'click', '1')
                    print('   клик-фокус xdotool по %d,%d' % (fsx, fsy))
                else:
                    for t in ('mousePressed', 'mouseReleased'):
                        cdp.call('Input.dispatchMouseEvent', {'type': t, 'x': fp['x'], 'y': fp['y'],
                                                              'button': 'left', 'clickCount': 1})
                    print('   клик-фокус CDP по %d,%d' % (fp['x'], fp['y']))
                time.sleep(0.6)
            else:
                print('   свободной точки для клика-фокуса в окне не нашлось — шлю клавишу как есть')
            if a.via == 'x':
                # 🔴 Настоящая клавиша на X-дисплее. CDP-событие 1С в этом месте не приняла
                # (замер 12.08.2026: Ctrl+Enter через Input.dispatchKeyEvent окно не закрыл,
                # тот же Ctrl+Enter через xdotool — закрыл). Для клавиатурных сокращений
                # доверенный путь надёжнее синтетического.
                xk = xdo_hotkey(hk)
                r = xdo(a.display, 'key', '--clearmodifiers', xk)
                print('   послана горячая клавиша xdotool: %s (%s)' % (xk, 'ok' if r.returncode == 0 else r.stderr.strip()[:80]))
            else:
                send_hotkey(cdp, hk)
            try:
                cdp.ws.sock.close()
            except Exception:
                pass
            code, msg = wait_verdict(before, a.wait)
            print(msg)
            return code
        if b.get('obstructed'):
            print('внимание: центр кнопки перекрыт («%s»), бью в свободную точку внутри кнопки'
                  % b.get('blocker'))
        print('окно %s (форма %s): кнопка «%s» id=%s, DOM %d,%d -> ЭКРАН %d,%d'
              % (before.get('window_id'), before.get('form'), b['caption'], b['id'], cx, cy, sx, sy))
        if a.via == 'x':
            # 🔴 Путь «как человек»: настоящий указатель на X-дисплее, координаты НАТИВНЫЕ.
            r = xdo(a.display, 'mousemove', str(sx), str(sy), 'click', '1')
            if r.returncode != 0:
                print('xdotool: %s' % (r.stderr or '').strip()[:200])
                return 4
            print('КЛИК xdotool по %d,%d (DISPLAY=%s)' % (sx, sy, a.display))
        else:
            for t in ('mousePressed', 'mouseReleased'):
                cdp.call('Input.dispatchMouseEvent',
                         {'type': t, 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1})
            print('КЛИК CDP (доверенное событие) по DOM %d,%d' % (cx, cy))
        # 🔴 Вердикт — по DOM, а не по «похоже, изменилось». И с различением «занята» и «не дошёл»:
        # см. probe_scan() — путать их нельзя, это и был корень T232/T246.
        try:
            cdp.ws.sock.close()      # длинный сокет больше не нужен и мешал бы пробам
        except Exception:
            pass
        code, msg = wait_verdict(before, a.wait)
        print(msg)
        return code
    finally:
        try:
            cdp.ws.sock.close()
        except Exception:
            pass


def cmd_fill(a):
    """Ввод в поле верхнего модального окна.

    🔴 Посимвольно keyDown(text)+keyUp, а НЕ Input.insertText: веб-клиент 1С меняет значение в
    DOM, но своей внутренней моделью его не видит, и на сервер уезжает ПУСТАЯ строка (грабля
    T211, из-за неё «поиск не находит» при заполненном на вид поле)."""
    cdp = attach()
    try:
        d = scan(cdp)
        if not d.get('inputs'):
            print('В ВЕРХНЕМ ОКНЕ НЕТ ПОЛЯ ВВОДА (окно %s)' % d.get('window_id'))
            return 3
        f = d['inputs'][0]
        for t in ('mousePressed', 'mouseReleased'):
            cdp.call('Input.dispatchMouseEvent',
                     {'type': t, 'x': f['x'], 'y': f['y'], 'button': 'left', 'clickCount': 1})
        time.sleep(1.2)   # редактор поля создаётся асинхронно; 0,4 с не хватало (T211)
        # 🔴 Ctrl+A перед набором: поле модалки часто УЖЕ заполнено (повторная попытка, значение
        # по умолчанию), и без выделения новый текст дописывается к старому — получается
        # «6056319246001333», а ошибка выглядит как «не найдено», а не как «набрали не то».
        for t, mod in (('rawKeyDown', 2), ('keyUp', 2)):
            cdp.call('Input.dispatchKeyEvent', {'type': t, 'key': 'a', 'code': 'KeyA',
                                                'windowsVirtualKeyCode': 65, 'nativeVirtualKeyCode': 65,
                                                'modifiers': mod})
        time.sleep(0.2)
        for ch in a.text:
            cdp.call('Input.dispatchKeyEvent', {'type': 'keyDown', 'text': ch, 'key': ch,
                                                'unmodifiedText': ch})
            cdp.call('Input.dispatchKeyEvent', {'type': 'keyUp', 'key': ch})
            time.sleep(0.04)
        time.sleep(0.4)
        val, _ = cdp.evaluate('(function(){var e=document.getElementById(%s);return e?String(e.value):"НЕТ ПОЛЯ";})()'
                              % json.dumps(f['id']))
        print('ПОЛЕ %s: «%s» (введено %d симв.)' % (f['id'], val, len(a.text)))
        return 0 if str(val).strip() == a.text.strip() else 2
    finally:
        try:
            cdp.ws.sock.close()
        except Exception:
            pass


def xdo_hotkey(hk):
    """«Ctrl+Enter» -> «ctrl+Return» (имена клавиш X отличаются от подписей 1С)."""
    имена = {'enter': 'Return', 'esc': 'Escape', 'escape': 'Escape', 'del': 'Delete',
             'ins': 'Insert', 'backspace': 'BackSpace', 'space': 'space', 'tab': 'Tab'}
    parts = [p.strip() for p in hk.split('+') if p.strip()]
    out = []
    for i, p in enumerate(parts):
        low = p.lower()
        if i < len(parts) - 1:
            out.append(low)                       # модификаторы: ctrl/alt/shift
        else:
            out.append(имена.get(low, p if re.match(r'^F\d{1,2}$', p) else low))
    return '+'.join(out)


def send_hotkey(cdp, hk):
    """Горячая клавиша вида «Ctrl+Enter», «Alt+F7», «F7» — событиями CDP.

    🔴 Модификаторы в CDP — БИТОВАЯ МАСКА в поле modifiers (Alt=1, Ctrl=2, Meta=4, Shift=8),
    а не отдельные события клавиш. Отправка Ctrl отдельным keyDown 1С не понимает."""
    parts = [p.strip() for p in hk.split('+') if p.strip()]
    mods, key = 0, parts[-1]
    for p in parts[:-1]:
        low = p.lower()
        mods |= 1 if low == 'alt' else 2 if low == 'ctrl' else 8 if low == 'shift' else 4 if low == 'meta' else 0
    spec = KEYMAP.get(key, None)
    if spec:
        keyname, vk, text = spec
    elif re.match(r'^F\d{1,2}$', key):
        keyname, vk, text = key, 111 + int(key[1:]), ''
    else:
        keyname, vk, text = key.lower(), ord(key.upper()[0]), key.lower()
    p = {'type': 'rawKeyDown' if mods else 'keyDown', 'key': keyname,
         'windowsVirtualKeyCode': vk, 'nativeVirtualKeyCode': vk, 'modifiers': mods}
    if text and not mods:
        p['text'] = text
    cdp.call('Input.dispatchKeyEvent', p)
    cdp.call('Input.dispatchKeyEvent', {'type': 'keyUp', 'key': keyname,
                                        'windowsVirtualKeyCode': vk, 'nativeVirtualKeyCode': vk,
                                        'modifiers': mods})
    print('   послана горячая клавиша %s (modifiers=%d, vk=%d)' % (hk, mods, vk))


KEYMAP = {
    'Enter': ('Enter', 13, '\r'), 'Return': ('Enter', 13, '\r'),
    'Escape': ('Escape', 27, ''), 'Esc': ('Escape', 27, ''),
    'Tab': ('Tab', 9, '\t'), 'Space': (' ', 32, ' '),
}


def cmd_keys(a):
    cdp = attach()
    try:
        k = KEYMAP.get(a.key, (a.key, 0, ''))
        for t in ('keyDown', 'keyUp'):
            p = {'type': t, 'key': k[0], 'windowsVirtualKeyCode': k[1], 'nativeVirtualKeyCode': k[1]}
            if t == 'keyDown' and k[2]:
                p['text'] = k[2]
            cdp.call('Input.dispatchKeyEvent', p)
        time.sleep(0.8)
        d = scan(cdp)
        print('клавиша %s отправлена; окон 1С сейчас: %d (%s)'
              % (a.key, d.get('windows', 0), d.get('window_id', '—')))
        return 0
    finally:
        try:
            cdp.ws.sock.close()
        except Exception:
            pass


def main():
    p = argparse.ArgumentParser(description='модальные окна 1С (веб-клиент) через CDP')
    sub = p.add_subparsers(dest='cmd')
    s = sub.add_parser('scan'); s.add_argument('--json', action='store_true'); s.set_defaults(f=cmd_scan)
    c = sub.add_parser('click'); c.add_argument('caption')
    c.add_argument('--via', choices=['cdp', 'x'], default='cdp')
    c.add_argument('--display', default=os.environ.get('RC_DISPLAY', ':99'))
    c.add_argument('--wait', type=float, default=12.0); c.set_defaults(f=cmd_click)
    f = sub.add_parser('fill'); f.add_argument('text'); f.set_defaults(f=cmd_fill)
    k = sub.add_parser('keys'); k.add_argument('key'); k.set_defaults(f=cmd_keys)
    a = p.parse_args()
    if not getattr(a, 'f', None):
        p.print_help()
        return 2
    # 🔴 БЕЗ CDP — ЧЕСТНЫЙ ОТВЕТ, А НЕ ТРАССИРОВКА. Этот модуль умеет только ВЕБ-клиент 1С: окно
    # там это DOM, и читается оно через CDP. У ТОНКОГО клиента (RustDesk/AnyDesk на живой кассе)
    # DOM нет вовсе, порт 9222 никто не слушает, и `modal` до этой правки вываливал двадцать
    # строк питоновской трассировки ConnectionRefusedError. Вызывающий из этого не мог понять
    # ни что случилось, ни что делать дальше, и терял время на отладку инструмента вместо задачи
    # (поймано фактом в T298, 02:24). Теперь тот же случай — одна строка JSON с указанием пути
    # для тонкого клиента.
    try:
        return a.f(a)
    except (ConnectionRefusedError, socket.error, OSError, URLError) as e:
        out = {'found': False, 'reason': 'cdp-unreachable',
               'cdp_port': os.environ.get('CDP_PORT', '9222'),
               'error': str(e),
               'hint': 'это ВЕБ-клиентский путь. Тонкий клиент (RustDesk/AnyDesk): '
                       'rc.sh modal-click --tmpl <эталон>, либо rc.sh read <x,y,w,h> <scale> '
                       'для текста и rc.sh click по вычисленной точке'}
        print(json.dumps(out, ensure_ascii=False))
        return 5


if __name__ == '__main__':
    sys.exit(main())
