# GATE.md — ИТОГОВАЯ ВЫПИСКА по фреймворку vnc_work_v2-vm121-review-windows

Прочитан целиком: `C:\Users\user\ssl-ops\vnc_work_v2-vm121-review-windows` — 220 файлов
(6 .md, 17 .py, 5 .sh, 27 .js, 144 .png/.jpg, 11 .txt, 2 .pyc, 1 .xml, 7 .omx). Детальный конспект: NOTES.md рядом.

ЧТО ЭТО: Windows-копия = (1) доки обобщённого VNC+CDP-фреймворка (рабочие скрипты vnc.sh/cdp.mjs — в WSL
`/work/vnc_work_v2-vm121-review/`, здесь их НЕТ); (2) Windows-нативный CDP-драйвер Edge (`cdp/edge_cdp.py`)
и скрипты на нём (Selectel-сессия, catbox, smoke); (3) evidence-кадры прошлых задач (AnyDesk/RDP/1C/T400)
и синтетические fixtures. По правилу владельца 04.11: это ЗЕРКАЛО, нативного Windows-GUI-драйвера тут НЕТ.

---

## (а) Полный список инструментов

| Файл | Назначение | Как вызывать |
|---|---|---|
| `cdp/edge_cdp.py` | ЯДРО: Windows-нативный CDP-драйвер Edge (изолированный профиль, raw-WS без Origin) | `python cdp\edge_cdp.py start [--port 19444] [--profile-dir P]` / `status` / `get URL [--js E] [--wait PRED] [--waitms N] [--click X,Y] [--out F]` / `eval --js E` / `click X,Y [--clicks N] [--btn left]` / `screenshot [--out F]` / `cookies [--url U]` / `stop` / `ru-center-login`. Env: `EDGE_CDP_PORT` (19444), `EDGE_CDP_PROFILE`, `EDGE_CDP_BINARY`, `EDGE_CDP_UA`. Python-API: `from edge_cdp import attach, is_up, cmd_start, cmd_stop, CDP` |
| `cdp/nclick.py` | НАТИВНЫЙ OS-клик (настоящий жест мыши): CSS-координаты элемента → экранные → PowerShell user32 SetCursorPos + mouse_event | `python cdp\nclick.py --js "<js -> [x,y]>"` или `--xy 100,200` |
| `catbox_upload.py` | Залив файла на catbox.moe через Edge CDP (DOM.setFileInputFiles в Dropzone) | `python catbox_upload.py "C:\файл.zip" [--port 19446] [--timeout 180]` |
| `smoke_test.py` | 10 смоук-тестов edge_cdp.py на изолированных порту 19445 / профиле (не трогает залогиненный 19444) | `python smoke_test.py` |
| `cdp/selectel_type_vpc.py` | РАБОЧИЙ выбор роли в ant-design tree-select: впечатать «vpc» доверенными клавишами → клик узла → дети | `EDGE_CDP_PORT=9222 python cdp\selectel_type_vpc.py` |
| `cdp/selectel_atomic.py` | Атомарный замер+клик в одном WS-соединении (анти-перерисовка) + скрин до «Сохранить» | `EDGE_CDP_PORT=9222 python cdp\selectel_atomic.py` |
| `cdp/wheel_once.py` | Одно доверенное колесо по центру открытого дропдауна | `python cdp\wheel_once.py [DELTA]` |
| `cdp/selectel_check.py` / `selectel_scroll_vpc.py` / `selectel_wheel_noreply.py` / `grid_scroll_vpc.py` / `selectel_step_expand.py` / `selectel_diag_roles.py` / `selectel_final_vpc.py` / `selectel_wheel_flow.py` | Отладочные/диагностические этапы той же Selectel-сессии (видимость vpc, scrollTop контейнера, fire-and-forget колесо, координатная сетка 1:1, раскрытие узла, сеть дропдауна, Emulation-viewport) | каждый — `EDGE_CDP_PORT=9222 python cdp\<имя>.py` |
| `cdp/selectel_role_retry.sh` / `_v2` / `_v3` / `_v4` / `find_vpc.sh` | Bash-обвязки вокруг edge_cdp.py CLI (Git Bash): циклы открыть→проверить→клик→ROLE_NOW; эволюция граблей (overlay-container, Promise, treenode) | `export EDGE_CDP_PORT=9222; bash cdp/selectel_role_v4.sh` |
| `cdp/js/*.js` (27) | Сниппеты для `edge_cdp.py eval --js <файл|строка>`: pagetext/links/form_dump/ua/cookies (инспекция); q/s_fw/click_search/reset/search_25f/set_brand/set_cat*/paging/results_* (АТОЛ-архив, __doPostBack, deferred); r_docs/r_row2/r_row6290/r_water (mk_rect-зонды координат для доверенного клика); head_driver/range_probe/zip_drv (fetch/Range/ZIP-central-directory); sp_lists (SharePoint REST); grid_rows (Vaadin); shoplist_lin (карточки магазинов с ценой) | `python cdp\edge_cdp.py eval --js cdp\js\pagetext.js` (load_js подставит файл) |
| `fixtures/make_fixtures.py` | Генератор детерминированных тест-картинок (синтет-десктоп, кнопка с ground truth 640,505, тулбар 40px, dead-кадры, шаблоны) | `python fixtures\make_fixtures.py` (нужен OpenCV; результат — рядом) |
| `RDPLauncher.backup.xml` | Бэкап задачи планировщика: запуск mstsc на 10.8.0.29:3389 (RDP через VPN-адрес) | восстановление schtasks /create /tn RDPLauncher /xml ... (в папке — только бэкап) |
| `.omx/*` | Служебное состояние оркестратора oh-my-codex (сессия 18.09) — НЕ инструмент | — |
| Изображения (144) | Evidence прошлых сессий (см. (д) и NOTES §5) + fixtures | смотреть глазами, не по имени |

WSL-часть фреймворка (здесь только докоментация в docs/README_vnc_work.md, скриптов в папке нет):
`bash /work/vnc_work_v2-vm121-review/vnc.sh up|go|shot|text|find|click|clicksel|type|press|wait|eval|url|bbox|xclick|xkey|paste|viewer|status|down` + `tap/remember/recall/mem` + `fetch_email_code.py`.

---

## (б) Как поднять туннель к РМК

В ЭТОЙ папке скриптов туннеля к РМК НЕТ (grep по «РМК/rmk» — пусто). Документированная база:
`docs/REMOTE_EXEC_no_gui_sc_over_smb.md` (прецедент SOCHI11, T228):
1. Схема постоянного reverse-SSH-туннеля: на целевой Windows ставится OpenSSH.Server (Add-WindowsCapability);
   пары ключей `_me` (наш доступ) / `_tunnel` (reverse); `_tunnel.pub` кладётся в authorized_keys VPS
   **178.253.55.128** с опциями `restrict,port-forwarding`; создаётся задача планировщика (SYSTEM, ONSTART,
   cmd-loop) с `ssh -N -R 0.0.0.0:<порт>:127.0.0.1:22`; доступ с нашей стороны: `ssh -p <порт> <юзер>@178.253.55.128`.
2. Порты VPS 2243–2249 были заняты (SOCHI11=2249, SERVER-1S=2248); «следующий свободный — 2250» —
   по глобальным правилам владельца 2250 и есть канал РМК (reverse-туннель держит служба sshd РМК;
   прецедент 04.11: убийство sshd РМК pid 5096 = потеря канала; службы SRV1STunnel/StatKassaTunnel НЕ ТРОГАТЬ).
3. Хелперы канала (`sochi_ssh.sh`, `sochi_scp.sh`, `srv1s_ps.sh`, `srv1s_scp.sh`) живут в ПРОЕКТЕ
   (loyalty/ops, /work/kso), не здесь. ПОЛНАЯ инструкция: `/work/kso/docs/INSTRUCTION_openssh_tunnel_novaya_mashina.md`.
4. Если до машины не достучаться, а SMB жив — remote-exec через `sc.exe \\<ip> create/start/delete` (см. NOTES §1).

