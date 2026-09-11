# CursiveOS — What It Does To Your System

**For anyone running a test on behalf of the CursiveOS project.**

---

## The short version

CursiveOS runs a set of performance tweaks on your Linux machine, measures whether they help, and uploads benchmark results to CursiveRoot. **Every change it makes is temporary.** The harness reverts presets when the run completes. The **CursiveOS** window on your Desktop has a Stop button if you need the computer back immediately.

The public website cannot change your computer. Occupancy ("busy / free") stays on your machine.

## What gets uploaded (and why)

- Uploaded: CPU/GPU model, OS/kernel, benchmark deltas, a one-way hardware fingerprint hash
- Not uploaded: personal files, documents, photos, browser history, shell history, whether you are sitting at the chair

Why: the organism learns which optimizations work on which hardware.

---

## What it actually changes

All of these are standard Linux tuning knobs. Canonical parent is **v0.12** (not v0.8).

### Network (path-scoped)
Large ordinary ≤1GbE lossy-path wins are mostly CUBIC→BBR. CursiveOS buffer/qdisc changes add ~0% with BBR held constant on that path. Each machine is measured, not promised a result.

### CPU
Performance governor and some idle-state changes can cut latency and raise idle watts. Idle power is measured and currently **gate-only** in fitness (it can block a bad candidate; it does not pay).

### Memory
v0.12 uses a zram swap device and `vm.swappiness=60`. That is the earned memory-pressure win. It is **not** "never swap."

---

## What it does NOT change

- Nothing permanent. No boot parameters, no package installs required for a screen (Arc inference setup is a separate optional script).
- No changes to your mining software, Ollama, or any application besides kernel/sysctl/zram for the duration of the test.
- No firewall rules, no open ports, no remote access from the website.
- Intel Arc GPU frequency tweaks only if you have Arc; NVIDIA/AMD application settings are untouched.

---

## How to run it

**First time:** paste the one command from the [README](README.md).

**After that:** open **CursiveOS** on the Desktop → Update from GitHub. Do not paste the bootstrap every time.

A full parent-vs-candidate screen is long (parent full-test, then candidate). You will get a popup when it starts. Stop gives the machine back and undoes presets.

Windows / WSL: you can watch results. You cannot join the fleet. The genome is Linux kernel settings.
