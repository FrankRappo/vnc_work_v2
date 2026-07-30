#!/usr/bin/env python3
"""
local_page.py — вождение ЛОКАЛЬНОЙ страницы (file:// или http://localhost) через CDP
в headless-хромиуме на этой же машине. Скриншоты + JS + консоль текстом.

Зачем в этом фреймворке: cdp/ водит браузер на УДАЛЁННОЙ машине (cdp_up.sh + cdp_get.ps1),
а rc.sh — пиксельный GUI. Когда проверять надо локально собранную HTML-страницу
(демо, отчёт, прототип), оба пути не подходят: удалённой машины в схеме нет,
GUI-сессии тоже. Раньше это делалось разовым puppeteer-скриптом в /tmp — то есть
никак не переиспользовалось и не хранило гочи. Здесь то же самое, но одним файлом,
без node и без npm: python + websocket-client, которые в окружении уже есть.

Гочи, на которых это писалось:
  * headless-Chrome нужен профиль в отдельном каталоге, иначе цепляется к чужому;
  * Page.captureScreenshot отдаёт видимую область — для полной страницы нужен
    Emulation.setDeviceMetricsOverride на всю высоту документа;
  * Runtime.evaluate по умолчанию не ждёт промисов — awaitPromise=True обязателен,
    иначе клик по кнопке, открывающей модалку, снимается «до» открытия;
  * console-ошибки страницы приходят только если включить Runtime.enable ДО navigate;
  * Chrome 111+ отвечает 403 на WebSocket без --remote-allow-origins=*;
  * websocket-client не понимает max_size (это параметр библиотеки `websockets`).

CLI:
    python3 local_page.py shot   <url> <out.png> [--w 1600 --h 1000 --full]
    python3 local_page.py script <url> <steps.json> <outdir>

steps.json — список шагов:
    {"js": "...выражение..."}                выполнить JS
    {"shot": "01_main", "full": true}        скриншот в <outdir>/01_main.png
    {"wait": 0.4}                            пауза, сек
    {"expect": "выражение", "name": "..."}   проверка: результат должен быть истинным
Итог — <outdir>/report.json: console-ошибки, результаты expect, список снимков.
"""
import base64, json, os, shutil, socket, subprocess, sys, tempfile, time

try:
    import websocket  # websocket-client
except ImportError:
    sys.exit('нужен websocket-client: pip install websocket-client')

import urllib.request

CHROME = next((p for p in ('/usr/local/bin/chromium', '/usr/bin/chromium-browser',
                           '/usr/bin/google-chrome', '/usr/bin/chromium')
               if os.path.exists(p)), None)


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


