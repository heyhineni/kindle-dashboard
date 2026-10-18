#!/bin/sh
# Name: Cat Clock
# Author: October Cat Clock
# DontUseFBInk

FBINK="/mnt/us/libkh/bin/fbink"
IMAGE="/mnt/us/documents/cat_october.png"

# -------------------------------------------------
# DATE / TIME
# -------------------------------------------------
export LC_TIME=C

TIME=$(date "+%H:%M")
DAY=$(date "+%A" | tr '[:lower:]' '[:upper:]')
DATE=$(date "+%-d %B %Y")
YEAR=$(date "+%Y")

DOY=$(date "+%j")
DOY=$(echo "$DOY" | sed 's/^0*//')

case "$YEAR" in
    2024|2028|2032|2036|2040|2044|2048)
        DAYS_IN_YEAR=366
        ;;
    *)
        DAYS_IN_YEAR=365
        ;;
esac

DAYS_LEFT=$((DAYS_IN_YEAR - DOY))

# Percentage with one decimal place, to match the reference image ("70.3%")
PERCENT=$(awk "BEGIN {printf \"%.1f\", ($DOY/$DAYS_IN_YEAR)*100}")
# Integer percentage, used to size the hand-drawn bar fill
PERCENT_INT=$((DOY * 100 / DAYS_IN_YEAR))

# -------------------------------------------------
# Real graphical progress bar, matching the reference
# image's clean solid rectangle (not text characters).
# Uses -k/--cls, which can clear/fill an arbitrary
# rectangular region with a background color — draw a
# light-gray "track" rect first, then a black "fill"
# rect on top, narrower, proportional to percent elapsed.
# Track: 520px wide, 40px tall, left margin 40px.
# -------------------------------------------------
BAR_TRACK_WIDTH=520
BAR_FILL_WIDTH=$((BAR_TRACK_WIDTH * PERCENT_INT / 100))

# Solid separator — Unicode box-drawing horizontal line,
# confirmed via test_line_char.sh to render as a clean
# thin solid line. Both separators use the SAME scale
# (S2) — using different scales for the two in an earlier
# round made them visibly different thicknesses/lengths.
SEP="──────────────────────────────"

# -------------------------------------------------
# CLEAR SCREEN (buffer only, no sleep needed — every
# call below is -b until the single final -s).
# -------------------------------------------------
"$FBINK" -q -c

# -------------------------------------------------
# Full pixel budget for the 800px-tall screen. CONFIRMED
# formula: row height = 8 * S px (verified via `fbink -E`,
# see DEVICE_REFERENCE.md). Every row number below was
# independently re-verified with `fbink -E` via
# verify_layout_v2.sh before being used here (two earlier
# rounds of this table both had real arithmetic mistakes
# caught only by that check — do not skip it when editing
# these numbers again).
#
# Element              Scale  Row   Pixel(=row*8*scale) Height  Ends
# TODAY                   2     3       48                16      64
# Time                   10     2      160                80     240
# Day (uppercase)         3    11      264                24     288
# Date                    2    19      304                16     320
# Separator 1             2    21      336                16     352
# Image (y=368px)         -     -      368              ~147     515
# Separator 2             2    33      528                16     544
# Year progress header    2    35      560                16     576
# Days left               3    25      600                24     624
# Bar (rect fill)         -     -      648                32     680
# Percentage              2    43      688                16     704
# Quote line 1            2    45      720                16     736
# Quote line 2            2    47      752                16     768
#
# WARNING: this table was wrong THREE times in earlier
# rounds (comments claiming e.g. "row 6 scale 8 = 48px"
# when 6*8*8=384px) because the comment was written from
# a mis-remembered target value instead of actually
# computing row*8*scale. The values above were computed
# fresh, one at a time, independent of any prior comment
# in this file — if editing again, do the same: compute
# row*8*scale yourself, don't trust what's written here
# or assume a comment matches its own code.
# -------------------------------------------------

