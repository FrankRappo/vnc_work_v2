#!/bin/bash
# rc.sh — vnc_work_v2 remote-control driver (reliable targeting + verify + reconnect).
#
# WHY v2: the legacy AnyDesk/RustDesk drivers (anydesk_kso.sh, rustdesk/x99.sh)
# read a screenshot by eye and click guessed pixels (+-20..50 px -> missed
# buttons). rc.sh replaces "guess" with:
#   * template matching (vmatch.py) -> exact element centre + confidence; below
#     threshold it REPORTS A MISS instead of clicking wild.
#   * a haiku-eye crop/grid (veye.py) whose coordinates are computed, not eyeballed.
#   * verify-after-every-click (before/after regional diff); on a miss it re-locates
#     and retries once, never proceeding from an unverified state.
#   * reconnect (reconnect.py) preferring the stable RustDesk channel.
#
# SAFETY: rc.sh is DRY-RUN by default. It NEVER performs a real click/keystroke on
# a live machine unless RC_LIVE=1 is set explicitly. Tests run without RC_LIVE, so
# no live cash register / AnyDesk session is ever touched. Everything is driven off
# image FILES; only `click*`/`reconnect --run` translate a match into xdotool, and
# only under RC_LIVE=1.
#
# Runtime discovery (no hardcode): display, screens dir, click backend, target IDs
# and the calibration offset are all read from env with sane defaults; nothing is
# pinned to one cash register or user.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$DIR/lib"
PY="${RC_PYTHON:-python3}"

# --- runtime-discovered config (all overridable via env) --------------------
DISPLAY_="${RC_DISPLAY:-:99}"                 # X display carrying the viewer
SCREENS="${RC_SCREENS:-$DIR/screens}"         # where shots land
USER_="${RC_USER:-hgff}"                      # display owner (for root->runuser)
MIN_SCORE="${RC_MIN_SCORE:-0.80}"             # refuse-to-click threshold
LIVE="${RC_LIVE:-0}"                          # 1 = really click; else dry-run
OFFSET_FILE="$SCREENS/.offset"                # calibrated toolbar offset DX,DY
mkdir -p "$SCREENS" 2>/dev/null

log(){ printf '%s\n' "$*" >&2; }
die(){ log "rc: $*"; exit 3; }

# xdotool/scrot on the right display. Root -> runuser as the display owner;
# non-root -> direct (the agent runs as the owner). No hardcode beyond env.
X(){
  if [ "$(id -u)" = "0" ]; then
    runuser -u "$USER_" -- env -i HOME="/home/$USER_" PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISPLAY_" "$@"
  else
    env DISPLAY="$DISPLAY_" "$@"
  fi
}

# Capture one frame to $1. Pluggable via RC_SHOT_CMD (runtime-discovered capture
# backend: scrot here, but could be a scheduled-task pull like shot1.sh, or — in
# offline tests — a fixture copier). RC_SHOT_DEST is exported for the custom cmd.
#
# 🔴 A frame must NEVER be inherited from an earlier run (kso-anydesk-stale-frame,
# 2026-08-05): the previous version left the old $dest (and its .jpg sibling) in
# place when capture failed, so the next reader picked up a week-old picture and
# reasoned about it as if it were now. We therefore delete both artefacts BEFORE
# capturing and treat "capture returned 0 but wrote nothing" as a failure too.
_shot_to(){
  local dest="$1" jpg="${1%.png}.jpg"
  rm -f "$dest" "$jpg" 2>/dev/null
  if [ -n "${RC_SHOT_CMD:-}" ]; then
    RC_SHOT_DEST="$dest" bash -c "$RC_SHOT_CMD" || { log "SHOT_FAIL: RC_SHOT_CMD failed -> $dest"; return 1; }
  else
    X scrot -o "$dest" 2>/dev/null || { log "SHOT_FAIL: scrot got nothing from DISPLAY=$DISPLAY_ -> $dest (is the display up?)"; return 1; }
  fi
  [ -s "$dest" ] || { log "SHOT_FAIL: capture returned 0 but $dest is empty/missing"; rm -f "$dest"; return 1; }
  return 0
}

_read_offset(){ [ -r "$OFFSET_FILE" ] && cat "$OFFSET_FILE" || echo "0,0"; }

