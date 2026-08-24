#!/bin/bash
# srvold_scp.sh <src> <dst> — копировать файлы с/на СТАРЫЙ сервер DESKTOP-VGVHEOU
# (машина товароведа, 192.168.0.10) *через джамп* SERVER-1S, когда её собственный обратный
# туннель (VPS:2244) лежит. Алиас  srvold:  разворачивается в путь на машине.
#
#   bash srvold_scp.sh ./file             srvold:C:/srv/file    # /work -> машина
#   bash srvold_scp.sh srvold:C:/srv/out  ./out                 # машина -> /work
#
# Windows-пути — через прямой слэш после буквы диска (C:/...), иначе scp спорит за ':'.
# 🔴 Ключ НЕ копируется на SERVER-1S: SERVER-1S работает только TCP-релеем (-W),
#    аутентификация к старой машине выполняется НАШИМ локальным ssh-клиентом.
# 🔴 Запускать с dangerouslyDisableSandbox — песочница агента рубит scp сигналом 16.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
OLDHOST=192.168.0.10
OLDUSER='Админ'
JUMPVPS=178.253.55.128
JUMPPORT=2248
JUMPUSER='User'

PROXY="ssh -i $DIR/ssh_channel/srv1s_me -p $JUMPPORT -o User=$JUMPUSER \
 -o UserKnownHostsFile=$DIR/ssh_channel/known_hosts_srv1s \
 -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 -o BatchMode=yes \
 $JUMPVPS -W %h:%p"

args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    srvold:*) args[$i]="$OLDHOST:${args[$i]#srvold:}";;
  esac
done

exec scp -i "$DIR/ssh_channel/srv_me" \
  -o User="$OLDUSER" \
  -o ProxyCommand="$PROXY" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_srvold" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30 -o BatchMode=yes \
  "${args[@]}"
