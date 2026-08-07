#!/bin/bash
# shotlib.sh — общая защита от ЗАЛЕЖАВШЕГОСЯ КАДРА для всех «глаз» проекта.
#
# 🔴 Грабля kso-anydesk-stale-frame (05.08.2026, стоила неверного вывода про живую сессию на боевой
# кассе). Каноничная (сломанная) форма съёмки была такой:
#
#     scrot -o "$S/$L.png" 2>/dev/null && convert "$S/$L.png" ... "$S/$L.jpg" && echo "$S/$L.jpg"
#
# Что с ней не так — три вещи сразу:
#   1) при неудаче она МОЛЧИТ (2>/dev/null + && ) и возвращает 0 из-за последнего оператора цепочки;
#   2) прошлые $L.png/$L.jpg ОСТАЮТСЯ лежать — значит «кадр» по этому пути всё равно есть;
#   3) в выводе нет ВРЕМЕНИ съёмки — по картинке не отличить сегодняшнюю от июльской.
# Итог: вызывающий берёт файл (часто по маске `ls -t ... | head -1`), видит правдоподобную картинку
# и принимает по ней решения — вплоть до кликов по координатам на живой кассе.
#
# Контракт shot_guarded: путь к кадру — ПОСЛЕДНЯЯ строка stdout (вызовы вида `| tail -1` не ломаются),
# диагностика и предупреждения — в stderr, провал — ненулевой код возврата.
#
# Подключение:  . "$(cd "$(dirname "$0")" && pwd)/shotlib.sh"      # для rustdesk/* — на уровень выше
# Использование:
#   shot_guarded <label> <screens_dir> <display> [runner...]   # runner: U / RUN / runuser ... ; пусто = напрямую
#   shot_where   <display> <screens_dir>
#   shot_clean   <screens_dir> [days]                          # старые кадры → attic/<ts>/ (НЕ удаляет)

# кадры старше стольких минут рядом в каталоге считаем залежью и предупреждаем о них
SHOT_STALE_MIN="${SHOT_STALE_MIN:-360}"

# внутреннее: предупредить о залежавшихся кадрах рядом (именно они и вводят в заблуждение)
_shot_warn_old(){
  local sd="$1" keep="$2" old
  old=$(find "$sd" -maxdepth 1 -name '*.png' ! -name "$keep.png" -mmin +"$SHOT_STALE_MIN" 2>/dev/null | head -3)
  [ -n "$old" ] && {
    echo "ВНИМАНИЕ: в $sd лежат СТАРЫЕ кадры (>$((SHOT_STALE_MIN/60)) ч) — не путать с текущим:" >&2
    printf '%s\n' "$old" | sed 's/^/  /' >&2
    echo "  (убрать: shot_clean / команда clean драйвера)" >&2
  }
  return 0
}

