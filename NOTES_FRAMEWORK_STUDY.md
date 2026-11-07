# NOTES — конспект чтения фреймворка vnc_work_v2-vm121-review-windows

Дата: 2026-11-06. Агент: только чтение, никаких действий.
Источник: `C:\Users\user\ssl-ops\vnc_work_v2-vm121-review-windows` (Windows-копия фреймворка).
Всего файлов: **220** (6 .md, 17 .py, 5 .sh, 27 .js, 144 .png/.jpg, 11 .txt, 2 .pyc, 1 .xml, 7 служебных .omx).

ВАЖНОЕ ПОНИМАНИЕ (подтверждено чтением + глобальное правило 04.11):
- Windows-копия — НЕ самостоятельный GUI-драйвер. Это: (1) доки обобщённого VNC+CDP-фреймворка,
  чьи рабочие скрипты живут в WSL (`/work/vnc_work_v2-vm121-review/`: vnc.sh, cdp.mjs, fetch_email_code.py);
  (2) Windows-нативный CDP-драйвер Edge (`cdp/edge_cdp.py`) + скрипты вокруг него (Selectel, catbox);
  (3) evidence-кадры прошлых задач (AnyDesk/RDP/1С/t400) и синтетические fixtures.
- RustDesk в папке НЕ автоматизирован (единственные упоминания — комментарии в fixtures/make_fixtures.py).

---

## 1. docs/ (5 документов)

### docs/README_vnc_work.md — главный README обобщённого VNC+CDP «руля»
- Архитектура WSL-стека: `SOCKS5(опц.) → Xvfb :98 → fluxbox → chromium(--remote-debugging-port=9334) → x11vnc :5901`.
  Агент «видит» через scrot по :98 (натив 1920×1080 → jpg → Read), «руки» — через CDP (cdp.mjs).
  Человек подключается TigerVNC → localhost:5901 (добивает SMS/капчу).
- Два канала рук: (1) CDP основной — click/clicksel/type/press/eval по селектору/тексту, без координат;
  (2) xdotool по координатам — запасной, только для не-DOM (всплывашки браузера, canvas, капчи).
- Команды `vnc.sh` (в WSL!): up [URL], go URL, shot label, text, find regex, click text, clicksel css,
  type css val, press Key, wait css, eval js, url, bbox css|text (НАТИВНЫЕ координаты центра элемента),
  xclick x y, xkey seq, paste text (clipboard+Ctrl+V через xclip), viewer/status/down.
  Продвинутые: tap '<text>' [имя] (scrollIntoView → zoom 0.8 если ниже фолда → CDP-мышь → проверка landed=true/false
  → показывает POST/PUT-ответ сервера), remember/recall/mem/forget (память координат coords_memory.json per-URL,
  локатор = текст+роль+тег), mclick, map.
- Env: VNC_DISPLAY VNC_PORT VNC_CDP VNC_PROFILE VNC_SCREENS VNC_SOCKS VNC_SCREEN. Параллельные задачи = разные наборы.
- Playbook: up → shot → Read → действие через CDP → shot+Read после каждого шага → eval/text извлечь → down.
- Грабли из README — см. раздел 6 ниже (координаты, «клик не сработал», AMBIGUOUS, RU-IP/SOCKS, профиль=сессия,
  песочница, scrot по :98, лимитные кабинеты, кириллица, viewport vs native ~120px, input.value vs innerText).

### docs/README_SELECTEL_MIGRATION.md — статус Selectel-миграции BT Dialer (02.11.2026)
- Скрипты selectel_*.py/wheel_once.py — рабочие инструменты сессии выбора роли vpc.admin в my.selectel.ru
  через Edge CDP порт :9222 (живой Edge владельца, профиль владельца).
- Итог сессии: серверы telephony-prod (12vCPU/24G/500G, 135.106.145.179) и crm-prod (8vCPU/48G/300G) ACTIVE в ru-6a;
  API-пользователь btdialer-api с ролью vpc.admin создан (UID dabe36e8...; пароль — у владельца,
  C:/Users/user/AppData/Local/Temp/cred_api.txt и /work/asterisk/CREDENTIALS.md).
- Статус скриптов: РАБОЧИЙ способ = `selectel_type_vpc.py` (впечатать «vpc» в поиск селекта доверенными клавишами →
  клик по узлу → дети). `selectel_atomic.py`/`selectel_wheel_flow.py` — атомарный замер+клик в одном WS.
  `selectel_final_vpc.py`/`selectel_wheel_flow.py` — черновики борьбы с дропдауном (НЕ финал).
  `selectel_scroll_vpc.py`, `selectel_check.py`, `selectel_wheel_noreply.py` — отладочные.

### docs/SELECTEL_PANEL_CDP_LESSONS_2026-11-02.md — чеклист граблей (читать ПЕРВЫМ перед UI-автоматизацией)
Полный чеклист в GATE.md (е). Ключевое: visibilityState/hasFocus ДО автоматизации; не убивать браузер владельца;
сброс body.zoom и Emulation-override; ant-select-dropdown искать по всему документу; родитель = раскрыть, роль = дети;
кликабелен весь treenode; виртуальный список перерисовывается — замер и клик атомарно; mouseWheel без ответа
(fire-and-forget); viewport=граница кликов; скрины CDP в 1.5× DPI; страница скроллится между действиями.
Рабочий рецепт: visible → mouseMoved+Pressed+Released по центру селекта → проверка загрузки (маркер «billing») →
найти узел (innerText.trim()==='vpc') → навести → СКРИН (подсветка = курсор на строке) → колесо → клик →
дети → клик роли → проверить поле → скрин → только потом «Сохранить».

### docs/REMOTE_EXEC_no_gui_sc_over_smb.md — запуск команд на Windows за NAT без GUI (sc.exe по SMB)
- Приём с SOCHI11 (T228): когда schtasks/RPC, WinRM, DCOM закрыты, но жив SMB 445 —
  `sc.exe \\<ip> create Kick binPath= "cmd /c C:\path\kick.cmd" type= own start= demand` → `sc.exe \\<ip> start Kick`
  (1053 «не ответила вовремя» — НОРМА) → `sc.exe \\<ip> delete Kick`.
