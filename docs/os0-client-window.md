# OS.0 Client Window

**Status:** ACTIVE (2026-09-11)
**Files:** `tools/cursive_panel.py`, `tools/cursive_desk.py`, `tools/cursive_status.py`, `tools/cursive-stop.sh`

**CursiveRoot** and the tester PC are two different jobs. This window is the client-side one.

## What it is

A small GTK window on the Linux Desktop:

- **FREE / BUSY** — this machine only
- **Now / next** — which screen is running, which leftover or ledger ticket is lined up
- **Phase bar** — parent then candidate: rest, memory, network, cold-start, sustained. Honest steps, not a fake percent
- **Update from GitHub** — `git pull --ff-only` when idle and the tree is clean
- **Stop** — kill the screen, undo presets, give the computer back
- **Popup** (`notify-send`) when a measurement starts

Occupancy is written to `.cursiveos/closed-loop/panel.json` and **never** to CursiveRoot.

## What it is not

- Not the website. A button on CursiveRoot cannot stop this PC.
- Not a remote shell. GitHub / the dashboard never SSH in.
- Not an ISO. First install is still the one-paste; this window is what you use after that.

## Who owns the facts

The **contributor daemon** owns busy/idle/stop/undo and writes live progress while `seed_organism.py screen-variant` runs.

The window is a face on those facts. Gtk does not live inside the daemon, so a headless box can still measure.

## First install vs later

1. First time: paste from the README / Join page.
2. After that: Desktop icon **CursiveOS** → Update from GitHub.
3. Do not paste the bootstrap command every session.

## Safety

- Update refuses to run while BUSY, and refuses if the tree is dirty.
- Stop always attempts `--undo` on v0.12 and any `v0.13-*` leftover presets.
- Fail-closed enqueue is unchanged: this window does not insert `measurement_requests`.
