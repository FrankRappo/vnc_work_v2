#!/bin/bash
# w1c_up.sh — поднять КАДРОПРИГОДНЫЙ сеанс ВЕБ-КЛИЕНТА 1С и войти в него.
#
# 🔴 Зачем. Удалённые экраны боевого контура регулярно непригодны для кадра: SERVER-1S по RustDesk
#    отдаёт ЭКРАН БЛОКИРОВКИ (в консольном сеансе никого нет — T311 28.08, подтверждено T316 02.09),
#    машина кассира — чёрный кадр. А веб-публикация базы на IIS жива всегда. Открываем её в СВОЁМ
#    Chromium через ssh-туннель: кадр снимается с НАШЕГО X-сервера и заведомо не врёт, координаты
#    берутся из DOM (`w1c.py`), а не «на глаз».
#
# 🔴 Пароль не печатается и в argv не попадает — только переменная среды для w1c.py.
# 🔴 Запускать с dangerouslyDisableSandbox (ssh) и из-под hgff.
#
#   bash w1c_up.sh up            поднять туннель + X + браузер и войти
#   bash w1c_up.sh down          снять браузер, X-дисплей и туннель за собой
#   bash w1c_up.sh status        что сейчас поднято
#
# env (значения по умолчанию — боевой контур КСО):
#   W1C_SSH=/work/vnc_work_v2-vm121-review/srv1s_ssh.sh   чем ходить на машину с публикацией
#   W1C_PUB=/kso/ru/                                      путь публикации базы на IIS
#   W1C_HTTP=9180  W1C_CDP=9333  W1C_DISPLAY=:99
#   W1C_USER=ОтрошенкоЛВ                                  ИБ-пользователь
#   W1C_START=<url>                                       АДРЕС, НА КОТОРОМ ОТКРЫТЬ БРАУЗЕР
#     По умолчанию — корень публикации. Задают его, когда нужно попасть СРАЗУ на конкретную форму
#     (`…/e1cib/app/Документ.ЧекККМ.Форма.ФормаДокументаРМК`).
#     🔴 Зачем отдельной переменной, а не «зайти и перейти по ссылке»: веб-клиент 1С вешает на
#     страницу `beforeunload`, и переход через `location.href` поднимает НАТИВНОЕ окно браузера
#     «Leave site?». Пока оно висит, CDP не отвечает вообще — Runtime.evaluate уходит в таймаут, и
#     сеанс приходится добивать вручную (поймано T375 12.09.2026). Открыть нужный адрес СРАЗУ —
#     значит не создавать этого окна вовсе. Проверка живости публикации по-прежнему идёт на
#     W1C_PUB, а не на этот адрес: у формы может быть свой код ответа.
#   W1C_PASS=…                                            пароль; если пуст — берётся из CREDENTIALS.md
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="${W1C_SSH:-/work/vnc_work_v2-vm121-review/srv1s_ssh.sh}"
PUB="${W1C_PUB:-/kso/ru/}"
HTTP="${W1C_HTTP:-9180}"
CDP="${W1C_CDP:-9333}"
DISP="${W1C_DISPLAY:-:99}"
USER1C="${W1C_USER:-ОтрошенкоЛВ}"
START="${W1C_START:-}"
PROFILE="${W1C_PROFILE:-/tmp/w1c_chrome}"
W="python3 $DIR/w1c.py"

case "${1:-status}" in

down)
  pkill -9 -f "remote-debugging-port=$CDP" 2>/dev/null
  pkill -f "$HTTP:127.0.0.1:80" 2>/dev/null
  pkill -f "Xvfb $DISP" 2>/dev/null
  echo "СНЯТО: браузер, X-дисплей $DISP, туннель $HTTP"
  echo "🔴 сеансы 1С на СЕРВЕРЕ так не закрываются — снимать их отдельно (rac session terminate),"
  echo "   иначе они висят в пуле лицензий до таймаута."
  exit 0
  ;;

status)
  ss -ltn 2>/dev/null | grep -q ":$HTTP " && echo "туннель $HTTP: ЕСТЬ" || echo "туннель $HTTP: нет"
  curl -s -m 5 "http://127.0.0.1:$CDP/json/version" >/dev/null 2>&1 && echo "браузер CDP $CDP: ЕСТЬ" || echo "браузер CDP $CDP: нет"
  pgrep -f "Xvfb $DISP" >/dev/null && echo "X-дисплей $DISP: ЕСТЬ" || echo "X-дисплей $DISP: нет"
  exit 0
  ;;

