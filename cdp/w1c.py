#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""w1c.py — драйвер ВЕБ-КЛИЕНТА 1С через CDP: вход, навигация, клики, КАДРЫ.

🔴 Зачем отдельный драйвер, а не пиксельный `rc.sh` по RustDesk/AnyDesk. Оба удалённых экрана
боевого сервера регулярно непригодны для кадра: `SERVER-1S` по RustDesk отдаёт ЭКРАН БЛОКИРОВКИ
(в консольном сеансе никого нет, окну 1С негде появиться — поймано T311 28.08 и снова T316 02.09),
машина кассира — чёрный кадр. При этом веб-публикация базы на IIS жива, и её открывают в СВОЁМ
Chromium через ssh-туннель: кадр снимается с НАШЕГО X-сервера и заведомо не врёт, а координаты
берутся из DOM, а не «на глаз» (главная боль пиксельных драйверов, ради которой писался v2).

Родословная: вырос из `orch/loyalty/_t311/cdp1c.py` (KSO-репозиторий, задача T311). Здесь он стал
переиспользуемым: добавлены кадр `shot`, ожидание `waittext`, разбор командного интерфейса `ui`,
ввод в поля формы по подписи, работа со ссылками-«гиперссылками» 1С и закрытие модальных окон.

🔴 Пароль НИКОГДА не попадает ни в argv, ни в stdout: только через переменные среды
P1C_USER / P1C_PASS.

Запуск (браузер уже поднят с --remote-debugging-port):
    CDP_PORT=9333 python3 w1c.py <команда> [аргументы]

Команды:
    text [N]              innerText страницы (по умолчанию 4000 символов)
    inputs                видимые поля/кнопки с координатами (DOM)
    ui [regex]            видимые ЭЛЕМЕНТЫ ИНТЕРФЕЙСА 1С (кнопки, команды, ячейки) + координаты
    shot <файл.png>       кадр страницы через CDP (без X-сервера, точный, для инструкций)
    login                 вход по P1C_USER / P1C_PASS
    click <текст>         клик по видимому тексту (настоящие события мыши на найденный элемент)
    clickid <id>          клик по DOM-id
    mclick <x> <y>        клик по координатам вьюпорта
    dblclick <текст>      двойной клик (открыть строку списка 1С)
    key <Key> [mods]      клавиша (Enter, Escape, F5, Tab, ArrowDown…)
    fill <id> <текст>     ввод в поле по id (реальные события, а не .value)
    waittext <текст> [сек] ждать появления текста на странице (код 0 — дождались)
    dialog [no]           закрыть НАТИВНОЕ окно браузера (alert/confirm)
    eval '<js>'           выполнить выражение

🔴 Три грабли веб-клиента 1С, из-за которых наивный код «нажал, а ничего не произошло»:
 1. Команды нарисованы НЕ кнопками, а div-ами со своими обработчиками мыши: синтетический
    element.click() до них не доходит. Шлём mouseover/mousedown/mouseup/click НА ЭЛЕМЕНТ.
 2. Значение поля, поставленное присваиванием .value, веб-клиент не видит — нужен нативный сеттер
    прототипа + события input/change (или ещё честнее — CDP Input.insertText).
 3. Нативное окно браузера (alert/confirm) ОСТАНАВЛИВАЕТ JS целиком, и любой Runtime.evaluate
    висит до таймаута — выглядит как «страница умерла». Закрывается только протоколом: `dialog`.