Итог: чтобы реально поднять/проверить туннель к РМК — читать проектную инструкцию /work/kso/docs/...;
эта папка даёт только методику (reverse-SSH + VPS 178.253.55.128 + порт 2250) и запреты (не убивать sshd/службы).

## (в) Как подключиться RustDesk и ввести пароль

В фреймворке RustDesk НЕ автоматизирован (упоминания — только комментарий в fixtures/make_fixtures.py:
«simulated AnyDesk/RustDesk toolbar band»). Готового скрипта подключения/ввода пароля НЕТ. Что есть:
1. Родственное evidence: нативная ANYDESK-сессия 18.09 (19 кадров native_anydesk_*.png + 11 .txt-дампов окон).
   По дампам: локальный AnyDesk владельца ID **1 336 347 805** (просмотрен anydesk_fresh.png), удалённая машина —
   окно «**1 397 277 972** - AnyDesk». Последовательность кадров: start → focus → auth (диалог пароля) →
   typed/typed2 (ввод) → checkbox (+postmsg, +check) → afterenter → connect_resume/after_enter_resume → resume →
   postauth → connecting2. Инструмент, делавший эти кадры и .txt-дампы (перечисление окон), в папке ОТСУТСТВУЕТ.
2. RDP-ветка: RDPLauncher.backup.xml → `mstsc /v:10.8.0.29:3389`; evidence srv1s_*.jpg (подключение к SERVER-1S).
3. По правилам владельца (23.10 + 31.10): GUI-клики в любых удалённых десктопах выбирает Flash-агент по СВЕЖЕМУ
   скрину; ввод пароля = нативная автоматизация по этим координатам. Пример механики нативного клика в папке —
   nclick.py (user32 SetCursorPos + mouse_event через PowerShell).
4. Глобальное правило 04.11: единственный реальный GUI-канал — WSL-стек; RustDesk-Windows-клиент был
   «вариантом на решение владельца», НЕ установлен.

Итог: процедура «подключиться RustDesk и ввести пароль» в этой папке НЕ задокументирована как скрипт;
ближайший работавший образец — AnyDesk-автоматизация 18.09 (кадры есть, скрипта нет) + правило «координаты по
свежему скрину, пароль через нативный ввод».

## (г) Как кликнуть по координатам и ввести текст через буфер

В браузере (основной путь, viewport CSS-координаты):
- `python cdp\edge_cdp.py click X,Y [--clicks N] [--btn left|right]` — Input.dispatchMouseEvent
  mousePressed/mouseReleased; координаты брать из `getBoundingClientRect()` (eval), НЕ со скрина (DPI 1.5×!).
- Надёжный клик по элементу: eval-зонд `cdp\js\r_*.js`-паттерна (найти элемент → rect → центр → vis=) → click.
- НАСТОЯЩИЙ жест мыши (попапы/капчи): `python cdp\nclick.py --js "<js -> [x,y]>"` — сам пересчитает
  CSS→экран (Browser.getWindowForTarget + devicePixelRatio) и кликнет user32-мышью.
Ввод текста:
- Доверенные клавиши: посимвольно `Input.dispatchKeyEvent {type:keyDown, key:ch, text:ch, unmodifiedText:ch}`
  (+keyUp, пауза ~60мс) — образец: type_text в selectel_type_vpc.py. Кириллица работает.
- В поля React — через native setter: `Object.getOwnPropertyDescriptor(el.__proto__,'value').set.call(el,v)`
  + `new Event('input',{bubbles:true})` (образец в selectel-скриптах).
- Буфер обмена: в WSL-версии — `vnc.sh paste <text>` (xclip + Ctrl+V). В Windows-копии готового paste-скрипта
  НЕТ; эквивалент — PowerShell `Set-Clipboard` + `SendKeys ^v` / xkey-паттерн (не закодировано здесь).
- Постбэки/действия с перезагрузкой страницы — отложенно через setTimeout (иначе CDP EVAL=NULL).

## (д) Как снять скрин и посмотреть его глазами

- В браузере: `python cdp\edge_cdp.py screenshot [--out F]` — Page.captureScreenshot PNG
  (дефолт C:\Users\user\ssl-ops\screenshot.png); jpeg quality 75–80 — как в selectel-скриптах.
  🔴 CDP-скрин в 1.5× Windows DPI — для координат НЕ годится (×1.5), только координаты из DOM.
- Нативный скрин Windows: специализированного скрипта в папке НЕТ (native_anydesk_*.png делались внешним
  средством с дампом окон в .txt — PowerShell-перечислитель, в папку не входит); любой нативный способ
  (PrintWindow/графзахват) — вне этой папки.
- ПРОСМОТР (правила владельца 8–12): пиксели обязаны реально попасть агенту в глаза ДО любых выводов.
  В этой среде Read по PNG отдаёт CDN-URL (НЕ просмотр) — рабочий канал: nodeRepl.emitImage + vision-модель;
  проверено на 3 кадрах. 🔴 Имя файла ≠ содержимому (native_anydesk_auth.png реально показывал терминал;
  t400_srv1s_desktop.png — пустую консоль). Остальные 141 кадр — каталогизированы, индивидуально не просмотрены.
- В WSL-стеке: `vnc.sh shot <label>` → screens/<label>.jpg → Read.

## (е) Все задокументированные грабли

Координаты/клики:
1. Не угадывать координаты по скрину (Read рендерит в другом масштабе) — координаты из bbox/getBoundingClientRect.
2. CDP-скрины в 1.5× DPI — не смешивать экранные и viewport-координаты.
3. Нативный клик мажет на ~120px относительно viewport (хром сверху): viewport=1903×1040 vs натив 1920×1080.
4. Viewport = граница кликов: y>innerHeight уходит в никуда; ниже фолда — zoom 0.8 / скролл контейнера / Emulation.
5. Страница скроллится между действиями: scrollIntoView → замер → клик без промежуточных скроллов.
6. Виртуальные списки перерисовываются: замер и клик атомарно в ОДНОМ WS-соединении.
7. Кликабелен весь treenode (центр rect), не текстовый span; родитель-продукт = раскрыть, роль = в детях.
8. «Клик не сработал» — проверить СКРИН/elementFromPoint, не URL (SPA-модалки не меняют URL и не светят сеть).
9. find/tap при неоднозначности печатают AMBIGUOUS и НЕ кликают — уточнять clicksel / CDP_FORCE=1.
10. mouseWheel не имеет CDP-ответа — только fire-and-forget (иначе таймаут cdp.call).

Браузер/окружение:
11. visibilityState='hidden' (свёрнуто) — дропдауны не открываются, клики в пустоту; проверять ДО автоматизации.
12. НЕ убивать браузер владельца ради CDP-порта (прецедент: убита 2FA-сессия Selectel).
13. Сбрасывать body.style.zoom и Emulation-override после экспериментов — сдвигают все координаты.
14. ant-select-dropdown искать по всему документу (offsetParent), не в .cdk-overlay-container.
15. «Не найдено» в дереве — Escape → переоткрыть (новый запрос), не долбить кликами.
16. Всплывашки браузера не в DOM (CDP их не видит) — prefs + xkey Escape.
17. Кириллица: CDP type / xclip-paste ок; голый xdotool type ломает.
18. Поля проверять по input.value, не по innerText.
19. Токены/ключи читать eval/text, не глазами с jpg (l/I/1, O/0).
20. Песочница Bash убивает длинные процессы сигналом 16 — стек/SOCKS/sleep с dangerouslyDisableSandbox.
21. scrot по :98, не по WSLg :0 (чёрный кадр). Сессия живёт в профиле (бэкап профиля = бэкап сессии).
22. Лимитные кабинеты (1С Fresh=1 сеанс) — всегда down/logout. RU-IP — свой SOCKS5 (VNC_SOCKS).
23. edge_cdp.py status всегда rc=0 — проверять is_up(). smoke — только на изолированном порту/профиле.
24. Фреймворковый eval НЕ ждёт Promise — синхронный JS; перезагрузка страницы = EVAL=NULL → setTimeout-deferred.
25. Кириллицу в .js-файлах возить \uXXXX-эскейпами (кодировка при передаче).

