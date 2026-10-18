#!/bin/sh
# Name: Restart Cat Clock Daemon
# Author: October Cat Clock
# DontUseFBInk

LOG="/mnt/us/documents/restart_daemon.log"
echo "=== restart_daemon.sh run at $(date) ===" > "$LOG"

# IMPORTANT: upstart (cat-clock-daemon.conf, with "respawn") already
# supervises this daemon — confirmed via check_processes.sh / an earlier
# version of this script: killing the daemon manually caused upstart to
# instantly respawn a new copy anyway, and then OUR manual start added yet
# another on top, stacking up to 4 simultaneous lipc-wait-event processes.
# From now on, let upstart own the single instance; use its own
# stop/start instead of raw kill + manual background start.
#
# ALSO: cat_clock_daemon.sh now lives at
# /mnt/us/catclock/cat_clock_daemon.sh, not /mnt/us/documents/ — a
# copy left in documents/ was getting independently launched by the
# Kindle's own scriptlet indexer, causing a second daemon instance on
# top of upstart's (see find_daemon_triggers.sh / FINDINGS.md Round
# 8). If this script ever finds a straggler, double check it isn't
# coming from a documents/ copy that got re-created by mistake.

echo "--- processes before ---" >> "$LOG"
ps | grep -E "cat_clock|lipc-wait-event" | grep -v grep >> "$LOG" 2>&1

echo "--- initctl stop cat-clock-daemon ---" >> "$LOG"
initctl stop cat-clock-daemon >> "$LOG" 2>&1

sleep 1

echo "--- killing any leftover stragglers not owned by upstart ---" >> "$LOG"
ps | grep "cat_clock_daemon.sh" | grep -v grep | awk '{print $1}' | while read pid; do
    echo "killing straggler cat_clock_daemon.sh PID $pid" >> "$LOG"
    kill -9 "$pid" 2>>"$LOG"
done
ps | grep "lipc-wait-event" | grep -v grep | awk '{print $1}' | while read pid; do
    echo "killing straggler lipc-wait-event PID $pid" >> "$LOG"
    kill -9 "$pid" 2>>"$LOG"
done

sleep 1

echo "--- processes after full stop (should be empty) ---" >> "$LOG"
ps | grep -E "cat_clock|lipc-wait-event" | grep -v grep >> "$LOG" 2>&1

echo "--- initctl start cat-clock-daemon ---" >> "$LOG"
initctl start cat-clock-daemon >> "$LOG" 2>&1

sleep 1

echo "--- processes after upstart start (should be exactly 1 shell + 1 lipc-wait-event) ---" >> "$LOG"
ps | grep -E "cat_clock|lipc-wait-event" | grep -v grep >> "$LOG" 2>&1

echo "=== restart_daemon.sh finished at $(date) ===" >> "$LOG"
