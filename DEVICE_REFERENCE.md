Confirmed device/FBInk reference for this Kindle — captured via
`calibrate.sh` (`fbink -v`, `fbink --help`) on 2026-10-07. Use this
instead of re-deriving or guessing these values again.

## Device

- Kindle Basic 3 (0VB -> 0x3AB => Jaeger on Rex), 10th gen basic.
- Screen: 600x800, 8bpp, 167 dpi.
- Rotation: 3 (Counter Clockwise, 270°) — internal panel wiring info;
  FBInk handles this itself, does not need compensating for in our
  own `-x`/`-y` row-grid math.
- Framebuffer: `mxc_epdc_fb`, pixel format Y8, line length 608 bytes.
- `fbink -e` **segfaults on this device** — do not rely on it for
  device info; use `fbink -v` instead.

## Row-grid math (confirmed, matches Round 1's formula)

- Font size at scale 1: 16x16 px (IBM base glyph 8x8).
- **Page size: 50 rows** for the 800px-tall screen at scale 1 →
  800 / 50 = **16px per row at scale 1**, confirming `-S N` scales
  linearly: row height = 16 * N px.
- Line length: 37 cols at scale 1.
- `fbink -v` also reports this directly — rerun it any time this
  needs reconfirming after an update.

## Confirmed behavioral quirks (from FINDINGS.md, still valid)

- `-g` image draws corrupt the row-grid cursor for every subsequent
  text/`-P` draw call in the same invocation — always draw images
  LAST.
- A leading `-` in a plain STRING argument (e.g. a dashed separator)
  is read as an unknown flag by FBInk's parser and aborts that call
  silently (output goes to stderr/log, not the screen) — always pass
  `--` before such a string.
- `-P`/`--progressbar` bakes in its own "NN%" label on this device's
  build, contrary to upstream FBInk's documented behavior — use a
  hand-drawn bar instead if a clean label-free bar is wanted.
- `lipc-wait-event [options] [<event-source>] <event-names>` — `-s N`
  means max-wait-N-seconds (N must be >0), NOT "exit after one event".
  `-m` means "wait for multiple events, don't exit after one" — the
  opposite of a one-shot wait. For a simple one-shot wait (the common
  case), pass neither flag.

## Full `fbink --help` output

See `fbink_help.txt` in this folder for the complete, verbatim CLI
reference (flags, image options, OpenType support, daemon mode, etc.)
— captured directly from this device's FBInk 1.25.0 build so it
reflects exactly what's available here, not a generic/upstream guess.
