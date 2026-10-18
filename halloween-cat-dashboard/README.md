# Halloween Cat Dashboard

Part of [Kindle Dashboard](../README.md) — see the top-level README
for background reading that applies to every version (jailbreaking,
what FBInk is, device specs).

A dynamic lock-screen dashboard: time, date, a year-progress bar,
and Halloween-themed cat artwork, redrawn every time the device
sleeps.

![screensaver example](assets/cat_october.png)

## Requirements

- A jailbroken Kindle. This was built and tested on a **10th-gen
  basic ("Rex") Kindle, firmware 5.18.1.1.1, hard-float**, jailbroken
  via [SpiderCat](https://kindlemodding.org/jailbreaking/SpiderCat/).
  Other hard-float (`kindlehf`) Kindles should work with the same
  setup; soft-float devices will need a different `screensaver_shield`
  binary (see Credits).
- [FBInk](https://github.com/NiLuJe/FBInk) present on-device (ships
  with most modern jailbreak toolchains at `/mnt/us/libkh/bin/fbink`
  — check your own device's path and update `cat_clock.sh` if it
  differs).
- USB file access to the Kindle (no SSH required — everything here
  runs via tap-to-run scriptlets).

## What's in this folder

```
src/                  the scripts that actually run on the Kindle
bin/screensaver_shield  prebuilt binary that makes the custom draw
                         reliably win over the stock lock screen
reference/fbink_help.txt  full FBInk CLI reference for this build
SCREENSAVER_GUIDE.md    the real technical writeup — gotchas, the
                         row/pixel math, why the shield is needed
debugging-log.md        optional: the full round-by-round debugging
                         history, if you're curious how a specific
                         bug was actually diagnosed
assets/cat_october.png  the artwork used in this version
```

## Setup

1. **Jailbreak the device first** if it isn't already (out of scope
   here — see [kindlemodding.org](https://kindlemodding.org)).
2. Connect the Kindle over USB; it should mount as a plain drive.
3. Copy files to these locations on the device:
   - `src/cat_clock.sh` → `documents/`
   - `src/disable_ads.sh` → `documents/`
   - `src/restart_daemon.sh` → `documents/`
   - `src/setup_daemon.sh` → `documents/`
   - `src/cat_clock_daemon.sh` → `catclock/` (create this folder at
     the root of the Kindle drive — **not** inside `documents/`, see
     note below)
   - `bin/screensaver_shield` → `catclock/`
   - Your own artwork PNG → `documents/` (update the `IMAGE=` path
     at the top of `cat_clock.sh` to match its filename)
4. Eject the Kindle safely.
5. On the Kindle, open your library/home screen and tap **"Setup Cat
   Clock Daemon"** (this is `setup_daemon.sh`, now indexed as a
   tappable book). It sets up the background daemon as a persistent
   system service.
6. **Reboot the Kindle once** so the daemon starts cleanly.
7. Tap **"Disable Ads (custom)"** (`disable_ads.sh`). This also
   needs to be re-run after every future reboot — see
   SCREENSAVER_GUIDE.md for why.
8. Lock the screen. The dashboard should appear.

> **Why `cat_clock_daemon.sh` can't live in `documents/`**: any
> `.sh` file placed there gets indexed by the Kindle as a tappable
> "book". A background daemon script living there can get
> accidentally double-launched by that same indexing mechanism. Keep
> it in a separate folder.

## Customizing

- **Time/date/text**: edit the variables and `fbink` calls directly
  in `cat_clock.sh`. See SCREENSAVER_GUIDE.md for the row/scale
  pixel math (`pixel = row * 8 * scale`) before changing positions —
  it's not what the defaults might suggest.
- **Artwork**: point `IMAGE=` at your own PNG. Simple black-and-white
  or grayscale illustrations render best on e-ink; keep it under
  ~600px wide since FBInk scales it to fit.
- **Removing ads permanently on boot**: not automated yet —
  currently a manual one-tap step after every reboot.

## Credits

- [FBInk](https://github.com/NiLuJe/FBInk) by NiLuJe — the drawing
  tool everything here is built on.
- `bin/screensaver_shield` is a prebuilt binary from
  [chengandre/kindle-custom-screensaver](https://github.com/chengandre/kindle-custom-screensaver)
  (MIT licensed), reused here to reliably block the stock UI from
  repainting over the custom screensaver. See that project for
  source and for builds targeting other architectures.
- Layout inspired by a screensaver shared on
  [r/kindle](https://www.reddit.com/r/kindle/).

## License

MIT — see [LICENSE](LICENSE). `bin/screensaver_shield` is
redistributed under its own project's MIT license (see Credits).
