# Kindle screensaver project — explained simply

Background questions and answers from building a custom dynamic
lock-screen dashboard on a jailbroken Kindle. Written for a general
audience, not just for people already deep in Kindle hacking.

## Why is resizing and moving things around on screen so complicated?

Three things stack on top of each other:

1. **No visual editor.** You don't drag boxes on a screen and see
   results instantly — you type numbers (a "row", a "scale") into a
   script, copy it to the device, lock the screen, and only then
   find out what it actually looks like. Every other layout tool
   (CSS, PowerPoint, Figma) gives instant visual feedback; this
   workflow gives none until a full round trip completes.
2. **The positioning math isn't obvious.** The tool we used (FBInk,
   explained below) doesn't place things in plain pixels by default
   — it uses a "row" grid where the real pixel position is
   `row × 8 × scale`. That hidden multiplication is easy to get
   wrong, and it was gotten wrong three separate times in this
   project even after the formula was already known and written
   down.
3. **Everything is sequential and relative.** Each element's position
   only makes sense relative to where the element above it ended.
   Move one thing up or down, and every element below it has to be
   recalculated by hand — there's no "auto-layout" that pushes
   later content down automatically the way a webpage or document
   does.

No live preview, plus a non-obvious formula, plus manual cascading
math, equals a lot of arithmetic done blind and checked only by slow
photo round trips.

## Is FBInk the "language" Amazon made for the Kindle?

No. **FBInk is a third-party, independent, open-source tool**,
written by a developer (NiLuJe) for jailbroken e-ink devices —
Amazon didn't make it, doesn't support it, and doesn't ship it.
Amazon's own Kindle software is written internally in C/C++ and Lua,
and has nothing to do with FBInk. FBInk exists purely because
jailbreak hobbyists needed *some* simple way to draw text and images
straight to the screen without going through Amazon's actual reading
app — it's a minimal, low-level tool built to fill that gap, not a
polished product, which is a big part of why working with it feels
rough.

## If Amazon didn't make it, how does the Kindle even run it?

The Kindle doesn't need to specially recognize FBInk. Underneath
Amazon's custom reading interface, the Kindle runs a normal embedded
Linux operating system. FBInk is just an ordinary compiled program
(the same binary format — ELF — as any Linux executable) that runs
on that Linux layer like any other program would. It works by writing
directly into the **framebuffer**: a block of memory that the
display hardware reads to know what to show on screen. That's a
standard Linux concept, not something Kindle-specific — FBInk's
author simply wrote the code that knows how to talk to *this
particular* e-ink panel's hardware quirks correctly. The Kindle
doesn't run FBInk by default; it only runs because jailbreaking gave
us root access to execute arbitrary programs at all.

## Why didn't we just build this in C/C++ and Lua, like Amazon's own software?

Not because Lua/C would have been worse — because there was no
realistic path to use them for this project:

1. **No toolchain available.** Writing and compiling real C or Lua
   for this exact ARM chip needs a cross-compiler setup — a much
   bigger investment than writing a shell script and copying it to
   the device over USB.
2. **Shell + FBInk is the established jailbreak-community path.**
   Homebrew Kindle projects use this combination specifically because
   it needs nothing beyond what jailbreaking already grants: a root
   shell and the ability to run a prebuilt tool.
3. **No access to Amazon's own UI framework.** Amazon's Lua scripts
   drive the internals of their own proprietary reading app. We have
   no documentation or hooks into that system — this project bypasses
   Amazon's UI entirely rather than extending it, so their tooling
   wasn't an option regardless of preference.

## What does "jailbreaking" mean, simply?

**Removing a device's built-in restrictions so you can run your own
software on it, instead of only what the manufacturer allows.**

Normally a Kindle only runs Amazon-approved, digitally signed
software — their reading app and nothing else. Jailbreaking exploits
a bug in that software to gain **root access**: the ability to run
any program as the most powerful user on the system. That turns the
device from "Amazon's sealed appliance" into "a small Linux computer
you fully control."

## Can we build an emulator for this specific Kindle model instead?

In principle yes — there are existing community projects using QEMU
(a general hardware emulator) to run Kindle firmware images without
a physical device, for testing jailbreak exploits safely. In
practice it's a serious undertaking: you'd need the exact firmware
image, the right Linux kernel/driver stack for this specific chip
(the "Rex"/Jaeger platform used in the 10th-gen basic Kindle), and a
way to simulate e-ink display output, which behaves very differently
from a normal screen. For a project this size, it would have been
far more effort than it saved. The lighter-weight alternative we
actually used — `fbink -E`, which reports exact pixel coordinates
without needing to look at the real screen — served a similar
purpose (catch positioning mistakes before testing) at a fraction of
the setup cost.

## Did Amazon intentionally make the Kindle hard to customize, like Apple does with iPhones?

Functionally yes, though the mechanism is different. Apple builds
dedicated anti-jailbreak hardware security (the Secure Enclave,
hardware-backed code signing checks). Amazon's approach is simpler:
the Kindle is a **locked-down retail appliance** — it runs signed
firmware, blocks root access by default, and offers only the
customization Amazon's own settings menu exposes (fonts, a fixed set
of screensaver images, etc.). It's not that Amazon built elaborate
countermeasures specifically to fight hobbyists — the device was
simply never designed to be a general-purpose, user-programmable
computer. It's built for reading and buying books, with no official
scripting layer or app-development kit for end users. That's exactly
why jailbreaking communities exist around it: all of the tools used
in this project (SpiderCat, FBInk, KPM) are reverse-engineered or
improvised workarounds bolted onto a device that was deliberately
sealed as a business decision, not a polished, intended feature set.