catbox:
26. «Invalid uploader» = грязный IP; один чистый IP ≈ одна загрузка (смена v2rayN); Electron/IAB ZCode не годится.
27. Лимит 200 МБ (крупняк — litterbox 72ч); HEAD Content-Length:0 — норм, проверять реальной скачкой;
    ASCII-имя архива; второй пустой .dz-preview — косметика.

remote-exec/SMB/туннели:
28. sc.exe start → 1053 «служба не ответила» — НОРМА (полезная работа уже сделана).
29. Транзитная служба-скрипт НЕ должна работать >30с (SCM убьёт дерево) — порождать SYSTEM-schtasks-задачу.
30. Одноразовые задачи /sc ONCE /st HH:MM удалять после отработки (иначе повторно выстрелят).
31. LocalAccountTokenFilterPolicy=1 нужен для админ-действий по SMB; длинный -EncodedCommand рвётся — файлом.
32. sshd_config: глобальные директивы ВЫШЕ первого Match (иначе sshd exit 1067); icacls по SID (*S-1-5-18,
    *S-1-5-32-544) на русской Windows — англ. имена молча падают.
33. Vaadin-grid: текст в light-DOM cell-content; строки вне буфера отсутствуют — сначала пейджинг/скролл.

Кадры/evidence (мои проверки):
34. Имя файла ≠ содержимому — кадр смотреть, не верить имени (два пойманных примера).
35. В этой среде Read по картинке = CDN-URL = НЕ просмотр; канал просмотра — emitImage + vision; в отчёте
    честно писать «не просмотрено», если пиксели не видел.

Плюс: в selectel-скриптах лежит пароль сервисного пользователя (btdialer-api) — уже сдан владельцу
(/work/asterisk/CREDENTIALS.md), помнить при копировании папки.

---
---

# WSL-фреймворк — /work/vnc_work_v2-vm121-review (в Ubuntu-24.04)

Прочитан целиком (все исходники; исключая .git, браузерный профиль .beget_vnc_profile и каталог screens/):
~330 файлов-источников + helpers_neproshity (212 черновиков). Это НАСТОЯЩИЙ фреймворк; Windows-копия — его зеркало (доки+edge_cdp).

Слои: (1) веб-стек vnc.sh+cdp.mjs (браузер на :98, CDP-руки); (2) пиксельный драйвер rc.sh+lib/ (DRY-RUN, точный таргетинг для AnyDesk/RustDesk на :99); (3) каналы RustDesk/AnyDesk (rustdesk/, anydesk_kso*); (4) SSH-туннели ко всем машинам (*_ssh.sh + ssh_channel/); (5) текстовый браузер cdp/ (антибот, 0 токенов на зрение); (6) clipboard-каналы к кассам (z*, zd*, rps*, ksod); (7) LLM-ветка VM121 (запускатели).

## (а) Полный список инструментов

ЯДРО:
| Инструмент | Назначение | Вызов |
|---|---|---|
| `vnc.sh` | Веб-стек :98 (Xvfb+fluxbox+chromium CDP 9334+x11vnc 5901); prefs глушилки попапов; viewer в tmux на WSLg :0 | `bash vnc.sh up [URL] / go / shot <lbl> / where / clean / text / find <re> / click <текст> / clicksel <css> / upload <файл> [css] / type <css> <val> / press <Key> / wait <css> / eval '<js>' / url / map [re] / mclick x y / tap '<текст>' [имя] / zoom 0.8 / remember/recall/mem/forget / keytype <текст> / cclick '<re>' [N] / bbox <css\|текст> / grant / xclick x y / xkey <seq> / paste <текст> / viewer / tabs / front <подстр> / closetab <подстр> / status / down`. Env: VNC_DISPLAY/PORT/CDP/PROFILE/SCREENS/SOCKS/SCREEN |
| `cdp.mjs` | CDP-движок: клики по тексту/селектору с guard AMBIGUOUS (CDP_FORCE=1), tap (scroll→zoom→CDP-мышь→проверка landed→POST/PUT-отчёт→память), bbox = нативные координаты через screenX/Y+хром-оффсет, map, память координат coords_memory.json, targets (CDP_TARGET_ID, CDP_KEEP_VIEWPORT) | через vnc.sh; напрямую `NODE_PATH=/home/hgff/node_modules node cdp.mjs <PORT> <cmd>` |
| `rc.sh` | Пиксельный драйвер GUI (AnyDesk/RustDesk-вьювер на X-дисплее): template-match/haiku-глаз/verify/reconnect. 🔴 DRY-RUN по умолчанию, реальный клик только RC_LIVE=1 | `bash rc.sh shot <lbl> / where / clean [сут] / find <tmpl> / crop x,y,w,h out scale --grid / deproject ox,oy scale px,py / grid / ocr <text> / read [x,y,w,h] [scale] [psm] / hover x y / type / typefile <файл> / key / click x y / rclick / dclick / scroll x y up\|down [n] / field-left <tmpl> / click-template <tmpl> / modal [--json] / modal-click <подпись> [--via cdp\|x] / modal-click --tmpl / modal-fill / modal-key / verify b a x,y,w,h / calibrate <anchor> / classify / livecheck / reconnect [--run] / selftest`. Env: RC_DISPLAY(:99) RC_SCREENS RC_USER RC_MIN_SCORE(0.8) RC_LIVE RC_SHOT_CMD RC_AD_ID RC_RD_ID RC_PREFER RC_SCENE_MAX_MIN(30) RC_CDP_PORT(9222) |
| `lib/vmatch.py` | Template-match (multi-scale CLAHE + ORB-фоллбэк), verify (региональный diff), calibrate (оффсет панели→screens/.offset); возраст сцены в каждом JSON | `python3 lib/vmatch.py find --scene S --template T [--min-score] [--offset] / verify --before --after [--region] / calibrate --scene --anchor [--expect]` |
| `lib/veye.py` | «haiku-глаз»: crop+upscale+сетка с подписями РЕАЛЬНЫХ пикселей, deproject (real=origin+point/scale), roi, ocr/text (tesseract, crop+scale обязателен, --channel b\|g\|r для цветных плашек) | `python3 lib/veye.py crop --scene --out --region --scale 3.0 --grid / deproject / grid / roi / ocr / text` |
| `lib/reconnect.py` | classify live/black/banner (по дисперсии+шаблону баннера), backoff (детерминированный), plan (RustDesk-first) | через rc.sh classify/livecheck/reconnect |
| `lib/modal1c.py` | Модалки 1С веб-клиента: scan (окна ps*win/VW_page*win+cloud, кнопки a.press с hit-тестом и hotkey), click (cdp/x, вердикт ушло/ЗАНЯТА/не дошло), fill (посимвольный keyDown+Ctrl+A), keys | через rc.sh modal*; env CDP_PORT |
| `shotlib.sh` | Контракт съёмки: shot_guarded (снести старое→scrot→проверить→jpg→ВРЕМЯ+путь последней строкой), shot_where, shot_clean (эталоны/git/.keepframes не трогать) | подключается во все драйверы |
| `lib/cdp_target.cjs` | Выбор CDP-таргета по CDP_TARGET_ID (fail-closed) | для cdp.mjs |

