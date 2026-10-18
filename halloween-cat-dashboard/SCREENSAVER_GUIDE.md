# Kindle custom screensaver — reusable reference

Everything needed to build another FBInk-based dynamic screensaver on
this same device, without re-deriving it from scratch. For the blow-
by-blow debugging history of *this* project, see `FINDINGS.md`
instead — this file is the distilled, reusable version.

## Device

- Kindle 10th gen basic ("Rex" / Kindle Basic 3), jailbroken via
  SpiderCat, firmware 5.18.1.1.1, hard-float.
- Screen: 600x800, 8bpp, 167 dpi.
- **ROW HEIGHT IS 8px/row AT SCALE 1, NOT 16px/row.** This was wrong
  from Round 1 onward and is the real root cause of most of this
  project's layout bugs (text clipping, "missing" bottom-of-screen
  elements, etc.) — every previous round's row math assumed double
  the real height. Confirmed via `fbink -E` (`--coordinates`), which
  reports FBInk's own exact drawn pixel rect — the authoritative
  source, no photo-measuring/guessing needed:
  - Scale 1: row N → Top = 8*N px, Height = 8px.
  - Scale 2: row N → Top = 16*N px (= 2x scale-1 height, consistent).
  - Scale 4: row N → Top = 32*N px (= 4x scale-1 height, consistent).
  - General formula: **row height = 8 * S px**, where S is the
    `-S`/`--size` value.
  - `fbink -v`'s "Page size: 50 rows" is still correct as a row
    *count* (valid rows are 0-49 at scale 1) but describes a 400px
    tall usable area (50 * 8px), not the full 800px screen — i.e.
    **the positive `-y` row-grid only reaches the top half of this
    screen at scale 1**. To reach lower on-screen, either use a
    negative `-y` (per `--help`: "a negative value... count[s] back
    from the bottom of the screen") or a higher `-S` scale (which
    covers more screen per row), or `-Y` for a raw pixel offset.
  - Use `fbink -E -S <scale> -y <row> "text"` directly any time this
    needs reconfirming — it prints `lastRect_Top`/`lastRect_Height`
    etc. straight to stdout, no screen refresh, no photo needed.
  - Getting here took several wrong turns worth knowing about if
    repeating this exercise: an initial wide-angle photo was
    misjudged as confirming the (wrong) 16px/row figure; a second
    photo that seemed to confirm it turned out to be a cropped
    video-player screenshot with UI chrome hiding the real screen
    bottom edge; only a dense full-ladder photo (all 50 rows) made
    the compression undeniable, and `-E` gave the final exact
    numbers. If a formula ever "looks confirmed" by eyeballing a
    photo, prefer `-E`'s direct numeric output over trusting the
    photo.
- `fbink -e` **segfaults** on this device — use `fbink -v` for device
  info instead.
- Full `fbink --help` text, captured verbatim from this device's
  FBInk 1.25.0 build: `fbink_help.txt`.

## Toolchain already in place

