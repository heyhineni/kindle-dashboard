# Cat Clock — FBInk debugging findings

Kindle 10th gen (basic, 2019), 600x800 @ 167 PPI, jailbroken via SpiderCat.
`fbink` binary at `/mnt/us/libkh/bin/fbink`. Script lives at
`/mnt/us/documents/cat_clock.sh` so the Kindle's SH_Integration scriptlet
system indexes it as a tappable "book" in the library.

## Root cause of the original bugs

Two separate issues, found in this order:

### 1. Missing `# DontUseFBInk` header
Without this header comment, SH_Integration pipes the script's own
stdout/stderr through FBInk's display path automatically. That collided
with our direct `fbink` draw calls and produced garbled/scrambled output
(wrong order, missing elements) that looked like a layout bug but wasn't.
Fix: add `# DontUseFBInk` to the header block (same area as `# Name:` /
`# Author:`).

### 2. No delay between consecutive `fbink` calls (the real layout bug)
Confirmed empirically via isolated test scripts (test1–test4 in this
folder) run directly on the device:

- **test1** (1 draw, `-y 0`): rendered correctly.
- **test2** (2 draws, `-y 0` and `-y 10`, both with `-b`): both rendered
  correctly, confirming the row-grid math (`-S`/`-y`) was never actually
  wrong.
- **test3** (4 draws, `-b` + single final `-s` refresh): only the first
  draw showed up. Rows 5/10/15 vanished entirely.
- **test4** (4 draws, no `-b`, so every call does its own full refresh):
  draw 1 rendered fully, draw 2 showed only a single stray "T" glyph
  (cut off mid-render), draw 3 rendered fully, draw 4 was missing.

The stray "T" in test4 is the key clue: a draw was caught **mid-render**
by the next `fbink` call firing before the e-ink panel's physical refresh
had finished. This is a hardware/driver timing race, not a row-position
or flag problem — the row math (`-S` scale × row number → pixel offset)
was correct the whole time.

**Fix:** add `sleep 1` after every single `fbink` draw call in
`cat_clock.sh`, so each write settles before the next one fires. Whole
seconds only — Kindle's BusyBox shell may not support fractional `sleep`
arguments (e.g. `sleep 0.3`) depending on build flags
(`FEATURE_FLOAT_SLEEP`), and risking a decimal value could reintroduce a
silent parse failure. The 10 added sleeps cost ~10s per run, which is
fine since the script already idles with `sleep 60` at the end of its
loop.

## Flags confirmed against FBInk's real CLI.md (not guessed)

Source: https://raw.githubusercontent.com/NiLuJe/FBInk/master/CLI.md

- `-x`/`--col`, `-y`/`--row`: text-grid row/column, not raw pixels.
  Negative values count from the far edge.
- `-X`/`--hoffset`, `-Y`/`--voffset`: pixel **offset** added on top of
  the `-x`/`-y` position — not a standalone absolute-pixel coordinate
  system.
- `-S`/`--size`: scale multiplier. Default `0` = automatic, picked from
  screen resolution (range 1–4). We always pass it explicitly (1, 2, or
  4) to avoid relying on the automatic behavior.
- `-m`/`--centered`: overrides column only (horizontal). `-M`/`--halfway`
  is the vertical equivalent — not currently used in `cat_clock.sh`.
