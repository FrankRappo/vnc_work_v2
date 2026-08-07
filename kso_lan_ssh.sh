#!/bin/bash
# kso_lan_ssh.sh "<remote command>" — reach the KSO cash sshd over the LAN by JUMPING through
# the 1C-server box (DESKTOP-VGVHEOU), used when the cash's OUTBOUND reverse tunnel (VPS:2243)
# is down but its LAN sshd (192.168.0.186:22) is still up.
#
# Path:  /work --ssh--> VPS:2244 (reverse tunnel) --> 1C server sshd (Админ/srv_me)
#              --(direct-tcpip -W)--> cash LAN 192.168.0.186:22 (sco_m210/kso_me)
#
# This is the recovery path to restart the cash's KSOTunnel task when 2243 is dead.
# NON-fiscal use only per money-safety; fiscal ops must go over the restored direct 2243.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh with signal 16.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
CASHLAN=192.168.0.186
CASHUSER=sco_m210
SRVUSER='Админ'
VPS=178.253.55.128
SRVPORT=2244
PROXY="ssh -i $DIR/ssh_channel/srv_me -o User=$SRVUSER -p $SRVPORT \
  -o UserKnownHostsFile=$DIR/ssh_channel/known_hosts_srv -o StrictHostKeyChecking=accept-new \
  -o BatchMode=yes -o ConnectTimeout=25 -W $CASHLAN:22 $VPS"
exec ssh -i "$DIR/ssh_channel/kso_me" \
  -o ProxyCommand="$PROXY" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_cash_lan" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=30 -o BatchMode=yes \
  "$CASHUSER@$CASHLAN" "$@"