- FBInk binary: `/mnt/us/libkh/bin/fbink`.
- KPM (package manager), KTerm (terminal — **on-screen keyboard is
  broken on this device**, don't rely on it for typing), KOReader all
  installable via `;kpm install <name>` from the search bar.
- No SSH/USBNetwork available (package doesn't exist on this
  jailbreak's KPM repo) — all on-device work happens via tap-to-run
  `.sh` scriptlets placed in `/mnt/us/documents/` (indexed
  automatically as tappable "books"), with results read back via
  log files over the USB mass-storage connection. This full
  round-trip (write script locally → copy via USB → tap on device →
  read log back via USB) is slower than SSH but was the only
  reliable option here.

## Architecture that actually works (confirmed end-to-end)

1. **Drawing**: a shell script using `fbink` calls, buffer-only
   (`-b`) for every draw except a single final `-s` refresh — see
   "FBInk gotchas" below for the specific bugs this avoids.
2. **Removing ads** (`disable_ads.sh`): `lipc-set-prop
   com.lab126.blanket unload ad_screensaver` then `lipc-set-prop
   com.lab126.blanket load screensaver` — both lines required, in
   that order. This state is **runtime-only**, reset on every reboot;
   re-run after every boot.
3. **Hooking the sleep event** (`cat_clock_daemon.sh`, run as an
   upstart job so it survives reboots): loop on `lipc-wait-event
   com.lab126.powerd goingToScreenSaver` (no `-s`/`-m` flags — see
   gotcha below), then:
   - Transiently unload blanket's `screensaver` component (separate
     from the permanent ad-removal unload above).
   - Raise an X11 shield window (see below) to block the window
     manager from repainting over our draw.
   - Run the actual drawing script.
   - Wait for `lipc-wait-event com.lab126.powerd outOfScreenSaver`.
   - Tear down the shield, force a wake refresh (`fbink -k -f -W
     GC16` + `DISPLAY=:0 xrefresh`), restore the blanket component.
4. **The X11 shield is the part that actually makes this reliable.**
   `goingToScreenSaver` fires *before* the screen visually blanks —
   the window manager hasn't finished its own repaint yet, so a bare
   FBInk draw gets raced and overwritten (confirmed on-device: text
   flashed briefly over the still-visible home screen, then lost the
   race). A fixed delay cannot reliably fix this since it's racing a
   whole separate rendering layer, not just timing. The reused
   `screensaver_shield` prebuilt ARM hard-float binary (from
   `chengandre/kindle-custom-screensaver`, MIT-equivalent open
   project, prebuilt for `kindlehf` — this exact architecture) solves
   this by opening a fullscreen `override_redirect` X11 window with
   no background pixmap, physically blocking repaints until torn
   down. This is NOT something you can skip by tuning a sleep delay —
   confirmed by direct experiment (2s and 10s delays alone, without
   the shield, both failed the same way).

## FBInk gotchas (all confirmed on-device, not guesses)

- **Draw images LAST.** A `-g` image draw corrupts the row-grid
  cursor for every subsequent text/`-P` call in the same script
  invocation — text drawn *after* an image stops respecting `-y`
  and stacks incorrectly right after the image instead. Text drawn
  *before* the image is unaffected.
- **A leading `-` in a plain STRING argument is read as a flag.**
  E.g. a dashed separator string starting with `-` aborts that call
  with `unrecognized option` and dumps the full `--help` text to
  stderr (not the screen — easy to miss). Always pass `--` before
  such a string: `fbink -S 1 -y N -- "----..."`.
- **`-P`/`--progressbar` bakes in its own "NN%" label** on this
  device's build, contrary to upstream FBInk's documented behavior
  (`-P` is documented as a bare filled rectangle, no text), AND it
  can render as corrupted/garbled boxes depending on position —
  confirmed broken twice on this device across two different
  attempts. Don't use `-P` at all.
- **For a real graphical bar (not text characters), use `-k`/`--cls`
  with `-B`/`--background` to fill two overlapping rectangles.**
  `-k` normally just clears a region, but combined with `-B <color>`
  it paints that whole rectangle with a solid background color —
  draw a light-gray "track" rect first, then a narrower black "fill"
  rect on top at the same position, sized proportional to percent
  complete:
  ```sh
  fbink -b -k top=T,left=L,width=TRACK_W,height=H -B GRAYC
  fbink -b -k top=T,left=L,width=FILL_W,height=H -B BLACK
  ```
  This produces a genuinely clean solid bar matching a real progress
  bar's look — confirmed working on-device, and a better result than
  either `-P` or a hand-drawn `#`/`-` text bar. A hand-drawn `#`/`-`
  bar is still a reasonable fallback if `-k`/`-B` isn't available in
  a given FBInk build.
- **Unicode box-drawing/block characters don't all share the same
  rendered width as plain ASCII in this font.** The horizontal line
  char `─` (U+2500) renders as a clean thin solid line and is safe to
  use for separators. The solid block char `█` (U+2588) renders
  VISIBLY WIDER than `-`/`#`/`[`/`]` — confirmed on-device: a bar
  built from `█` for the filled portion and `-` for the empty portion
  overflowed past where the closing `]` should land, leaving a stray
  fragment of the string floating past the bar. For a hand-drawn
  progress bar, stick to plain ASCII (`#`/`-`/`[`/`]`) for the fill —
  they're from the same monospace glyph set and line up correctly.
  Confirm any new Unicode character's width empirically
  (`test_line_char.sh` pattern: print it, look at the result) before
  relying on it being the same cell width as ASCII.
- **No `sleep` needed between consecutive `-b` (buffer-only) calls.**
  Only needed around consecutive *physical refresh* (`-s`) calls,
  which race the panel's actual refresh completing. A script that
  does N buffer-only draws then one final `-s` needs zero sleeps.
- **`lipc-wait-event` flag meanings are non-obvious — confirmed via
  `lipc-wait-event --help` on-device:**
  `lipc-wait-event [options] [<event-source>] <event-names>`
  - `-s N`: max wait **N seconds**, N must be `>0` (NOT "exit after
    one event" — `-s 0` is actually an invalid value).
  - `-m`: wait for **multiple** events, don't exit after one (NOT
    "match this event source" — passing it when you want a simple
    one-shot wait causes the call to hang forever after the first
    event instead of returning).
  - For the common one-shot case (wait for exactly one event, then
    continue), pass **neither** flag.
- **`-y`/`--row` is capped to the valid 0-49 row range at every
  scale** (confirmed via `fbink -v`'s "Page size: 50 rows") — a row
  number outside that range is invalid input, not just "further down
  the screen". To position an element below the row-grid's reach at
  a given scale (common for anything in the bottom half of this
  800px screen at scale 1-2), use **`-Y`/`--voffset` WITHOUT any
  `-y`/`-x` flag at all**: `-Y` is normally documented as an
  additional pixel adjustment *on top of* `-y`'s row position, but
  when `-y` is omitted it defaults to row 0 and `-Y`'s value becomes
  the element's absolute pixel position directly — confirmed via
  `-E`: `fbink -E -S 1 -Y 672 "text"` reported `lastRect_Top=672`
  exactly, bypassing the row-range limit entirely. `-Y` also stacks
  additively with `-y` when both are given (e.g. `-y 3 -Y 80` with
  scale 2 landed at `3*8*2 + 80 = 128`, confirmed via `-E`) — useful
  for a **global vertical offset**: to shift an entire multi-element
  layout down by a fixed amount (e.g. to center it vertically instead
  of leaving empty space pile up at one end), add the same `-Y`
  value to every single draw call rather than recomputing every row
  number by hand.

## Layout workflow that actually avoids wasted test cycles

Hand-computing row/scale pixel math and testing only by locking the
screen and photographing the result burned a lot of cycles in this
project — multiple rounds had real arithmetic mistakes (wrong
row-height formula, bar width exceeding screen width, elements
landing past the 800px bottom edge, two elements overlapping) that
only became obvious as a visibly broken photo, one fix at a time.

The fix: **before testing a layout change on the real screen, dry-run
every element's exact position with `fbink -E`** (`--coordinates`):

```sh
fbink -E -S <scale> -y <row> "representative text" 
# prints: lastRect_Left=…;lastRect_Top=…;lastRect_Width=…;lastRect_Height=…;
```

This prints FBInk's own exact drawn rectangle straight to stdout —
no screen refresh, no photo, no guessing. Write one throwaway
verification script that calls `-E` for every element in the planned
layout (see `verify_layout_v3.sh` for the pattern), check every
`Top`/`Height` pair for: (1) strictly increasing order top-to-bottom,
(2) no overlap between consecutive elements, (3) nothing exceeding
the screen's pixel height. Only then copy the real drawing script
over and test visually. This caught several real bugs (a percentage
line computed to land at 832px on an 800px screen; a bar landing
4px away from the next separator) before they ever reached a photo.

**If a script edit doesn't seem to take effect on a re-test, suspect
stale file caching before suspecting the new code is wrong.** The
Kindle's library/scriptlet indexer sometimes keeps serving an old
version of a tapped `.sh` file's content even after it's overwritten
on disk with new content (confirmed repeatedly this session: a
`verify_layout.sh` edit produced byte-identical old output,
including an identical timestamp, across two separate re-copy
attempts). The reliable fix is not to debug the caching mechanism —
just **save the edited script under a new filename** (e.g.
`verify_layout_v2.sh`) and tap that instead; a never-before-seen
filename can't be served from a stale cache.

**Don't trust an inline comment's arithmetic — recompute it
yourself, every time.** A later round of this project skipped the
`-E` dry-run check "just this once" while editing several rows at
once, and shipped a layout where a comment read "row 6 scale 8 =
48px" — but `6 * 8 * 8 = 384`, not `48`. The mistake wasn't caught
until a broken photo showed the clock missing entirely (it was
drawing inside the image area and getting painted over). This
happened twice in the same editing session, on two different
elements, because each new comment was written to justify a desired
pixel target rather than computed from the actual row/scale values
being passed to `fbink`. When writing or reviewing a row/scale
comment, actually multiply `row * 8 * scale` by hand (or rerun
`-E`) — never assume a comment is correct just because it reads
plausibly, including comments from earlier in the same file.

## Design limitation worth knowing up front

- **`-S`/`--size` only accepts whole-number multipliers (1, 2, 3...)
  — there's no fractional/in-between size.** If a given scale looks
  slightly too big and the next one down looks slightly too small,
  there's no "1.5" to split the difference. The only way to get a
  genuinely in-between visual size is to try a different built-in
  font family at the same scale (FBInk ships several — `IBM`
  (default), `UNSCII`, `ORP`, `TEWI`, and others, listed in
  `fbink_help.txt`) — some render visually smaller/thinner than `IBM`
  at an identical `-S` value. Not deeply explored in this project;
  worth testing directly on-device if this granularity gap matters
  for a future layout.

## System-level gotchas

- **`/etc/init` (upstart jobs) is read-only by default**, even as
  root (`uid=0`). Writing there silently fails (exit code 1) unless
  wrapped in `mntroot rw` ... `mntroot ro`.
- **A tap-to-run `.sh` scriptlet should never also be a background
  daemon's script**, if that same file also needs to live outside
  `/mnt/us/documents/`. Any `.sh` file in `documents/` is indexed as
  a tappable library "book" — a daemon script left there can get
  independently launched a second time by that indexing/tap
  mechanism, stacking a duplicate instance on top of the "real" one
  started by upstart. Keep daemon scripts in a separate folder (this
  project uses `/mnt/us/catclock/`) and only put scripts meant for
  manual tapping in `documents/`.
- **`ps` process names can collide.** `grep "lipc-wait-event"` will
  also match totally unrelated system processes (e.g. a stock
  `playermgr` watcher) that happen to use the same binary. Check the
  full cmdline (`/proc/<pid>/cmdline`) and parent chain
  (`/proc/<pid>/status` → `PPid`) before concluding there's a
  duplicate-process bug.
- **Blanket renderer state (`com.lab126.blanket` load/unload) is
  runtime-only**, not persisted — every reboot resets it back to
  Amazon's defaults (ads back on, our transient unloads gone).

## Files in this folder worth keeping as a reference / reusing

- `cat_clock_daemon.sh` — the daemon, shield-integrated version.
  Reusable almost as-is for a different drawing script; just change
  the `SCRIPT=` path.
- `screensaver_shield` — the prebuilt ARM hard-float shield binary.
  Reusable directly, no rebuild needed, as long as the target device
  is also `kindlehf`-architecture hard-float (confirmed match here).
- `disable_ads.sh` — reusable as-is on any ad-supported blanket-based
  Kindle.
- `setup_daemon.sh` — the upstart-job + `mntroot rw`/`ro` pattern is
  reusable; the specific file-moving/cleanup logic is project-specific.
- `DEVICE_REFERENCE.md` / `fbink_help.txt` — device-specific captured
  data; re-run `calibrate.sh` on a different device to get its own
  version of these.
