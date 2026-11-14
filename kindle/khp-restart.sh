#!/bin/sh
# Restart kindle-hid-passthrough daemon. Usage: khp-restart.sh [debug|hci]
kill $(pgrep -f "dist/main.bin") 2>/dev/null
sleep 3
cd /mnt/us/kindle_hid_passthrough || exit 1
: > /var/log/hid_passthrough.log
if [ -n "$1" ]; then export KINDLE_HID_DEBUG="$1"; fi
nohup ./kindle-hid-passthrough --daemon >/dev/null 2>&1 &
sleep 12
tail -3 /var/log/hid_passthrough.log