- `-g`/`--image`: `file=PATH,x=NUM,y=NUM,w=NUM,h=NUM,halign=,valign=`.
  The inline `x=`/`y=` here are **pixel** coordinates (confirmed by
  FBInk's own doc note contrasting it with `-x`/`-y`), which is why the
  cat image positioned correctly from the start while row-grid text did
  not.
- `-P`/`--progressbar NUM`: real native full-width progress bar.
  Ignores `-m`, `-x`, `-X`, `-o`, `-p` (all horizontal/overlay/padding
  flags), but is not documented as ignoring `-y` — so vertical row
  placement still applies.
- `-b`/`--norefresh`: write to the framebuffer only, skip the physical
  e-ink refresh. Used on every draw call except the last, which uses
  `-s`/`--refresh` to do one single physical refresh at the end.

## Things ruled out along the way

- **Not** a row-to-pixel scale miscalculation — test1/test2 proved
  `-y 0` and `-y 10` both land correctly at scale 2.
- **Not** left-edge clipping — confirmed visually (margin present before
  text in the device photos).
- **Not** FBInk's automatic resolution-based font upscaling overriding
  our explicit `-S` values — never actually confirmed either way, but
  ruled out as the primary cause once the timing issue was isolated.
- **Not** the `-P` or `-f unscii` flags — both were tried and reverted
  earlier while chasing this bug; `-P` is real and now back in use, `-f`
  (pixelated/unscii font) was never confirmed to exist on this FBInk
  build and is still unused. If a pixelated font is wanted later, verify
  the real font list on-device first (e.g. `fbink --help` output or
  equivalent) rather than guessing a name again.

## Round 2: timing fix worked, but time display vanished

After adding `sleep 1` between every draw call (see above), a real
on-device test showed day/date/image/progress-bar/percentage all
rendering correctly — but the big time display was completely absent,
with "Monday" sitting right at the top of the screen (no gap above it).

Theory: everything is batched with `-b` (framebuffer write only, no
refresh) until the single `-s` at the end. If the Day text's drawing
region (row 8 at scale 2 — originally row 3, before this fix) physically
overlapped the Time text's region (row 0 at scale 4), FBInk would clear
that overlapping area to the background color before drawing "Monday",
silently erasing the still-unrefreshed time pixels in the shared
framebuffer before the final `-s` ever shows anything. This would
explain "time appeared then disappeared" if watched live, and a final
image with no gap at all (not even blank space).

**Fix:** gave the time row much more vertical clearance before the next
element, then recomputed every row/pixel position below it so nothing
else collides. Also shrank the cat image from `w=560` (~187px tall) to
`w=450` (~150px tall) to keep the whole layout within the 800px screen
after the extra clearance was added at the top.

## Round 3: layout fix confirmed, but time fails on the SECOND run only

Retested on-device: first run after the clearance fix worked correctly
end-to-end, including the time display (confirmed via photos taken
mid-run at 00:05/00:10/00:16 of a screen recording — time, then
day/date, then the full bottom section with bar and percentage, all
appeared in order with no overlap). The earlier "time vanished" bug from
round 2 is resolved.

However: tapping the script a **second time immediately after** (no
screensaver/sleep in between, no idle period — confirmed with the user)
reproduced a *different* symptom: time failed to show on that second
run, while every other element (day/date/image/bar/percentage) rendered
correctly, same as the first run.

Theory: the script's very first action, `-q -c` (clear), may need
settling time before the next draw — the same class of timing race
already fixed between individual draw calls (see Round 1), just not
yet applied at the very start of the script. On a true "first" run
(from a static library/UI screen) there's likely enough incidental delay
before the first draw for this to not matter; on a quick re-tap right
after the previous run's final `-s` refresh, there may not be.

**Fix:** added `sleep 1` immediately after the initial `-q -c`, and
another `sleep 1` after the final `-q -s` (before the script's closing
`sleep 60`) — covers both "clear needs to settle before drawing" and
"this run's final refresh needs to settle before the next run's clear
fires", in case repeated quick taps are a realistic usage pattern (not
just a one-off test artifact).

**Not yet confirmed on-device** — next test should specifically be two
quick back-to-back taps, same as what reproduced the bug, to check the
added settle time resolves it.

This fix is **not yet confirmed on-device** — recomputed from the same
`16px × scale` row-height assumption that held up in test1/test2
earlier, but applied with a larger safety margin this time specifically
because we don't have hard confirmation of the real cell height at
`-S 4`. If the time still doesn't show, the next step is an isolated
test: draw time alone at `-S 4 -y 0`, then day at a much larger row
(e.g. `-y 20` at scale 2) to find exactly how much clearance scale 4
actually needs.

## Round 4: found a reference implementation, matched its layout

User found the original inspiration via a Reddit post
(r/kindle, "Jailbroke my kindle today") — a different device (Kindle
8th gen, WinterBreak2 jailbreak, not our 10th gen/SpiderCat setup) but
the same concept: FBInk shell script combining a cat image with time,
weekday, date, and a year-progress bar. Not the same binary/build as
ours, so nothing about their exact flags is assumed to transfer
directly — but the visual layout was a useful reference to match:

`TODAY` (small label) → big time → weekday → date → separator → cat
image → "YYYY YEAR PROGRESS" / "N DAYS LEFT" → progress bar (no text
inside it) → "NN.N% OF YYYY ELAPSED".

Investigated why our own bar had "76%" rendered overlapping it (visible
in an earlier screenshot) while the reference's bar is clean: confirmed
via FBInk's CLI.md that `-P`/`--progressbar` does **not** draw any text
of its own — it's purely a filled rectangle. So the "76%" we saw wasn't
a `-P` feature bleeding through; it was our own
`"$PERCENT% OF YEAR ELAPSED"` text row rendering too close to the bar's
row and visually overlapping it. Fixed by giving more clearance between
the bar row and the percentage text row below it (`-P`'s real pixel
height still isn't documented anywhere, so the gap is a safety margin,
not a measured value).

**Added:** a `"TODAY"` label (scale 1) directly above the time, matching
the reference layout. Time shifted from row 0 to row 1 (scale 4) to
leave room for it.

**Not done:** the reference's pixelated/blocky font and the gray
background box behind its cat image. Deliberately skipped for now:
- The pixel font in the reference image doesn't confirm anything about
  *our* FBInk binary (different device/jailbreak toolchain entirely).
  If this is revisited, test the font flag in an isolated throwaway
  script first — same pattern as the earlier timing bug investigation —
  rather than risking the whole script on an unverified flag again.
- The gray box behind their cat image is not something `cat_october.png`
  has baked in (confirmed transparent/white background), so matching it
  would require FBInk drawing a filled background rectangle behind the
  image — not attempted yet, no confirmed flag for it in CLI.md.

## Round 5: confirmed working end-to-end, then a punch list from the real photo

On-device test (with the Round 4 changes) rendered everything in order
with no missing elements, and — critically — **worked on a second,
immediate re-tap too** (no screensaver/sleep in between), confirming the
clear-settle sleep fix from Round 3 held up.

But the actual photo revealed `-P` does draw its own inline "NN%" label
baked into the bar, directly contradicting both FBInk's CLI.md and
fbink.h docs (neither mentions any label/text option for
`fbink_print_progress_bar`). Given the contradiction between documented
behavior and observed behavior, and burned by guessing before, the
decision was to stop relying on `-P` entirely rather than chase the
mystery further.

Punch list from that photo, all fixed in this round:
1. **Bar showed "76%" overlapping it.** Replaced `-P` with a hand-drawn
   text bar (`#`/`-` characters, same approach as the very original
   script, which was already proven to render correctly) — full control
   over what's shown, no hidden label.
