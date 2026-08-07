#!/bin/bash
# vnc.sh — универсальный VNC+CDP «руль» для веб-задач, которые не берутся headless'ом
# (входы в ЛК, OAuth/2FA, капчи, дашборды без API, виджеты/карты).
#
# СТЕК:  [SOCKS] → Xvfb :DISP → fluxbox → chromium(--remote-debugging-port=CDP) → x11vnc :PORT
#   Скрин агента: scrot по :DISP (НАТИВ 1920×1080). Человек смотрит/кликает: TigerVNC localhost:PORT.
#   Действия на странице: ЧЕРЕЗ CDP (cdp.mjs) — реальные мышь/клавиатура, UTF-8. xdotool — только
#   для браузерного chrome (попапы) / canvas, по координатам из `bbox`.
#
# 🔴 Запускать из агентского Bash с dangerouslyDisableSandbox (песочница режет sleep/ssh/chromium сигналом 16).
#
# КОНФИГ (env, со значениями по умолчанию):
#   VNC_DISPLAY=:98  VNC_PORT=5901  VNC_CDP=9334  VNC_PROFILE=/tmp/vnc_work_profile
#   VNC_SCREENS=/work/vnc_work_v2-vm121-review/screens  VNC_SOCKS=""  (напр. socks5://127.0.0.1:1080 для RU-IP)
#   VNC_SCREEN=1920x1080x24
#
# КОМАНДЫ:
#   up [URL]            поднять стек (идемпотентно). URL по умолчанию about:blank.
#   go <URL>            навигация (CDP)
#   shot <label>        scrot :DISP → screens/<label>.png + .jpg (jpg открывать Read'ом); печатает ВРЕМЯ съёмки
#   where               какой DISPLAY / каталог кадров использует ЭТОТ запуск
#   clean [сут]         кадры старше N суток → screens/attic/<ts>/ (не удаляет)
#   text [max]          innerText страницы (CDP)
#   find <regex>        найти кликабельные/инпуты по тексту → подсказка селекторов (CDP)
#   click <text|regex>  клик по видимому тексту (CDP, реальная мышь)
#   clicksel <css>      клик по CSS-селектору (CDP)
#   type <css> <value>  впечатать в поле (CDP, кириллица ок)
#   press <Key>         клавиша (Enter/Escape/Tab…) (CDP)
#   wait <css> [ms]     дождаться селектора (CDP)
#   eval '<js>'         выполнить JS в странице (CDP)
#   url                 URL вкладок
#   tabs                список вкладок: id + url (CDP HTTP /json)
#   front <url-подстр>  вывести вкладку на передний план (CDP /json/activate) — если открылась чужая вкладка
#   closetab <url-подстр>  закрыть вкладку(и) по подстроке URL (CDP /json/close)
#   bbox <css|text>     нативные коорд. центра элемента "x y" (для xclick)
#   xclick <x> <y>      нативный клик мышью (xdotool) — для chrome-попапов/canvas
#   xkey <keyseq>       нативная клавиша (xdotool: Escape, ctrl+v…)
#   paste <text>        вставить текст через X-clipboard+Ctrl+V (xdotool) — запасной ввод
#   viewer              запустить TigerVNC-вьюер (или подключись Windows-TigerVNC к localhost:PORT)
#   status | down
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/shotlib.sh"          # защита от залежавшегося кадра (грабля kso-anydesk-stale-frame)
DISP="${VNC_DISPLAY:-:98}"; PORT="${VNC_PORT:-5901}"; CDP="${VNC_CDP:-9334}"
PROFILE="${VNC_PROFILE:-/tmp/vnc_work_profile}"; SCREENS="${VNC_SCREENS:-$HERE/screens}"
SCREEN="${VNC_SCREEN:-1920x1080x24}"; SOCKS="${VNC_SOCKS:-}"
# root -> runuser как hgff; сам hgff -> напрямую (runuser доступен только root). Без этой ветки
# драйвер НЕЛЬЗЯ проверить из агентской сессии (она под hgff): любая съёмка падала бы на runuser,
# а «проверить глаз» — единственный способ узнать, что он не подсовывает вчерашний кадр.
RUN(){ if [ "$(id -u)" = "0" ]; then runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" "$@"; else env DISPLAY="$DISP" "$@"; fi; }
NODE(){ runuser -u hgff -- env HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin NODE_PATH=/home/hgff/node_modules node "$HERE/cdp.mjs" "$CDP" "$@"; }
cdp_alive(){ curl -s -m3 "http://127.0.0.1:$CDP/json/version" >/dev/null 2>&1; }

seed_prefs(){  # выключить всплывашки: сохранение паролей, гео/нотификации
  runuser -u hgff -- mkdir -p "$PROFILE/Default"
  local pf="$PROFILE/Default/Preferences"
  if [ ! -f "$pf" ]; then
    runuser -u hgff -- bash -c "cat > '$pf'" <<'JSON'
{"credentials_enable_service":false,"profile":{"password_manager_enabled":false,"default_content_setting_values":{"notifications":2,"geolocation":2}}}
JSON
  fi
}

case "${1:-}" in
  up)
    URL="${2:-about:blank}"
    if [ -n "$SOCKS" ]; then
      if curl -s -m8 --socks5 "${SOCKS#socks5://}" https://api.ipify.org >/dev/null 2>&1; then
        echo "[=] SOCKS доступен: $SOCKS"
      else
        echo "[!] SOCKS недоступен: $SOCKS (подними туннель отдельно и повтори)"
      fi
    fi
    if cdp_alive; then echo "[=] стек уже поднят (CDP $CDP). Навигация: $0 go <URL>"; exit 0; fi
    mkdir -p "$SCREENS"; runuser -u hgff -- mkdir -p "$PROFILE"; seed_prefs
    rm -f "$PROFILE"/Singleton* "$PROFILE"/Default/DevToolsActivePort 2>/dev/null; true
    rm -f "/tmp/.X${DISP#:}-lock" 2>/dev/null; [ -e "/tmp/.X11-unix/X${DISP#:}" ] && rm -f "/tmp/.X11-unix/X${DISP#:}" 2>/dev/null; true
    for p in "Xvfb $DISP" "fluxbox.*$DISP" "x11vnc.*$PORT"; do pkill -f "$p" 2>/dev/null; done; sleep 1
    setsid runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin Xvfb "$DISP" -screen 0 "$SCREEN" -nolisten tcp >>/tmp/vnc_work.log 2>&1 </dev/null &
    sleep 2; RUN xdpyinfo >/dev/null 2>&1 || { echo "[X] Xvfb не встал"; exit 1; }
    setsid runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" fluxbox >>/tmp/vnc_work.log 2>&1 </dev/null &
    sleep 2
    PROXY=""; [ -n "$SOCKS" ] && PROXY="--proxy-server=$SOCKS"
    setsid runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
      /usr/local/bin/chromium --no-sandbox --disable-setuid-sandbox --remote-debugging-port="$CDP" \
      --user-data-dir="$PROFILE" --no-first-run --no-default-browser-check --disable-extensions --password-store=basic \
      --disable-features=PasswordLeakDetection $PROXY --window-position=0,0 --window-size=1920,1080 --new-window "$URL" \
      >>/tmp/vnc_work.log 2>&1 </dev/null &
    sleep 4
    setsid runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin x11vnc -display "$DISP" -rfbport "$PORT" -localhost -nopw -forever -shared -quiet >>/tmp/vnc_work.log 2>&1 </dev/null &
    sleep 2
    WIN=$(RUN xdotool search --class chromium 2>/dev/null | head -1); [ -n "$WIN" ] && RUN xdotool windowsize "$WIN" 1920 1080 2>/dev/null
    echo "[OK] стек поднят. CDP=$CDP VNC=localhost:$PORT URL=$URL ${SOCKS:+SOCKS=$SOCKS}"
    ;;
  go)       NODE go "$2" ;;
  text)     NODE text "${2:-4000}" ;;
  find)     NODE find "$2" ;;
  click)    NODE click "$2" ;;
  clicksel) NODE clicksel "$2" ;;
  upload)   NODE upload "$2" "${3:-input[type=file]}" ;;  # загрузить файл: upload <путь> [css-инпута]
  type)     NODE type "$2" "${3:-}" ;;
  press)    NODE press "$2" ;;
  wait)     NODE wait "$2" "${3:-15000}" ;;
  eval)     NODE eval "$2" ;;
  url)      NODE url ;;
  map)      NODE map "${2:-.}" ;;
  mclick)   NODE mclick "$2" "$3" ;;   # клик по VIEWPORT-координатам через CDP-мышь (надёжно)
  tap)      NODE tap "$2" "${3:-}" ;;  # 🟢 надёжный клик по тексту: scroll/zoom + проверка + отчёт сети + запомнить
  zoom)     NODE zoom "${2:-1}" ;;     # body zoom (0.8 поднимает фикс-футер в зону видимости)
  remember) NODE remember "$2" "${3:-}" ;;  # запомнить элемент по тексту без клика
  recall)   NODE recall "$2" ;;        # достать координаты из памяти (пере-находит вживую) → "x y"
  mem)      NODE mem ;;                 # показать память для текущего URL
  forget)   NODE forget "$2" ;;        # забыть запись/страницу
  keytype)  NODE keytype "$2" ;;       # ввод в сфокусированное поле (после mclick по полю)
  cclick)   # точный клик: координаты из DOM (map) → CDP-мышь. cclick '<regex>' [index]
    IDX="${3:-1}"; LINE=$(NODE map "$2" | sed -n "${IDX}p")
    CX=$(printf '%s' "$LINE" | cut -f1); CY=$(printf '%s' "$LINE" | cut -f2)
    if printf '%s' "$CX" | grep -qE '^[0-9]+$'; then NODE mclick "$CX" "$CY" >/dev/null; echo "cclick → $(printf '%s' "$LINE" | cut -f3-)"; else echo "нет совпадений по /$2/ (строка $IDX)"; fi ;;
  bbox)     NODE bbox "$2" ;;
  grant)    shift; NODE grant "$@" ;;
  xclick)   RUN xdotool mousemove "$2" "$3" click 1; echo "xclick $2 $3" ;;
  xkey)     RUN xdotool key "$2"; echo "xkey $2" ;;
  paste)    printf '%s' "$2" | runuser -u hgff -- env DISPLAY="$DISP" xclip -selection clipboard; RUN xdotool key ctrl+v; echo "pasted" ;;
  shot)     # печатает ВРЕМЯ съёмки; путь — последняя строка; провал = SHOT_FAIL + код 1 (shotlib.sh)
    shot_guarded "${2:-shot}" "$SCREENS" "$DISP" RUN || exit 1 ;;
  where)    shot_where "$DISP" "$SCREENS" ;;
  clean)    shot_clean "$SCREENS" "${2:-1}" ;;
  viewer)
    # 🔴 Рабочий способ (2026-07-02): окно вьювера на десктопе Windows (через WSLg :0) живёт ТОЛЬКО
    # если запущено в ПЕРСИСТЕНТНОЙ tmux-сессии. Прямой setsid/disown умирает при завершении вызова
    # (агентский bash тащит SIGTERM за детьми); запуск от hgff через `env -i` вьювер вообще не стартует
    # (пустой лог). Root + DISPLAY=:0 + tmux-сессия = работает (X0-сокет world-writable). См. VNC_LAUNCH.md.
    VS="vnc_viewer_$PORT"
    tmux kill-session -t "$VS" 2>/dev/null; sleep 1
    tmux new-session -d -s "$VS"; sleep 1
    tmux send-keys -t "$VS" "DISPLAY=:0 XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir xtigervncviewer -SecurityTypes None -Fullscreen=0 localhost:$PORT >/tmp/$VS.log 2>&1" Enter
    sleep 4
    if pgrep -f "xtigervncviewer.*localhost:$PORT" >/dev/null 2>&1; then
      echo "[+] вьювер-окно на десктопе Windows (tmux $VS; connect-лог /tmp/$VS.log). Снять: tmux kill-session -t $VS"
    else
      echo "[!] вьювер не поднялся — см /tmp/$VS.log; запасной путь: свой Windows-TigerVNC → localhost:$PORT"
    fi ;;
  tabs)
    curl -sS -m8 "http://127.0.0.1:$CDP/json" 2>/dev/null | python3 -c "import sys,json;[print(t['id'],'|',t.get('url','')[:90]) for t in json.load(sys.stdin) if t.get('type')=='page']" ;;
  front|closetab)
    # front <url-подстр> = вывести вкладку на перед; closetab <url-подстр> = закрыть. Через DevTools HTTP.
    ACT=$([ "$1" = closetab ] && echo close || echo activate)
    curl -sS -m8 "http://127.0.0.1:$CDP/json" 2>/dev/null | python3 -c "
