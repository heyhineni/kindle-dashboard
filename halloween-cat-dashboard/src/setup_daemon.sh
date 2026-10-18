#!/bin/sh
# Name: Setup Cat Clock Daemon
# Author: October Cat Clock
# DontUseFBInk
#
# This script no longer embeds cat_clock_daemon.sh's content inline —
# that led to this file and the real cat_clock_daemon.sh drifting out
# of sync more than once. Copy cat_clock_daemon.sh and
# screensaver_shield to /mnt/us/catclock/ yourself via File Explorer
# BEFORE running this; this script only sets up the surrounding
# structure (folders, upstart job) and does cleanup.

LOG="/mnt/us/documents/setup_daemon.log"
echo "=== setup_daemon.sh run at $(date) ===" > "$LOG"

mkdir -p /mnt/us/catclock
mkdir -p /mnt/us/catclock/diagnostics

echo "--- checking required files are already in place ---" >> "$LOG"
ls -la /mnt/us/catclock/cat_clock_daemon.sh >> "$LOG" 2>&1
ls -la /mnt/us/catclock/screensaver_shield >> "$LOG" 2>&1
chmod +x /mnt/us/catclock/cat_clock_daemon.sh 2>>"$LOG"
chmod +x /mnt/us/catclock/screensaver_shield 2>>"$LOG"

echo "--- removing old copy from documents/ if present (it was the duplicate-launch source) ---" >> "$LOG"
rm -f /mnt/us/documents/cat_clock_daemon.sh
echo "removed /mnt/us/documents/cat_clock_daemon.sh (rm exit code: $?)" >> "$LOG"

echo "--- moving diagnostic scripts to catclock/diagnostics/ ---" >> "$LOG"
for f in check_processes.sh check_upstart_write.sh check_daemon.sh find_daemon_triggers.sh check_status.sh test_simple.sh; do
    if [ -f "/mnt/us/documents/$f" ]; then
        mv "/mnt/us/documents/$f" "/mnt/us/catclock/diagnostics/$f"
        echo "moved $f (exit code: $?)" >> "$LOG"
    else
        echo "$f not found in documents/, skipping" >> "$LOG"
    fi
done

# -------------------------------------------------
# Remount root read-write, write the upstart job,
# remount back read-only immediately after.
# /etc/init -> /etc/upstart is read-only by default
# (confirmed via check_upstart_write.sh: write failed
# with exit code 1 even as root), so this step is
# required for the .conf to persist.
# -------------------------------------------------
echo "--- mntroot rw ---" >> "$LOG"
mntroot rw >> "$LOG" 2>&1
sleep 1

cat > /etc/init/cat-clock-daemon.conf <<'EOF'
start on started lab126_gui
stop on stopping lab126_gui

respawn

script
    test -x /mnt/us/catclock/cat_clock_daemon.sh || { stop; exit 1; }
    sh /mnt/us/catclock/cat_clock_daemon.sh
end script
EOF
WRITE_RESULT=$?
echo "Wrote /etc/init/cat-clock-daemon.conf, write exit code: $WRITE_RESULT" >> "$LOG"

echo "--- verifying file now exists ---" >> "$LOG"
ls -la /etc/init/cat-clock-daemon.conf >> "$LOG" 2>&1

echo "--- mntroot ro ---" >> "$LOG"
sleep 1
mntroot ro >> "$LOG" 2>&1

echo "=== setup_daemon.sh finished at $(date) ===" >> "$LOG"
echo "NOTE: this run does NOT manually start the daemon in the background." >> "$LOG"
echo "A reboot is required so upstart launches the single correct instance." >> "$LOG"