# scene defaults to the most recent shot if not given
_last_scene(){ ls -t "$SCREENS"/*.png 2>/dev/null | head -1; }

# 🔴 Guard against reasoning over a stale frame. `ls -t | head -1` is exactly the
# trap that cost us a wrong conclusion on 2026-08-05: when a shot fails, the newest
# .png in the directory is some frame from days ago and every downstream command
# (crop/grid/find/ocr/classify) happily analyses it and returns a clean JSON.
# An IMPLICITLY chosen scene is age-checked; a scene named on the command line is
# trusted (the caller meant that file) but its age is still reported.
# RC_SCENE_MAX_MIN=0 disables the hard check.
SCENE_MAX_MIN="${RC_SCENE_MAX_MIN:-30}"
_scene_age_min(){ echo $(( ( $(date +%s) - $(stat -c %Y "$1" 2>/dev/null || echo 0) ) / 60 )); }
# _scene_guard <path> <implicit|explicit>
_scene_guard(){
  local s="$1" how="${2:-implicit}" age; age="$(_scene_age_min "$s")"
  log "scene: $s (снят $(date -d "@$(stat -c %Y "$s" 2>/dev/null || echo 0)" '+%Y-%m-%d %H:%M:%S'), ${age} мин назад)"
  if [ "$how" = implicit ] && [ "$SCENE_MAX_MIN" -gt 0 ] && [ "$age" -gt "$SCENE_MAX_MIN" ]; then
    die "STALE_SCENE: последний кадр в $SCREENS старше ${SCENE_MAX_MIN} мин (${age} мин) — это НЕ текущий экран.
    Сделай свежий: $0 shot <label>   (или сними проверку: RC_SCENE_MAX_MIN=0)"
  fi
}
# Pick the scene into the global SCENE. Deliberately NOT a command substitution:
# `die` inside $( ) would only kill the subshell and the caller would sail on with
# an empty path — the very kind of silent failure this whole change is about.
SCENE=""
# 🔴 ЛЕЙБЛ — ТОЖЕ ИМЯ КАДРА (T311, 29.08.2026). `shot <label>` печатает путь, а команды разбора
# принимали ТОЛЬКО путь: `rc.sh classify t311c` отвечало «нет такого кадра», хотя кадр только что
# снят и лежит в screens/. Разница между «снять» и «разобрать» в этом месте бессмысленна и стоит
# лишнего круга у каждого, кто ведёт GUI. Теперь голое имя доразворачивается в screens/<имя>.png
# (и .jpg), а сообщение об ошибке называет ОБА проверенных пути, чтобы не гадать.
_expand_scene(){
  local s="$1"
  [ -f "$s" ] && { printf '%s' "$s"; return 0; }
  case "$s" in */*) ;; *)
    [ -f "$SCREENS/$s.png" ] && { printf '%s' "$SCREENS/$s.png"; return 0; }
    [ -f "$SCREENS/$s.jpg" ] && { printf '%s' "$SCREENS/$s.jpg"; return 0; }
  ;; esac
  printf '%s' "$s"; return 1
}
_scene(){
  local s="${1:-}"
  if [ -n "$s" ]; then
    local e; e="$(_expand_scene "$s")" || die "нет такого кадра: $s (искал «$s» и «$SCREENS/$s.png»)"
    s="$e"; _scene_guard "$s" explicit
  else s="$(_last_scene)"; [ -n "$s" ] || die "no scene; run shot first"; _scene_guard "$s" implicit; fi
  SCENE="$s"
}

usage(){
  sed -n '1,32p' "$0"
  cat >&2 <<'EOF'

commands:
  shot <label>                         capture DISPLAY -> screens/<label>.png(+jpg); prints capture TIME, path last
  where                                which DISPLAY / screens dir / staleness limit THIS run uses
  clean [days]                         move frames older than N days (default 1) to screens/attic/<ts>/ (nothing deleted)
  find <template> [scene]              template-match -> exact centre + score (JSON)
  crop <x,y,w,h> <out> [scale] [--grid]   haiku-eye crop (coords computed, not eyeballed)
  grid <out> [step]                    stamp a labelled coordinate ruler over last shot
  deproject <ox,oy> <scale> <px,py>    map a point read on a crop -> real screen pixel
  ocr <text> [scene]                   optional tesseract text->coord (degrades cleanly)
  read [x,y,w,h] [scale] [psm] [scene] ДОСЛОВНЫЙ текст области кадра (tesseract, rus+eng)
                                       🔴 текст на ЦВЕТНОЙ плашке: RC_CHANNEL=b|g|r RC_BIN=1
                                       (белое на ЖЁЛТОМ в сером канале не читается вовсе — T307)
  hover <x> <y> [сек]                  подвести указатель без клика — показать подсказку 1С
  type <строка>                        набрать текст в поле с фокусом (DRY-RUN unless RC_LIVE=1)
  key <клавиши…>                       нажать клавиши: Return, Tab, ctrl+a (DRY-RUN unless RC_LIVE=1)
  click <x> <y>                        click (DRY-RUN unless RC_LIVE=1); applies offset
  click-template <template>            shot->find->click->VERIFY->retry-once (flagship)
  modal [--json]                       🔴 ЧТО ЗА МОДАЛЬНОЕ ОКНО 1С сейчас: заголовок, текст,
                                       кнопки с координатами (DOM и ЭКРАН), поля ввода
  modal-click <подпись> [--via cdp|x]  🔴 нажать кнопку модального окна 1С С ПРОВЕРКОЙ по DOM
                                       (--via x = настоящий указатель xdotool в НАТИВНЫХ пикселях)
  modal-click --tmpl <эталон>          то же для ТОНКОГО клиента: по картинке, без CDP
  modal-fill <текст>                   ввести текст в поле верхнего модального окна 1С
  modal-key <Enter|Escape|…>           клавиша в верхнее модальное окно 1С
  verify <before> <after> <x,y,w,h>    did the target region change? (exit 0=yes)
  calibrate <anchor> [expectX,Y]       measure toolbar offset -> screens/.offset
  classify [frame]                     session liveness: live | black | banner
  livecheck                            frozen-frame detector (viewer error dialog present?)
  reconnect [--run]                    print (or --run under RC_LIVE) the reconnect plan
  selftest                             run the offline fixture test

env: RC_DISPLAY RC_SCREENS RC_USER RC_MIN_SCORE RC_LIVE(=1 to really click)
     RC_AD_ID RC_RD_ID RC_PREFER(rustdesk|anydesk)
     RC_SCENE_MAX_MIN  max age (min) of an IMPLICITLY picked scene before commands refuse
                       to reason about it (default 30; 0 = off). Explicitly named scenes are
                       trusted but their age is still printed. See FIELD_NOTES: kso-anydesk-stale-frame.
EOF
}