import sys,json,urllib.request
port,act,sub=sys.argv[1],sys.argv[2],sys.argv[3]
if not sub: print('нужна подстрока URL: vnc.sh',act,'<url-подстр>'); sys.exit(1)
hit=0
for t in json.load(sys.stdin):
    if t.get('type')=='page' and sub in t.get('url',''):
        try: r=urllib.request.urlopen('http://127.0.0.1:%s/json/%s/%s'%(port,act,t['id']),timeout=8).read().decode()
        except Exception as e: r='ERR '+str(e)
        print(act,'->',t.get('url','')[:60],'::',r); hit+=1
        if act=='activate': break
if not hit: print('вкладок с URL ~',repr(sub),'нет')
" "$CDP" "$ACT" "${2:-}" ;;
  status)
    cdp_alive && echo "chromium/CDP $CDP: OK" || echo "chromium/CDP $CDP: нет"
    ss -ltn 2>/dev/null | grep -q ":$PORT " && echo "x11vnc $PORT: слушает" || echo "x11vnc $PORT: нет"
    [ -n "$SOCKS" ] && echo "SOCKS exit: $(curl -s -m8 --socks5 "${SOCKS#socks5://}" https://api.ipify.org 2>/dev/null)" ;;
  down)
    tmux kill-session -t "vnc_viewer_$PORT" 2>/dev/null
    pkill -f "remote-debugging-port=$CDP" 2>/dev/null; pkill -f "x11vnc.*$PORT" 2>/dev/null
    pkill -f "fluxbox.*$DISP" 2>/dev/null; pkill -f "Xvfb $DISP" 2>/dev/null; pkill -f "xtigervncviewer.*$PORT" 2>/dev/null
    echo "[OK] стек погашен (SOCKS, если был, оставлен)" ;;
  *) sed -n '2,60p' "$0"; exit 2 ;;
esac