2. **Wording**: "OF YEAR ELAPSED" → "OF $YEAR ELAPSED" (e.g. "OF 2026
   ELAPSED"), matching the reference image's phrasing.
3. **General spacing was uneven / "wonky"**: reworked the whole
   pixel budget — tightened the day/date gap below the time (was
   row 8/9 at scale 2, now row 5/6, still well clear of the time row
   per the proven fix), and enlarged the cat image from `w=450`
   (~150px tall) to `w=600` (full screen width, ~200px tall) to match
   the reference's more prominent, centered illustration. Every row
   below the image was recomputed to stay consistent with the larger
   image and tighter top section.

**Not yet confirmed on-device.**

## Round 6: bar reverted to -P, image/bar overlap found and fixed

On-device test of Round 5 showed the hand-drawn text bar overlapping
directly with the "76.44% OF 2026 ELAPSED" line below it, AND the cat
image's top edge (visible cat ears/hat poking through) bleeding into
that same region — the image was landing lower/taller on screen than
the exact `w=600 → h=200` arithmetic predicted, for the second time.

Decision: revert the bar back to `-P` (accepting its inline "NN%"
label as a known cosmetic quirk rather than fighting it further — a
native filled rectangle looks better than hand-drawn `#`/`-` text
regardless).

For the image/overlap problem: since exact pixel arithmetic has now
been wrong twice in a row for this specific image despite being
internally consistent on paper (`y=271` + `h=200` should end at 471,
with a separator placed at 480 — only a 9px gap, and that's exactly
where the real overlap appeared), the fix this round is a much larger
safety margin (40px, not 9-15px) on both sides of the image, treated
as load-bearing rather than cosmetic. The root cause of the
discrepancy itself is still not fully understood — possibly `-g`'s
`h=0` auto-scaling doesn't round the same way our own division does,
or there's rendering overhead (e.g. dithering/padding) FBInk adds
around images that isn't reflected in the raw width/height numbers.

**Not yet confirmed on-device** — if 40px margins still aren't enough,
the next step should be an isolated test: draw the image alone at a
known y, then a text marker directly below it at increasing offsets,
to find the real rendered height empirically rather than trusting the
`w × src_h/src_w` formula.

## Round 7: found the real root cause — image draws corrupt everything after them

Ran the isolated-marker test (test5): confirmed the `w × src_h/src_w`
height formula WAS correct all along (~200px for `w=600`) — image drawn
alone at `y=100` with text markers below it showed the real bottom edge
around y≈280-300px, matching the formula almost exactly. So the Round 6
"give it more margin" fix was treating the wrong symptom.

Ran a second isolated test (test6): image at `y=100`, then a `-P` bar
at `-S 2 -y 21` (which should resolve to pixel 672 per our row math),
then a marker labeled with that expected pixel. Result: the bar
rendered immediately after the image (~y=300-330), nowhere near the
marker at 672px, which sat alone in blank space. **`-P` ignores `-y`
entirely** and instead renders right after whatever was drawn
immediately before it — contrary to FBInk's own CLI.md, which never
documents this.

This looked at first like it explained an earlier screenshot where the
bar HAD landed correctly (right between "N DAYS LEFT" and the
percentage text) — reasoned as coincidence, since in that script `-P`
was called right after that text, so "renders after the previous draw"
happened to match the intended position.

But a third, more thorough test (test7) reproducing the real script's
full bottom-section sequence (image → separator → year-progress →
days-left → `-P`) showed something bigger: **every text element after
the image stacked tightly right after the image too, not just `-P`** —
"2026 YEAR PROGRESS", "86 DAYS LEFT", and the bar all landed clustered
right below the image, while every "MARK-XXX-EXPECTED" pixel marker sat
far below, untouched, exactly where the row math predicted they
should've been (confirming the row-grid math itself is still correct —
it's just not being applied).

**Real root cause**: drawing an image via `-g` appears to corrupt or
reset FBInk's row-grid cursor/state for every subsequent text (and
`-P`) draw call in the same script invocation. Text drawn *before* an
image respects `-y` correctly (proven repeatedly in test1-test4); text
drawn *after* an image does not.

**Fix**: reordered `cat_clock.sh` so the image is the LAST draw call in
the script, after every text element (including the bar). All text
keeps its original intended `-y` row so the page should look the same
once the image is layered in last — draw order no longer matches
visual/vertical order, but that's fine since each element's position
is independent (text via row-grid, image via its own pixel `y=`).

**Not yet confirmed on-device.**

## Image sizing

Source `cat_october.png` is 2172x724 (~3:1 aspect ratio). Scaled via
`-g "file=...,w=600,h=0,y=271"` — `h=0` tells FBInk to preserve aspect
ratio automatically, landing at ~200px tall. At `w=600` the image spans
the full screen width, so `-m` centering has no horizontal margin to
work with (no white space on either side, unlike the reference image).

## Layout reference (current `cat_clock.sh`)

Row numbers below are `-y` values per their own `-S` scale (rows are
NOT interchangeable across different scales — a row 10 at `-S 1` is not
the same pixel position as row 10 at `-S 2`):

| Element              | Scale | Row | ~Pixel | Notes |
|-----------------------|-------|-----|--------|-------|
| "TODAY" label         | 1     | 0   | 0      | top of screen |
| Time                  | 4     | 1   | 64     | |
| Day                   | 2     | 5   | 160    | |
| Date                  | 2     | 6   | 192    | |
| Separator             | 1     | 15  | 240    | ends ~256px |
| Cat image             | —     | —   | 296    | pixel y, w=600, h=0 (exact 200px tall, full width); 40px margin above/below treated as load-bearing, see Round 6 |
| Separator             | 1     | 34  | 544    | 40px below image (ends ~496px) |
| "YYYY YEAR PROGRESS"  | 2     | 18  | 576    | |
| "N DAYS LEFT"         | 2     | 19  | 608    | |
| Progress bar (`-P`)   | 2     | 21  | 672    | native, full-width, bakes in its own "NN%" label (accepted) |
| Percentage text       | 2     | 23  | 736    | below the bar, ~32px margin to screen edge (tight) |