RUSTDESK/ANYDESK-КАНАЛЫ:
| `rustdesk/connect.sh` | Поднять :99 (Xvfb+fluxbox+x11vnc 5902) + rustdesk --service + GUI + `--connect <ID>` + скрин | `bash rustdesk/connect.sh [ID]` (умолч. 243540605); параллельно: `RD_DISPLAY=:97 RD_PORT=5903` |
| `rustdesk/x99.sh` | Примитивы на :99: click/dbl/type(латиница)/key/shot/zoom/where/wins | `bash rustdesk/x99.sh click X Y / dbl / type '<ascii>' / key ctrl+v / shot / zoom 700x420+560+230 250% / wins`; env X99_DISPLAY/X99_SCREENS |
| `rustdesk/rd_health.sh` | Здоровье канала с НАШЕЙ стороны: check (окно «ID@host»=live), up (пересборка), refresh (перезапуск демона, живую сессию пропускает), down, status (дисплей+процессы+порты hbbs), prune (логи RustDesk 0.5–1 ГБ/сут) | `bash rustdesk/rd_health.sh up\|check\|refresh\|status\|down\|prune 7 500`; env RD_DISPLAY/RD_ID/RD_SERVER |
| `rustdesk_kso.sh` | Легаси-руль: up <ID> <PASS> (типа пароль + Enter), verify (окно+движение/дисперсия), shot/status/down | `bash rustdesk_kso.sh up 243540605 '<pw>'` (README: предпочтителен GUI-путь connect.sh) |
| `anydesk_kso.sh` | AnyDesk-стек КСО на :99/5902 (root): up/down/shot/where/clean/click/dblclick/move/key/type(ascii)/paste/id <anydesk-id>/pos/wins/status/viewer | `bash anydesk_kso.sh up` и т.д.; env AD_DISPLAY/AD_PORT/AD_SCREENS/AD_PULSE |
| `anydesk_kso_hgff.sh` | Версия для агента от hgff (без runuser): shot/where/zoom/click/dblclick/move/drag/paste2/key/type/paste/scroll/pos/alive; авто-фокус окна сессии | `bash anydesk_kso_hgff.sh paste2 '<кириллица>'` |
| `profiles/` + `restore_profiles.sh` | Снапшот конфигов RustDesk/AnyDesk (сервер+ключ, peers, пароли — В .gitignore); check/hgff/root | `bash profiles/restore_profiles.sh check` |

СЪЁМКА КАДРОВ:
| `shot1.sh` | Нативный кадр с кассы (1024×768, сессия-1) через SSH: schtasks KSOCapture → scp; проверка возраста ПО ЧАСАМ КАССЫ (SHOT1_MAX_AGE_SEC=120) | `bash shot1.sh <label>`; env SHOT1_SSH/SHOT1_SCP/SHOT1_OUT |
| `srvshot/srvshot.sh` (+shot_run/shot_inner.ps1) | Нативный кадр ЛЮБОЙ машины по SSH (.NET CopyFromScreen через schtasks /it; авто-детект владельца сессии по explorer.exe; скрытый powershell, не .bat; снос png ДО съёмки, маркер SHOT=байты TIME=) | `bash srvshot/srvshot.sh out.png [focus-подстрока] [settle]`; env SSH/SCP/RHOST/RDIR/RUNAS |

ВВОД/ФАЙЛЫ НА КАССУ:
| `clip_paste.sh` | Надёжная вставка текста (в т.ч. кириллица) через X-буфер+Ctrl+V; DRY-RUN без RC_LIVE; авто-поиск окна вьюера по площади | `RC_LIVE=1 clip_paste.sh "<текст>" [x,y] [--replace] [--enter] [--set-only]`; env RC_DISPLAY/RC_SYNC_MS(700)/RC_WIN_MATCH |
| `type_exact.sh` | Регистрозависимый посимвольный набор (base64/коды/пароли): раздельный Shift, явный keyup shift, без --clearmodifiers, спецсимволы по таблице; печатает только sha256 | `bash type_exact.sh <файл>` |
| `push_clip.sh` / `zput.sh` / `kso_put.sh` / `zdput.sh` | Файл на кассу через буфер (base64) + чтение c2f.ps1/WriteAllBytes; sha256-сверка; авто-подбор времени синка | `bash push_clip.sh <лок> <удал>`; PSX/PSY/TB_X/TB_Y |
| `zget.sh` / `zdget.sh` | Файл с кассы через буфер (base64 за NONCE) | `bash zget.sh <remote> [local]` |
| `ztx.sh` / `zx.sh` / `rps_paste.sh` | Набор ASCII-команды PS в сфокусированное окно + чтение stdout из буфера (NONCE); zx = дренаж консоли + ретрай | `bash zx.sh '<ascii PS>'`; PSX/PSY/WAIT |
| `zd.sh` + `ksod.ps1` | Клипборд-команда через ДЕМОН на кассе (фокус-независимо): KSOCMD::id::cmd → KSORES::id::out | `bash zd.sh '<powershell>'` (нужен запущенный ksod.ps1) |
| `zq.sh` + `cash_runner.ps1` | Очередь заданий: файл-джоб в C:\kso\q + маркер JDONE_id в буфере | `bash zq.sh <script.ps1>` |
| `zrun.sh` | Push скрипта (кириллица ок, UTF-8 BOM) + запуск + stdout из буфера | `bash zrun.sh <local.ps1>` |
| `rps.sh` + `rps_run.ps1` | PS на удалённой машине (SSH-канал) с UTF-8 наверх, BOM, стриминг вывода, САМОЗАЧИСТКА скрипта с секретами на удалённой стороне | `bash rps.sh <ps1|-> [out]`; env SSH/SCP/RHOST/RDIR |
| `s1run.sh` | PS в ИНТЕРАКТИВНОЙ сессии-1 кассы (schtasks KSOS1, RunLevel Highest) | `bash s1run.sh <ps1> [remote_out] [local_out] [wait]` |
| `eznav.sh` / `ezxy.sh` | UIA-навигация EasySet на кассе (найти элемент по Name → клик → дамп UIA-дерева) | `bash eznav.sh "<имя цели>" [фильтр дампа]` |
| `kiosk_reveal.sh` | Киоск Electron перекрывает окна: desktop (Win+D) / cmd / focus-cmd / restore-kiosk / taskbar | `bash kiosk_reveal.sh cmd` |
| `kso_layout.sh` + `t09_layout.ps1` | Раскладка киоска (report/seten) + инъекция скан-кода (sendcode, ~GS~ = GS 0x1D) | `bash kso_layout.sh report\|seten\|sendcode '<payload>'` |
| `topmost_console.ps1` / `c2f.ps1` / `ksod.ps1` / `cash_runner.ps1` | PS-хелперы на кассе: always-on-top консоль; буфер→файл (sha256+len в c2f.out); клипборд-демон KSOCMD/KSORES; queue-executor C:\kso\q | ставятся на кассу однократно |

