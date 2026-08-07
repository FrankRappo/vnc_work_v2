# vnc_work — универсальный VNC + CDP «руль» для веба

Инструмент, чтобы агент (и при необходимости человек) **управлял реальным браузером** на сервере:
входы в личные кабинеты, OAuth/2FA, капчи, дашборды без API, виджеты/карты, любые формы.
Берёт там, где не справляются headless-puppeteer и HTTP-клиенты: гео-блокировки, антибот-фингерпринт,
чужой капризный DOM, SMS/почтовые коды, капча. Человек в любой момент подключается к ТОМУ ЖЕ экрану
через TigerVNC и добивает то, что агент не может (SMS, залипшая reCAPTCHA).

> Происхождение: обобщено из реальных VNC/CDP-сессий по входам в кабинеты, OAuth/2FA,
> капчам, картам/виджетам и разовым web-only интеграциям.

---

## Когда использовать
- Веб-ресурс **не отдаёт API** или API за договором/онбордингом, а данные нужны из UI.
- Сайт **режет не-RU IP** / автоматизацию (СДЭК, Яндекс-виджеты, банки, госуслуги-подобное).
- Нужен **вход с капчей/2FA/SMS/почтовым кодом** — агент ведёт поток, человек добивает шаг.
- Надо **разово достать креды/ключи/настроить кабинет**, а не строить постоянную интеграцию.

Если у сайта есть нормальный API/HTTP — используй API, это быстрее. vnc_work — для «ручного» веба.

---

## Архитектура
```
[SOCKS5 (опц., RU-IP)] → Xvfb :98 → fluxbox → chromium(--remote-debugging-port=9334) → x11vnc :5901
                                                         │
        агент: scrot по :98 (НАТИВ 1920×1080) → jpg → Read     ← «видит глазами»
        агент: действия через CDP (cdp.mjs): click/type/eval   ← «руки» (реальные мышь/клава, UTF-8)
        человек: TigerVNC → localhost:5901                     ← добивает SMS/капчу
```
Два канала «рук»:
1. **CDP (основной)** — `click/clicksel/type/press/eval` через DevTools Protocol. Реальные события,
   кириллица без проблем, **без угадывания координат**. Так делается 90% действий.
2. **xdotool по координатам (запасной)** — только для того, что НЕ в DOM страницы: всплывашки самого
   браузера (сохранение пароля, гео), `<canvas>`/карты, капча-картинки. Координаты бери из `bbox`,
   не на глаз со скрина.

---

## Предпосылки (на машине уже есть)
`chromium` (/usr/local/bin/chromium), `x11vnc`, `Xvfb`, `fluxbox`, `scrot`, `xdotool`, `xclip`,
`convert` (ImageMagick), `node` + `/home/hgff/node_modules/puppeteer`, `sshpass` (для SOCKS).
Запуск — от root (внутри `runuser -u hgff`), из агентского Bash **с `dangerouslyDisableSandbox: true`**
(песочница убивает長 sleep/ssh/chromium сигналом 16).

---

## Быстрый старт
```bash
# поднять стек (по умолчанию без прокси). Для RU-IP: VNC_SOCKS=socks5://127.0.0.1:1080
bash /work/vnc_work_v2-vm121-review/vnc.sh up "https://example.com/login"

# посмотреть глазами
bash /work/vnc_work_v2-vm121-review/vnc.sh shot step01            # → screens/step01.jpg → открыть Read'ом

# найти селектор и действовать через CDP (без координат!)
bash /work/vnc_work_v2-vm121-review/vnc.sh find 'log ?in|войти'   # подсказка селекторов
bash /work/vnc_work_v2-vm121-review/vnc.sh type 'input[name=login]' 'user@example.com'
bash /work/vnc_work_v2-vm121-review/vnc.sh type 'input[type=password]' "$PW"
bash /work/vnc_work_v2-vm121-review/vnc.sh click 'LOG IN'          # клик по видимому тексту
bash /work/vnc_work_v2-vm121-review/vnc.sh text                    # прочитать состояние страницы

# почтовый код (OAuth/passwordless)
python3 /work/vnc_work_v2-vm121-review/fetch_email_code.py --host imap.example.com --user user@example.com --pass "$PW" --from example

# браузерная всплывашка (не в DOM) — по координатам из bbox или просто xclick
bash /work/vnc_work_v2-vm121-review/vnc.sh xkey Escape

# человек добивает SMS/капчу:
#   Windows-TigerVNC → localhost:5901  (или `vnc.sh viewer`)

bash /work/vnc_work_v2-vm121-review/vnc.sh down                    # погасить стек
```

