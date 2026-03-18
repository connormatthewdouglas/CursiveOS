# TAO-OS

**AI-optimized, self-improving Linux for Bittensor miners, validators and beyond.**

The operating system built to close the loop:  
Make miners faster → earn more TAO → improve the OS → repeat forever.

### Why TAO-OS exists

Every Bittensor subnet (especially SN64 Chutes — the “Linux of AI”) runs on plain Ubuntu.  
We’re fixing that. TAO-OS auto-generates, benchmarks, and applies safe configs & tweaks so your rig runs cooler, faster, more stable, and more profitable 24/7.

### Hardware Focus

Developed and tested on **AMD CPU + Intel Arc A750 GPU**.  
This isn't a limitation — it's a deliberate choice. Bittensor is a **decentralized network** that can't thrive long-term if it relies solely on one company's hardware (NVIDIA). TAO-OS aims to unlock efficient mining and inference on diverse silicon — starting with Intel Arc — to make the network truly hardware-agnostic and resilient.  
Non-NVIDIA users: this project is for you too. Let's build the multi-vendor foundation together.

### First benchmarks already live

- v0.1: Safe CPU performance tweaks (AMD governor tested — measurable gains even idle).  
- v0.2: Stacked tweaks + network ping test (AMD energy bias attempted, real before/after data).  
- **benchmark-v0.6-vanilla.sh** (latest)  
  Pure vanilla benchmark – measures mining simulation load (CPU + network) with **no system changes**.  
  Features:  
  - Progress updates every ~30s with CPU temp (auto-detects AMD Tctl/k10temp)  
  - Hardware snapshot (CPU model, cores, RAM, kernel, distro, GPU)  
  - Current governor & energy preference logged  
  - % delta vs last run (saved in last_baseline.txt)  
  - Clean, dated logs in ~/TAO-OS/logs/  

  Run: `./benchmark-v0.6-vanilla.sh`  
  Goal: Neutral, repeatable yardstick for TAO-OS optimizations.

Preset applicator (temporary tweaks) coming next.

### Roadmap

- **v0.1** → Safe CPU/GPU/power tweaks (live today — AMD CPU + Intel Arc A750 tested)  
- **v0.2** → Network stability tests + AMD-specific attempts (live — energy bias skipped on some chips, but gains visible)  
- **v0.3** → Intel Arc optimizations (XPU frequency/power limits, OpenVINO/SYCL inference tweaks, one-click local LLM benchmarks)  
- **v0.4** → AI-generated tweaks (using free tools like Grok/Claude to suggest + auto-test configs)  
- **v1.0** → One-click pre-tuned ISO + auto-updates for miners/validators  
- **v2.0+** → Full self-improving subnet (emissions for best tweaks, multi-vendor validation) — when traction and funding allow

Built with love for the TAO network.  
Star the repo if you're a miner, validator, or just believe in decentralizing AI compute beyond one vendor.  
Contributions, tests on your hardware, and feedback welcome!

Made by @connormatthewdouglas