- Условия: LocalAccountTokenFilterPolicy=1 + `net use \\<ip>\IPC$ /user:Admin <pw>`.
- 🔴 kick.cmd НЕ должен работать долго (SCM убьёт дерево через ~30с): он создаёт SYSTEM-задачу планировщика
  (schtasks /create ... /ru SYSTEM /rl HIGHEST + /run), она несёт долгую нагрузку.
- 🔴 Одноразовые задачи `/sc ONCE /st HH:MM` удалять после отработки, иначе выстрелят повторно в HH:MM.
- Доставка файлов: scp на машину-посредник (SERVER-1S, туннель 2248, хелперы srv1s_ps.sh/srv1s_scp.sh — В ПРОЕКТЕ,
  не в этой папке) → Copy-Item по SMB (\\<ip>\C$). Большой -EncodedCommand рвётся — файлом.
- Схема постоянного туннеля (reverse-SSH onboarding): пары ключей _me/_tunnel; _tunnel.pub в authorized_keys VPS
  178.253.55.128 с restrict,port-forwarding; задача SochiTunnel (SYSTEM, ONSTART, cmd-loop
  `ssh -N -R 0.0.0.0:2249:127.0.0.1:22`); хелперы loyalty/ops/sochi_ssh.sh/sochi_scp.sh (В ПРОЕКТЕ).
  Порты VPS 2243–2249 заняты, следующий свободный — 2250.
- ПОЛНАЯ инструкция: `/work/kso/docs/INSTRUCTION_openssh_tunnel_novaya_mashina.md` (в проекте KSO, не здесь).
- Грабли: sshd_config StrictModes внутрь Match-блока → sshd exit 1067 (глобальные директивы ВЫШЕ первого Match);
  icacls англ. именами молча падает на русской Windows — ACL по SID (*S-1-5-18, *S-1-5-32-544).

### docs/UPLOAD_catbox.md — залив на catbox.moe (обход «Invalid uploader»)
- catbox режет: не-браузерные клиенты (curl/Node/PS) → 412; Electron-UA (встроенный браузер ZCode) → 412; грязный IP → 412.
  Нужен настоящий Edge + чистый IP; практически один чистый IP = одна загрузка (потом смена узла v2rayN).
- Быстрый путь: `python catbox_upload.py "C:\файл.zip" --timeout 180` (сам поднимет Edge на изолированном профиле
  %TEMP%\catbox-edge-profile, порт 19446).
- Механика: CDP `DOM.setFileInputFiles` кладёт файл прямо в `input[type=file]` Dropzone (мимо системного диалога);
  результат в `.dz-preview` (успех = ссылка files.catbox.moe/XXX; «Invalid uploader» = сменить IP и `get` заново).
- Проверка: реальная скачка curl + zipfile testzip; HEAD может отдавать Content-Length: 0 — это нормально.
- Лимит 200 МБ (крупняк → litterbox, 72 ч). Имя архива ASCII. Второй пустой .dz-preview — косметика.

---

## 2. Корень

### catbox_upload.py — готовый скрипт залива на catbox (см. доку выше)
- CLI: `python catbox_upload.py FILE [--port 19446] [--timeout 180]`.
- Шаги: ensure_edge (если is_up() False — cmd_start) → get catbox.moe с --wait 'document.querySelector("input[type=file]")'
  → attach() + DOM.enable + DOM.getDocument + DOM.querySelector input[type=file] → DOM.setFileInputFiles →
  цикл опроса .dz-preview каждые 5с (URL_RE → «ГОТОВО: ссылка»; «Invalid uploader» → SystemExit с подсказкой смены IP).

### smoke_test.py — смоук-тесты edge_cdp.py
- ПИНирует себя на изолированные порт 19445 и профиль ...\ru-center-ssl-smoke\edge-profile
  (чтобы НИКОГДА не тронуть залогиненный профиль на 19444).
- 10 тестов: status до/после, start, /json/list, screenshot в C:\Users\user\ssl-ops\smoke_results\,
  навигация example.com, Runtime.evaluate document.title, Input.dispatchMouseEvent mouseMoved(10,10), stop, verify.
- Паттерн импорта: sys.path.insert(0, <repo>/cdp); from edge_cdp import ...

### RDPLauncher.backup.xml — бэкап задачи планировщика Windows
- `\RDPLauncher`, InteractiveToken, HighestAvailable, TimeTrigger 23:59 →
  `mstsc /v:10.8.0.29:3389` (RDP-клиент на адрес 10.8.0.x — VPN-сеть; сам RDP-канал фреймворком не автоматизируется).

### Изображения корня (см. раздел 5).

---

## 3. cdp/ — Windows-нативный CDP-драйвер и Selectel-сессия

### cdp/edge_cdp.py — ЯДРО: Windows-нативный CDP-драйвер Microsoft Edge (изолированный профиль)
- CLI:
  - `python edge_cdp.py start [--port 19444] [--profile-dir PATH]` — запуск Edge с флагами
    --user-data-dir, --remote-debugging-port, --remote-allow-origins=*, --no-first-run, --window-size=1400,1200,
    --lang=ru-RU, about:blank; DETACHED_PROCESS; ждёт /json/version до 30с.
  - `status` — печатает UP/DOWN. 🔴 rc всегда 0 — в скриптах проверять is_up(), не returncode.
  - `get URL [--js EXPR_OR_FILE] [--wait PRED] [--waitms N] [--settle ms] [--out FILE] [--nonav] [--click X,Y]`
    — навигация (Page.navigate), клики (Input.dispatchMouseEvent mousePressed/Released по clickCount),
    ожидание предиката (поллинг !!pred каждые 0.5с; дефолт readyState+body>200 символов), затем eval выражения
    (дефолт outerHTML) в stdout или --out. Network.setExtraHTTPHeaders Accept-Language ru-RU.
  - `eval --js EXPR_OR_FILE` (с --nonav), `click X,Y [--clicks N] [--btn left|right]`.
  - `screenshot [--out FILE]` — Page.captureScreenshot PNG; дефолт C:\Users\user\ssl-ops\screenshot.png.
  - `cookies [--url URL]` — Network.getCookies → «name=value; ...».
  - `stop` — wmic по ProcessId,CommandLine; убивает ТОЛЬКО процессы своего профиля (строка PROFILE в командной строке)
    + terminate по remote-debugging-port=ПОРТ. (Не трогает чужие Edge.)
  - `ru-center-login [--creds PATH] [--out-dir DIR]` — вход в nic.ru по DPAPI-шифрованным кредам
    (CryptUnprotectData CurrentUser), заполнение форм через JS (focus+value+Event input), submit,
    классификация результата (SUCCESS/BLOCKED:CAPTCHA/MFA/ACCOUNT/ERROR), сохранение HTML и RU_LOGIN_STATUS.txt.