## Test scripts in this folder

`test1_single.sh` through `test4_refresh_each.sh` are the isolated
diagnostic scripts used to find the timing bug. Safe to delete once
`cat_clock.sh` is confirmed working end-to-end on-device — they're not
needed for the clock to run, only kept for reference if similar
symptoms show up again after future edits.

## Round 8: turning the tap-to-run script into an actual screensaver

Goal shifted from "script renders correctly when tapped" to "script
renders automatically every time the Kindle sleeps" — i.e. actually
replacing the lock screen, not just a manually-run dashboard.

### Ad removal: `com.lab126.blanket`

Ads and the stock screensaver are controlled via LIPC's `blanket`
component system, not a config file:

- `lipc-get-prop com.lab126.blanket load` — lists currently loaded
  components (confirmed values on this device: `langpicker
  blankwindow ad_screensaver usb` by default).
- `lipc-set-prop com.lab126.blanket unload ad_screensaver` — removes
  the ad screensaver.
- `lipc-set-prop com.lab126.blanket load screensaver` — loads the
  stock non-ad screensaver.

**Both lines are required.** Unloading `ad_screensaver` alone — even
without touching `screensaver` — left `blanket` with nothing to show
on sleep and froze the power button completely (confirmed twice
on-device; only fixed by a reboot). Explicitly loading `screensaver`
right after gives blanket a fallback. Do not unload `screensaver`
either — tried that too, same frozen-power-button result.

**This state is runtime-only, not persisted.** Every reboot resets
blanket back to showing ads. `disable_ads.sh` must be re-run manually
after every reboot until this is automated (not yet done — see Open
Issues below). Implemented in `disable_ads.sh`.

### FBInk bug: leading `-` in a string is read as a flag

The horizontal rule strings (`"----...----"`) were being passed as
bare arguments and FBInk's CLI parser read the leading `-` as an
unknown option, aborting that call and dumping the full `--help` text
to stderr instead of drawing anything. Confirmed via `check_daemon.sh`
log output: `fbink: unrecognized option '----...'`. This was silent
on-screen (the error went to our log redirect, not the framebuffer)
but meant that specific draw call never happened.

**Fix**: pass `--` before the string to mark end-of-options, e.g.
`"$FBINK" -q -b -S 1 -m -y 15 -- "----...----"`. Applied to both
separator lines and the hand-drawn progress bar (which starts with
`[` so wasn't actually affected, but given `--` for consistency/safety
since it contains many `-` characters in the middle).

### Removed the per-call `sleep 1`s — confirmed fix

Round 1 added `sleep 1` after every single `fbink` call to fix a
timing race. Revisited this: every call except the final one uses
`-b` (buffer-only, no physical refresh), so there should be nothing
to race against between them — the Round 1 race was specifically
about *consecutive full-refresh* calls, which doesn't describe this
script's structure (only the last call refreshes).

**Confirmed on-device**: removing all the inter-call sleeps fixed the
"piece-by-piece reveal" visual bug (elements appearing one at a time
with a visible delay) — the whole dashboard now paints in one clean
refresh, as intended. The dash-flag bug above was actually the bigger
contributor to the *corrupted/clipped-text* symptoms seen while both
bugs were present simultaneously; once both were fixed, output was
clean in a direct manual run (see "Confirmed working" note below).

### Progress bar: back to hand-drawn, this time it stuck

Replaced `-P` with the hand-drawn `#`/`-` bar (see Round 5) again,
now combined with both fixes above (image-last ordering from Round 7,
`--` fix, no inter-call sleeps). Percentage format changed from 2
decimals to 1 (`70.3%` not `76.16%`) to match the reference image.