# shot_guarded <label> <screens_dir> <display> [runner...]
shot_guarded(){
  local L="$1" SD="$2" DP="$3"; shift 3
  local RUN=("$@")
  [ ${#RUN[@]} -eq 0 ] && RUN=(env)
  mkdir -p "$SD" 2>/dev/null
  # 1. Прошлые артефакты ЭТОГО лейбла сносим ДО съёмки: кадр не должен «унаследоваться» от прошлого
  #    запуска ни при каких обстоятельствах.
  rm -f "$SD/$L.png" "$SD/$L.jpg" 2>/dev/null
  # 2. Съёмка. Провал — громко и ненулевым кодом, а не тишиной.
  if ! "${RUN[@]}" scrot -o "$SD/$L.png" 2>/dev/null; then
    echo "SHOT_FAIL: scrot не снял кадр с DISPLAY=$DP → $SD/$L.png (стек поднят? см. \`status\`/\`up\`)" >&2
    return 1
  fi
  # 3. scrot может вернуть 0 и не написать ничего — пустой файл тоже провал.
  if [ ! -s "$SD/$L.png" ]; then
    echo "SHOT_FAIL: scrot вернул 0, но кадр $SD/$L.png пуст" >&2
    rm -f "$SD/$L.png"; return 1
  fi
  # 4. JPG. Если convert не отработал — старый .jpg НЕ должен пережить съёмку (иначе .png свежий,
  #    а .jpg, который обычно и читают, — прошлый).
  if command -v convert >/dev/null 2>&1; then
    if ! convert "$SD/$L.png" -quality 88 "$SD/$L.jpg" 2>/dev/null; then
      rm -f "$SD/$L.jpg"
      echo "SHOT_FAIL: convert не собрал JPG из $SD/$L.png" >&2
      return 1
    fi
  fi
  _shot_warn_old "$SD" "$L"
  # 5. ВРЕМЯ съёмки — обязательно: только оно отличает сегодняшний кадр от июльского.
  echo "снят $(date '+%Y-%m-%d %H:%M:%S') DISPLAY=$DP size=$(stat -c%s "$SD/$L.png" 2>/dev/null)б"
  if [ -f "$SD/$L.jpg" ]; then echo "$SD/$L.jpg"; else echo "$SD/$L.png"; fi   # путь — ПОСЛЕДНЯЯ строка
}

# shot_where <display> <screens_dir> — куда ЭТОТ запуск пишет кадры (AD_SCREENS легко забыть передать,
# и кадры расходятся по двум каталогам: в одном свежие, в другом залежь, которую потом и читают).
shot_where(){
  echo "DISPLAY=$1"; echo "SCREENS=$2"; echo "SHOT_STALE_MIN=$SHOT_STALE_MIN"
  ls -la --time-style=+%Y-%m-%d_%H:%M:%S "$2" 2>/dev/null | tail -n +2
}

# shot_clean <screens_dir> [days] — кадры старше N суток УБРАТЬ в attic/<ts>/ (не удалять).
# Смысл не в месте на диске, а в том, чтобы старый кадр перестал быть «самым свежим *.png» в каталоге.
#
# 🔴 ЭТАЛОНЫ НЕ ТРОГАЕМ. В каталогах кадров рядом со снимками живут опорные картинки для vmatch
# (*_tmpl*.png, tmpl_*.png, *template*) — им ПОЛОЖЕНО быть старыми, и увезти их в attic = сломать
# поиск элементов. Дополнительно можно перечислить свои шаблоны-исключения (по одной glob-маске в
# строке) в файле <screens_dir>/.keepframes.
shot_clean(){
  local SD="$1" DAYS="${2:-1}" AT N K f base keep TRACKED=""
  AT="$SD/attic/$(date +%Y%m%d_%H%M%S)"
  # 🔴 Файлы ПОД ГИТОМ не двигаем: в каталогах кадров лежат и закоммиченные артефакты-доказательства
  # (screens_t67/* в vnc_work_v2 — приложение к отчёту T67). Увезти их в attic = получить пачку
  # «удалений» в git и потерять приложение к отчёту. Проверено на себе 05.08: clean увёз 21 такой файл.
  if git -C "$SD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    TRACKED="$(git -C "$SD" ls-files -- . 2>/dev/null | sed 's|.*/||')"
  fi
  local -a MOVE=() KEPT=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f")"; keep=0
    case "$base" in *tmpl*|*template*|*etalon*|*эталон*) keep=1 ;; esac
    [ "$keep" = 0 ] && [ -n "$TRACKED" ] && printf '%s\n' "$TRACKED" | grep -qxF "$base" && keep=1
    if [ "$keep" = 0 ] && [ -r "$SD/.keepframes" ]; then
      while IFS= read -r K; do
        [ -n "$K" ] || continue; case "$K" in \#*) continue ;; esac
        case "$base" in $K) keep=1; break ;; esac
      done < "$SD/.keepframes"
    fi
    if [ "$keep" = 1 ]; then KEPT+=("$base"); else MOVE+=("$f"); fi
  done < <(find "$SD" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' \) -mtime +"$DAYS" 2>/dev/null)
  N=${#MOVE[@]}
  [ ${#KEPT[@]} -gt 0 ] && echo "clean: оставлены на месте — эталоны и файлы под git (${#KEPT[@]}): $(printf '%s ' "${KEPT[@]}")"
  if [ "$N" = "0" ]; then echo "clean: нечего убирать (нет кадров старше ${DAYS} сут в $SD)"; return 0; fi
  mkdir -p "$AT" || return 1
  printf '%s\0' "${MOVE[@]}" | xargs -0 mv -t "$AT" 2>/dev/null
  echo "clean: убрано $N кадров старше ${DAYS} сут → $AT (НЕ удалено)"
}