case "${1:-}" in
  shot)
    # Prints WHEN the frame was taken and from which display, then the path as the
    # LAST line (callers do `| tail -1`). A silent path alone is what let a July
    # frame pass for "now".
    L="${2:-shot}"
    _shot_to "$SCREENS/$L.png" || die "capture failed on $DISPLAY_ (is the display up?)"
    if command -v convert >/dev/null; then
      convert "$SCREENS/$L.png" -quality 88 "$SCREENS/$L.jpg" 2>/dev/null \
        || { rm -f "$SCREENS/$L.jpg"; log "SHOT_WARN: convert не собрал JPG — .jpg удалён, чтобы не остался старый"; }
    fi
    OLD=$(find "$SCREENS" -maxdepth 1 -name '*.png' ! -name "$L.png" -mmin +360 2>/dev/null | head -3)
    [ -n "$OLD" ] && { log "ВНИМАНИЕ: в $SCREENS лежат СТАРЫЕ кадры (>6 ч) — не путать с текущим:"; log "$(printf '%s' "$OLD" | sed 's/^/  /')"; }
    echo "снят $(date '+%Y-%m-%d %H:%M:%S') DISPLAY=$DISPLAY_ size=$(stat -c%s "$SCREENS/$L.png")б"
    echo "$SCREENS/$L.png"
    ;;

  where)
    # which display and which frame directory THIS invocation uses — RC_SCREENS is
    # easy to pass on one call and forget on the next, and then frames diverge.
    echo "DISPLAY=$DISPLAY_"; echo "SCREENS=$SCREENS"; echo "RC_SCENE_MAX_MIN=$SCENE_MAX_MIN"
    ls -la --time-style=+%Y-%m-%d_%H:%M:%S "$SCREENS" 2>/dev/null | tail -n +2
    ;;

  clean)
    # move frames older than N days (default 1) out of the way into screens/attic/<date>/
    # Nothing is deleted: stale frames only have to stop being the newest .png.
    #
    # 🔴 Reference images STAY. vmatch templates live right next to the shots (*_tmpl*.png,
    # tmpl_*.png, *template*) and are SUPPOSED to be old — sweeping them into attic breaks
    # find/click-template. Extra exceptions: one glob per line in $SCREENS/.keepframes.
    # 🔴 Git-tracked frames stay too: some frame directories hold COMMITTED evidence attached to a
    # report (screens_t67/* — the T67 attachment). Sweeping those into attic shows up as 21 staged
    # deletions and quietly detaches the evidence from its report. Learned the hard way, 2026-08-05.
    DAYS="${2:-1}"; AT="$SCREENS/attic/$(date +%Y%m%d_%H%M%S)"
    TRACKED=""
    if git -C "$SCREENS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      TRACKED="$(git -C "$SCREENS" ls-files -- . 2>/dev/null | sed 's|.*/||')"
    fi
    MOVE=(); KEPT=()
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      b="$(basename "$f")"; k=0
      case "$b" in *tmpl*|*template*|*etalon*|*эталон*) k=1 ;; esac
      [ "$k" = 0 ] && [ -n "$TRACKED" ] && printf '%s\n' "$TRACKED" | grep -qxF "$b" && k=1
      if [ "$k" = 0 ] && [ -r "$SCREENS/.keepframes" ]; then
        while IFS= read -r g; do
          [ -n "$g" ] || continue; case "$g" in \#*) continue ;; esac
          case "$b" in $g) k=1; break ;; esac
        done < "$SCREENS/.keepframes"
      fi
      if [ "$k" = 1 ]; then KEPT+=("$b"); else MOVE+=("$f"); fi
    done < <(find "$SCREENS" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' \) -mtime +"$DAYS" 2>/dev/null)
    [ ${#KEPT[@]} -gt 0 ] && echo "clean: оставлены на месте — эталоны и файлы под git (${#KEPT[@]}): $(printf '%s ' "${KEPT[@]}")"
    N=${#MOVE[@]}
    if [ "$N" = "0" ]; then echo "clean: нечего убирать (нет кадров старше ${DAYS} сут в $SCREENS)"; exit 0; fi
    mkdir -p "$AT"
    printf '%s\0' "${MOVE[@]}" | xargs -0 mv -t "$AT" 2>/dev/null
    echo "clean: убрано $N кадров старше ${DAYS} сут -> $AT (не удалено)"
    ;;

  find)
    T="${2:?need template}"; _scene "${3:-}"; S="$SCENE"
    OFF="$(_read_offset)"
    "$PY" "$LIB/vmatch.py" find --scene "$S" --template "$T" \
        --min-score "$MIN_SCORE" --offset "$OFF" --json
    ;;

  crop)
    R="${2:?need x,y,w,h}"; O="${3:?need out}"; SC="${4:-3.0}"; shift 4 2>/dev/null || shift $#
    GRID=""; for a in "$@"; do [ "$a" = "--grid" ] && GRID="--grid"; done
    _scene ""; S="$SCENE"
    "$PY" "$LIB/veye.py" crop --scene "$S" --out "$O" --region "$R" --scale "$SC" $GRID --json
    ;;

  grid)
    O="${2:?need out}"; ST="${3:-100}"; _scene ""; S="$SCENE"
    "$PY" "$LIB/veye.py" grid --scene "$S" --out "$O" --step "$ST" --json
    ;;

  deproject)
    "$PY" "$LIB/veye.py" deproject --origin "${2:?ox,oy}" --scale "${3:?scale}" --point "${4:?px,py}" --json
    ;;

  ocr)
    # ocr <text> [scene] [region X,Y,W,H] [scale]
    # 🔴 Region+scale matter: on a full 1920x1080 frame tesseract reads none of the small UI
    # captions, so a "not found" there is not evidence of absence. Crop to the area and scale 3x.
    # 🔴 T317, 02.09.2026: УМОЛЧАНИЕ МАСШТАБА 1.0 БЫЛО ЛОВУШКОЙ. Ровно то, о чём предупреждает
    # комментарий выше, случалось на каждом втором вызове: `ocr «Поиск по списку»` отвечал
    # "not found", хотя надпись на экране есть и `read` её читает. «Не найдено» при scale=1
    # означает только «мелко», а читается как «этого нет на экране» — и приёмка идёт искать
    # несуществующую поломку. Умолчание переведено на 2.0 (как у `read`), psm 6 — сплошной блок.
    TX="${2:?need text}"; _scene "${3:-}"; S="$SCENE"
    RG="${4:-}"; SC="${5:-${RC_OCR_SCALE:-2.0}}"; PSM="${6:-6}"
    if [ -n "$RG" ]; then
      "$PY" "$LIB/veye.py" ocr --scene "$S" --text "$TX" --region "$RG" --scale "$SC" --psm "$PSM" --json
    else
      "$PY" "$LIB/veye.py" ocr --scene "$S" --text "$TX" --scale "$SC" --psm "$PSM" --json
    fi
    ;;

  read)
    # read [x,y,w,h] [scale] [psm] [scene] — ДОСЛОВНЫЙ текст области последнего кадра.
    # 🔴 Это то, чем отчёт цитирует экран, не загружая картинку в контекст дорогого агента (§27).
    # Без региона читается весь кадр; мелкие подписи 1С при scale=1 не читаются вообще, поэтому
    # умолчание scale=2 и psm=6 (сплошной блок). Для разрозненных подписей — psm 11.
    # 🔴 RC_CHANNEL=b|g|r|gray + RC_BIN=1 — для текста на ЦВЕТНОЙ плашке. Белая надпись на ЖЁЛТОЙ
    # кнопке киоска («Скидочная карта») в сером канале не читается ВООБЩЕ: жёлтый и белый почти
    # одинаково светлые, tesseract отдаёт пустоту, и кажется, что кнопки на экране нет (T307,
    # 25.08.2026). В синем канале жёлтый тёмный — надпись читается целиком. Правило: брать канал,
    # в котором ФОН самый тёмный (жёлтый→b, розовый→g, голубой→r).
    RG="${2:-}"; SC="${3:-2.0}"; PS="${4:-6}"; _scene "${5:-}"; S="$SCENE"
    EX=""
    [ -n "${RC_CHANNEL:-}" ] && EX="$EX --channel ${RC_CHANNEL}"
    [ "${RC_BIN:-0}" = "1" ] && EX="$EX --binarize"
    if [ -n "$RG" ] && [ "$RG" != "-" ]; then
      "$PY" "$LIB/veye.py" text --scene "$S" --region "$RG" --scale "$SC" --psm "$PS" $EX
    else
      "$PY" "$LIB/veye.py" text --scene "$S" --scale "$SC" --psm "$PS" $EX
    fi
    ;;

  type)
    # type <строка> — набрать текст в поле, имеющее фокус. DRY-RUN без RC_LIVE=1.
    # 🔴 xdotool type --clearmodifiers: без него залипшая Shift/Alt даёт другой символ.
    TXT="${2?need text}"
    if [ "$LIVE" = "1" ]; then
      X xdotool type --clearmodifiers --delay 40 -- "$TXT" && echo "typed ${#TXT} симв."
    else
      echo "DRY-RUN would type ${#TXT} симв.; set RC_LIVE=1 to execute"
    fi
    ;;

  hover)
    # hover <x> <y> — подвести указатель БЕЗ нажатия и подождать всплывающую подсказку.
    # 🔴 Зачем: 1С обрезает длинный текст поля многоточием, и полный текст виден ТОЛЬКО в
    # подсказке. Без hover отчёт цитирует «к оплате 2 000,00; начислим 100,00 бонус...» —
    # то есть теряет ровно те даты, ради которых сценарий и проверяется.
    X_="${2:?need x}"; Y_="${3:?need y}"; W="${4:-1.5}"
    OFF="$(_read_offset)"; DX="${OFF%%,*}"; DY="${OFF##*,}"
    FX=$((X_ + DX)); FY=$((Y_ + DY))
    if [ "$LIVE" = "1" ]; then
      X xdotool mousemove "$FX" "$FY" && sleep "$W" && echo "hovered $FX $FY (${W}s)"
    else
      echo "DRY-RUN would hover $FX $FY; set RC_LIVE=1 to execute"
    fi
    ;;

  typefile)
    # typefile <файл> — набрать содержимое файла, НЕ показывая его.
    # 🔴 Для паролей: аргумент команды виден в `ps` всей машине, файл 600 — нет.
    # Перевод строки в конце файла стал бы нажатием Enter, поэтому он срезается.
    F="${2:?need file}"; [ -r "$F" ] || die "typefile: не читается $F"
    N=$(LC_ALL=C.UTF-8 "$PY" -c 'import io,sys;print(len(io.open(sys.argv[1],encoding="utf-8").read().rstrip("\n")))' "$F")
    if [ "$LIVE" = "1" ]; then
      "$PY" -c 'import io,sys;sys.stdout.write(io.open(sys.argv[1],encoding="utf-8").read().rstrip("\n"))' "$F" \
        | X xdotool type --clearmodifiers --delay 40 --file - && echo "typefile: набрано $N симв. (значение не печатается)"
    else
      echo "DRY-RUN would type $N симв. from $F; set RC_LIVE=1 to execute"
    fi
    ;;

  key)
    # key <клавиши…> — xdotool key (Return, ctrl+a, Tab…). DRY-RUN без RC_LIVE=1.
    shift
    [ $# -gt 0 ] || die "key: нужны клавиши"
    if [ "$LIVE" = "1" ]; then
      X xdotool key --clearmodifiers "$@" && echo "key: $*"
    else
      echo "DRY-RUN would press: $*; set RC_LIVE=1 to execute"
    fi
    ;;

  click)
    X_="${2:?need x}"; Y_="${3:?need y}"
    OFF="$(_read_offset)"; DX="${OFF%%,*}"; DY="${OFF##*,}"
    FX=$((X_ + DX)); FY=$((Y_ + DY))
    if [ "$LIVE" = "1" ]; then
      X xdotool mousemove "$FX" "$FY" click 1 && echo "clicked $FX $FY (offset $OFF)"
    else
      echo "DRY-RUN would click $FX $FY (offset $OFF); set RC_LIVE=1 to execute"
    fi
    ;;

  scroll)
    # scroll <x> <y> <up|down> [шагов] — колесо мыши над точкой. Появилось в T301: экраны
    # приложения длиннее окна, и без прокрутки половина проверяемого просто не попадает в кадр,
    # а «не видно на кадре» читается как «этого нет». Клавиши PgDn тут не годятся: фокус может
    # стоять в поле ввода, и страница не поедет.
    X_="${2:?need x}"; Y_="${3:?need y}"; DIR_="${4:-down}"; N="${5:-3}"
    BTN=5; [ "$DIR_" = "up" ] && BTN=4
    OFF="$(_read_offset)"; DX="${OFF%%,*}"; DY="${OFF##*,}"
    FX=$((X_ + DX)); FY=$((Y_ + DY))
    if [ "$LIVE" = "1" ]; then
      X xdotool mousemove "$FX" "$FY" click --repeat "$N" --delay 120 "$BTN" && echo "scrolled $DIR_ x$N at $FX,$FY"
    else
      echo "DRY-RUN would scroll $DIR_ x$N at $FX,$FY; set RC_LIVE=1 to execute"
    fi
    ;;

  field-left)
    # field-left <эталон> [ширина_поля] [pad] — ПРОЧИТАТЬ ПОЛЕ ВВОДА СЛЕВА ОТ ЭЛЕМЕНТА-ЯКОРЯ.
    #
    # 🔴 ЗАЧЕМ ЭТО В ДРАЙВЕРЕ, А НЕ РАЗОВЫМ СКРИПТОМ В /tmp (урок T301, 24.08.2026).
    # Задача читала поле пароля приложения: сначала OCR искал подпись кнопки «ПОКАЗАТЬ» в
    # большой области — и НЕ НАХОДИЛ её, хотя кнопка была на экране. Причина не в кнопке:
    # tesseract на широкой области с мешаниной текста и psm 3 просто не выделяет короткое слово
    # мелкими прописными на светлой заливке; на узкой области та же кнопка читается с
    # уверенностью 96 %. Дальше пошли ручные кропы и подбор порогов — то есть ровно то, против
    # чего написан §27: одноразовая работа, которую следующая задача сделает заново.
    #
    # 🔴 ЛЕЧЕНИЕ — ЯКОРЬ ЭТАЛОНОМ, А НЕ ТЕКСТОМ. Кнопка ищется vmatch'ем (картинкой), а поле
    # читается по её координатам. Картинке всё равно, какой у окна масштаб и что рядом написано.
    # Эталоны экрана лежат в templates/loyalty_app/.
    #
    # Печатает: строку «якорь: <x,y,w,h>» и прочитанный текст поля.
    T="${2:?нужен эталон (templates/…png)}"; W="${3:-130}"; PAD="${4:-8}"
    _shot_to "$SCREENS/_fl.png" || die "capture failed"
    M=$("$PY" "$LIB/vmatch.py" find --scene "$SCREENS/_fl.png" --template "$T" \
          --min-score "$MIN_SCORE" --offset "$(_read_offset)" --json)
    FOUND=$(printf '%s' "$M" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("found"))')
    if [ "$FOUND" != "True" ]; then echo "field-left: якорь не найден ($M)"; exit 2; fi
    read BX BY BW BH < <(printf '%s' "$M" | "$PY" -c \
      'import sys,json;d=json.load(sys.stdin);print(d["left"],d["top"],d["w"],d["h"])')
    echo "якорь: $BX,$BY,$BW,$BH"
    "$PY" - "$SCREENS/_fl.png" "$BX" "$BY" "$BH" "$W" "$PAD" <<'PYEOF'
