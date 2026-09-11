# CursiveOS — Agent Handover (2026-09-11)

Pick-up note for the next agent. Pairs with `docs/action-plan.md`.
This file = live operational state. Supersedes the 2026-09-10 handover.

## TL;DR

- **Canonical parent: v0.12.** Two accepted bundles (v0.9c, v0.11). Genome did not move on 2026-09-11.
- **Two surfaces.** **CursiveRoot** = public science log. Desktop **CursiveOS window** = task manager (update, now/next, phase bar, Stop). Occupancy is **not** published to CursiveRoot.
- **Cycle 7 leftovers (Stardust, 2026-09-11) all rejected:** `v0.13-watermark200`, `v0.13-dirtyexpire1500`, `v0.13-migcost5ms`, `v0.13-notsentlowat16k`.
- **Do not promote** `v0.13-pagecluster0` or `v0.13-vfscache50`.
- **Enqueue fail-closed.** Anon INSERT on `measurement_requests` is denied. Proposer materializes files; it does not put work on the wire.
- **`payout_eligible` hard-false.** Refuse any SQL/draft that turns it on.
- **Stardust Arc un-voided.** Idle 5.50 W package (CV 0.006), GPU 36.94 W (CV 0.002); cold 3703 ms (CV 0.002); sustained 141.5 tok/s (CV 0.005); 23/23 offload on `127.0.0.1:11435`.
- Founder granted Tailscale to this agent for **read-only / agreed ops** on Stardust. Still do not write live CursiveRoot from a cloud sandbox. Still do not remote-Stop a PC from the website.

## Lineage

| Preset | Role | Notes |
| --- | --- | --- |
| v0.9 | Superseded parent | cycle 1 accept (v0.9c) |
| v0.11-zram-swappiness | Accepted candidate | cycle 3 accept 2026-06-26 |
| **v0.12** | **Canonical parent** | still default |
| v0.13-pagecluster0 | Retired | cycle 5 honest null |
| v0.13-vfscache50 | Retired | cycle 6 honest null |
| v0.13-watermark200 | Rejected | cycle 7 leftover |
| v0.13-dirtyexpire1500 | Rejected | cycle 7 leftover |
| v0.13-migcost5ms | Rejected | cycle 7 leftover |
| v0.13-notsentlowat16k | Rejected | cycle 7 leftover |

## What landed 2026-09-10 → 2026-09-11

- Closed loop (`tools/closed_loop.py`): leftover propose → screen → upload → keep only if it wins. Popup + Desktop window for the person at the chair.
- Client window (`tools/cursive_panel.py` + `cursive_desk.py` + `cursive_status.py`): git pull when idle, now/next, harness phase bar, Stop/undo.
- Contributor daemon writes **local** progress while a screen runs. Does not attach `sprint_loop` occupancy to `machine_capabilities`.
- Arc idle + inference probes taken; sustained channel un-voided on founder desktop.
- `llama3.2:3b` pulled on Stardust for proposer tests (disk cap: keep extra models under 30% of then-free space).

## Safety rails (do not relax)

- No live CursiveRoot writes from the Grok / cloud sandbox.
- No auto-enqueue until a signed proposer identity exists.
- No mining pagecluster / vfscache cousins.
- Stop lives on the Desktop, not the public app.
- Ideas on CursiveRoot stay local drafts until a privileged rail exists.

## Next (priority)

1. Signed proposer identity + gated auto-enqueue of leftovers (still simulated, still Linux-only).
2. Ground `organism_proposer.py` in the live QD archive (`tools/qd_organism.py`) instead of static library order.
3. CursiveRoot-owned independent aggregation (the remaining G4 hard piece).
4. Rebase Stardust's two local commits onto `origin/main` (`f8fd956` and docs follow-up) without discarding the Desktop window.
5. First *invited* external Linux tester using the Desktop window — not a public Join blast.

## How to run (Stardust)

```bash
# Desktop window
python3 tools/cursive_panel.py

# Unattended daemon (already the tester path)
OLLAMA_HOST=127.0.0.1:11435 python3 tools/contributor_daemon.py daemon --interval 300

# Closed leftover loop (founder, idle machine only)
python3 tools/closed_loop.py --max-cycles 1
```

Arc inference: `~/ollama-arc/start-arc.sh`, host `127.0.0.1:11435`. Trust `serve.log` offload lines, not `ollama ps`.