**Confirmed on-device** (manual run via `check_daemon.sh`, after both
the `--` fix and sleep removal): full dashboard rendered correctly in
one clean paint, no clipping, no overlap, exit code 0, no FBInk
errors in the log.

### The daemon: hooking `goingToScreenSaver`

`cat_clock_daemon.sh` loops on `lipc-wait-event -s 0 -m
com.lab126.powerd goingToScreenSaver`, then calls `cat_clock.sh`.
Added a `sleep 2` before drawing, on the theory that the stock
screensaver (still loaded — see above) needs time to finish its own
render first so our draw isn't immediately overwritten. **This delay
value is an unconfirmed guess**, not measured.

### `/etc/init` is read-only — `mntroot rw` required

First attempt to write `/etc/init/cat-clock-daemon.conf` (the upstart
job that should start the daemon on boot) reported success but
silently did nothing — confirmed via a dedicated check
(`check_upstart_write.sh`): `/dev/root` is mounted `ro`, and even as
root (`uid=0`), a direct write to `/etc/init/` failed with exit code 1.

**Fix**: wrap the write in `mntroot rw` / `mntroot ro` (the standard,
documented Kindle command for this). Confirmed working — `ls -la`
after the write showed the file genuinely persisted this time, with
a non-zero size and current timestamp. Implemented in
`setup_daemon.sh`.

### Open issue: duplicate daemon processes after every boot

Even starting from a clean reboot with the upstart job correctly
persisted, `ps` consistently shows **two** `lipc-wait-event` processes
alive (e.g. PIDs 1956 and 4018), not one. One appears very early in
the boot sequence (consistent with `start on started lab126_gui`
firing once, as expected); the second appears much later, interleaved
with other user-level shell/scriptlet activity, for a reason not yet
identified.

This matters beyond tidiness: two daemons both listening for the same
sleep event means two concurrent `cat_clock.sh` invocations per lock,
racing to clear/draw the same framebuffer. This is the leading
suspect for why the dashboard has not yet been confirmed visible on
an actual lock screen (as opposed to a direct manual run, which has
been confirmed clean) — ads are confirmed off and the daemon is
confirmed catching the event and running `cat_clock.sh` successfully
(exit code 0, per `cat_clock_daemon_live.log`), but the stock
screensaver rotation is still what's visible on lock, not our
dashboard.

Also unresolved: `initctl stop cat-clock-daemon` returned `"Unknown
instance:"` rather than cleanly stopping it, suggesting the upstart
job's `script ... end script` block (no `exec` line, no instance
name) may not be registering as a normal stoppable job the way
`cri.dev`'s reference example assumed. Not yet root-caused.

**Next step**: `find_daemon_triggers.sh` was written to check for a
second trigger source (duplicate `.conf` file, or something else
spawning the daemon) and to walk the parent-process tree of both
`lipc-wait-event` PIDs — not yet run/confirmed as of this writing.

### Files added this round

- `disable_ads.sh` — unloads `ad_screensaver`, loads `screensaver`.
- `setup_daemon.sh` — writes `cat_clock_daemon.sh` + the upstart
  `.conf` (via `mntroot rw`/`ro`), starts the daemon once.
- `restart_daemon.sh` — stops/starts the daemon via `initctl`
  (with a manual-kill fallback for stragglers); use this instead of
  re-running `setup_daemon.sh` when the daemon needs restarting after
  a script edit.
- `check_daemon.sh`, `check_upstart_write.sh`, `check_processes.sh`,
  `find_daemon_triggers.sh` — one-off diagnostics, safe to delete once
  the duplicate-daemon issue above is resolved.

## Round 9: the "duplicate daemon" theory was a false lead; the real
## fix was the X11 shield