- Env: EDGE_CDP_PORT (19444), EDGE_CDP_PROFILE (...\ClawSecureTasks\ru-center-ssl\edge-profile),
  EDGE_CDP_BINARY, EDGE_CDP_UA.
- Внутренности: класс RawWS — сырой WebSocket на сокете БЕЗ заголовка Origin (обходит 403 CDP origin-check);
  класс CDP (call/evaluate с returnByValue, awaitPromise, timeout 30с); http_json (/json/version, /json/list);
  attach() → CDP первого page-таргета; find_edge() перебирает пути x86/x64.
- Python API для импорта: attach(), is_up(), cmd_start(), cmd_stop(), CDP(ws_url) — так его используют
  catbox_upload.py, nclick.py и все selectel_*.py.

### cdp/nclick.py — НАТИВНЫЙ OS-клик по позиции элемента страницы (настоящий жест мыши)
- CLI: `python nclick.py --js "<js -> [x,y] CSS px>"` или `--xy 100,200` (raw viewport CSS).
- Механика: берёт window.devicePixelRatio/innerWidth/innerHeight (page-CDP) → Browser.getWindowForTarget
  (browser-level WS /json/version) → bounds окна; если окно не normal/maximized — сначала normal;
  пересчёт: content_top = top + (height - inner*dpr); screen = content_left + css*dpr →
  PowerShell Add-Type user32: SetCursorPos(x,y) → mouse_event(2)/(4) (down/up). Печатает «clicked X,Y».
- Зачем: браузер видит настоящий пользовательский жест (попапы разрешаются, капчи довольны).

### cdp/selectel_type_vpc.py — РАБОЧИЙ способ выбора роли vpc (02.11)
Escape-закрыть залипшее → клик по div.ant-select-selector (scrollIntoView center + свежий rect центр) →
type_text('vpc') посимвольно Input.dispatchKeyEvent (keyDown/keyUp по 60мс) → найти узел (innerText.trim()==='vpc',
кликабельный предок .ant-select-tree-treenode) → клик → проверка «Роль\n(...)» в body.innerText → заполнение полей
через native setter value + Event('input') (React-совместимо).

### cdp/selectel_atomic.py — атомарный замер+клик в ОДНОМ WS-соединении
Навигация на /iam/service-users/new → заполнение полей → до 6 попыток: открыть дропдаун реальной мышью →
state-проба (NO_DD/NO_VPC/OK) → NO_VPC = колесо deltaY 250 ниже центра; не-OK = Escape+переоткрыть;
OK = клик НЕМЕДЛЕННО (список не успел перерисоваться) → ROLE_NOW → SUCCESS → заполнить поля →
скрин jpeg в %TEMP%\sel_created.jpg ДО нажатия «Добавить пользователя».

### cdp/selectel_check.py, selectel_scroll_vpc.py, selectel_wheel_noreply.py, wheel_once.py — отладочные скроллеры
- wheel_once.py [DELTA=250] — одно доверенное колесо по центру открытого дропдауна (mouseMoved + mouseWheel).
- selectel_check.py — цикл: проверка видимости vpc (rect внутри границ дропдауна) → клик / колесо внутри.
- selectel_scroll_vpc.py — scrollTop внутреннего скролл-контейнера дропдауна (overflow auto/scroll,
  scrollHeight>clientHeight+10) += 200 → клик при 100<=y<=820.
- selectel_wheel_noreply.py — как check, но mouseWheel отправляется fire-and-forget
  (ws.send с id+1000, БЕЗ ожидания ответа — у события его нет, cdp.call() таймаутит).

### cdp/selectel_final_vpc.py — черновик-финал (Emulation.setDeviceMetricsOverride 1432x1150)
Расширение виртуального viewport, click helper, dd_finder, выбор первой дочерней роли (kids[0]),
скрин sel_role_selected.jpg. Не финал (борьба с дропдауном), но полезные приёмы.

### cdp/selectel_step_expand.py — открыть дропдаун, впечатать vpc, РАСКРЫТЬ узел, показать детей (+скрин sel_expanded.jpg).
### cdp/grid_scroll_vpc.py — координатная сетка 1:1 (скрин=viewport): move/wheel/click по центру списка,
скрины grid_*.jpg на каждом шаге.
### cdp/selectel_diag_roles.py — диагностика: performance.clearResourceTimings → Escape → клик по селекту →
что в дропдауне + какие fetch/XHR ушли (getEntriesByType('resource')).

### cdp/selectel_role_retry.sh / v2 / v3 / v4 + find_vpc.sh — бэш-обвязки вокруг edge_cdp.py CLI
(для WSL/GitBash, cd в /c/Users/.../cdp, export EDGE_CDP_PORT=9222):
- retry: цикл 6 попыток открыть дропдаун (eval центр селекта → click X,Y) → state (NO_DD/LOADED/VPC=x,y) → клик.
- v2: + scrollIntoView дропдаун-листа, WheelEvent на list-holder, повторный замер.
- v3: синхронный JS (фреймворк не ждёт Promise) — async-функции в eval НЕ работают, убраны.
- v4: клик по центру ВСЕГО tree-node (closest('.ant-select-tree-treenode')), не текстового ребёнка.
- find_vpc.sh: цикл 12: eval-проверка → VPC_XY=x,y при y<=820 → click → ROLE_NOW → иначе wheel_once.py 300.
Эволюция показывает грабли: .cdk-overlay-container НЕ годится (дропдаун не там), Promise не ждётся, клик по span мажет.

