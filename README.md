# vnc_work_v2 — надёжный таргетинг для удалённого управления (AnyDesk/RustDesk/VNC)

v2 чинит главную боль пиксельных драйверов `/work/vnc_work` (anydesk_kso.sh,
rustdesk/x99.sh): **слепой клик по угаданным координатам**. Там цикл был
«scrot → Read jpg → прикинуть X,Y на глаз → xdotool click» — и haiku по
уменьшенному кадру мазал на ±20–50 px, попадая между кнопок.

Оригинал (`/work/vnc_work`) НЕ тронут — это отдельная папка с рабочим ядром.

---

## Идея v2 («haiku-глаз с точными координатами»)

Дорогой основной агент **никогда не грузит скриншот в свой контекст** (не жжёт
токены/лимит). Координаты для клика он получает как ЧИСЛА, а не «на глаз», одним
из двух способов — оба делают пиксель *вычисленным*, а не угаданным:

1. **Template-matching (основной путь, вообще без LLM-глаз).** Есть эталон-кроп
   элемента (кнопка/иконка) → `vmatch find` даёт точный центр + `score`. Ниже
   порога — `found:false` = *зарепорченный промах*, а НЕ дикий клик.
2. **Haiku-глаз по КРОПУ с координатной сеткой (когда эталона нет).** Основной
   агент вырезает зону, увеличивает 3× и штампует сетку, подписанную **реальными
   пикселями экрана** (`veye crop --grid`). Дешёвый haiku-субагент читает
   координату *по линейке* крупного чёткого кропа и возвращает точку; обратный
   пересчёт в полный кадр — арифметика (`veye deproject`), без ошибки масштаба.

Плюс три обязательных механизма надёжности:
- **verify-after-every-action** — скрин до/после, региональный diff по зоне
  цели; `changed:false` ⇒ промах ⇒ не продолжаем из неверного состояния (retry).
- **калибровка смещения панели** AnyDesk/RustDesk — `vmatch calibrate` находит
  якорь и меряет offset ОДИН раз, дальше он прибавляется к каждому клику.
- **reconnect** — классификатор живости кадра (live/black/banner) + backoff,
  **предпочтение стабильного RustDesk-канала** (AnyDesk-free рвётся ~5 мин).

---

## Состав

```
vnc_work_v2/
  rc.sh                 драйвер: shot | find | crop | grid | deproject | ocr |
                        click | click-template | verify | calibrate | classify |
                        reconnect | selftest   (DRY-RUN по умолчанию!)
  lib/
    vmatch.py           template-match (multi-scale + edges) / verify / calibrate
    veye.py             haiku-глаз: crop+grid / deproject / roi / grid / ocr(опц.)
    reconnect.py        classify(live/black/banner) / backoff / plan
  fixtures/
    make_fixtures.py    генератор ЛОКАЛЬНЫХ синтетических скринов (ground truth)
  examples/demo.sh      сквозной проход всех механизмов на фикстуре
  test/
    test_core.py        14 юнит-тестов (пиксель-в-пиксель)
    run_tests.sh        фикстуры + юнит-тесты + dry-run проверка драйвера
```

Зависимости: `python3` + `opencv-python` (cv2) + `numpy` (есть в окружении:
cv2 4.13, numpy 2.4). Для `shot/click` — `scrot`/`xdotool`. OCR — опционально
`tesseract` (если нет, `veye ocr` аккуратно деградирует, основной путь —
template-match — не страдает).

---

## 🔴 Безопасность (почему это не тронет живые прод-машины)

`rc.sh` **по умолчанию DRY-RUN**: `click`/`click-template`/`reconnect --run`
НИЧЕГО не жмут на живой машине, пока явно не выставлен `RC_LIVE=1`. Всё ядро
работает с файлами-изображениями. Тесты и demo идут без `RC_LIVE` → ни одного
реального клика/коннекта. Никакого хардкода: дисплей, папка скринов, бэкенд
захвата, ID целей и offset — из env с дефолтами (runtime-discovery).

---

## Быстрый старт (офлайн, на фикстуре)

```bash
cd /work/vnc_work_v2
python3 fixtures/make_fixtures.py     # сгенерить локальные скрины
bash examples/demo.sh                 # сквозной проход всех механизмов
bash test/run_tests.sh                # 14 тестов + dry-run драйвера
```