import sys
from PIL import Image
scene, bx, by, bh, w, pad = sys.argv[1], *map(int, sys.argv[2:])
im = Image.open(scene)
# 🔴 Поле берём ЛЕВЕЕ якоря и чуть выше/ниже его строки: у кнопки и поля общая базовая линия,
#    но поле выше на пару пикселей — обрезав по высоте кнопки, мы срезаем верх букв.
box = (max(0, bx - pad - w), max(0, by - pad), max(1, bx - pad), min(im.height, by + bh + pad))
crop = im.crop(box)
# Увеличение + порог: мелкий текст поля иначе не читается вовсе (та же причина, что у --scale).
crop = crop.resize((crop.width * 6, crop.height * 6), Image.LANCZOS).convert('L')
crop = crop.point(lambda p: 0 if p < 140 else 255)
crop.save('/tmp/_fl_pole.png')
PYEOF
    "$PY" "$LIB/veye.py" text --scene /tmp/_fl_pole.png --scale 1 --psm 7
    ;;

  rclick)
    # rclick <x> <y> — ПРАВЫЙ клик. Появился в T301: контекстное меню — второй путь к вставке
    # (первый, Ctrl+V, ломает нелатинская раскладка), и проверять его надо тем же движением,
    # каким его делает человек. Драйвер до этого умел только левую кнопку.
    X_="${2:?need x}"; Y_="${3:?need y}"
    OFF="$(_read_offset)"; DX="${OFF%%,*}"; DY="${OFF##*,}"
    FX=$((X_ + DX)); FY=$((Y_ + DY))
    if [ "$LIVE" = "1" ]; then
      X xdotool mousemove "$FX" "$FY" click 3 && echo "right-clicked $FX $FY (offset $OFF)"
    else
      echo "DRY-RUN would right-click $FX $FY (offset $OFF); set RC_LIVE=1 to execute"
    fi
    ;;

  dclick)
    # dclick <x> <y> [пауза_мс] — ДВОЙНОЙ клик. Появился в T301 (24.08.2026): ярлык на рабочем
    # столе Windows открывается только двойным нажатием, а `click` умеет одинарный. Обходились
    # двумя вызовами `click` подряд — и это НЕ то же самое: между отдельными вызовами проходит
    # больше времени, чем интервал двойного щелчка Windows (по умолчанию 500 мс), и рабочий стол
    # честно считает их двумя одиночными кликами. Поймано фактом на кассе: ярлык «Лояльность»
    # дважды «нажали», приложение не открылось ни разу.
    # 🔴 Тем же нужен и обратный опыт: «двойное нажатие ярлыка» — это проверка замка единственной
    #    копии (T299/T300), и она обязана нажимать ровно так, как нажимает человек.
    X_="${2:?need x}"; Y_="${3:?need y}"; MS="${4:-120}"
    OFF="$(_read_offset)"; DX="${OFF%%,*}"; DY="${OFF##*,}"
    FX=$((X_ + DX)); FY=$((Y_ + DY))
    if [ "$LIVE" = "1" ]; then
      X xdotool mousemove "$FX" "$FY" click --repeat 2 --delay "$MS" 1 && echo "double-clicked $FX $FY (offset $OFF)"
    else
      echo "DRY-RUN would double-click $FX $FY (offset $OFF); set RC_LIVE=1 to execute"
    fi
    ;;

  click-template)
    # flagship: shot -> find -> click -> verify-after -> retry-once. Never clicks
    # below threshold; never proceeds from an unverified state.
    T="${2:?need template}"
    attempt=1; ok=0
    while [ "$attempt" -le 2 ]; do
      _shot_to "$SCREENS/_ct_before.png" || die "capture failed"
      M=$("$PY" "$LIB/vmatch.py" find --scene "$SCREENS/_ct_before.png" --template "$T" \
            --min-score "$MIN_SCORE" --offset "$(_read_offset)" --json)
      echo "find[$attempt]: $M"
      FOUND=$(printf '%s' "$M" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("found"))')
      if [ "$FOUND" != "True" ]; then
        log "miss[$attempt]: below threshold ($MIN_SCORE) -> not clicking"; attempt=$((attempt+1)); continue
      fi
      read CX CY BX BY BW BH < <(printf '%s' "$M" | "$PY" -c \
        'import sys,json;d=json.load(sys.stdin);print(d["x"],d["y"],d["left"],d["top"],d["w"],d["h"])')
      if [ "$LIVE" = "1" ]; then
        X xdotool mousemove "$CX" "$CY" click 1
      else
        echo "DRY-RUN would click $CX $CY"
      fi
      sleep 0.4
      # 🔴 The after-frame decides whether the click worked. If capture fails here we
      # must NOT fall back to whatever _ct_after.png was left by an earlier run — that
      # verdict would be about a frame from another session entirely.
      _shot_to "$SCREENS/_ct_after.png" || die "capture failed AFTER the click — вердикт по клику невозможен (кадр не сравнить)"
      V=$("$PY" "$LIB/vmatch.py" verify --before "$SCREENS/_ct_before.png" \
            --after "$SCREENS/_ct_after.png" --region "$BX,$BY,$BW,$BH" --json)
      echo "verify[$attempt]: $V"
      CHANGED=$(printf '%s' "$V" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("changed"))')
      if [ "$LIVE" != "1" ]; then echo "(dry-run: verify is informational)"; ok=1; break; fi
      if [ "$CHANGED" = "True" ]; then ok=1; break; fi
      log "no change after click[$attempt] -> re-locate & retry"; attempt=$((attempt+1))
    done
    [ "$ok" = "1" ] && echo "click-template OK" || { echo "click-template FAILED (no verified click)"; exit 2; }
    ;;

  modal|modal-click|modal-fill|modal-key)
    # 🔴 МОДАЛЬНЫЕ ОКНА 1С. Две задачи подряд (T232 §4.1, T246 §8) встали на том, что кнопку «Да»
    # в вопросе 1С не удавалось нажать ничем: ни OCR-координатами, ни якорем от соседнего слова,
    # ни Enter, ни Left+Enter. Разбор — в lib/modal1c.py и в FIELD_NOTES («1c-modal-windows»).
    #
    # 🔴 ВЕБ-КЛИЕНТ И ТОНКИЙ КЛИЕНТ — РАЗНЫЕ СЛУЧАИ:
    #   веб-клиент  — окно 1С это DOM; работаем через CDP (порт RC_CDP_PORT), координаты и
    #                 подписи ТОЧНЫЕ, вердикт клика — «окно исчезло», а не диф картинки;
    #   тонкий клиент — DOM нет вообще; там только картинка: `modal-click --tmpl <эталон>`
    #                 (обычный template-match + клик в НАТИВНЫХ пикселях + контрольный кадр).
    SUB="${1#modal}"; SUB="${SUB#-}"; [ -n "$SUB" ] || SUB="scan"
    [ "$SUB" = "key" ] && SUB="keys"   # modal-key -> подкоманда keys
    shift
    # --tmpl уводит на путь картинки (тонкий клиент): CDP не нужен вовсе
    if [ "$SUB" = "click" ] && [ "${1:-}" = "--tmpl" ]; then
      shift; exec bash "$DIR/rc.sh" click-template "${1:?нужен эталон}"
    fi
    export CDP_PORT="${RC_CDP_PORT:-${CDP_PORT:-9222}}"
    export RC_DISPLAY="$DISPLAY_"
    "$PY" "$LIB/modal1c.py" "$SUB" "$@"
    ;;

  verify)
    "$PY" "$LIB/vmatch.py" verify --before "${2:?before}" --after "${3:?after}" --region "${4:?x,y,w,h}" --json
    ;;

  calibrate)
    A="${2:?need anchor template}"; EXP="${3:-}"; S="$(_last_scene)"; [ -n "$S" ] || die "no scene"
    if [ -n "$EXP" ]; then
      R=$("$PY" "$LIB/vmatch.py" calibrate --scene "$S" --anchor "$A" --expect "$EXP" --json)
    else
      R=$("$PY" "$LIB/vmatch.py" calibrate --scene "$S" --anchor "$A" --json)
    fi
    echo "$R"
    OFF=$(printf '%s' "$R" | "$PY" -c 'import sys,json
d=json.load(sys.stdin)
print("%d,%d"%tuple(d["offset"])) if d.get("ok") else print("")' )
    [ -n "$OFF" ] && { echo "$OFF" > "$OFFSET_FILE"; echo "saved offset $OFF -> $OFFSET_FILE"; }
    ;;

  livecheck)
    # Is the viewer showing the REAL remote screen right now, or a FROZEN last frame?
    # classify() only measures picture content -- a dead session leaves the last frame on :99 and
    # still scores "live". The give-away is the viewer's own modal: alongside the session window
    # ("<id>@<host> - Remote Desktop - RustDesk") a bare "RustDesk" dialog appears on disconnect.
    # 🔴 Two bugs lived here: it read $RC_DISPLAY (unset -> `set -u` killed the
    # subshell) and it could not tell "no viewer dialog" from "could not look at all"
    # — with an empty window list it printed stale:false and exited 0, i.e. the
    # stale-frame detector itself reported "all good" while blind. Now: use the
    # resolved display, and refuse to answer if the display is not reachable.
    X xdpyinfo >/dev/null 2>&1 || die "livecheck: DISPLAY=$DISPLAY_ недоступен — ответить про свежесть кадра НЕЧЕМ (это не 'всё хорошо')"
    wins="$(X xdotool search --name "." getwindowname %@ 2>/dev/null)"
    sess=0; dlg=0
    while IFS= read -r w; do
      case "$w" in
        *"Remote Desktop - RustDesk") sess=1 ;;
        "RustDesk") dlg=$((dlg+1)) ;;
      esac
    done <<< "$wins"
    printf '{"session_window":%s,"viewer_dialog":%s,"stale":%s}\n' \
      "$([ "$sess" = 1 ] && echo true || echo false)" \
      "$dlg" \
      "$([ "$dlg" -gt 0 ] && echo true || echo false)"
    [ "$dlg" -gt 0 ] && exit 1 || exit 0
    ;;

  classify)
    # 🔴 classify() only measures picture CONTENT: a month-old frame classifies as
    # "live" just as happily as the real screen. Hence the age guard on the scene.
    _scene "${2:-}"; F="$SCENE"
    "$PY" "$LIB/reconnect.py" classify --frame "$F" ${RC_BANNER_TEMPLATE:+--banner-template "$RC_BANNER_TEMPLATE"} --json
    ;;

  reconnect)
    RUN=""; [ "${2:-}" = "--run" ] && RUN=1
    PREFER="${RC_PREFER:-rustdesk}"
    PLAN=$("$PY" "$LIB/reconnect.py" plan --prefer "$PREFER" \
             ${RC_AD_ID:+--ad-id "$RC_AD_ID"} ${RC_RD_ID:+--rd-id "$RC_RD_ID"} --json)
    echo "$PLAN"
    if [ -z "$RUN" ] || [ "$LIVE" != "1" ]; then
      echo "(dry-run: not executing; pass --run AND set RC_LIVE=1 to actually reconnect)"; exit 0
    fi
    # LIVE reconnect: walk the plan with backoff, verify liveness after each step.
    SCHED=$("$PY" "$LIB/reconnect.py" backoff --json)
    log "reconnect plan resolved; executing (RC_LIVE=1) — driver cmds relative to /work/vnc_work_v2-vm121-review"
    echo "$SCHED"
    log "NOTE: rc.sh delegates the actual connect to the drivers that now live ALONGSIDE it in /work/vnc_work_v2-vm121-review (T201); wire RC_AD_ID/RC_RD_ID and run those under dangerouslyDisableSandbox."
    ;;

  selftest)
    exec bash "$DIR/test/run_tests.sh"
    ;;

  ""|-h|--help|help) usage ;;
  *) die "unknown command: $1 (try: $0 help)" ;;
esac