# -------------------------------------------------
# Global vertical offset: shifts EVERY element down by
# the same fixed amount, to vertically center the whole
# layout instead of leaving unused space collect at one
# end. Added via -Y on every single call below (stacks on
# top of -y's row position, per --help) rather than
# recomputing every row number.
#
# Recomputed from the CONFIRMED on-device result with
# V_OFFSET=80 (verify_layout_v10.log): content top was at
# 128px, content bottom (quote) ended at 768+8=776px. Top
# margin 128px, bottom margin 800-776=24px, total margin
# 152px. For truly even top/bottom margins (76px each),
# the offset needs to shrink by 128-76=52px: 80-52=28.
# -------------------------------------------------
V_OFFSET=28

# "TODAY" label (scale 2). Row 3 = 3*8*2=48px, +80 offset
# = 128px.
"$FBINK" -q -b -S 2 -m -y 3 -Y "$V_OFFSET" "TODAY"

# Big time (scale 10). Row 1 scale 10 = 80px, +80 offset
# = 160px.
"$FBINK" -q -b -S 10 -m -y 1 -Y "$V_OFFSET" "$TIME"

# Day (scale 3). Row 8 scale 3 = 192px, +80 offset = 272px.
"$FBINK" -q -b -S 3 -m -y 8 -Y "$V_OFFSET" "$DAY"

# Date (scale 2). Row 14 scale 2 = 224px, +80 offset = 304px.
"$FBINK" -q -b -S 2 -m -y 14 -Y "$V_OFFSET" "$DATE"

# First solid separator (scale 2). Row 16 scale 2 = 256px,
# +80 offset = 336px.
"$FBINK" -q -b -S 2 -m -y 16 -Y "$V_OFFSET" -- "$SEP"

# -------------------------------------------------
# Bottom text block. Image is drawn LAST in the script
# (an earlier -g image draw corrupts the row-grid cursor
# for every later text call — FINDINGS.md Round 7) but
# its -g y= pixel coordinate places it visually between
# the two separators regardless of draw order.
# -------------------------------------------------

# Second solid separator (scale 2). Row 31 scale 2 =
# 496px, +80 offset = 576px.
"$FBINK" -q -b -S 2 -m -y 31 -Y "$V_OFFSET" -- "$SEP"

# Year progress header (scale 2). Sep2 ends at 576+16=
# 592px; moved down to 608px (16px gap, was 0px before —
# per feedback, "blank space between line and 2026 year
# progress").
"$FBINK" -q -b -S 2 -m -Y $((528 + V_OFFSET)) "$YEAR YEAR PROGRESS"

# Days remaining (scale 3). Year progress now ends at
# 608+16=624px; shifted down 16px from before to keep the
# same clearance (was 632px, now 648px).
"$FBINK" -q -b -S 3 -m -y 23 -Y $((V_OFFSET + 16)) "$DAYS_LEFT DAYS LEFT"

# Progress bar track (light gray) + fill (black), real
# filled rectangles via -k/--cls + -B, not text chars.
# Shifted down 16px with everything else below Year
# Progress (was 672px, now 688px).
BAR_TOP=$((592 + V_OFFSET + 16))
"$FBINK" -q -b -k top=$BAR_TOP,left=40,width=$BAR_TRACK_WIDTH,height=32 -B GRAYC
"$FBINK" -q -b -k top=$BAR_TOP,left=40,width=$BAR_FILL_WIDTH,height=32 -B BLACK

# Percentage, below the bar (scale 2). Shifted down 16px
# (was 720px, now 736px).
"$FBINK" -q -b -S 2 -m -y 40 -Y $((V_OFFSET + 16)) "$PERCENT% OF $YEAR ELAPSED"

# Quote, below the percentage line (scale 1). Shifted
# down 16px (was 752px, now 768px — right at the 800px
# edge with 24px margin, since height=8 at scale 1).
"$FBINK" -q -b -S 1 -m -Y $((672 + V_OFFSET + 16)) "One breath, one page, one day at a time."

# -------------------------------------------------
# CAT — drawn LAST (see note above). Source is 2172x724
# (~3:1 aspect). w=580 -> 580*724/2172 ~= 193px tall.
# Base y=288, +80 offset = 368px.
# -------------------------------------------------
"$FBINK" -q -b -m -g "file=$IMAGE,w=580,h=0,y=$((288 + V_OFFSET))"

# -------------------------------------------------
# ONE SCREEN REFRESH
# -------------------------------------------------
"$FBINK" -q -s