### cdp/js/ — 27 JS-сниппетов для `edge_cdp.py eval --js` / get --js (файл подставляется автоматически load_js)
Инспекция страницы:
- pagetext.js — URL+TITLE+текст (3000) + все input(type,name,ph) + кликабельные (60).
- pagetext_lin.js — компактный лин (=light?) вариант для длинных страниц.
- links.js — все a[href] без javascript:/#, дедуп, текст -> href.
- form_dump.js — все select (с options) и input/button с name/id/value.
- ua.js — navigator.userAgent; cookies.js — document.cookie.
Специфика АТОЛ-файлоархива (SharePoint-like, __doPostBack):
- q.js / s_fw.js / click_search.js / reset.js / search_25f.js — поиск в FileArchiveFilter
  (впечатать в txtDescr → btn.click() через setTimeout 300мс — DEFERRED, иначе перезагрузка страницы убьёт
  контекст и CDP вернёт EVAL=NULL); search_25f — выбор модели «АТОЛ 25Ф» в drdModel.
- set_brand.js / set_cat.js / set_cat_kkt.js — выбор option в select (drdBrand='АТОЛ', drdCategory='Контрольно')
  + __doPostBack(name) отложенно; кириллица в \uXXXX чтобы кодировка не побила файл.
- paging.js — пейджинг (a[href*=Page$], __doPostBack, .ms-paging) + счётчик FileHandler.ashx ссылок.
- results_rows.js / results_text.js — строки таблицы результатов (guid= из href + текст) / текст фильтра.
- r_docs.js / r_row2.js / r_row6290.js / r_water.js — сгенерированные mk_rect.py зонды: найти элементы по тексту
  («Документы», id строки, «6290», a[href*=water.crpt.ru]) → (опц. scrollIntoView) → координаты центра rect
  + vis= внутри viewport — ДЛЯ ДОВЕРЕННОГО КЛИКА.
- head_driver.js / range_probe.js / zip_drv.js — fetch с credentials:include на FileHandler.ashx:
  статус/финальный URL/заголовки; HTTP Range (206, content-range, размер); ПОЛНЫЙ парсинг ZIP central directory
  в браузере (EOCD 0x06054b50, CD 0x02014b50, UTF-8/CP866 имена, до 4000 записей) — листинг архива без скачивания.