## Команды `vnc.sh`
| Команда | Что | Канал |
|---|---|---|
| `up [URL]` | поднять стек (идемпотентно) | — |
| `go <URL>` | навигация | CDP |
| `shot <label>` | scrot → `screens/<label>.{png,jpg}` | scrot |
| `text [max]` | innerText страницы | CDP |
| `find <regex>` | кликабельные/инпуты по тексту → селекторы | CDP |
| `click <text>` | клик по видимому тексту | CDP |
| `clicksel <css>` | клик по CSS | CDP |
| `type <css> <val>` | впечатать (UTF-8/кириллица) | CDP |
| `press <Key>` | Enter/Escape/Tab… | CDP |
| `wait <css> [ms]` | дождаться элемента | CDP |
| `eval '<js>'` | JS в странице (извлечь токен и т.п.) | CDP |
| `url` | URL вкладок | CDP |
| `bbox <css\|text>` | НАТИВНЫЕ коорд. центра элемента | CDP→экран |
| `xclick <x> <y>` | нативный клик мышью | xdotool |
| `xkey <seq>` | нативная клавиша (Escape, ctrl+v) | xdotool |
| `paste <text>` | вставка через clipboard+Ctrl+V | xdotool |
| `viewer` / `status` / `down` | вьюер / статус / погасить | — |

Конфиг через env: `VNC_DISPLAY VNC_PORT VNC_CDP VNC_PROFILE VNC_SCREENS VNC_SOCKS VNC_SCREEN`.
Разные задачи параллельно — задавай разные `VNC_DISPLAY`/`VNC_PORT`/`VNC_CDP`/`VNC_PROFILE`.

---

## Playbook (проверенный цикл)
1. `up <URL>` → `shot` → **Read jpg** → описать, что видно.
2. Действие — **через CDP**: `find` (узнать селектор) → `type`/`click`/`press`. Читать результат `text`/`url`.
3. **Всплывашка браузера** (save-password, гео) — обычно уже подавлена prefs'ами (см. ниже); если вылезла — `xkey Escape` или `xclick` по `bbox`.
4. **Код из почты** — `fetch_email_code.py`. **SMS/капча** — позвать человека в TigerVNC.
5. После каждого нетривиального шага — `shot` + Read (глаза — источник истины, не computed-style).
6. Извлечь нужное (`eval`/`text`), сохранить. `down` в конце (для лимитных кабинетов — обязательно).

---

## Грабли и решения (уроки)
- 🔴 **Не угадывай координаты по скрину.** Read рендерит jpg в РАЗНОМ масштабе → попадёшь мимо.
  Кликай/печатай **через CDP по селектору/тексту**. Координаты — только для не-DOM, и только из `bbox`
  (он считает нативные пиксели через `screenX/Y + (outerHeight-innerHeight)`).
- 🔴 **«Клик не сработал»? Сначала посмотри СКРИН, а не URL/сеть.** Модалки и настройки SPA
  открываются на ТОМ ЖЕ URL (напр. `…/terminals`) и часто без POST/PUT → успешный `mclick`/`click`/`tap`
  НЕ меняет URL и не «светит» сеть. Вывод «промах» по неизменному URL или обрезанному `text` — **ложный**.
  Проверяй `shot`+Read (и `elementFromPoint(x,y)` — что реально под точкой), а не косвенные признаки.
  Реальный кейс: `mclick` по «Настроить» открыл модалку, а вывод «мимо» сделали по URL — координаты были точные.
- **`find`/`tap`/`click` ранжируют кандидатов** (точное совпадение текста > по слову > startsWith > подстрока;
  −штраф `<a>` на чужой origin, +бонус button/tab). При неоднозначности (или единственный матч — cross-origin
  ссылка, увела бы со страницы) `tap`/`click` **НЕ кликают**, печатают `AMBIGUOUS:` со списком → уточняй
  `clicksel '<css>'` (в списке есть `sel=` с id/automation-id) или `CDP_FORCE=1` чтобы взять верхний.
