# Запуск команд на удалённой Windows за NAT БЕЗ GUI (sc.exe по SMB)

Приём, найденный на SOCHI11 (машина тестировщика, T228, 11.08.2026). Когда до Windows-машины не достучаться
напрямую, а стандартные способы удалённого запуска заблокированы файрволом/антивирусом — но SMB (445) жив.

## Проблема

На SOCHI11 (Kaspersky + Windows Firewall) заблокированы:
- `schtasks /s <ip> /run /tn <task>` (Task Scheduler RPC) → пустой список / EXIT 1;
- WMI / `Invoke-Command` (WinRM 5985 закрыт); DCOM (порт 135) по TCP открыт, но интерфейс не отвечает.

То есть привычные «дёрни задачу/процесс по сети» не работают.

## Решение: `sc.exe \\<ip>` — менеджер служб svcctl по именованному каналу SMB (445)

Тот же транспорт, что и доставка файлов на `\\<ip>\C$`. Работает при
`LocalAccountTokenFilterPolicy=1` (иначе локальный админ по сети получает урезанный токен) и креды
локального `Admin`, уже поднятые в SMB-сессии (`net use \\<ip>\IPC$ /user:Admin <pw>`):

```powershell
net use \\<ip>\IPC$ /user:Admin <admin_pw>          # аутентифицируем SMB-сессию
sc.exe \\<ip> query state= all                        # проверка: работает ли svcctl (список служб)
sc.exe \\<ip> create Kick binPath= "cmd /c C:\path\kick.cmd" type= own start= demand
sc.exe \\<ip> start  Kick        # вернёт 1053 «служба не ответила вовремя» — ЭТО НОРМАЛЬНО
sc.exe \\<ip> delete Kick        # убрать транзитную службу
```

- Служба стартует как **LocalSystem** и выполняет `binPath`. `1053` — потому что наш `cmd` быстро
  завершается, не рапортуя SCM протокол службы. Полезная работа к этому моменту уже сделана.
- 🔴 **`kick.cmd` НЕ должен делать долгую работу сам** — SCM убьёт дерево процессов службы через ~30 c.
  Он лишь **локально** создаёт и запускает SYSTEM-задачу планировщика, которую Task Scheduler отвязывает
  от SCM, и она уже несёт долгую нагрузку (установка, настройка и т.п.):

  ```bat
  @echo off
  schtasks /create /tn Setup /tr "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Users\User\setup.ps1" /sc ONCE /st 23:59 /ru SYSTEM /rl HIGHEST /f
  schtasks /run /tn Setup
  ```

- 🔴 `schtasks /create /st HH:MM /sc ONCE` оставляет триггер на это время СЕГОДНЯ — одноразовые задачи
  после отработки удаляй (`schtasks /delete /tn <n> /f`), иначе они повторно выстрелят в HH:MM.

## Доставка файлов (тот же канал)

Если своей машины в LAN с целью нет — доставляй через уже подключённую машину той же сети (у нас
SERVER-1S, туннель 2248, `srv1s_ps.sh`/`srv1s_scp.sh`): scp файл на неё, затем оттуда `Copy-Item` по SMB:
```powershell
net use \\<ip>\C$ /user:Admin <admin_pw>
Copy-Item C:\srv1s\setup.ps1 \\<ip>\C$\Users\User\setup.ps1 -Force
```
Большой `-EncodedCommand` через `*_ps.sh` рвётся («слишком длинная командная строка») — не встраивай
base64 в команду, копируй файлом.

## Где это применили: reverse-SSH onboarding SOCHI11 (T228)

Полная схема постоянного туннеля — в ПРОЕКТЕ: `/work/kso/docs/INSTRUCTION_openssh_tunnel_novaya_mashina.md`.
Кратко: пары ключей `_me`(наш доступ)/`_tunnel`(reverse); `_tunnel.pub` в authorized_keys VPS
`178.253.55.128` с `restrict,port-forwarding`; доставка+`sc.exe`-запуск payload → `Add-WindowsCapability
OpenSSH.Server`; задача `SochiTunnel` (SYSTEM, ONSTART, cmd-loop `ssh -N -R 0.0.0.0:2249:127.0.0.1:22`);
хелперы `loyalty/ops/sochi_ssh.sh`/`sochi_scp.sh`; приёмка по `hostname`. Порты VPS заняты 2243-2249,
следующий свободный — **2250**.

Две грабли, стоившие времени (детали и фиксы — в проектной инструкции):
- 🔴 `StrictModes` дописан в конец `sshd_config` попал ВНУТРЬ `Match Group administrators` → sshd падает
  с exit **1067**. Глобальные директивы вставлять ВЫШЕ первого `Match`.
- 🔴 Приватный ключ «too open / will be ignored»: `icacls` англ. именами (`SYSTEM`,`BUILTIN\Administrators`)
  молча падает на РУССКОЙ Windows. Задавать ACL по SID: `*S-1-5-18`, `*S-1-5-32-544`.