The "two `lipc-wait-event` processes" finding from Round 8 turned out
to be a **misread, not a bug**. Walking the parent-process tree of
both PIDs (`find_daemon_triggers.sh`) showed one was genuinely our
daemon (parent chain led back to upstart's `cat-clock-daemon`
instance); the other was `lipc-wait-event com.lab126.playermgr
playermgrStarted` — a completely unrelated **stock system process**
waiting on a different event, which only matched `ps | grep
lipc-wait-event` because it happens to use the same binary. There was
never a second copy of our daemon running. (This match-on-binary-name
trap is now documented in SCREENSAVER_GUIDE.md's system gotchas.)

So the real reason the dashboard wasn't appearing on lock (ads
confirmed off, daemon confirmed catching the event and running
`cat_clock.sh` successfully) was something else: **`goingToScreenSaver`
fires before the screen visually blanks** — the window manager
(`awesome`/Xorg) hasn't finished its own repaint yet, so a bare FBInk
draw gets raced and overwritten. Confirmed directly: the dashboard
flashed briefly over the still-visible home screen, then lost the
race to the stock UI. Neither a 2s nor a 10s fixed delay fixed this,
because it's a race against a whole separate rendering layer, not a
timing problem.

**The fix**: reused the `screensaver_shield` prebuilt ARM hard-float
binary from the open `chengandre/kindle-custom-screensaver` project
(matches this device's `kindlehf` architecture exactly, no rebuild
needed). It opens a fullscreen X11 `override_redirect` window with no
background pixmap, physically blocking the window manager from
repainting until torn down — not a timing trick. Rebuilt
`cat_clock_daemon.sh` around that project's proven sequence: unload
blanket's `screensaver` transiently → raise the shield → run
`cat_clock.sh` → wait for `outOfScreenSaver` → tear down the shield →
force a wake refresh (`fbink -k -f -W GC16` + `DISPLAY=:0 xrefresh`)
→ restore blanket. **Confirmed working end-to-end on the real lock
screen** after this — the long-standing "runs successfully but isn't
visible" symptom was fully resolved.

Also found and fixed in the same round: `lipc-wait-event -s 0 -m
...` was hanging forever after the first event instead of returning.
`lipc-wait-event --help` revealed `-s N` means "max wait N seconds,
N must be >0" (so `-s 0` was invalid) and `-m` means "wait for
multiple events, don't exit after one" — the literal opposite of the
one-shot wait we wanted. Fix: drop both flags; a bare `lipc-wait-event
<source> <event>` already exits after exactly one match.

## Round 10: the row-height formula was wrong since Round 1 — real
## root cause of the recurring "missing bottom content" bug

Everything in Rounds 1-9 assumed scale-1 row height = 16px (from the
very first test in this file). A calibration pass this round, using
`fbink -E` (`--coordinates`, which prints FBInk's own exact drawn
pixel rectangle) rather than eyeballing a photo, found the real value:
**row height = 8 * S px**, exactly half of what was assumed the
entire time. `fbink -v`'s "Page size: 50 rows" is still correct as a
row *count*, just describing a 400px band (50 rows * 8px), not the
800px full screen, at scale 1.

This fully explains the "bottom block missing/clipped" symptom that
recurred across multiple earlier rounds: every row number in the
script was landing at roughly *half* its intended pixel position,
compressing the whole layout into the top of the screen and pushing
anything meant for the bottom half out past where it was ever
checked.

Getting to this number took a few wrong turns, documented in detail
in SCREENSAVER_GUIDE.md's "Layout workflow" section: an early
wide-angle photo was misjudged as confirming the wrong 16px figure;
a second, seemingly-confirming photo turned out to be a cropped
video-player screenshot with UI chrome hiding the real screen edge.
Only `-E`'s direct numeric output, plus a dense full-ladder photo (all
50 rows at once), made the real ratio undeniable.

With the corrected formula, `cat_clock.sh`'s entire layout was
rebuilt and iteratively refined against real user feedback over
several more passes (bigger/smaller element sizes, spacing between
every pair of elements, a real graphical progress bar via `-k`/`-B`
instead of text characters or the broken `-P`, and a global `-Y`
offset to vertically center the whole composition) — each change
re-verified with a throwaway `-E` dry-run script before testing on
the real screen. This workflow, and the specific mistakes it caught
(including two further arithmetic errors in hand-written row-math
comments, not re-confirmed before shipping), is documented in full in
SCREENSAVER_GUIDE.md rather than repeated here.

**Confirmed final state**: the dashboard renders correctly and
reliably on every real lock/unlock cycle, vertically centered, with
a clean graphical progress bar, matching the original reference
image's layout closely. Project considered functionally complete as
of this round.
