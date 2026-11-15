#!/bin/sh
# A/B suspend test: 180 s asleep with BT daemon, then 180 s without
L=/mnt/us/btclicker/sleeptest.log
mark() { echo "MARK $(date +%H:%M:%S) $1 batt=$(lipc-get-prop com.lab126.powerd battLevel)" >> $L; logger "SLEEPTEST $1"; }
: > $L
mark A_start_bt_on
lipc-set-prop com.lab126.powerd powerButton 1
sleep 180
lipc-set-prop com.lab126.powerd powerButton 1   # wake
sleep 10
stop hid-passthrough >/dev/null 2>&1
sleep 5
mark B_start_bt_off
lipc-set-prop com.lab126.powerd powerButton 1
sleep 180
lipc-set-prop com.lab126.powerd powerButton 1
sleep 10
mark done
start hid-passthrough >/dev/null 2>&1
grep -E "SLEEPTEST|statech|Repeated_unknown|TimeSpentInSUSPENDEDState" /var/log/messages | cut -c1-160 >> $L