## Боевой цикл (когда :99 поднят и RC_LIVE=1 разрешён явно)

```bash
# эталонный путь: найти по шаблону, кликнуть, ПРОВЕРИТЬ, повторить при промахе
RC_LIVE=1 bash rc.sh click-template templates/pay_button.png

# калибровать offset панели один раз (якорь = уголок удалённого стола)
bash rc.sh shot cur
bash rc.sh calibrate templates/anchor.png 0,0      # → screens/.offset

# haiku-глаз, если шаблона нет:
bash rc.sh shot cur
bash rc.sh crop 480,440,320,140 /tmp/zone.png 3.0 --grid   # → отдать haiku
#   haiku вернул точку (px,py) НА КРОПЕ:
bash rc.sh deproject 480,440 3.0 480,195                   # → реальные x,y
RC_LIVE=1 bash rc.sh click <x> <y>

# сессия жива?
bash rc.sh classify            # live | black | banner
bash rc.sh reconnect           # план (dry); --run + RC_LIVE=1 чтобы выполнить
```

Драйвер `rc.sh reconnect` делегирует сам коннект **оригинальным** скриптам
`/work/vnc_work/rustdesk/connect.sh` и `anydesk_kso.sh` (v2 их не дублирует и не
трогает) — задай `RC_RD_ID`/`RC_AD_ID` и запускай под `dangerouslyDisableSandbox`.

---

## Команды `rc.sh`

| Команда | Что делает | LLM-глаз? |
|---|---|---|
| `shot <label>` | захват дисплея → `screens/<label>.png(+jpg)` | — |
| `find <tmpl> [scene]` | template-match → точный центр + score (JSON) | нет |
| `click-template <tmpl>` | shot→find→click→**verify**→retry-once (флагман) | нет |
| `crop <x,y,w,h> <out> [scale] [--grid]` | кроп+увеличение+сетка для haiku | да |
| `deproject <ox,oy> <scale> <px,py>` | точка на кропе → реальный пиксель | — |
| `grid <out> [step]` | линейка координат поверх последнего скрина | да |
| `ocr <text> [scene]` | текст→координата (tesseract, опц.) | нет |
| `click <x> <y>` | клик (DRY-RUN без `RC_LIVE=1`), + offset | — |
| `verify <before> <after> <x,y,w,h>` | изменилась ли зона цели (exit 0=да) | нет |
| `calibrate <anchor> [expX,Y]` | offset панели → `screens/.offset` | нет |
| `classify [frame]` | живость: live / black / banner | нет |
| `reconnect [--run]` | план реконнекта (RustDesk-first) | нет |
| `selftest` | офлайн-тесты на фикстурах | — |

Env: `RC_DISPLAY RC_SCREENS RC_USER RC_MIN_SCORE RC_LIVE RC_SHOT_CMD RC_AD_ID
RC_RD_ID RC_PREFER RC_BANNER_TEMPLATE`.

---

## Как это устраняет ±20–50 px

- **Template-match** возвращает центр эталона в кадре с субпиксельной точностью и
  порогом уверенности — попадание либо точное, либо честный «не нашёл».
- **Крон+сетка+deproject**: haiku читает координату по линейке крупного кропа, а
  пересчёт `real = origin + point/scale` — арифметика. Ошибка «Read рендерит jpg
  в разном масштабе» исчезает как класс (масштаб известен и применён явно).
- **verify-after-action** ловит промах сразу (зона не изменилась) и не даёт
  агенту продолжать из неверного состояния.
- **calibrate** снимает системное смещение панели вьювера один раз.

Демонстрация точности — в `examples/demo.sh`: точка `(480,195)` на кропе
депроецируется ровно в центр кнопки `(640,505)`, 0 px ошибки.

---

## Миграция с оригинала (не ломая его)

v2 — надстройка, а не замена скриптов подъёма стека. Стек `:99` (Xvfb/fluxbox/
x11vnc + сам AnyDesk/RustDesk) поднимают **оригинальные** `anydesk_kso.sh up` /
`rustdesk/connect.sh`. v2 берёт на себя только «глаза+руки+проверку»: замените
слепые `x99.sh click X Y` на `rc.sh click-template <tmpl>` (или crop→deproject→
click). Оригинал остаётся рабочим фоллбэком.