SSH-КАНАЛЫ (все — с dangerouslyDisableSandbox; jump VPS 217.144.184.51, env KSO_VPS_HOST):
| `kso_ssh/scp/ps/put.sh` | Касса №1 DESKTOP-E8FF2LU: VPS-порт 2243, юзер sco_m210, ключ ssh_channel/kso_me; scp-алиас `kso:` | `bash kso_ssh.sh 'hostname'`; `bash kso_scp.sh ./f kso:C:/kso/f` |
| `kso2_*` / `kso3_*` | КСО №2 (2246, M210) / КСО №3 (2247, M210); 🔴 hostname у №2 и №3 ОДИНАКОВЫЙ — различать UUID/MAC/IP | аналогично |
| `srv_*` | Старый 1С-сервер DESKTOP-VGVHEOU: 2244, юзер 'Админ' (кириллица — только через -o User=) | `bash srv_ssh.sh '...'` |
| `srvold_ssh.sh` | Старый сервер ЧЕРЕЗ SERVER-1S (ProxyCommand -W на 192.168.0.10:22), когда 2244 лежит | `bash srvold_ssh.sh '...'` |
| `srv1s_ssh/ps/scp.sh` + `srv1s_rdp.sh` | SERVER-1S: 2248 (юзер User); RDP-канал: туннель 127.0.0.1:13389→3389 + xfreerdp3 на своём Xvfb :98 (пароль из CREDENTIALS.md через env, не argv); down не бросает сеанс (logoff отдельно) | `bash srv1s_ssh.sh '...'`; `bash srv1s_rdp.sh up\|shot f.png\|status\|down` |
| `ofd_ssh/scp.sh` | ОФД/ЭЦП desktop-i7oe05b: 2245, юзер User | `bash ofd_ssh.sh '...'` |
| `statkassa_lan_ssh/ps/scp.sh` | РМК DESKTOP-6NTV2D5 ЧЕРЕЗ LAN: /work → VPS:2247 (КСО №3) → LAN-IP кассы:22 (форвард 127.0.0.1:12250, юзер «днс»); 🔴 IP у РМК DHCP (.147→.187) | `bash statkassa_lan_ssh.sh '...'`; env STATKASSA_LAN_IP |
| `kso_lan_ssh.sh` / `srv1s_lan_ssh.sh` | LAN-обходы (через 1С-сервер 2244 / через КСО №3 2247), когда прямой VPS-порт лежит | аналогично |
| `ssh_channel/` | Ключи *_me/*_tunnel + known_hosts_* + УСТАНОВЩИКИ туннелей: srv/srv_setup(_v2,_v3).ps1, cash/ssh_setup.ps1 + kso_tunnel.ps1 (watchdog `ssh -R 0.0.0.0:PORT:127.0.0.1:22`, реконнект 10 с, задача SYSTEM boot+logon) | запуск на НОВОЙ машине в элевированном PS |

CDP/БРАУЗЕР (текст, антибот, 0 токенов на зрение):
| `cdp/cdp_linux.py` | Linux-близнец (чистая stdlib, свой RFC6455): start/get/eval/click/cookies/stop; UA-override, headless=new, дефолтный wait-предикат «мы не на антибот-заглушке» | `python3 cdp/cdp_linux.py start`; `… get URL --js f.js`; env CDP_PORT/PROFILE/CHROME/UA |
| `cdp/cdp_up.sh` + `cdp_start.ps1` | Headless Chrome на УДАЛЁННОЙ Windows (порт 9222, изолированный профиль, запуск через schtasks — OpenSSH убивает детей своей сессии; перебор путей Chrome x86/x64/LocalAppData) | `bash cdp/cdp_up.sh`; env SSH/SCP/RHOST/RDIR/CDP_PORT |
| `cdp/cdpq.sh` (+ `cdp_get.ps1`) | Страница→ТЕКСТ по SSH-каналу; env-ручки: CDP_NONAV / CDP_CLICK / CDP_CLICKS / CDP_BTN / CDP_WAIT / CDP_WAITMS / CDP_FRAME / CDP_REMOTE_JS (выражение-с-секретом уже на машине) | `bash cdp/cdpq.sh <url\|-> <out> [settle_ms] [js-файл]` |
| `cdp/cdpnet.sh` (+ `cdp_net.ps1`) | СЕТЬ страницы (Network domain): запросы + тела ответов по url-фильтру — данные из XHR, а не DOM | `bash cdp/cdpnet.sh <out> [сек] [фильтр]`; CDP_NAV/CDP_JS/CDP_NOBODY/CDP_MAXBODY |
| `cdp/mk_rect.py` / `mk_setselect.py` / `mk_textsearch.py` / `mk_zipindex.py` | Генераторы JS-сниппетов: координаты для доверенного клика (--scroll!); ASP.NET select+postback; поиск по тексту; ZIP-листинг через HTTP Range (UTF-8/CP866) | `python3 cdp/mk_rect.py '<css>' [--text Т --nth N --scroll] > js/x.js` |
| `cdp/w1c.py` + `w1c_up.sh` | ВЕБ-КЛИЕНТ 1С в СВОЁМ Chromium через SSH-туннель к IIS (кадр всегда годен, координаты из DOM): text/inputs/ui/shot/login/click/clickid/mclick/dblclick/key/fill/waittext/dialog/eval; пароль через env P1C_USER/P1C_PASS (из CREDENTIALS.md), не argv | `bash cdp/w1c_up.sh up\|down\|status`; `CDP_PORT=9333 python3 cdp/w1c.py ui [re]` |
| `cdp/local_page.py` | Вождение ЛОКАЛЬНОЙ страницы (file://) в headless-хромиуме: shot/script по steps.json + console-ошибки | `python3 cdp/local_page.py shot <url> <png> [--full]` |
| `cdp/js/` (27 сниппетов) | pagetext/links/form_dump/grid_rows/zip_drv/sp_lists/shoplist_lin/set_*/r_* и т.д. | `bash cdp/cdpq.sh - out.txt 5000 cdp/js/pagetext.js` |

