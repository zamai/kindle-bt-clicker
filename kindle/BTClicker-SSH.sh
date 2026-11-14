#!/bin/sh
# Name: BTClicker SSH
# Author: kindle-bt-clicker
# Starts a key-only SSH server (KOReader's dropbear) on port 2222 so the
# dev Mac can drive this Kindle. Safe to run repeatedly. Not persistent.
LOG=/mnt/us/btclicker/status.txt
mkdir -p /mnt/us/btclicker
exec >"$LOG" 2>&1
date
cd /mnt/us/koreader || exit 1
# keep the device awake while we test
lipc-set-prop com.lab126.powerd preventScreenSaver 1 || true
# make sure wifi is on
lipc-set-prop com.lab126.cmd wirelessEnable 1 || true
if [ -f /tmp/dropbear_btc.pid ] && kill -0 "$(cat /tmp/dropbear_btc.pid)" 2>/dev/null; then
  echo "dropbear already running"
else
  mkdir -p settings/SSH
  iptables -A INPUT -p tcp --dport 2222 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p tcp --sport 2222 -m conntrack --ctstate ESTABLISHED -j ACCEPT
  # -R gen hostkeys, -s no password logins, -E log to stderr
  ./dropbear -E -R -s -p 2222 -P /tmp/dropbear_btc.pid
  echo "dropbear rc=$?"
fi
sleep 3
IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
echo "ip=$IP"
ifconfig -a
FB=/mnt/us/libkh/bin/fbink; [ -x "$FB" ] || FB=/mnt/us/koreader/fbink
$FB -q -m -y -6 "BTClicker SSH ready: ${IP:-no wifi?}:2222" || true
