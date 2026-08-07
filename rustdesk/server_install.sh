#!/bin/bash
# Установка официального rustdesk-server (hbbs+hbbr) на VPS. Запускается на VPS через ssh 'bash -s'.
set -e
mkdir -p /opt/rustdesk-server /var/lib/rustdesk-server
URL="https://github.com/rustdesk/rustdesk-server/releases/latest/download/rustdesk-server-linux-amd64.zip"
echo "[*] download rustdesk-server"
curl -fsSL -o /tmp/rds.zip "$URL" || wget -qO /tmp/rds.zip "$URL"
ls -la /tmp/rds.zip
command -v unzip >/dev/null || { apt-get update -qq; apt-get install -y -qq unzip; }
rm -rf /tmp/rds && mkdir -p /tmp/rds
unzip -o -q /tmp/rds.zip -d /tmp/rds
HBBS=$(find /tmp/rds -name hbbs -type f | head -1)
HBBR=$(find /tmp/rds -name hbbr -type f | head -1)
echo "[*] hbbs=$HBBS hbbr=$HBBR"
[ -n "$HBBS" ] && [ -n "$HBBR" ] || { echo "FATAL: не нашёл hbbs/hbbr в архиве"; exit 1; }
install -m755 "$HBBS" /usr/local/bin/hbbs
install -m755 "$HBBR" /usr/local/bin/hbbr

cat > /etc/systemd/system/rustdesk-hbbs.service <<'UNIT'
[Unit]
Description=RustDesk ID/Rendezvous Server (hbbs)
After=network.target rustdesk-hbbr.service
[Service]
Type=simple
WorkingDirectory=/var/lib/rustdesk-server
ExecStart=/usr/local/bin/hbbs
Restart=always
RestartSec=2
LimitNOFILE=100000
[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/rustdesk-hbbr.service <<'UNIT'
[Unit]
Description=RustDesk Relay Server (hbbr)
After=network.target
[Service]
Type=simple
WorkingDirectory=/var/lib/rustdesk-server
ExecStart=/usr/local/bin/hbbr
Restart=always
RestartSec=2
LimitNOFILE=100000
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now rustdesk-hbbr.service
systemctl enable --now rustdesk-hbbs.service
sleep 5
echo "[*] active: hbbs=$(systemctl is-active rustdesk-hbbs.service) hbbr=$(systemctl is-active rustdesk-hbbr.service)"
echo "[*] порты:"; ss -ltnup 2>/dev/null | grep -E ":2111[5-9]" || echo "НЕТ ПОРТОВ"
echo "[*] PUBLIC KEY (id_ed25519.pub):"; cat /var/lib/rustdesk-server/id_ed25519.pub 2>/dev/null || echo "ключ не создан"