- sp_lists.js — SharePoint REST /_api/web/lists (Title/ItemCount/RootFolder).
- grid_rows.js — Vaadin grid → TSV: текст в LIGHT-DOM vaadin-grid-cell-content (в shadow DOM только slot'ы);
  заголовок задаёт число колонок; выброшенные из буфера строки ОТСУТСТВУЮТ — сначала пейджинг/скролл.
- shoplist_lin.js — карточки магазинов: от a[href*=product] подниматься по родителям до ₽/руб (цена выше ссылки);
  T198 (сканеры отпечатков).

---

## 4. fixtures/ + .omx/

### fixtures/make_fixtures.py — генератор ДЕТЕРМИНИРОВАННЫХ локальных тест-картинок (OpenCV, без сети)
Синтетический «удалённый рабочий стол» 1280×800 с реальными режимами отказов фреймворка:
- scene_before/after.png — киоск-десктоп: тулбар AnyDesk/RustDesk 40px сверху (ИСТОЧНИК СДВИГА),
  якорь-угол (0,0)+toolbar, зелёная кнопка «Оплата» с ИЗВЕСТНЫМ центром (ground truth), после нажатия —
  диалог «Podtverdite»; scene_black.png — мёртвый кадр (классификатор DEAD); scene_banner.png — «Connection Closed».
- tmpl_pay/anchor/banner.png — шаблоны для template matching.
- ground_truth.json: size, toolbar_h=40, pay_box [520,470,240,70], pay_center [640,505], anchor [0,40,46,46].
Смысл: тесты пиксельной математики (сдвиг на тулбар, поиск кнопки, детект разрыва) без живой машины.
(+ 8 png-фикстур, перечислены в ground_truth.)

### .omx/ — состояние оркестратора oh-my-codex (НЕ инструмент фреймворка)
- state/session.json: сессия omx-1789738057740-p971sl, 2026-09-18, cwd = эта папка, win32.
- state/sessions/.../AGENTS.md — шаблонный контракт OMX (автономность, делегирование, роли, model routing,
  verification, state_management). Относится к оркестратору, не к VNC-инструментам.
- metrics.json / update-check.json / logs/*.jsonl (855 байт, только session_start/end) — служебное.
- state/sessions/omx-1789737897270-o9bsru — пустая директория.

### cdp/__pycache__/edge_cdp.cpython-312/313.pyc — байткод-кэши edge_cdp.py (бинарные, дубликаты исходника; не читались).

---

## 5. Изображения (144 шт) — evidence прошлых сессий

Просмотрено лично через vision-канал 3 ключевых кадра (Read в этой среде отдаёт только CDN-URL, поэтому
канал = nodeRepl.emitImage + vision-модель; см. правила владельца 8–12):
1. anydesk_fresh.png (18.09 14:50) — ПРОСМОТРЕНО: главное окно AnyDesk «Новое соединение», поле «Введите
   удалённый адрес», «Это рабочее место» ID **1 336 347 805** (красным), кнопка «Пригласить», вкладки
   Новости/Избранные/Недавние, панели новостей AnyDesk 9. Это ЛОКАЛЬНЫЙ AnyDesk владельца.
2. native_anydesk_auth.png (18.09 14:35) — ПРОСМОТРЕНО: ВОПРЕКИ ИМЕНИ показывает НЕ AnyDesk-диалог, а терминал
   «✳ Прочитать workflow Asterisk проекта» с командами /status («Settings dialog dismissed»), ручной режим.
   → ГРАБЛИ: имя файла ≠ содержимое, смотреть кадр обязательно.
3. t400_srv1s_desktop.png (18.09 17:18) — ПРОСМОТРЕНО: развёрнутое окно консоли (C:\WINDOWS\System32\Wind...),
   пустое, каретка; таскбар: Start/Search/TaskView/активный терминал/«...», трей ENG, батарея-с-питанием,
   часы 17:57 18.09.2026. 1С-интерфейса в кадре НЕТ (имя файла обещало «desktop» сервера).

Остальные 141 кадр индивидуально НЕ просматривались (каталог по префиксам имён, содержание по именам НЕ утверждаю):
- native_anydesk_*.{png + .txt×11} (18.09 14:33–14:50, 19 png + 13 файлов) — последовательность нативной
  AnyDesk-автоматизации: start → focus → auth → typed/typed2 → checkbox → checkbox_postmsg(+check) →
  aftercheckbox_check → afterenter → connect_resume → after_enter_resume → resume → postauth → connecting2;
  сопроводительные .txt — дампы окон (SHOT=время SIZE=2160x1440/1440x960 FOCUSED + список заголовков WIN;
  среди окон всегда «1 397 277 972 - AnyDesk» — ID удалённой машины, PowerShell-окна, v2rayN, Edge/Telegram).
  Инструмент, делавший эти скрины+дампы, в папке ОТСУТСТВУЕТ (судя по формату .txt — PowerShell-перечислитель окон).
- srv1s_* (17 шт, .jpg/.png, 18.09) — RDP-сессия на SERVER-1S (mstsc): bootwait/retry×3/connect/auth_attempt2/
  bg_connect/connect_now/image_wait/wait2/session/topbar/emerg_prev/after_auth/after_wake/after_cancel/after_fullrestart.
- t400_* (~100 шт, 18.09) — задача T400 на 1С-конфигураторе через удалённый десктоп: меню Файл/Действия/Текст/
  Расширения/Конфигурация, дерево модулей (Общие/HTTP-сервис), диалоги паролей (contract/http/protection:
  pwd_dialog → pwd_filled → pwd_applied → verify_prompt), F10/Enter, поиск, zoom-кропы (password_crop),
  anydesk-кадры задачи (foreground/blackcheck/status2002/2003/retry×3/resume_now/wait_now), закрытие окон.
- oobe_tabs_contact.png, desktop_restored.png, uac_reset.png — одиночные кадры (OOBE-вкладка, восстановленный
  рабочий стол, UAC-сброс; не просмотрены).
- fixtures/*.png — 8 синтетических фикстур (описаны исходником make_fixtures.py, содержимое известно из кода).

---

## 6. Сводка граблей (всё, что задокументировано; полная выписка — в GATE.md)

Из README_vnc_work (WSL-стек):
1. Не угадывать координаты по скрину (Read рендерит в другом масштабе) — клик через CDP по селектору/тексту;
   координаты только из bbox (нативные пиксели через screenX/Y + (outerHeight-innerHeight)).
2. «Клик не сработал» — сначала СКРИН, не URL/сеть: SPA-модалки на том же URL без POST/PUT; проверка
   elementFromPoint(x,y).
3. find/tap/click ранжируют кандидатов; неоднозначность → AMBIGUOUS без клика → уточнять clicksel/CDP_FORCE=1.
4. Токены/статусы читать eval/text, не «вглядыванием» в jpg (l/I/1, O/0).
5. Всплывашки браузера не в DOM → prefs подавляют (password_manager_enabled=false и т.д.), остаточные — xkey Escape.
6. RU-IP — свой SOCKS5 (VNC_SOCKS), фреймворк туннель не поднимает.
7. Сессия живёт в профиле (VNC_PROFILE) — бэкап профиля = бэкап сессии; капчу проходишь один раз.
8. Песочница Bash убивает длинные процессы (сигнал 16) — dangerouslyDisableSandbox для стека/SOCKS/sleep.
9. scrot по :98, не по WSLg :0 (чёрный кадр).
10. Лимитные кабинеты (1С Fresh = 1 сеанс) — всегда down/logout.
11. Кириллица: CDP type и paste (xclip) ок; голый xdotool type ломает.
12. Координаты — VIEWPORT через CDP-мышь (tap/mclick); нативный клик мажет на ~120px (хром-оффсет);
    кнопки ниже фолда — zoom 0.8; map помечает ⬇below-fold.
13. Поля проверять по input.value, не по innerText.

Из Selectel-lessons (02.11):
14. visibilityState==='visible' + hasFocus() — ПЕРВАЯ проверка (свёрнутое окно = дропдауны не открываются; час потерь).
15. НЕ убивать браузер владельца ради CDP-порта (убита 2FA-сессия Selectel — правило OWNER_BROWSER_NO_KILL).
16. Сбрасывать body.style.zoom и Emulation.setDeviceMetricsOverride — артефакты сдвигают ВСЕ координаты.
17. ant-select-dropdown искать по всему документу с offsetParent, не в .cdk-overlay-container.
18. «Не найдено» в дереве — Escape и переоткрыть (новый запрос), не долбить кликами; маркер загрузки.
19. Клик по родителю-продукту = раскрыть; роль — в ДЕТЯХ.
20. Кликабелен весь .ant-select-tree-treenode (центр его rect), не span с текстом.
21. Виртуальный список перерисовывается — замер и клик атомарно в одном WS-соединении.
22. Input.dispatchMouseEvent mouseWheel НЕ имеет ответа — fire-and-forget (ws.send), cdp.call() таймаутит.
23. Viewport = граница кликов (y>innerHeight в никуда): zoom 0.8 / скролл внутреннего контейнера / Emulation.
24. CDP-скрины в 1.5× (Windows DPI): координаты со скрина ×1.5 ≠ viewport; брать getBoundingClientRect.
25. Страница скроллится между действиями: scrollIntoView → замер → клик БЕЗ промежуточных скроллов.
26. (из .sh-эволюции) фреймворковый eval НЕ ждёт async/Promise — синхронный JS.

Из catbox:
27. «Invalid uploader» = грязный IP (один IP ≈ одна загрузка, смена v2rayN); Electron/IAB-браузер ZCode не годится.
28. edge_cdp.py status всегда rc=0 — проверять is_up().
29. Лимит 200 МБ; HEAD Content-Length: 0 — норм, проверять реальной скачкой; ASCII-имя архива;
    второй пустой .dz-preview — косметика.

Из REMOTE_EXEC:
30. sc.exe start → 1053 — НОРМА; kick.cmd не работать >30с (SCM убьёт) — порождать SYSTEM-schtasks;
    одноразки /sc ONCE удалять; LocalAccountTokenFilterPolicy=1; длинный -EncodedCommand рвётся — файлом;
    sshd_config: глобальные директивы ВЫШЕ Match (иначе exit 1067); icacls по SID на русской Windows.

Из js-комментариев:
31. Перезагрузка страницы убивает контекст JS: постбэки/клики, ведущие к reload, — через setTimeout (deferred),
    иначе CDP EVAL=NULL.
32. Кириллицу в .js-файлах возить \uXXXX-эскейпами.
33. Vaadin: текст в light-DOM cell-content; строки вне буфера отсутствуют.

Моё наблюдение при просмотре кадров:
34. Имя evidence-файла ≠ содержимому (native_anydesk_auth.png = терминал; t400_srv1s_desktop.png = пустая консоль)
    — перед любым выводом по кадру смотреть его, а не имя.

Пароли в исходниках: selectel-скрипты содержат логин/пароль сервисного пользователя (btdialer-api) —
владельцу уже сдан (README_SELECTEL_MIGRATION), но помнить при передаче папки.

---
---

# WSL-фреймворк — /work/vnc_work_v2-vm121-review (Ubuntu-24.04)

Прочитано целиком 2026-11-07 (~330 файлов-источников + helpers_neproshity 212; исключены .git,
.beget_vnc_profile (профиль браузера), screens/). Итоговая выписка — GATE.md, раздел «WSL-фреймворк».

## Доки верхнего уровня
- README.md — v2 «надёжный таргетинг»:.template-match (vmatch) = 0 LLM; haiku-глаз по кропу-линейке (veye
  crop --grid/deproject); verify-after-every-action; calibrate оффсет панели; reconnect RustDesk-first;
  модалки 1С (rc.sh modal*) с hit-тестом и запасным входом горячей клавишей. rc.sh DRY-RUN по умолчанию.
- FIELD_NOTES.md — 9+ полевых открытий и граблей (см. GATE (е)); ключевые: клик-фокус для клавиатуры;
  кириллица только буфером; калибровка haiku (узкий кроп, мелкая сетка); livecheck (classify врёт);
  srvshot (кадр с самой машины; сессия 0 = чёрный); JS-антибот (curl = заглушка 13602); Vaadin/iframe;
  ЭЦП attached; rps.sh (UTF-8 наверх); PS-гочи ($h/$H, алиас H); stale-frame (T175) и контракт shotlib;
  нативные пиксели координат; 1c-modal-windows (3 причины «кнопка не нажимается»); T251 (--via x мажет
  на вложенных окнах — CDP-клик первичен; расширение с ошибкой компиляции не применяется молча);
  redroid/uiautomator (FLAG_SECURE: screencap 0 байт, uiautomator видит; анимация = idle state fail);
  OCR-каналы для цветных плашек; connect.sh RD_DISPLAY; T382 — матрица 4 способов ввода (итог: буфер).
- VNC_LAUNCH.md — TL;DR подъёма :98 + ГЛАВНОЕ про окно вьювера на WSLg :0 (только tmux-сессия от root;
  env -i от hgff не стартует; запасной — Windows-TigerVNC localhost:5901); персистентность VNC_PROFILE в /work.
- IMPROVEMENTS.md — P0-P2: всё на CDP; долгоживущий CDP-демон (cdpd.mjs — НЕ реализовано); flow-файлы;
  Network-перехват; gridshot; SMS-хендофф; чего НЕ автоматизировать (SMS/ЭДО/юр-согласия/банк).
- VM121-CLAW-START.md + SECOND-LLM-SRV2-HANDOFF-20260606.md + VM121-*.cmd/sh — вторая LLM (VM121@gemma4
  260k ctx на srv1 GPU2 через RPC srv2; jump 217.144.184.51 → srv1 134.0.107.8:234 → 192.168.87.33;
  не трогать srv1:8080; burn-in 6-8ч). К VNC-инструментарию отношения не имеет — лежит в папке.
- docs/VPS_BROWSER_NOVNC.md — noVNC-хендофф владельцу (x11vnc 5907 + websockify 6087 на VPS + SSH-туннель
  в tmux + ссылка 127.0.0.1:6087/vnc.html; проверка слоями 200/101/RFB; WAITING_OWNER_2FA; не down-ить
  сессию по своей воле).

## Ядро
- vnc.sh (171 стр.) — диспетчер стека :98 и CDP-руки (см. GATE (а)); viewer в tmux; front/closetab; upload
  (uploadFile + лог сети 4с); координатные правила в шапке (viewport vs native ~120px, zoom 0.8 ниже фолда).
- cdp.mjs (445) — все команды CDP-движка; guard decideTarget (AMBIGUOUS + score-ранжирование: точное>граница
  слова>startsWith, бонус button/tab, штраф cross-origin -30); tap: сетевой слушатель ДО клика, landed-чек
  через once-listener, memory-record; bbox: nx=sx+(ow-iw)/2+x*dpr, ny=sy+(oh-ih)+y*dpr; map помечает ⬇below-fold.
- rc.sh (584) — полный пиксельный драйвер; X() с LC_ALL=C.UTF-8 (T382); _shot_to с RC_SHOT_CMD (плагинный
  бэкенд съёмки); _scene_guard (STALE_SCENE 30 мин); лейбл = имя кадра (T311); field-left (якорь-эталон +
  PIL-кроп слева, порог 140, ×6, psm 7); clean (attic, эталоны/git/.keepframes); livecheck (2 бага-фикса:
  set -u на RC_DISPLAY и «слепой детектор ≠ всё хорошо»); modal* → lib/modal1c.py; reconnect делегирует
  connect.sh/anydesk_kso.sh (не дублирует).
- lib/vmatch.py — find (7 масштабов+CLAHE+ORB fallback+edges опция), verify (diff>18/255, min_change),
  calibrate; scene_age в каждом ответе. lib/veye.py — crop/grid (подписи РЕАЛЬНЫХ пикселей, halo), deproject,
  roi, ocr (crop+scale+обратный пересчёт), text (полный OCR; каналы b/g/r; промежуточный скан в /tmp!).
  lib/reconnect.py — classify (mean≤16=black; sd<0.03=black; banner по шаблону), backoff (LCG-jitter),
  plan (rustdesk/connect.sh <RD_ID> → anydesk_kso.sh id <AD_ID>, AnyDesk помечен «5-min throttle»).
  lib/modal1c.py — JS_SCAN (hitPoint 5×5, hotkey из submenuBlock, focus_point, enc_id форм), probe_scan
  (одноразовый сокет, BUSY), wait_verdict (3 исхода), xdo_hotkey (Ctrl+Enter→ctrl+Return), send_hotkey
  (битовая маска modifiers), cmd_fill (keyDown посимвольно + Ctrl+A + async-редактор 1.2с).
- lib/cdp_target.cjs — selectPage по CDP_TARGET_ID (fail-closed), evaluateJS (eval в странице).
- shotlib.sh — контракт съёмки (см. GATE грабля 7): shot_guarded/shot_where/shot_clean.

## Каналы удалённых десктопов
- rustdesk/README.md — СЕРВЕР СВОЙ: VPS 178.253.55.128, key OS6FFMq66QzmnraQDy+cy+fdryWDXA0fBVZTbYqc7Lk=;
  машины: касса 243540605 (DESKTOP-E8FF2LU, 2 конфига: служебный боевой LocalService; 4 процесса = норма;
  sc failure настроен), КСО2 288860502, КСО3 288860680, сервер 239677631, SERVER-1S 262446554, ЭЦП/ОФД
  474932946 (portable!), ZennoLab 2512413 (кнопка); «Remote desktop is offline» врёт; клиент протухает;
  grep update_pk НЕ работает (debug-уровень); Win не пробрасывается.
- rustdesk/connect.sh — подъём :99+коннект (RD_DISPLAY/RD_PORT; сам снимает кадр через shotlib).
- rustdesk/x99.sh — click/dbl/type/key/shot/zoom/where/wins (X99_DISPLAY/X99_SCREENS для проверки офлайн).
- rustdesk/rd_health.sh — check/up/refresh/down/status/prune; flock от двойного запуска; kill_client
  (pkill -x + connect.sh-обёртки по шаблону без self-match); SERVER=RD_SERVER (дефолт 217.144.184.51!).
- rustdesk/server_install.sh — воспроизводимая установка hbbs/hbbr (systemd, /var/lib/rustdesk-server,
  печатает PUBLIC KEY id_ed25519.pub).
- rustdesk/onboard_new_machine.ps1 — конфиг в ОБА пути + --password + sc failure + --get-id.
- rustdesk/rd_boot.ps1 — портативный бутстрап с зеркала http://178.253.55.128/rustdesk-1.4.8-…exe;
  рапорт ID двумя путями (hbbs db_v2.sqlite3 + http://178/rdid/<id> в nginx-лог).
- rustdesk/ONBOARD_via_anydesk.md — ПОЛНЫЙ протокол: 3 ограничения AnyDesk; буфер+iex(get-clipboard);
  runas -encodedcommand; §8 одностраничный боевой путь; §9 порядок первого запуска (конфиг→exe→Установить→
  админ-команды→приёмка слепым переподключением); §9.1 пароль (админ!; pw_set-проверка; одинарные кавычки;
  без кириллицы); §10 постоянный админ без UAC (KSO2Admin; служебный AnyDesk кликает UAC — SOCHI11;
  порядок диагностики перед «нужен человек»; открытые грабли 10.4: путь служебного конфига и молчащий
  --password); §11 SOCHI11 итог: SMB+sc.exe (LATFP=1).
- rustdesk_kso.sh — легаси up/verify (motion>2000px ИЛИ sd>0.03).
- anydesk_kso.sh (:99/5902, PULSE_SERVER=WSLg, kill_on_display по environ, down не трогает :98 и службу);
  anydesk_kso_hgff.sh (для hgff; RD_CLIP_SYNC; _focus по RD_ID/Remote Desktop/RustDesk; drag; scroll 4/5/6/7).
- profiles/ — снапшот конфигов + restore_profiles.sh (check/hgff/root); peers-карта машин.

## Съёмка/ввод/файлы (касса №1 и не только)
- shot1.sh (KSOCapture, возраст по часам кассы, MAX_AGE 120с, SHOT1_SSH/SCP переопределяемы для оффлайн-теста);
  srvshot/ (shot_run.ps1: RUNAS авто-детект по explorer.exe; скрытый PS не .bat; SHOT=<байты> TIME=; локальный
  и удалённый артефакты сносятся ДО); kso_capture_screen.ps1 упоминается на кассе.
- clip_paste.sh (WIN_MATCH 'Remote Desktop|RustDesk|AnyDesk' по площади, SYNC_MS 700, --replace/--enter/--set-only);
  type_exact.sh (SPECIAL таблица; shift-даун/ключ/shift-ап; keyup shift перед без-shift; печать только sha256).
- push_clip.sh (SYNC авто=3+b64/8000, ретрай с удвоением; reader c2f.ps1; вердикт sha+len из c2f.out);
  zput/zget (тип читателя, SYNC=3+b64/6000); zd/zdget/zdput (демон ksod.ps1, KSOCMD/KSORES, ksod.alive);
  zq (cash_runner.ps1: C:\kso\q, #EOJ-сентинел, .job→.run→.done, JDONE_id в буфер, truncate 120k);
  zrun (UTF-8 BOM обязателен); ztx/zx (Set-Clipboard за NONCE; zx: drain ctrl+c×2+Escape+Return, SETTLE 2.5с, TRIES 2).
- rps.sh + rps_run.ps1 (UTF-8 файл; BOM; Out-String -Stream; САМО-УДАЛЕНИЕ скрипта в finally; cleanup_remote
  с ПРОВЕРКОЙ LEFT/GONE); rps_paste.sh (вставка обёртки & { NONCE; cmd } | clip; НЕ ctrl+c перед вставкой
  пейлоада; РМК-киоск ворует фокус → topmost_console + клик в тело).
- s1run.sh (KSOS1 Interactive); eznav/ezxy (UIA EasySet по /tmp/ez_nav.ps1|ez_xy.ps1, возраст uia.txt<7с);
  kso_layout.sh + t09_layout.ps1 (LoadKeyboardLayout 00000409; WM_INPUTLANGCHANGEREQUEST; Tap с US-сканкодом;
  ~GS~ = Ctrl+OEM_6 под EN); kiosk_reveal.sh (Win+D; геометрия таскбара киоска; focus-cmd после превью).
- topmost_console.ps1 (HWND_TOPMOST, dot-source!); c2f.ps1; ksod.ps1; cash_runner.ps1; t09_layout.ps1.

## SSH-каналы (jump 217.144.184.51)
kso(2243, sco_m210)/srv(2244, 'Админ')/ofd(2245, User)/kso2(2246, M210)/kso3(2247, M210; UUID-различение)/
srv1s(2248, User; +rdp: xfreerdp3, /p из env, +clipboard, down→quser+logoff отдельно)/
srvold (ProxyCommand -W через SERVER-1S)/kso_lan (через 1С-сервер на 192.168.0.186)/srv1s_lan (через КСО3
на 192.168.0.10; LPORT 12248; T299: прямой 2248 внезапно отбивал ключ при живой машине)/statkassa_lan
(через КСО3 на РМК; LPORT 12250; юзер «днс»; 81МБ по 2250 рвётся).
*_ps.sh — EncodedCommand UTF-16LE + фильтр CLIXML; *_scp.sh — алиасы (kso:), forward-slash пути.
ssh_channel/: ключи <маш>_me/<маш>_tunnel(.pub), known_hosts_*, kso2_win.creds, jump194(.pub);
установщики: cash/ssh_setup.ps1 (OpenSSH cap+GitHub-fallback, key-only, KSOTunnel SYSTEM) + kso_tunnel.ps1
(watchdog -R 2243 → root@178.253.55.128, реконнект 10с); srv/srv_setup(_v2,_v3).ps1 (2244; bootstrap-blob
в paste.rs); fixperm.ps1.
ВАЖНО: watchdog-и тянутся к 178.253.55.128, а хелперы /work — к 217.144.184.51 (KSO_VPS_HOST): в доках ДЖАМП
менялся; при диагностике туннеля сверять оба адреса.

## cdp/ (текстовый браузер)
cdp_linux.py (std-lib RFC6455; wait-предикат «не заглушка qrator/__jhash_/ddos-guard»; выход 4=TIMEOUT);
cdp_up.sh/cdp_start.ps1 (schtasks-детач; кандидаты Chrome ×3); cdpq.sh (env-ручки; -NoNav без -Url;
CDP_REMOTE_JS); cdpnet.sh/cdp_net.ps1 (Network domain, тела по фильтру); mk_rect (–scroll!), mk_setselect,
mk_textsearch, mk_zipindex (EOCD/CD парсер, cp866); w1c.py (FIND_JS «самый мелкий элемент»; mouse-серия
mouseover/down/up; dialog; waittext; ui-разбор командного интерфейса) + w1c_up.sh (туннель 9180→IIS 80,
Xvfb :99, chromium 9333, вход по ОтрошенкоЛВ из CREDENTIALS.md, W1C_START); local_page.py (file://, report.json).
cdp/README — 13+8 гочей (см. GATE (е) 40-44).

## Прочее
fetch_email_code.py (IMAP; игнор 000000/hex); kso_probe.sh (JScript COM V83 32-bit; probe_exch_state.js —
пример с Pwd= в тексте!); kso_kiosk.sh; kso_app_backup.* (канал выбирает кассу; excludes); find_site.py /
e2e_validation.py / stress_test_vmatch.py / test_real_site.py (playwright-хвосты: подбор сложной сцены,
e2e vmatch, стрес-тест искажений); diadoc_submit.mjs (Diadoc-форма через CDP-мышь+сеть); coords_memory.json;
.gitignore (ssh_channel/, profiles/, screens*/, t[0-9][0-9][0-9]_*.png, *_crop*, *_grid); examples/1c-vnc
(обезличенные шаблоны; IC_URL/IC_USERNAME/IC_PASSWORD env); test/run_tests.sh (RC_SHOT_CMD-инъекция кадров
для офлайн-click-template!) + test_core.py (14 тестов); templates/ (1c_web_modal_ok/otmena + loyalty_app 8 шт).
helpers_neproshity/ (212): kling_*/gen_*/suno_*/p_*.txt/fix_* — черновики видео-музыкальных задач; CDP-утилиты
(trusted_click/raw_cdp/cdp_tool/netlib — websocket-client :9223, suppress_origin) — фреймворком не используются.

## Моё наблюдение
Расхождение VPS в доках (217.144.184.51 vs 178.253.55.128) — единственное место, где фреймворк внутренне
противоречив; всё остальное согласовано. RustDesk-сервер точно на 178 (README/profiles/rd_boot), jump-туннели
в свежих хелперах — на 217. При чтении задач сверять по дате правки файла.