ПРОЧЕЕ:
| `fetch_email_code.py` | Одноразовый код из почты по IMAP (игнорирует 000000/hex-цвета) | `python3 fetch_email_code.py --host … --user … --pass … [--from --subject --digits 6]` |
| `kso_probe.sh` | JScript COM-проба в 1С на кассе (32-bit cscript, UTF-16LE+BOM, результат в _probe_out.txt) | `bash kso_probe.sh <local.js>` |
| `kso_kiosk.sh` | Обратимая парковка киоска Electron (stop/start через KSORelaunch/status) | `bash kso_kiosk.sh stop\|start\|status` |
| `kso_app_backup.sh` + `.ps1` | Локальный бэкап C:\kso (без node_modules/логов) → /work/kso/backups; касса выбирается КАНАЛОМ (kassa1\|kassa2\|kassa3 — hostname нерелевантен) | `bash kso_app_backup.sh [dest] [kassa1\|kassa2\|kassa3]` |
| `examples/1c-vnc/` + `examples/demo.sh` + `test/` + `fixtures/` + `templates/` | Обезличенные шаблоны 1С-VNC (login/release/socks_keepalive/1C_CALIBRATION); офлайн-демо всех механизмов v2; 14 юнит-тестов + dry-run драйвера; генератор фикстур; эталоны кнопок (1c_web_modal_ok/otmena, loyalty_app/*) | `bash examples/demo.sh`; `bash test/run_tests.sh` |
| `docs/VPS_BROWSER_NOVNC.md` | Браузер VPS в браузере Windows: x11vnc(5907)+websockify/noVNC(6087) на VPS + SSH-туннель в tmux → человеку ссылка `http://127.0.0.1:6087/vnc.html?autoconnect=1&resize=scale`; хендофф WAITING_OWNER_2FA и возврат управления | см. доку (порты — пример, не константы) |
| `VM121-*.cmd/sh` + `VM121-CLAW-START.md` + `SECOND-LLM-SRV2-HANDOFF-20260606.md` | Запуск второй LLM: VM121 на srv1 (jump 217.144.184.51 → srv1 134.0.107.8:234 → VM121 192.168.87.33; run-claw-gemma2 → gemma4 @ 192.168.87.100:8081, ctx 260k) | из Windows: `VM121-terminal.cmd`; проверка: `/work/claster/vm121/vm121-terminal.sh --check` |
| `helpers_neproshity/` (212 файлов) | НЕ-фреймворковые черновики: видео/музыка-генерация (kling_* 47, gen_* 64, suno_* 15, p_*.txt промпты, fix_*) + CDP-утилиты на websocket-client порт 9223 (trusted_click/raw_cdp/cdp_tool/netlib) | справочно; в работу фреймворка не прошиты |
| `.beget_vnc_profile/` | ПЕРСИСТЕНТНЫЙ профиль браузера Beget (VNC_PROFILE; сессия переживает down/up) | `VNC_PROFILE=/work/vnc_work_v2-vm121-review/.beget_vnc_profile bash vnc.sh up <url>` |
| `coords_memory.json` | Память координат cdp.mjs (per-URL: текст+роль+тег → x,y) | пишется tap/remember; читается recall/mem |

## (б) Как поднять туннель к РМК из WSL

РМК = DESKTOP-6NTV2D5 (стационарная касса, RustDesk 114513449, LAN 192.168.0.x, юзер «днс»).
1. ОСНОВНОЙ внешний путь — reverse-SSH туннель, VPS-порт **2250** (jump **217.144.184.51**). Сам хелпер лежит
   В ПРОЕКТЕ KSO: `loyalty/ops/statkassa_ssh.sh` (в этой папке его НЕТ; здесь — ключи `ssh_channel/statkassa_me` +
   `known_hosts_statkassa(_lan/_vps)` и LAN-вариант). Схема на машине РМК — как у всех машин (шаблоны в ssh_channel/):
   watchdog-задача планировщика (SYSTEM, boot+logon) держит `ssh -R 0.0.0.0:2250:127.0.0.1:22 root@VPS` (kso_tunnel.ps1 —
   образец; полная инструкция /work/kso/docs/INSTRUCTION_openssh_tunnel_novaya_mashina.md).
   🔴 04.11: туннель держит служба sshd РМК — НЕ УБИВАТЬ (правило OWNER_NO_SERVICE_KILL_20261104).
2. Из ЭТОЙ папки рабочий путь — `bash statkassa_lan_ssh.sh '<команда>'`: /work → VPS:2247 (КСО №3) → LAN-адрес РМК:22
   (форвард 127.0.0.1:12250). 🔴 LAN-IP у РМК — DHCP, менялся (.147 → .187): проверять разрешением имени,
   переопределять STATKASSA_LAN_IP. 🔴 Крупные файлы через VPS-2250 РВУТСЯ (81 МБ оборвались на 74 МБ) — только LAN-путь.
3. Онбординг новой машины: docs/REMOTE_EXEC_no_gui_sc_over_smb.md + установщики ssh_channel/ (следующий свободный порт VPS).

## (в) Как подключиться RustDesk из WSL (connect.sh, x99.sh)

Сервер — СВОЙ hbbs/hbbr на VPS **178.253.55.128**, key `OS6FFMq66QzmnraQDy+cy+fdryWDXA0fBVZTbYqc7Lk=`
(порты 21115–21119; наш клиент :99 читает /home/hgff/.config/rustdesk/RustDesk2.toml; снапшот конфигов — profiles/).
1. `bash rustdesk/connect.sh [ID]` — ОТ ROOT, с dangerouslyDisableSandbox. Поднимает Xvfb :99 + fluxbox +
   x11vnc :5902 + `rustdesk --service` + GUI-клиент + `--connect <ID>` (умолчание 243540605 = касса №1),
   затем снимает контрольный кадр (провал = SHOT_FAIL + exit 1, «запущен, но подтверждения нет»).
   Параллельный сеанс, не трогая чужой :99: `RD_DISPLAY=:97 RD_PORT=5903 bash rustdesk/connect.sh <ID>`
   — ПЕРЕД стартом проверить `ls /tmp/.X11-unix/` и `ps aux | grep Xvfb` (грабля T378: запуск на занятом :99 убил бы сессию).
2. Пароль: обычно НЕ спрашивается (галка «Remember» в клиенте). Если выскочил диалог «Password required —
   Verify RustDesk password»: (а) КЛИК точно в поле пароля; (б) кадр/зум — поле в фокусе (голубая рамка, курсор);
   (в) `bash rustdesk/x99.sh type '<пароль>'`; (г) кадр — точки нужной длины; (д) клик по «Remember password»
   (проверить зумом, что галка встала); (е) OK / `x99.sh key Return`. Ввод xdotool-ом в диалог Flutter работает
   ТОЛЬКО в сфокусированное поле; «0% изменений» = печатали мимо поля, а НЕ «Flutter не принимает ввод».
   Пароли: касса №1 — /work/kso/chat/rustdesk_kassa.md; остальные — /work/kso/CREDENTIALS.md (в лог не печатать).
3. Признак установленной сессии — ТОЛЬКО hostname в заголовке окна: `<ID>@<hostname> - Remote Desktop - RustDesk`
   (RustDesk дописывает его после успешной аутентификации). `bash rustdesk/rd_health.sh check [ID]` (exit 0/1).
   🔴 «Remote desktop is offline» ВРЁТ — это «наш клиент не договорился»; сначала `rd_health.sh up` (пересборка нашей
   стороны), и только потом разбираться с машиной. Клиент «протухает» после >суток: `--connect` молча exit 0 → refresh.
4. Управление после коннекта: `x99.sh shot/zoom/click/dbl/type(латиница!)/key/wins`; точная работа — rc.sh
   (`click-template` по эталону, `calibrate` оффсет тулбара вьювера, `read`/`field-left`). Человек смотрит тот же
   экран: TigerVNC → localhost:5902.

## (г) Как кликнуть и ввести текст (x99.sh click/type, буфер)

КЛИК — координаты в НАТИВНЫХ пикселях кадра :99 (1920×1080), НЕ с уменьшенного просмотра (множители: 1500→1.28,
1400→1.371, 1200→1.6):
- быстрый: `bash rustdesk/x99.sh click X Y` (dbl — двойной одним вызовом; rc.sh rclick — правый; dclick — двойной с паузой);
- надёжный: `RC_LIVE=1 bash rc.sh click-template templates/<эталон>.png` — найти/кликнуть/ПРОВЕРИТЬ/retry; перед этим
  `bash rc.sh calibrate templates/<якорь>.png 0,0` (оффсет панели вьювера → screens/.offset, применяется ко всем кликам);
- в браузере — только CDP (vnc.sh tap/click/clicksel/mclick по координатам из DOM); xclick — для chrome-попапов/canvas;
- в модалках 1С — `rc.sh modal-click '<подпись>' [--via x]` (hit-тест перекрытий, горячая клавиша при полном перекрытии);
- ПЕРЕД любым вводом — РЕАЛЬНЫЙ клик в окно/поле (клавиатурный фокус ставится только кликом);
- ПОСЛЕ каждого клика — контрольный кадр (промах не бросает ошибку: команда «успешна», но попала не туда).

ВВОД ТЕКСТА (вердикт T382 — единственная рекомендация):
- КИРИЛЛИЦА / регистр вперемешку / произвольные спецсимволы — ТОЛЬКО ЧЕРЕЗ БУФЕР:
  `RC_LIVE=1 bash clip_paste.sh "<текст>" x,y` (клик-фокус в поле → xclip в X-буфер → пауза синка ~0.7 с → Ctrl+V;
  флаги --replace (Ctrl+A), --enter); вариант `anydesk_kso_hgff.sh paste2 '<текст>'` (RD_CLIP_SYNC=3..8 с — для
  длинной кириллицы и больших текстов); вариант без Ctrl+V: `rc.sh rclick x y` + клик по пункту «Вставить».
  Буфер RustDesk синкается медленно и ДВУНАПРАВЛЕННО (может вернуть СТАРОЕ значение — читать только за NONCE,
  проверять вставку зумом).
- Чистая латиница+цифры посимвольно: `x99.sh type '<ascii>'` / `rc.sh type '<строка>'` / `rc.sh typefile <файл>`
  (пароли — файлом, не аргументом: аргумент виден в ps). 🔴 Раскладка кассы РУС → латиница приедет «теми же
  физическими клавишами по-русски» (notepad → тщеузфв): сначала `xdotool key --clearmodifiers alt+shift`, проверить пробной строкой.
- Регистрозависимое (base64, коды маркировки): `bash type_exact.sh <файл>` — раздельная посылка Shift; НЕ умеет
  `$ # % ( )` и ПРОБЕЛ (молча пропускает) — их только буфером; в выводе только длина+sha256 (секрет не утекает).
- Файлы на кассу: `push_clip.sh`/`zput.sh` (буфер + c2f.ps1, sha256-сверка, авто-подбор синка) или SSH-каналом
  (`kso_scp.sh`) / демонами (`zdput.sh`).
- В поля 1С-вебклиента — только посимвольный keyDown (rc.sh modal-fill / w1c fill): Input.insertText теряется,
  1С видит пустую строку.

## (д) Как снять скрин и посмотреть

- Вьювер-канал: `bash rustdesk/x99.sh shot` (→ /tmp/x99.jpg; печатает ВРЕМЯ съёмки; SHOT_FAIL при провале) /
  `bash rc.sh shot <label>` (→ screens/); зум: `x99.sh zoom 700x420+560+230 250%` (свежий кадр + кроп).
- Нативно с самой машины (не зависит от вьювера и его «замороженных» кадров): `bash shot1.sh <label>` (касса №1,
  сессия-1, возраст по часам КАССЫ) / `bash srvshot/srvshot.sh out.png [focus]` (любая машина по SSH; задача /it;
  🔴 процесс из голого SSH живёт в сессии 0 и снимает ЧЁРНЫЙ кадр; .bat-лаунчер портит кадр — только скрытый PS;
  RunAs авто-детект владельца интерактивной сессии по explorer.exe).
- Браузер: `vnc.sh shot <label>` (по :98); веб-клиент 1С: `w1c.py shot <png>` (через CDP, без X-сервера).
- ПЕРЕД выводами по кадру: `rc.sh livecheck` (замороженный кадр? диалог вьювера?) → `rc.sh classify`; RustDesk не
  перерисовывает статичную область — перед контрольным кадром шевельнуть мышь (`DISPLAY=:99 xdotool mousemove 700 800`).
- ПРОСМОТР: Read jpg (в этой среде Read по PNG может вернуть URL — тогда emitImage/vision; правило: пока пиксели
  не в контексте — «не просмотрено»); мелкий текст — кроп+зум; текст БЕЗ картинки — `rc.sh read x,y,w,h scale [psm]`
  (дословный OCR; цветная плашка → RC_CHANNEL=b RC_BIN=1); выводы о координатах — vmatch/deproject, не глазами.

## (е) Все грабли WSL-фреймворка (полные тексты — FIELD_NOTES.md; здесь — сводка)

ОБЩИЕ/СРЕДА:
1. Песочница Bash убивает ssh/scp/Xvfb/rustdesk/долгие sleep сигналом 16 (exit 144) — всё канальное с dangerouslyDisableSandbox.
2. Self-match pkill: строки «Xvfb :99»/«rustdesk_kso.sh up» рядом с pkill убивают сам шелл — глушить по явному PID / kill_on_display (по environ процесса).
3. :99 бывает занят ЖИВОЙ работой — до подъёма стека проверять /tmp/.X11-unix и ps; параллельные сеансы через RD_DISPLAY/AD_DISPLAY/X99_DISPLAY (+свой XDG_RUNTIME_DIR).
4. Машины-двойники: КСО №2/№3 одинаковые hostname и юзер — различать UUID/MAC/IP; кириллический юзер 'Админ' не проходит в user@host (scp «invalid user name») — только -o User=; LAN-IP у машин DHCP и менялись.
5. Два VPS в документации: 217.144.184.51 (актуальный jump всех *_ssh.sh, KSO_VPS_HOST, SOCKS-канал прода) и 178.253.55.128 (RustDesk hbbs/hbbr + старые туннельные доки/сторожи kso_tunnel.ps1). Не смешивать; порт конкретной машины сверять по хелперу.
6. Профили/ключи/кадры в .gitignore (ssh_channel/, profiles/, screens*/): пароли и токены в git не попадают; чистка кадров не трогает эталоны (*tmpl*/*template*), git-файлы и .keepframes.

STALE-FRAME (семейство «картинка врёт»):
7. Каноничная съёмка молчала при провале и оставляла СТАРЫЙ кадр (T175: июльский кадр читали как «сейчас» и кликали по нему на живой кассе) → контракт shotlib: сносить артефакты ДО, SHOT_FAIL+код, ВРЕМЯ съёмки, путь последней строкой; неявная сцена старше RC_SCENE_MAX_MIN=30 мин — отказ; возраст сцены в каждом JSON vmatch/veye.
8. scrot не может перезаписать файл ДРУГОГО владельца (.jpg root, .png свой — читают .jpg прошлый).
9. RustDesk рисует мимо X-фреймбуфера (scrot отдаёт пустой стол при живой сессии); не перерисовывает статичное — шевелить указатель перед контрольным кадром (SendKeys отчитался, а кадр показал старое = «набор не сработал» — ЛОЖНО).
10. classify: live ≠ живая сессия (замороженный последний кадр классифицируется как live); рядом с окном сессии появляется голое окно «RustDesk» = диалог обрыва → livecheck (session_window/viewer_dialog/stale); viewer_dialog:1 = клики и клавиши НЕ доходят.
11. Кадр снимать по СОСТОЯНИЮ (окно закрылось / #modalSurface скрыт), не по таймеру: 1С-серверные вызовы длятся непостоянно, кадр через фикс. sleep показывает «прошлое».

КООРДИНАТЫ/КЛИКИ:
12. Нативный кадр 1920×1080 vs CDP-viewport 1903×1040 (native ≈ viewport + (8,120)); координаты с уменьшенного просмотра умножать (1500→×1.28, 1400→×1.371, 1200→×1.6); ImageMagick -crop +X+Y — ВСЕГДА пиксели, даже при задании размера в %.
13. Координаты из DOM (getBoundingClientRect) / vmatch / bbox — никогда «на глаз» с jpg; чужой puppeteer.connect без defaultViewport:null ужимает вьюпорт в 800×600 и валит всю верстку.
14. Verify-after-every-action (региональный diff); «клик не сработал» — сначала кадр/elementFromPoint (SPA-модалки не меняют URL); tap печатает landed=true/false и POST/PUT-ответы.
15. Не долбить клики по боевому кассовому GUI: каждый промах попадает КУДА-ТО ЕЩЁ (мусор в справочниках); способы закрытия модалки — по одному разу (Escape → клик заголовка+Escape → Alt+F4 → Tab+Enter → hwnd-сообщение), через 10 минут — программный путь (COM/агент).
16. Клавиатура требует РЕАЛЬНОГО клика для фокуса (окно вьювера на fluxbox, поле, окно 1С): windowactivate фокуса ввода НЕ даёт; «канал не отдаёт клавиатуру» = почти всегда «не в фокусе» (T320: полчаса потерь на известном открытии).
17. Эталоны: действительны для свежего кадра (после прокрутки экрана score падает 0.92→0.32) — click-template/field-left снимают кадр сами; ярлык приложения и установщик с ОДИНАКОВЫМ значком — различать подписью.

ВВОД ТЕКСТА:
18. КИРИЛЛИЦА посимвольно не доезжает ВООБЩЕ (в локальной раскладке Xvfb нет кириллических keysym; xdotool молча пропускает или падал без LC_ALL=C.UTF-8) — ТОЛЬКО буфер обмена.
19. Раскладка кассы РУС: латиница посимвольно превращается в «ту же клавишу по-русски» — Alt+Shift один раз + пробная строка; буфер от раскладки не зависит.
20. Буфер RustDesk: синк медленный (мелочь ~3 с; 30 КБ b64 рвётся при 3 с, ок при 8 с; 90 КБ ~14 с; авто = 3 + b64/8000), ДВУНАПРАВЛЕННЫЙ (вернёт старое — читать за NONCE); кириллица многословная — по одному слову или RD_CLIP_SYNC=5..8; «Магазин Мацеста» обрезалось до «Мацеста».
21. type_exact: раздельная посылка Shift; залп Shift портит следующую цифру (0→) 3→#); --clearmodifiers НЕ использовать (двойное нажатие Shift); таблица SPECIAL не содержит $ # % ( ) и ПРОБЕЛ.
22. Секреты: не в argv (ps), не в лог; typefile/файл 600; CDP_REMOTE_JS (выражение с секретом уже на машине); rps_run.ps1 САМ удаляет скрипт на удалённой стороне (на SERVER-1S находили брошенные .ps1 с паролями ИБ); в PowerShell маскировать секреты ДО обрезки строки.

RUSTDESK/ANYDESK:
23. Free-AnyDesk: обрывы ~5–8 мин; ТЕРЯЕТ ЗАГЛАВНЫЕ (Auto-mode Translate при разных раскладках); Ctrl+V в консоли Windows не вставляет (буфер синкан, но conhost не принимает; вставка — правая кнопка); UIPI: ввод неповышенного клиента в элевированные окна игнорируется.
24. СЛУЖЕБНЫЙ AnyDesk (LocalSystem) КЛИКАЕТ UAC secure-desktop (SOCHI11) и служебный RustDesk вводит в админ-окна — бутстрап-элевация без человека; портативный AnyDesk так НЕ умеет; UAC: слепой Enter = «Нет» (кнопка по умолчанию).
25. Постоянный админ-канал без UAC — SYSTEM-задача планировщика (KSO2Admin/SochiAdmin): schtasks /run от обычного юзера (ACL FRFX для Authenticated Users) → любой админ-шаг; ставить сразу после онбординга машины.
26. Клиент RustDesk «протухает» (>сутки → петля heartbeat/NAT → --connect молча exit 0, окно не открывается): rd_health refresh (пропускает живую сессию), cron 17 5; логи клиента 0.5–1 ГБ/сут → prune 7 500 (2.7 ГБ за месяц); «Remote desktop is offline» ВРЁТ — чинить свою сторону первой.
27. 4 процесса rustdesk.exe на машине = НОРМА (--service/--server/--tray/--cm); дубль = два процесса с ОДИНАКОВЫМ ключом; на кассе снимать ТОЛЬКО rustdesk.exe (electron = киоск, 1cv8 = 1С — торгуют).
28. Win/Super не пробрасывается (fluxbox перехватывает) — Пуск/поиск/двойной клик по ярлыку; Ctrl+Alt+Del — тулбар сессии.
29. Онбординг RustDesk: конфиг с НАШИМ сервером ДО первого запуска (иначе публичный); «Установить» службой; пароль И approve-mode пишутся ТОЛЬКО в СЛУЖЕБНЫЙ конфиг (ServiceProfiles\LocalService) и ТОЛЬКО с админ-правами — без прав «отрабатывает», но НЕ пишется (самая дорогая грабля); путь служебного конфига проверять ФАКТОМ (systemprofile vs ServiceProfiles); --get-id врёт (skip …dll), в конфиге id = enc_id → ID с экрана; приёмка = слепое переподключение без «Принять»; у пира view_style='original'+scrollauto → экран «прыгает» (peers/<ID>.toml: adaptive/scrollbar/edge_scroll=0).
30. Публичные серверы RustDesk требуют логин → свой hbbs/hbbr; NAT-пробы к 21115 и heartbeat к 21114 в логах клиента — НЕ фатально (21114 нет по дизайну).

1С-СПЕЦИФИКА:
31. Модалки веб-клиента: подложка #modalSurface.surfaceBlack z9000; окна — div[id$=win] с классом cloud (ps0win z≈9004 — простой вопрос; VW_pageNpsMwin z≈1004 — форма в вкладке; селектор по ХВОСТУ id — «^ps» теряет второй вид); кнопки — a.press (подпись = ТЕКСТОВЫЙ УЗЕЛ рядом: листовой обход не видит, rect узла 0×0 → кликать .pressBox); панель «Сообщения» ЛОЖИТСЯ ПОВЕРХ командной панели — hit-тест 5×5 внутри кнопки, при полном перекрытии — горячая клавиша из двойника «Еще» (ГотовоCtrl+Enter) + клик-фокус в свободную точку окна; вердикт = 3 исхода: окно ушло / страница ЗАНЯТА (клик дошёл! ждать, НЕ жать повторно) / на месте и отвечает (не дошёл); окно осталось, но ТЕКСТ изменился = тоже успех.
32. fill полей 1С: посимвольный keyDown(text)+keyUp (Input.insertText теряется — 1С видит пустую строку); Ctrl+A перед вводом; редактор поля создаётся асинхронно (~1.2 с); CDP-модификаторы = битовая маска (Alt=1 Ctrl=2 Meta=4 Shift=8); Ctrl+Enter через xdotool надёжнее CDP.
33. Веб-клиент и ТОНКИЙ клиент — РАЗНЫЕ случаи: у тонкого нет DOM → только картинка (modal-click --tmpl; эталоны с кадров ТОГО ЖЕ клиента); без CDP modal отвечает JSON cdp-unreachable с подсказкой.
34. Серверные вызовы 1С блокируют Runtime.evaluate на всё время вызова (наивная проверка врёт «клик не дошёл» — а он дошёл; Escape после сбрасывает ПОСЧИТАННУЮ скидку): одноразовый сокет, короткий таймаут, честный BUSY.
35. Расширение 1С с ошибкой компиляции НЕ применяется ЦЕЛИКОМ и МОЛЧА (видно только в журнале регистрации ConfigExtensionApplyError, причина в Comment; фильтр «все, кроме известных чужих»); проверка зацепок — t248_check_hooks.py.
36. Поле кода маркировки 1С не принимает ни Ctrl+V, ни посимвольный, ни GS — только СКАНЕР; марочный чек без человека у кассы не закладывать.
37. У SERVER-1S по RustDesk — ЭКРАН БЛОКИРОВКИ (консольный сеанс пуст): для кадров — веб-клиент (w1c_up.sh) или RDP-канал (srv1s_rdp.sh); beforeunload веб-клиента поднимает НАТИВНОЕ окно «Leave site?» и вешает CDP — нужный адрес открывать СРАЗУ (W1C_START); сеансы 1С не закрываются w1c down — rac session terminate отдельно (пул лицензий).

OCR/ЗРЕНИЕ/ТОКЕНЫ:
38. OCR без region+scale «not found» НИЧЕГО не доказывает (умолчание scale=2.0/psm 6; psm 11 для разрозненных; якорь — ЭТАЛОН vmatch, не текст); цветная плашка — один канал (жёлтый→b, розовый→g, голубой→r)+RC_BIN=1: белый на жёлтом в сером не читается ВООБЩЕ; пустой OCR ≠ элемента нет.
39. Дорогой агент НЕ грузит кадры в контекст (§27): vmatch/find/verify — 0 токенов; haiku-глаз — только УЗКИЙ кроп, мелкая сетка (--step 25), подписи с halo-обводкой (широкий кроп = мимо на сотни px); кропы-помощники писать в /tmp (не в screens/ — иначе «последний кадр» подхватит сам скан).

CDP/БРАУЗЕР:
40. Антибот: curl получает JS-заглушку (fs.atol.ru — ровно 13602 байта, маркер); решает только настоящий браузер; cookie живут минуты; UA обязан совпадать с cookie (__jua_); 403 с «IP: …» = бан (браузер не поможет), 401+JS = челлендж; SSH -D (SOCKS) для тяжёлых страниц медленный — браузер/curl НА удалённой машине.
41. Chrome ≥112 — headless=new; под root VPS --no-sandbox + --disable-dev-shm-usage; UA headless палится (HeadlessChrome/) — override; --dump-dom челлендж не проходит; GUID RFC6455 — ошибка в символе даёт молчаливый mismatch Accept.
42. Доверенный клик: el.click() не берут vaadin-grid (контент в light-DOM vaadin-grid-cell-content) — Input.dispatchMouseEvent по координатам getBoundingClientRect (mk_rect.py --scroll обязателен ниже фолда: viewport-координаты); ДВОЙНОЙ клик = ДВЕ пары press/release (clickCount 1, затем 2) — одно событие clickCount:2 не даёт dblclick.
43. Модалка может быть <iframe> — innerText страницы её НЕ покажет: CDP_FRAME=<подстрока URL>; постбэки откладывать setTimeout (EVAL=NULL); кириллица в .js — \uXXXX; -NoNav → -Url НЕ передавать вовсе; фиксированный settle — ставка → CDP_WAIT предикат; ClientWebSocket — ОДИН незавершённый ReceiveAsync.
44. Кабинет ЦРПТ: /api/v3/facade/* — вечный 403 (мёртвый префикс; живой /bff-elk, Bearer отовсюду); ЭЦП-вход = attached-подпись над UTF-8-байтами (detached → 403 код 2); SignedCms silent=true; CAdESCOM из PS падает; токен — JWT в localStorage + куки tokenPart<N> на domain=.crpt.ru; фильтр cis требует СПИСОК (два разных 400); выбытие через ККТ — в «Чеках», не в «Документах».
45. PowerShell-гочи: переменные РЕГИСТРОНЕЗАВИСИМЫ ($h/$H — одна); Try — зарезервировано; однобуквенные имена = алиасы (H=Get-History — аргумент-токен утёк в ошибку); Функция|Out-Null глотает вывод (0 байт = «ничего»); per-object Out-String после Format-Table падает → Out-String -Stream; cp866-мойбейк по SSH → -EncodedCommand/file+BOM; cmd.exe парсит ssh-команду раньше PS (*>&1 съедается).
46. Вьювер на десктопе Windows (WSLg :0): живёт ТОЛЬКО в ПЕРСИСТЕНТНОЙ tmux-сессии от root (прямой setsid умирает; env -i от hgff не стартует); по :0 НЕ снимать (RAIL/чёрный кадр) — только :98/:99.

Плюс всё из Windows-раздела (е) выше — Selectel/catbox/remote-exec и пр. полностью относятся и к WSL-фреймворку.

---
Детальный конспект по каждому файлу WSL-фреймворка — NOTES.md (раздел «WSL-фреймворк» после Windows-части).