esac

# 1. Туннель к IIS с публикацией базы
if ! ss -ltn 2>/dev/null | grep -q ":$HTTP "; then
  setsid bash "$SSH" -N -L "$HTTP:127.0.0.1:80" >/tmp/w1c_tunnel.log 2>&1 &
  for i in $(seq 1 20); do ss -ltn 2>/dev/null | grep -q ":$HTTP " && break; sleep 1; done
fi
ss -ltn 2>/dev/null | grep -q ":$HTTP " || { echo "ТУННЕЛЬ НЕ ПОДНЯЛСЯ — смотри /tmp/w1c_tunnel.log"; exit 1; }
code=$(curl -s -m 20 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$HTTP$PUB")
echo "туннель $HTTP OK, публикация $PUB отвечает $code"
[ "$code" = "200" ] || { echo "публикация не отвечает 200 — дальше идти незачем"; exit 1; }

# 2. X-дисплей и браузер. 🔴 Свой Xvfb, а НЕ :0 — на :0 в WSLg сидит рабочий стол пользователя.
pgrep -f "Xvfb $DISP" >/dev/null || { setsid Xvfb $DISP -screen 0 1920x1080x24 -nolisten tcp >/dev/null 2>&1 & sleep 3; }
pgrep -f "fluxbox" >/dev/null || { setsid env DISPLAY=$DISP fluxbox >/dev/null 2>&1 & sleep 2; }
if ! curl -s -m 5 "http://127.0.0.1:$CDP/json/version" >/dev/null 2>&1; then
  rm -rf "$PROFILE"
  setsid env DISPLAY=$DISP chromium --no-sandbox --disable-gpu \
    --remote-debugging-port=$CDP --remote-allow-origins='*' \
    --window-position=0,0 --window-size=1920,1080 --user-data-dir="$PROFILE" \
    --lang=ru-RU --no-first-run --no-default-browser-check --disable-features=Translate \
    "http://127.0.0.1:$HTTP${START:-$PUB}" >/dev/null 2>&1 &
  for i in $(seq 1 40); do curl -s -m 3 "http://127.0.0.1:$CDP/json/version" >/dev/null 2>&1 && break; sleep 2; done
fi
curl -s -m 5 "http://127.0.0.1:$CDP/json/version" >/dev/null 2>&1 || { echo "БРАУЗЕР НЕ ПОДНЯЛСЯ"; exit 1; }
echo "браузер CDP $CDP поднят на $DISP${START:+ (стартовый адрес: $START)}"

# 3. Дождаться формы входа и войти
for i in $(seq 1 40); do
  v=$(CDP_PORT=$CDP timeout 20 $W eval "document.getElementById('authWindow_basic_login')?1:0" 2>/dev/null)
  [ "$v" = "1" ] && break
  sleep 3
done
PASS="${W1C_PASS:-}"
if [ -z "$PASS" ]; then
  case "$USER1C" in
    ОтрошенкоЛВ) PASS=$(sudo grep -oP '\*\*ОтрошенкоЛВ\*\* \(`\K[^`]+' /work/kso/CREDENTIALS.md 2>/dev/null | head -1) ;;
    КСО)         PASS=$(sudo grep -oP 'пароль \*\*`\K[^`]+' /work/kso/CREDENTIALS.md 2>/dev/null | sed -n '1p') ;;
  esac
fi
[ -z "$PASS" ] && { echo "ПАРОЛЬ для «$USER1C» не найден — задай W1C_PASS"; exit 2; }
CDP_PORT=$CDP P1C_USER="$USER1C" P1C_PASS="$PASS" timeout 90 $W login
echo "вход отправлен под «$USER1C»; жду командный интерфейс"
for i in $(seq 1 40); do
  t=$(CDP_PORT=$CDP timeout 20 $W text 4000 2>/dev/null)
  case "$t" in
    *"Начальная страница"*) echo "ИНТЕРФЕЙС ГОТОВ"; exit 0;;
    # С W1C_START интерфейс открывается СРАЗУ на заказанной форме, и «Начальной страницы» в тексте
    # может не быть вовсе — ждём тогда любого непустого интерфейса с шапкой приложения.
    *"1С:Предприятие"*) [ -n "$START" ] && { echo "ИНТЕРФЕЙС ГОТОВ (стартовый адрес)"; exit 0; };;
  esac
  sleep 3
done
echo "интерфейс за 2 минуты не появился — сними кадр: CDP_PORT=$CDP $W shot /tmp/w1c.png"
exit 3