- 🔴 **CDP надёжнее скрина и для чтения**: токены/статусы тяни `eval`/`text`, а не «вглядывайся» в jpg
  (32-символьный ключ глазами не прочитать без ошибок `l/I/1`, `O/0`).
- **Всплывашки браузера не в DOM** → CDP их не видит. Решение в `vnc.sh`: профиль создаётся с prefs
  `password_manager_enabled=false`, `notifications=2`, `geolocation=2` → бабблы не появляются. Остаточные — `xkey Escape`.
- **RU-IP / geo-specific сайты**: `VNC_SOCKS=socks5://127.0.0.1:1080` (или любой доступный SOCKS5).
  Проект НЕ поднимает внешний туннель сам: принеси свой SOCKS и держи его живым keepalive'ом.
- **Сессия живёт в профиле**: `VNC_PROFILE` хранит cookies → капчу/вход проходишь ОДИН раз, дальше
  стек поднимается уже залогиненным (как chatgpt-профиль). Бэкап профиля = бэкап сессии.
- **Песочница** Bash режет長 процессы сигналом 16 → всё, что поднимает стек/SOCKS/sleep, гонять с `dangerouslyDisableSandbox`.
- **scrot по :98**, НЕ по WSLg `:0` (там чёрный кадр / RAIL).
- **Лимитные кабинеты** (1С Fresh = 1 сеанс) — всегда `down`/logout в конце.
- **Кириллица**: `type` (CDP) и `paste` (xclip) — ок; «голый» `xdotool type` кириллицу ломает.

---

## 🟢 Клик «чтобы не мазать» — `tap` + ПАМЯТЬ КООРДИНАТ
Уроки реальных сессий заполнения сложных SPA-форм запечены в движок:

- **Кликай через `tap '<text>'`** — он сам: `scrollIntoView` → если кнопка ниже фолда (фикс-футер на
  viewport y>960, т.е. ниже физического экрана 1080) делает `zoom 0.8` → CDP-мышь в центр →
  **проверяет, что клик долетел** (`elementFromPoint`+listener, печатает `landed=true/false`) →
  **показывает POST/PUT-ответ сервера** (ловит ошибки, невидимые в UI — напр. `400 organization_not_found`).
- **Координаты — только VIEWPORT через CDP-мышь** (`mclick`/`tap`). НЕ xdotool по нативным: scrot=1920×1080,
  а viewport=1903×1040, `native ≈ viewport + (8,120)` (хром сверху) — нативный клик мажет на ~120px.
- **Проверяй поля по `input.value`**, не по `text`/`innerText` (значений инпутов там нет — иначе ложный «не заполнено»).
- **`map`** помечает кнопки ниже фолда `⬇below-fold(zoom/tap)`.

**Память координат** (`coords_memory.json`, per-URL) — чтобы потом легче писать скрипты:
```bash
bash vnc.sh tap 'Continue' continue    # клик + запомнить под именем 'continue'
bash vnc.sh remember 'BIC' bik-field    # запомнить поле без клика
bash vnc.sh mem                         # что знаем про текущий URL
bash vnc.sh recall continue            # пере-найти вживую → "x y" (свежие коорд)
```
Локатор = **текст+роль+тег** (стабильно у SPA с хеш-классами `iwHHDm…`, которые меняются между сборками);
координаты — подсказка. `recall` всегда пере-находит элемент вживую и отдаёт свежие координаты,
на сохранённые падает только если вживую не нашёл. `tap` авто-запоминает каждый успешный клик.

---

## Файлы
- `vnc.sh` — лончер стека + диспетчер действий (CDP + xdotool).
- `cdp.mjs` — CDP-движок (click/type/eval/bbox/**tap/mclick/zoom** + **память: remember/recall/mem/forget**).
- `coords_memory.json` — память координат (создаётся автоматически, per-URL).
- `fetch_email_code.py` — IMAP-хелпер для почтовых кодов подтверждения.
- `screens/` — сюда падают скрины (png + jpg).
- `IMPROVEMENTS.md` — что докрутить для скорости/надёжности.
- `examples/1c-vnc/` — обезличенные VNC-templates для 1C web / Fresh сценариев.
- `README.md` — этот файл.