class Browser:
    def __init__(self, width=1600, height=1000):
        if not CHROME:
            sys.exit('не найден chromium/chrome')
        self.port = free_port()
        self.profile = tempfile.mkdtemp(prefix='cdp-local-')
        self.proc = subprocess.Popen([
            CHROME, '--headless=new', '--disable-gpu', '--no-sandbox',
            '--hide-scrollbars', '--disable-dev-shm-usage',
            '--allow-file-access-from-files',
            '--remote-debugging-port=%d' % self.port,
            # Chrome 111+ рубит WS-рукопожатие с Origin: http://127.0.0.1:<эфемерный порт>
            # ответом 403 Forbidden. Без этого флага подключиться нельзя вообще.
            '--remote-allow-origins=*',
            '--user-data-dir=' + self.profile,
            '--window-size=%d,%d' % (width, height),
            'about:blank',
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.ws = None
        self.msg_id = 0
        self.console = []
        for _ in range(120):
            try:
                d = json.load(urllib.request.urlopen(
                    'http://127.0.0.1:%d/json/list' % self.port, timeout=1))
                tgt = [t for t in d if t['type'] == 'page']
                if tgt:
                    # NB: у websocket-client нет параметра max_size (это из lib `websockets`) —
                    # передашь его, и create_connection молча падает TypeError в цикле ретраев.
                    self.ws = websocket.create_connection(tgt[0]['webSocketDebuggerUrl'], timeout=60)
                    break
            except Exception as e:
                last = e
                time.sleep(0.25)
        if not self.ws:
            print('CDP connect error:', repr(last) if 'last' in dir() else '?', file=sys.stderr)
            self.close()
            sys.exit('не удалось подключиться к CDP')
        self.send('Runtime.enable')          # до navigate, иначе ошибки страницы потеряются
        self.send('Page.enable')
        self.width, self.height = width, height

    def send(self, method, **params):
        self.msg_id += 1
        mid = self.msg_id
        self.ws.send(json.dumps({'id': mid, 'method': method, 'params': params}))
        while True:
            m = json.loads(self.ws.recv())
            if m.get('method') == 'Runtime.exceptionThrown':
                d = m['params']['exceptionDetails']
                self.console.append('EXCEPTION: ' + (d.get('text') or '') + ' ' +
                                    json.dumps(d.get('exception', {}).get('description', ''),
                                               ensure_ascii=False))
            elif m.get('method') == 'Runtime.consoleAPICalled':
                if m['params']['type'] in ('error', 'warning'):
                    args = ' '.join(str(a.get('value', a.get('description', '')))
                                    for a in m['params']['args'])
                    self.console.append(m['params']['type'].upper() + ': ' + args)
            if m.get('id') == mid:
                if 'error' in m:
                    raise RuntimeError('%s: %s' % (method, m['error']))
                return m.get('result', {})

    def goto(self, url):
        self.send('Page.navigate', url=url)
        time.sleep(1.2)
        for _ in range(40):
            r = self.eval('document.readyState')
            if r == 'complete':
                break
            time.sleep(0.2)

    def eval(self, expr):
        r = self.send('Runtime.evaluate', expression=expr, returnByValue=True,
                      awaitPromise=True, userGesture=True)
        if 'exceptionDetails' in r:
            d = r['exceptionDetails']
            raise RuntimeError('JS: ' + (d.get('exception', {}).get('description') or d.get('text')))
        return r.get('result', {}).get('value')

    def shot(self, path, full=False):
        if full:
            h = int(self.eval('Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)'))
            h = max(h, self.height)
            self.send('Emulation.setDeviceMetricsOverride', width=self.width, height=h,
                      deviceScaleFactor=1, mobile=False)
            time.sleep(0.25)
        r = self.send('Page.captureScreenshot', format='png')
        open(path, 'wb').write(base64.b64decode(r['data']))
        if full:
            self.send('Emulation.clearDeviceMetricsOverride')
            time.sleep(0.15)
        return path

    def close(self):
        try:
            if self.ws:
                self.ws.close()
        except Exception:
            pass
        try:
            self.proc.terminate()
            self.proc.wait(timeout=8)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass
        shutil.rmtree(self.profile, ignore_errors=True)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == 'shot':
        url, out = sys.argv[2], sys.argv[3]
        w = h = None
        args = sys.argv[4:]
        w = int(args[args.index('--w') + 1]) if '--w' in args else 1600
        h = int(args[args.index('--h') + 1]) if '--h' in args else 1000
        b = Browser(w, h)
        try:
            b.goto(url)
            b.shot(out, full='--full' in args)
            print(json.dumps({'shot': out, 'console': b.console}, ensure_ascii=False))
        finally:
            b.close()
        return
    if cmd == 'script':
        url, steps_file, outdir = sys.argv[2], sys.argv[3], sys.argv[4]
        os.makedirs(outdir, exist_ok=True)
        steps = json.load(open(steps_file, encoding='utf-8'))
        w = int(os.environ.get('CDP_W', 1600))
        h = int(os.environ.get('CDP_H', 1000))
        b = Browser(w, h)
        rep = {'url': url, 'shots': [], 'checks': [], 'console': []}
        try:
            b.goto(url)
            for st in steps:
                if 'wait' in st:
                    time.sleep(float(st['wait']))
                if 'js' in st:
                    try:
                        b.eval(st['js'])
                    except Exception as e:
                        rep['checks'].append({'name': st.get('name', st['js'][:60]),
                                              'ok': False, 'err': str(e)})
                if 'expect' in st:
                    try:
                        v = b.eval(st['expect'])
                        rep['checks'].append({'name': st.get('name', st['expect'][:60]),
                                              'ok': bool(v), 'value': v})
                    except Exception as e:
                        rep['checks'].append({'name': st.get('name', st['expect'][:60]),
                                              'ok': False, 'err': str(e)})
                if 'shot' in st:
                    p = os.path.join(outdir, st['shot'] + '.png')
                    b.shot(p, full=st.get('full', False))
                    rep['shots'].append(p)
            rep['console'] = b.console
        finally:
            b.close()
        json.dump(rep, open(os.path.join(outdir, 'report.json'), 'w', encoding='utf-8'),
                  ensure_ascii=False, indent=1)
        bad = [c for c in rep['checks'] if not c['ok']]
        print(json.dumps({'shots': len(rep['shots']), 'checks': len(rep['checks']),
                          'failed': bad, 'console': rep['console']}, ensure_ascii=False, indent=1))
        sys.exit(1 if (bad or rep['console']) else 0)
    sys.exit('неизвестная команда: ' + cmd)


if __name__ == '__main__':
    main()
