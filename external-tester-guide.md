# CursiveOS — What It Does To Your System

**For anyone running a test on behalf of the CursiveOS project.**

---

## The short version

CursiveOS runs a set of performance tweaks on your Linux machine, measures whether they help, and uploads benchmark results to CursiveRoot. **Every change it makes is temporary.** The script automatically reverts presets when the run completes. Reboot is optional, but will also immediatly revert all presets even mid test.

## What gets uploaded (and why)

At the end of the run, CursiveOS sends benchmark metadata to **CursiveRoot** (the project’s hardware-performance database).

- Uploaded: CPU/GPU model, OS/kernel, benchmark deltas, and a one-way hardware fingerprint hash
- Not uploaded: personal files, documents, photos, browser history, shell history, or private app data

Why: this lets us learn which optimizations work on which hardware and improve recommendations with real evidence instead of guesswork.

---

## What it actually changes

CursiveOS adjusts settings in three areas. All of these are standard Linux tuning knobs — nothing obscure, nothing dangerous.

### Network (path-scoped signal)
CursiveOS measures transport behavior in a controlled loopback WAN simulation (50ms RTT, 0.5% loss) and in real-path checks where available. Current evidence says the large ordinary ≤1GbE lossy-path win is mostly CUBIC→BBR; CursiveOS buffer/qdisc changes add ~0% with BBR held constant on that path. Real internet paths, existing custom tuning, multi-flow fairness, and real workloads can behave differently, which is why each machine is benchmarked rather than promised a result.

### CPU
CursiveOS v0.8 sets your CPU governor to "performance" mode and disables some aggressive idle states (C2, C3, C6). This can reduce response latency, but it can increase idle power. The May 25 Vega seed baseline recorded +3.2W; earlier machines also showed increases. The benchmark now stores repeated power readings so this tradeoff is measured rather than assumed.

### Memory
CursiveOS sets swappiness to 0 (never swap) and enables Transparent Huge Pages. This keeps model weights pinned in RAM and reduces memory allocation overhead during inference. On machines with plenty of RAM this is free performance. On machines with tight RAM it could cause issues — the benchmark will catch this.

---

## What it does NOT change

- Nothing permanent. No config files, no boot parameters, no package installs.
- No changes to your mining software, Ollama, or any application.
- No network configuration beyond the kernel TCP stack.
- No firewall rules, no open ports, no remote access of any kind.
- Intel Arc GPU frequency tweaks only apply if you have an Intel Arc GPU. NVIDIA and AMD GPU settings are untouched.

---

## How to run it

One command, copy-paste from the GitHub README:

```bash
git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "⚠ Local changes detected — skipping update, running your local version."; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh
```

It will:
1. Ask for your sudo password (needed to change kernel settings)
2. Run a baseline benchmark (~3 minutes)
3. Apply the tweaks
4. Run the same benchmark again (~3 minutes)
5. Revert everything
6. Show you the results and upload them automatically

Total time: about 10 minutes.

---

## How to undo manually (if you ever need to)

The wrapper reverts everything automatically when it finishes. If something goes wrong mid-run, just **reboot** — all changes are in-memory only and disappear on restart.

If you want to manually revert without rebooting:
```bash
cd ~/CursiveOS && bash presets/cursiveos-presets-v0.8.sh --undo
```

---

## What gets uploaded

Your benchmark results go to the CursiveOS hardware database (CursiveRoot). This includes:
- Your CPU model and core count
- Your GPU model
- Your kernel version and OS name
- Benchmark deltas (network %, cold-start ms, inference tok/s, power W)
- A hardware fingerprint hash (one-way hash of CPU microcode + GPU VBIOS + kernel — cannot be reversed to identify you)

Nothing else. No IP addresses, no usernames, no file system data.

---

## Questions or problems

Open an issue on GitHub or message the project directly. If something looks wrong with your results, the raw logs are saved in `~/CursiveOS/logs/` — share those and we can diagnose.
