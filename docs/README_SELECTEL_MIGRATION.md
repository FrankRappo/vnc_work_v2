# Selectel-миграция BT Dialer (02.11.2026) — скрипты в этой папке и статус

Все скрипты этой папки (`selectel_*.py`, `wheel_once.py`, `selectel_cdp.js`) — рабочие
инструменты сессии выбора роли vpc.admin в панели my.selectel.ru через Edge CDP (:9222).
Уроки и чеклист: `SELECTEL_PANEL_CDP_LESSONS_2026-11-02.md` (читать ПЕРВЫМ).

## Что сделано (итог сессии)

1. Облачные серверы созданы в проекте My First Project (ru-6a):
   - telephony-prod: 12 vCPU / 24 ГБ / 500 ГБ / Ubuntu 24.04, ACTIVE,
     ID c4f9fc62-c322-4ce0-a08b-b028a8925819, IP 135.106.145.179 (+порт 192.168.0.4);
   - crm-prod: 8 vCPU / 48 ГБ / 300 ГБ / Ubuntu 24.04, ACTIVE,
     ID c66e85ee-6a32-4b9f-905e-68e6703a238c.
2. Сервисный API-пользователь создан: btdialer-api, роль vpc.admin (Аккаунт),
   UID dabe36e810374b85bde6879ac8711f66. Пароль сохранён владельцу
   (C:/Users/user/AppData/Local/Temp/cred_api.txt и /work/asterisk/CREDENTIALS.md).

## Статус скриптов

- `selectel_final_vpc.py`, `selectel_wheel_flow.py` — черновики борьбы с дропдауном роли
  (НЕ финал; рабочий метод — по чеклисту из lessons-документа, наведение→проверка→колесо→клик).
- `selectel_type_vpc.py` — РАБОЧИЙ способ: впечатать «vpc» в поиск селекта доверенными
  клавишами → дерево фильтруется → клик по тексту узла (раскрыть) → дети → клик по роли.
- `selectel_scroll_vpc.py`, `selectel_check.py`, `selectel_wheel_noreply.py` —
  отладочные (fire-and-forget wheel: mouseWheel не имеет CDP-ответа, cdp.call() таймаутит).

## Грабли (кратко, полный список в lessons-документе)

- visibilityState 'hidden' (окно свёрнуто) — дропдауны не открываются; час потрачен впустую.
- Дропдаун искать по всему документу ([class*=ant-select-dropdown] + offsetParent), не в
  .cdk-overlay-container.
- mouseWheel — fire-and-forget (нет CDP-ответа).
- Клик по родителю-продукту (vpc) = только раскрыть; роль — в детях (vpc.admin).
- Координаты из getBoundingClientRect; скрины edge_cdp.py в 1.5× (DPI) — не смешивать.
- Сбрасывать body.zoom и Emulation-override после экспериментов — сдвигают координаты.