"""
import base64
import json
import os
import sys
import time
import urllib.request

import websocket

PORT = os.environ.get('CDP_PORT', '9333')


def page_ws():
    data = json.loads(urllib.request.urlopen('http://127.0.0.1:%s/json/list' % PORT, timeout=10).read())
    pages = [p for p in data if p.get('type') == 'page']
    if not pages:
        raise SystemExit('нет страницы в браузере')
    return pages[0]['webSocketDebuggerUrl']


class C:
    def __init__(self, timeout=60):
        self.ws = websocket.create_connection(page_ws(), timeout=timeout)
        self.i = 0

    def call(self, method, **params):
        self.i += 1
        self.ws.send(json.dumps({'id': self.i, 'method': method, 'params': params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get('id') == self.i:
                if 'error' in msg:
                    raise SystemExit('CDP %s: %s' % (method, msg['error']))
                return msg.get('result', {})

    def js(self, expr):
        r = self.call('Runtime.evaluate', expression=expr, returnByValue=True, awaitPromise=True)
        res = r.get('result', {})
        if res.get('subtype') == 'error':
            return 'JS ERROR: ' + str(res.get('description'))
        return res.get('value')

    def mouse(self, x, y, clicks=1):
        self.call('Input.dispatchMouseEvent', type='mouseMoved', x=x, y=y)
        for _ in range(clicks):
            self.call('Input.dispatchMouseEvent', type='mousePressed', x=x, y=y,
                      button='left', clickCount=1, buttons=1)
            self.call('Input.dispatchMouseEvent', type='mouseReleased', x=x, y=y,
                      button='left', clickCount=1, buttons=0)
            time.sleep(0.05)


# 🔴 Поиск элемента по ТОЧНОМУ тексту с выбором САМОГО МЕЛКОГО подходящего: у 1С текст кнопки
# лежит во вложенном span, а его родитель-контейнер содержит тот же текст и занимает пол-экрана.
# Без «самого мелкого» клик уходит в контейнер и никуда не попадает.
FIND_JS = """(function(t, exact){
  var best=null;
  var all=document.querySelectorAll('div,span,a,td,button,li,input');
  for(var i=0;i<all.length;i++){
    var e=all[i];
    var txt=((e.tagName==='INPUT'? e.value : e.textContent)||'').replace(/\\s+/g,' ').trim();
    if(exact ? (txt!==t) : (txt.indexOf(t)<0)) continue;
    var r=e.getBoundingClientRect();
    if(r.width<2||r.height<2) continue;
    if(r.bottom<0||r.top>window.innerHeight) continue;
    if(best===null || (r.width*r.height)<(best.w*best.h))
      best={x:r.x+r.width/2, y:r.y+r.height/2, w:r.width, h:r.height, id:e.id||'', tag:e.tagName};
  }
  return best?JSON.stringify(best):'';
})(%s, %s)"""

DISPATCH_JS = """(function(t, exact, dbl){
  var best=null;
  var all=document.querySelectorAll('div,span,a,td,button,li');
  for(var i=0;i<all.length;i++){
    var e=all[i];
    var txt=(e.textContent||'').replace(/\\s+/g,' ').trim();
    if(exact ? (txt!==t) : (txt.indexOf(t)<0)) continue;
    var r=e.getBoundingClientRect();
    if(r.width<2||r.height<2) continue;
    if(best===null || (r.width*r.height)<(best.r.width*best.r.height)) best={e:e,r:r};
  }
  if(!best) return '';
  var cx=best.r.x+best.r.width/2, cy=best.r.y+best.r.height/2;
  var seq = dbl ? ['mouseover','mousedown','mouseup','click','mousedown','mouseup','click','dblclick']
                : ['mouseover','mousedown','mouseup','click'];
  seq.forEach(function(t2){
    best.e.dispatchEvent(new MouseEvent(t2,{bubbles:true,cancelable:true,
      clientX:cx,clientY:cy,detail:(t2==='dblclick'?2:1),view:window}));
  });
  return JSON.stringify({x:Math.round(cx), y:Math.round(cy), id:best.e.id||'', tag:best.e.tagName});
})(%s, %s, %s)"""


def find(c, needle, exact=True):
    r = c.js(FIND_JS % (json.dumps(needle), 'true' if exact else 'false'))
    return json.loads(r) if r else None


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'text'
    c = C()

    if cmd == 'text':
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
        print(str(c.js("document.body ? document.body.innerText : '(нет body)'"))[:n])

    elif cmd == 'inputs':
        expr = """(function(){
          var out=[];
          document.querySelectorAll('input,button,a,div[role=button],select,textarea').forEach(function(e,i){
            var r=e.getBoundingClientRect();
            if(r.width<1||r.height<1) return;
            out.push([i,e.tagName,e.type||'',e.id||'',(e.value||'').slice(0,50),
                      (e.innerText||'').replace(/\\s+/g,' ').slice(0,50),
                      Math.round(r.x),Math.round(r.y),Math.round(r.width),Math.round(r.height)].join(' | '));
          });
          return out.join('\\n');
        })()"""
        print(c.js(expr))

    elif cmd == 'ui':
        # Видимые элементы командного интерфейса 1С с координатами. Фильтр — регулярка по тексту.
        rx = sys.argv[2] if len(sys.argv) > 2 else '.'
        expr = """(function(rxs){
          var rx=new RegExp(rxs,'i'), out=[], seen={};
          var all=document.querySelectorAll('div,span,a,td,button,li');
          for(var i=0;i<all.length;i++){
            var e=all[i];
            if(e.children.length>2) continue;                 // только листья — иначе дубли контейнеров
            var txt=(e.textContent||'').replace(/\\s+/g,' ').trim();
            if(!txt || txt.length>90 || !rx.test(txt)) continue;
            var r=e.getBoundingClientRect();
            if(r.width<3||r.height<3||r.bottom<0||r.top>window.innerHeight) continue;
            var k=txt+'@'+Math.round(r.x)+','+Math.round(r.y);
            if(seen[k]) continue; seen[k]=1;
            out.push(Math.round(r.x+r.width/2)+','+Math.round(r.y+r.height/2)+'  ['+e.tagName+' '+(e.id||'-')+']  '+txt);
          }
          return out.join('\\n');
        })(%s)""" % json.dumps(rx)
        print(c.js(expr))

    elif cmd == 'shot':
        out = sys.argv[2]
        # 🔴 fromSurface=True — иначе на безголовом X кадр приходит пустым/битым.
        r = c.call('Page.captureScreenshot', format='png', fromSurface=True, captureBeyondViewport=False)
        data = base64.b64decode(r['data'])
        with open(out, 'wb') as f:
            f.write(data)
        print('SHOT %s bytes=%d' % (out, len(data)))

    elif cmd == 'login':
        user = os.environ.get('P1C_USER', '')
        pwd = os.environ.get('P1C_PASS', '')
        if not user:
            raise SystemExit('нет P1C_USER')
        expr = """(function(u,p){
          function put(el,v){ el.focus();
            var s=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
            s.call(el,v);
            el.dispatchEvent(new Event('input',{bubbles:true}));
            el.dispatchEvent(new Event('change',{bubbles:true}));
          }
          var lo=document.getElementById('authWindow_basic_login');
          var pa=document.getElementById('authWindow_basic_password');
          if(!lo){ var ins=[].slice.call(document.querySelectorAll('input')).filter(function(e){
              var r=e.getBoundingClientRect(); return r.width>0&&r.height>0;});
            lo=ins[0]; pa=ins[1]; }
          if(!lo) return 'полей ввода не видно';
          put(lo,u); if(pa) put(pa,p);
          return 'логин заполнен: '+lo.value+'; пароль задан: '+(pa? (pa.value.length>0) : 'нет поля');
        })(%s,%s)""" % (json.dumps(user), json.dumps(pwd))
        print(c.js(expr))
        b = find(c, 'Войти')
        if b:
            c.mouse(b['x'], b['y'])
            print('нажата «Войти» в (%d,%d)' % (b['x'], b['y']))
        else:
            print('кнопка «Войти» не найдена — нажми сам')

    elif cmd in ('click', 'dblclick'):
        needle = sys.argv[2]
        exact = 'false' if (len(sys.argv) > 3 and sys.argv[3] == 'sub') else 'true'
        dbl = 'true' if cmd == 'dblclick' else 'false'
        r = c.js(DISPATCH_JS % (json.dumps(needle), exact, dbl))
        if not r:
            print('НЕ НАЙДЕНО: ' + needle)
            sys.exit(2)
        print('%s «%s» → %s' % (cmd.upper(), needle, r))

    elif cmd == 'clickid':
        eid = sys.argv[2]
        pos = c.js("(function(id){var e=document.getElementById(id); if(!e) return '';"
                   "var r=e.getBoundingClientRect(); return JSON.stringify({x:r.x+r.width/2,y:r.y+r.height/2});})(%s)"
                   % json.dumps(eid))
        if not pos:
            print('НЕТ ЭЛЕМЕНТА: ' + eid)
            sys.exit(2)
        pt = json.loads(pos)
        c.mouse(pt['x'], pt['y'])
        print('КЛИК по %s в (%d,%d)' % (eid, pt['x'], pt['y']))

    elif cmd == 'mclick':
        x, y = float(sys.argv[2]), float(sys.argv[3])
        clicks = int(sys.argv[4]) if len(sys.argv) > 4 else 1
        c.mouse(x, y, clicks)
        print('КЛИК в (%s,%s) x%d' % (x, y, clicks))

    elif cmd in ('xclick', 'xclicktext'):
        # 🔴 Выпадающие меню 1С («Еще», подменю «Печать»/«Отчеты») НЕ открываются ни от
        # element.dispatchEvent, ни от CDP Input.dispatchMouseEvent — им нужен НАСТОЯЩИЙ указатель
        # X-сервера (поймано фактом на журнале «Чеки ККМ», T316). Поэтому здесь координата из DOM
        # пересчитывается в экранную и кликается xdotool'ом.
        #   экран = вьюпорт + (лево_окна, верх_окна), где верх = screenY + (outerHeight-innerHeight)
        import subprocess
        off = c.js("JSON.stringify({sx:window.screenX,sy:window.screenY,ow:window.outerWidth,"
                   "oh:window.outerHeight,iw:window.innerWidth,ih:window.innerHeight})")
        o = json.loads(off)
        dx = o['sx'] + (o['ow'] - o['iw']) // 2
        dy = o['sy'] + (o['oh'] - o['ih'])
        if cmd == 'xclick':
            vx, vy = float(sys.argv[2]), float(sys.argv[3])
        else:
            b = find(c, sys.argv[2], exact=(len(sys.argv) < 4 or sys.argv[3] != 'sub'))
            if not b:
                print('НЕ НАЙДЕНО: ' + sys.argv[2])
                sys.exit(2)
            vx, vy = b['x'], b['y']
        sx, sy = int(round(vx + dx)), int(round(vy + dy))
        disp = os.environ.get('RC_DISPLAY', ':99')
        subprocess.run(['xdotool', 'mousemove', str(sx), str(sy), 'click', '1'],
                       env=dict(os.environ, DISPLAY=disp), check=True)
        print('X-КЛИК вьюпорт(%d,%d) → экран(%d,%d) [сдвиг %+d,%+d]' % (vx, vy, sx, sy, dx, dy))

    elif cmd == 'wheel':
        # 🔴 Списки 1С виртуализованы и прокручиваются СВОИМ скроллбаром: ни scrollTop у DOM-узла,
        # ни клавиша End до них не доходят (у контейнера overflow:hidden). Доходит колесо мыши.
        x, y = float(sys.argv[2]), float(sys.argv[3])
        delta = float(sys.argv[4]) if len(sys.argv) > 4 else 300
        times = int(sys.argv[5]) if len(sys.argv) > 5 else 1
        c.call('Input.dispatchMouseEvent', type='mouseMoved', x=x, y=y)
        for _ in range(times):
            c.call('Input.dispatchMouseEvent', type='mouseWheel', x=x, y=y, deltaX=0, deltaY=delta)
            time.sleep(0.12)
        print('КОЛЕСО в (%s,%s) delta=%s x%d' % (x, y, delta, times))

    elif cmd == 'key':
        keymap = {
            'Enter': (13, 'Enter'), 'Escape': (27, 'Escape'), 'Tab': (9, 'Tab'),
            'F5': (116, 'F5'), 'F9': (120, 'F9'), 'F2': (113, 'F2'), 'F7': (118, 'F7'),
            'ArrowDown': (40, 'ArrowDown'), 'ArrowUp': (38, 'ArrowUp'),
            'ArrowLeft': (37, 'ArrowLeft'), 'ArrowRight': (39, 'ArrowRight'),
            'Delete': (46, 'Delete'), 'Backspace': (8, 'Backspace'),
            'Insert': (45, 'Insert'), 'End': (35, 'End'), 'Home': (36, 'Home'),
        }
        name = sys.argv[2]
        mods = int(sys.argv[3]) if len(sys.argv) > 3 else 0   # 1=Alt 2=Ctrl 4=Meta 8=Shift
        vk, key = keymap.get(name, (0, name))
        # 🔴 Enter/Tab в веб-клиенте 1С доходят только с СИМВОЛЬНОЙ частью события: голая пара
        # keyDown/keyUp без text/unmodifiedText молча теряется, поле остаётся заполненным, а поиск
        # не срабатывает — выглядит как «клавиша не дошла» (поймано фактом на строке поиска
        # журнала «Чеки ККМ», T316).
        txt = {'Enter': '\r', 'Tab': '\t'}.get(name)
        for t in ('keyDown', 'keyUp'):
            a = dict(type=t, key=key, code=key, modifiers=mods,
                     windowsVirtualKeyCode=vk, nativeVirtualKeyCode=vk)
            if txt and t == 'keyDown':
                a.update(text=txt, unmodifiedText=txt)
            c.call('Input.dispatchKeyEvent', **a)
            time.sleep(0.05)
        print('КЛАВИША %s (mods=%d)' % (name, mods))

    elif cmd == 'fill':
        eid, text = sys.argv[2], sys.argv[3]
        pos = c.js("(function(id){var e=document.getElementById(id); if(!e) return '';"
                   "var r=e.getBoundingClientRect(); return JSON.stringify({x:r.x+r.width/2,y:r.y+r.height/2});})(%s)"
                   % json.dumps(eid))
        if not pos:
            print('НЕТ ПОЛЯ: ' + eid)
            sys.exit(2)
        pt = json.loads(pos)
        c.mouse(pt['x'], pt['y'])
        time.sleep(0.15)
        for t in ('keyDown', 'keyUp'):   # Ctrl+A — заменить, а не дописать
            c.call('Input.dispatchKeyEvent', type=t, modifiers=2, key='a', code='KeyA',
                   windowsVirtualKeyCode=65, nativeVirtualKeyCode=65)
        time.sleep(0.1)
        c.call('Input.insertText', text=text)
        time.sleep(0.2)
        print('ПОЛЕ %s = %s' % (eid[-30:],
              c.js("(function(id){var e=document.getElementById(id);return e?e.value:'';})(%s)" % json.dumps(eid))))

    elif cmd == 'typetext':
        # 🔴 Строка поиска в командной панели списка 1С «вооружается» ТОЛЬКО настоящими нажатиями:
        # Input.insertText кладёт значение в поле (оно видно), но обработчик 1С его не замечает и
        # поиск по Enter не срабатывает. Поэтому здесь каждый символ идёт парой keyDown/keyUp
        # с text — как от живой клавиатуры.
        text = sys.argv[2]
        for ch in text:
            for t in ('keyDown', 'keyUp'):
                a = dict(type=t, key=ch, text=ch, unmodifiedText=ch)
                if ch.isdigit():
                    a.update(code='Digit' + ch, windowsVirtualKeyCode=ord(ch), nativeVirtualKeyCode=ord(ch))
                c.call('Input.dispatchKeyEvent', **a)
            time.sleep(0.08)
        print('НАБРАНО «%s»' % text)

    elif cmd == 'waittext':
        needle = sys.argv[2]
        limit = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0
        t0 = time.time()
        while time.time() - t0 < limit:
            body = c.js("document.body ? document.body.innerText : ''") or ''
            if needle in body:
                print('ЕСТЬ «%s» через %.1f с' % (needle, time.time() - t0))
                return
            time.sleep(0.5)
        print('НЕ ДОЖДАЛИСЬ «%s» за %.0f с' % (needle, limit))
        sys.exit(2)

    elif cmd == 'nav':
        # 🔴 Веб-клиент 1С вешает beforeunload: любая смена адреса поднимает НАТИВНОЕ окно браузера
        # «Leave site? / Changes you made may not be saved». Оно блокирует ВЕСЬ рендерер — и не
        # только свою вкладку, а все вкладки того же origin (соседняя вкладка тогда показывает
        # «Не удается установить соединение», и это выглядит как падение сервера, хотя сервер жив).
        # Поэтому навигация делается протоколом с включённым доменом Page и автоприёмом окна.
        url = sys.argv[2]
        limit = float(sys.argv[3]) if len(sys.argv) > 3 else 45.0
        c.call('Page.enable')
        c.i += 1
        c.ws.send(json.dumps({'id': c.i, 'method': 'Page.navigate', 'params': {'url': url}}))
        want, done, t0 = c.i, False, time.time()
        c.ws.settimeout(3)
        while time.time() - t0 < limit:
            try:
                msg = json.loads(c.ws.recv())
            except Exception:
                if done:
                    break
                continue
            if msg.get('method') == 'Page.javascriptDialogOpening':
                print('окно браузера: «%s» — принимаю' % msg['params'].get('message', ''))
                c.i += 1
                c.ws.send(json.dumps({'id': c.i, 'method': 'Page.handleJavaScriptDialog',
                                      'params': {'accept': True}}))
            elif msg.get('id') == want:
                if 'error' in msg:
                    print('НАВИГАЦИЯ ОТКАЗАНА: %s' % msg['error'])
                    sys.exit(2)
                done = True
        print('НАВИГАЦИЯ → %s' % url)

    elif cmd == 'closeother':
        # Закрыть все вкладки, кроме первой (JS-окно в соседней вкладке того же origin вешает
        # рендерер и у ЖИВОЙ вкладки тоже).
        data = json.loads(urllib.request.urlopen('http://127.0.0.1:%s/json/list' % PORT, timeout=10).read())
        pages = [p for p in data if p.get('type') == 'page']
        for p in pages[1:]:
            urllib.request.urlopen('http://127.0.0.1:%s/json/close/%s' % (PORT, p['id']), timeout=10).read()
            print('закрыта вкладка %s' % p['url'][:80])
        print('осталось вкладок: 1')

    elif cmd == 'dialog':
        accept = (len(sys.argv) < 3 or sys.argv[2] != 'no')
        try:
            c.call('Page.enable')
            c.call('Page.handleJavaScriptDialog', accept=accept)
            print('НАТИВНОЕ ОКНО ЗАКРЫТО (accept=%s)' % accept)
        except SystemExit as e:
            print('нативного окна нет: %s' % e)

    elif cmd == 'eval':
        print(c.js(sys.argv[2]))

    else:
        raise SystemExit('неизвестная команда: ' + cmd)


if __name__ == '__main__':
    main()
