# VNC_LAUNCH.md — как поднять VNC-стек и ОТКРЫТЬ окно вьювера на десктопе (проверено 2026-07-02)

Как агент открывает браузер на сервере (Xvfb :98) и показывает его **окном на десктопе Windows**,
чтобы человек логинился/добивал SMS/капчу. Стек — `/work/vnc_work_v2-vm121-review/vnc.sh` (см. README.md).

## TL;DR (три команды, от ROOT, каждую с dangerouslyDisableSandbox)
```bash
# 1. RU-IP (если ресурс требует, напр. банки/госуслуги)
bash /work/marketplace/orch/scripts/socks_ru.sh up          # exit 178.253.55.128

# 2. Поднять стек (браузер на :98 + x11vnc localhost:5901 + CDP 9334). Профиль — ПЕРСИСТЕНТНЫЙ в /work.
VNC_PROFILE=/work/<проект>/.<имя>_vnc_profile VNC_SOCKS=socks5://127.0.0.1:1080 \
  bash /work/vnc_work_v2-vm121-review/vnc.sh up "https://пример.ru/"

# 3. Открыть окно вьювера на десктопе Windows
bash /work/vnc_work_v2-vm121-review/vnc.sh viewer
```
Погасить: `bash /work/vnc_work_v2-vm121-review/vnc.sh down` (гасит и вьювер, и стек; SOCKS оставляет).

## 🔴 ГЛАВНОЕ про окно вьювера (грабли и рабочий способ)
Окно `xtigervncviewer` на десктоп Windows идёт через **WSLg дисплей `:0`**. Нюансы, на которые убили время:
- **WSLg `:0` для СКРИНШОТОВ (scrot) даёт чёрный кадр/RAIL** — поэтому агент СНИМАЕТ экран через CDP/`vnc.sh shot` по `:98`, а НЕ по `:0`. (README строка ~134.) Но ОТОБРАЖАТЬ окно вьювера на `:0` можно — это другое.
- **Прямой запуск вьювера умирает.** `setsid runuser -u hgff -- env -i ... xtigervncviewer & disown` — процесс убивается, когда завершается агентский bash-вызов (SIGTERM тащится за детьми). А запуск от **hgff через `env -i`** вьювер вообще не стартует (пустой лог — не хватает WSLg-окружения).
- ✅ **РАБОЧИЙ способ: вьювер в ПЕРСИСТЕНТНОЙ tmux-сессии, от ROOT, DISPLAY=:0.** tmux-сессия переживает завершение вызова (как `orv_socks_ka`/`global_ram_guard`), поэтому окно остаётся. Root имеет доступ к `:0` (X0-сокет `srwxrwxrwx`, world-writable). Именно это делает `vnc.sh viewer` (починен 2026-07-02):
  ```bash
  tmux new-session -d -s vnc_viewer_5901
  tmux send-keys -t vnc_viewer_5901 \
    "DISPLAY=:0 XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir xtigervncviewer -SecurityTypes None -Fullscreen=0 localhost:5901 >/tmp/vnc_viewer_5901.log 2>&1" Enter
  ```
  Проверка успеха — в `/tmp/vnc_viewer_5901.log` строки `Connected to host localhost port 5901` + `Using pixel format depth 24` и живой процесс `pgrep -f xtigervncviewer`.
- **Запасной путь (всегда работает):** человек открывает СВОЙ **Windows-TigerVNC Viewer → `localhost:5901`** (WSL форвардит localhost на Windows автоматически). Это документированный основной путь (README строки 30/71); авто-вьювер — удобство поверх него.

## Персистентность сессии (не перелогиниваться)
- Профиль браузера задаётся `VNC_PROFILE=` (дефолт `/tmp/vnc_work_profile` — НЕнадёжно, чистится). Для сохранения логина — клади профиль в `/work/<проект>/.<имя>_vnc_profile`. Куки/сессия переживут `down`/`up`.
- Бэкап: `tar czf /work/<проект>/_backups/<имя>_profile_$(date +%F).tar.gz -C <PROFILE> .` (лучше при закрытом chromium, иначе куки в памяти могут не сброситься).

## Управление (руки агента, без координат — через CDP)
`bash /work/vnc_work_v2-vm121-review/vnc.sh {shot <lbl>|find <regex>|type <sel> <текст>|click <текст|sel>|press <key>|eval <js>|url|text|status|down}`.
SMS/почтовый код — `fetch_email_code.py` или человек в TigerVNC. Подробнее — README.md.
