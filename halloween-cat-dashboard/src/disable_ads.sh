#!/bin/sh
# Name: Disable Ads (custom)
# Author: October Cat Clock
# DontUseFBInk

LOG="/mnt/us/documents/disable_ads.log"
echo "=== disable_ads.sh run at $(date) ===" > "$LOG"

echo "--- blanket load BEFORE ---" >> "$LOG"
lipc-get-prop com.lab126.blanket load >> "$LOG" 2>&1

echo "--- unloading ad_screensaver ---" >> "$LOG"
lipc-set-prop com.lab126.blanket unload ad_screensaver >> "$LOG" 2>&1

# Unloading ad_screensaver alone leaves blanket with nothing to show on
# sleep (confirmed on-device: power button went completely unresponsive,
# only fixed by a reboot). Explicitly loading "screensaver" right after
# gives blanket something to fall back to, same as the very first working
# version of this script. Do NOT remove this line again.
echo "--- loading screensaver (so blanket has something to show on sleep) ---" >> "$LOG"
lipc-set-prop com.lab126.blanket load screensaver >> "$LOG" 2>&1

echo "--- blanket load AFTER ---" >> "$LOG"
lipc-get-prop com.lab126.blanket load >> "$LOG" 2>&1

echo "=== disable_ads.sh finished at $(date) ===" >> "$LOG"
