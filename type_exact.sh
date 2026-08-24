#!/bin/bash
# type_exact.sh <файл-с-текстом> — НАБРАТЬ ТЕКСТ ПОБУКВЕННО, СОХРАНИВ РЕГИСТР.
#
# Нужен везде, где текст РЕГИСТРОЗАВИСИМЫЙ и ошибка в одном символе не видна глазом: base64,
# коды маркировки, пароли, токены, GUID. Пришёл из T303 (25.08.2026), где 52 символа base64
# приехали на кассу в нижнем регистре целиком и дали ложный отказ «код не распознан».
#
# 🔴 ЗАЧЕМ, ЕСЛИ ЕСТЬ `xdotool type`. Через RustDesk `xdotool type` ТЕРЯЕТ SHIFT: строка
# «AbCdEfXYZ» приезжает на кассу как «abcdefxyz». Для пароля это незаметно, а для base64 —
# смертельно: регистр в нём значащий, и код маркировки после потери регистра становится другим
# кодом. Поймано фактом: 52 символа base64 приехали в нижнем регистре целиком, увеличение
# --delay до 160 мс не помогло.
#
# 🔴 ЧИНИТ ЭТО РАЗДЕЛЬНАЯ ПОСЫЛКА МОДИФИКАТОРА: keydown shift → key <буква> → keyup shift.
# Тогда RustDesk передаёт нажатие Shift отдельным событием, и Windows его видит. Проверено на
# «AbC» → на кассе «AbC».
#
# 🔴 САМ ТЕКСТ НЕ ПЕЧАТАЕТСЯ: в вывод идут только длина и контрольная сумма (коды маркировки в
# отчёт, чат и git не выносятся, §21.2).
# 🔴 Запускать с dangerouslyDisableSandbox.
set -u
FILE="${1:?usage: type_exact.sh <файл>}"
DISPLAY_="${RC_DISPLAY:-:99}"
[ -f "$FILE" ] || { echo "🔴 НЕТ ФАЙЛА: $FILE"; exit 2; }

python3 - "$FILE" "$DISPLAY_" <<'PY'
import subprocess, sys, time, hashlib
text = open(sys.argv[1], 'r', encoding='utf-8').read().strip()
disp = sys.argv[2]
print('НАБИРАЮ: %d символов, sha256[:8]=%s' % (len(text), hashlib.sha256(text.encode()).hexdigest()[:8]))

# Клавиша и нужен ли Shift — по таблице, а не по «isupper»: у base64 есть «+», «/» и «=»,
# и у каждого своя клавиша.
SPECIAL = {'+': ('equal', True), '/': ('slash', False), '=': ('equal', False),
           '-': ('minus', False), '_': ('minus', True), '.': ('period', False)}

def run(args):
    subprocess.run(['env', 'DISPLAY=' + disp, 'xdotool'] + args, check=False)

for ch in text:
    if ch in SPECIAL:
        key, shift = SPECIAL[ch]
    elif ch.isdigit():
        key, shift = ch, False
    elif ch.isalpha():
        key, shift = ch.lower(), ch.isupper()
    else:
        print('🔴 НЕИЗВЕСТНЫЙ СИМВОЛ, пропускаю'); continue
    # 🔴 SHIFT СНИМАЕТСЯ ЯВНО ПЕРЕД КАЖДЫМ БЕЗ-SHIFT СИМВОЛОМ. Иначе «залипший» Shift доезжает
    # до следующей цифры и превращает 0 в «)», 8 в «*», 3 в «#». Поймано фактом: в поле base64
    # вместо «…OTU0MDMy…» приехало «…OTU)MDMY…».
    # 🔴 БЕЗ --clearmodifiers. Он «чистит» модификаторы, СНИМАЯ и снова НАЖИМАЯ их, и через
    # RustDesk это выглядит как лишнее нажатие Shift: цифра 0 приезжала как «)», 3 как «#».
    # Вместо этого Shift снимается явно и с запасом по времени.
    if shift:
        run(['keydown', 'shift']);  time.sleep(0.15)
        run(['key', key]);          time.sleep(0.15)
        run(['keyup', 'shift']);    time.sleep(0.15)
    else:
        run(['keyup', 'shift']);    time.sleep(0.12)
        run(['key', key])
    time.sleep(0.08)
print('НАБРАНО')
PY
