#!/bin/sh
# Name: Cat Clock Daemon
# Author: October Cat Clock
# DontUseFBInk
#
# NOTE: this file's on-device home is
# /mnt/us/catclock/cat_clock_daemon.sh, NOT /mnt/us/documents/.
# Anything under documents/ gets indexed by the Kindle's scriptlet
# system as a tappable "book" — confirmed via find_daemon_triggers.sh
# that a copy left in documents/ caused a SECOND, independently-
# launched instance of this daemon to run alongside upstart's own,
# doubling every draw. setup_daemon.sh writes this file directly to
# /mnt/us/catclock/ and deletes any stray copy from documents/ —
# don't put this file back in documents/.
#
# Round 9 architecture, following the proven
# chengandre/kindle-custom-screensaver pattern directly (confirmed
# working, prebuilt kindlehf binaries, see FINDINGS.md):
#   goingToScreenSaver fires BEFORE the screen actually blanks — the
#   window manager (awesome/Xorg) hasn't finished its own repaint yet,
#   so a bare FBInk draw gets raced and overwritten (confirmed
#   on-device: text flashed briefly over the still-visible home
#   screen, then the home screen won). Their fix is a small X11
#   override-redirect "shield" window that physically blocks the
#   window manager from repainting while we draw — not a timing
#   delay. We reuse their prebuilt screensaver_shield binary as-is;
#   our own cat_clock.sh still does the actual drawing (kept dynamic,
#   not flattened to a static PNG).

SCRIPT="/mnt/us/documents/cat_clock.sh"
SHIELD="/mnt/us/catclock/screensaver_shield"
SHIELD_PIDFILE="/tmp/cat_clock_shield.pid"
LOG="/mnt/us/catclock/daemon.log"

exec >> "$LOG" 2>&1

shield_down() {
    if [ -f "$SHIELD_PIDFILE" ]; then
        SPID="$(cat "$SHIELD_PIDFILE" 2>/dev/null)"
        if [ -n "$SPID" ]; then
            kill "$SPID" 2>/dev/null
            wait "$SPID" 2>/dev/null
        fi
        rm -f "$SHIELD_PIDFILE"
        echo "[daemon] shield stopped"
    fi
}

shield_up() {
    shield_down
    DISPLAY=:0 "$SHIELD" >>"$LOG" 2>&1 &
    SPID=$!
    echo "$SPID" > "$SHIELD_PIDFILE"
    echo "[daemon] shield started (PID $SPID)"
}

while true; do
    echo "[daemon] waiting for goingToScreenSaver..."
    lipc-wait-event com.lab126.powerd goingToScreenSaver
    echo "[daemon] caught goingToScreenSaver at $(date)"

    # Transient unload, just for this sleep cycle — restored on wake
    # below. Separate from disable_ads.sh's permanent ad_screensaver
    # removal.
    lipc-set-prop com.lab126.blanket unload screensaver
    echo "[daemon] unloaded blanket screensaver"

    shield_up

    sh "$SCRIPT"
    echo "[daemon] $SCRIPT exited with code $?"

    lipc-wait-event com.lab126.powerd outOfScreenSaver
    echo "[daemon] woke up at $(date)"

    shield_down

    # Force a real refresh on wake, same as the reference daemon —
    # without this, the display can settle on a stale frame instead
    # of properly redrawing the live UI (observed on-device before
    # this fix: the screen just showed the home screen underneath
    # with no clean wake transition).
    /mnt/us/libkh/bin/fbink -q -k -f -W GC16 >>"$LOG" 2>&1
    DISPLAY=:0 xrefresh >>"$LOG" 2>&1

    lipc-set-prop com.lab126.blanket load screensaver
    echo "[daemon] restored blanket screensaver"
done
