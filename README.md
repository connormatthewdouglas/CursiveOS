# TAO-OS

**AI-optimized Linux for Bittensor miners. One command. Measurable results.**

```bash
git clone https://github.com/connormatthewdouglas/TAO-OS.git
cd TAO-OS
./tao-os-full-test-v1.0.sh
```

Runs all benchmarks, applies presets, shows you exactly what you gain. All changes revert automatically.

---

## Results (test rig: AMD Ryzen 7 5700 · Intel Arc A750)

| Benchmark | Default | TAO-OS Presets | Delta |
|-----------|---------|---------------|-------|
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 169.2 Mbit/s | 384.4 Mbit/s | **+127%** |
| **Cold-start latency** (GPU idle → first inference token) | 1023.6ms | 1001.1ms | **-22ms (-2.19%)** |
| Sustained inference (warm model, steady-state) | 68.75 tok/s | 68.07 tok/s | flat (expected) |

**Network is the headline.** The 212KB default Linux socket buffer is smaller than the bandwidth-delay product on any real WAN link. TAO-OS raises it to 16MB and switches to BBR congestion control — 2.3x faster chain sync, weight delivery, and Bittensor gossip traffic.

**Cold-start latency matters for mining.** Validators query miners unpredictably. Between queries, your GPU idles to 300–600 MHz. TAO-OS pins the Arc A750 to 2000 MHz minimum — 22ms faster on every cold request. At scale this is the difference between making the active set or not.

---

## What it does

TAO-OS applies a set of temporary, safe OS tweaks tuned for Bittensor mining workloads. Every change reverts on reboot or with `--undo`.

**14 tweaks in `tao-os-presets-v0.5.sh`:**

| Tweak | Value | Why |
|-------|-------|-----|
| CPU governor | performance | Full clock speed, no scaling delays |
| Energy perf preference | performance | AMD/Intel power hint to hardware |
| Net buffers (rmem/wmem_max) | 16MB | Bittensor gossip + chain traffic |
| TCP congestion control | BBR + fq | Better sustained throughput on WAN |
| TCP slow start after idle | disabled | Throughput doesn't drop after mining pauses |
| Scheduler autogroup | disabled | Desktop grouping hurts server workloads |
| vm.swappiness | 10 | Avoid swap under sustained mining load |
| NMI watchdog | disabled | Reduces interrupt overhead |
| GPU SLPC efficiency hints | ignored | Arc A750 full performance mode |
| GPU min frequency | 2000 MHz | Prevents drop to 300 MHz between requests |
| GPU boost frequency | 2400 MHz | Hardware max |
| CPU C2 idle state | disabled | Eliminates 18μs wakeup latency |
| CPU C3 idle state | disabled | Eliminates 350μs wakeup latency |
| Transparent Huge Pages | always | Better for large ML model allocations |

Apply manually:
```bash
./tao-os-presets-v0.5.sh --apply-temp   # apply
./tao-os-presets-v0.5.sh --undo         # revert
```

---

## Intel Arc A750 — AI Inference Setup

Getting Arc running AI inference is normally a 6-step process most people never finish. One script:

```bash
./setup-intel-arc.sh
```

Installs Intel compute-runtime (OpenCL 3.0), Level Zero, and configures Ollama's Vulkan backend for Arc. After running, your A750 does inference at ~69 tok/s on TinyLlama.

**Vulkan backend note:** Stable for 1B models. At 3B+, ollama 0.18.1 has a precision bug on Arc — garbled output or crashes. Intel SYCL backend is the fix (in roadmap).

---

## Benchmark Tools

Each benchmark is also runnable standalone:

```bash
./benchmark-network-v0.1.sh ./tao-os-presets-v0.5.sh        # TCP throughput, WAN sim
./benchmark-inference-v0.2.sh ./tao-os-presets-v0.5.sh tinyllama  # cold-start latency
./benchmark-inference-v0.1.sh ./tao-os-presets-v0.5.sh tinyllama  # sustained tok/s
./benchmark-v0.9-paired.sh ./tao-os-presets-v0.5.sh          # CPU sysbench (paired)
```

---

## Roadmap

- **Done** → Intel Arc inference stack (one-script setup)
- **Done** → Preset stack v0.5 (14 tweaks, fully reversible)
- **Done** → Network benchmark: +127% confirmed (BBR + 16MB buffers)
- **Done** → Cold-start inference benchmark: -22ms confirmed (GPU freq lock)
- **Done** → Full-test wrapper v1.0 (single command, sudo prompt, auto-revert)
- **Next** → External validation: 3 miners run it, send logs
- **Next** → Intel Arc SYCL backend: stable 7B+ inference
- **v1.0** → One-click pre-tuned ISO + auto-updates for miners/validators
- **v2.0+** → Full self-improving subnet (AI generates + validates tweaks, emissions for best configs)

---

## Why this hardware

Bittensor can't thrive long-term on a single vendor's silicon. TAO-OS is built and tested on **AMD CPU + Intel Arc GPU** — hardware most mining guides ignore. If you're a non-NVIDIA miner, this project is for you.

---

Built for the TAO network. Star the repo if you're a miner, validator, or believe in decentralizing AI compute.
Contributions, test results from other hardware, and feedback welcome.

Made by [@connormatthewdouglas](https://github.com/connormatthewdouglas)
