# TAO-OS — Claude Orientation File

## Project Purpose
AI-optimized Linux for Bittensor miners, validators, and beyond.
The loop: make miners faster → earn more TAO → improve the OS → repeat.
End goal: a one-click pre-tuned OS image that is auto-updated by AI.

Primary subnet target: **SN64 Chutes** ("the Linux of AI").
Hardware philosophy: break NVIDIA dependency — develop and test on AMD CPU + Intel Arc GPU.

## Developer Hardware (test rig)
- CPU: AMD Ryzen 7 5700 (16 logical CPUs)
- GPU: Intel Arc A750 (DG2)
- RAM: 15GB
- OS: Linux Mint 22.3
- Kernel: 6.17.0-19-generic
- Default governor: powersave (performance when presets applied)

## Two Separate Tools — Keep Them Separate

### 1. Benchmark Tool (`benchmark-vX.X-vanilla.sh`)
**Purpose:** Pure measurement. No tweaks. Neutral, repeatable yardstick.
- Simulates Bittensor mining load: CPU stress (sysbench, all threads, 300s) + network flood (ping -f)
- 3 runs × 5 min, averages events/sec
- Logs CPU temp during runs, ping latency after each run
- Saves baseline to `last_baseline.txt`, shows % delta vs previous run
- Writes timestamped logs to `~/TAO-OS/logs/`

**Current version:** v0.7 (latest file)
**Known regression in v0.7:** Switched from custom progress loop to sysbench `--report-interval=30`,
but captures all output into a variable — progress is never shown live, CPU temp monitoring is gone,
and `tee -a "$LOG_FILE"` was removed so logs are incomplete. Needs to be fixed.

**v0.6 had the right behavior:** live `Elapsed: Xs / 300s | Temp: XX.X°C` every 30s, tee to log throughout.
**v0.5 had a race condition** in its progress subshell — avoid that pattern.

### 2. Preset Applicator (`tao-os-presets-vX.X.sh`)
**Purpose:** Apply temporary mining-tuned OS settings. Fully reversible (`--undo` or reboot).
- `--apply-temp`: applies tweaks, backs up original state
- `--undo`: reverts to saved state

**Current version:** v0.2 tweaks:
- CPU governor → performance (via cpupower)
- Energy performance preference → performance (AMD/Intel)
- Net buffers: rmem_max + wmem_max → 16MB (for Bittensor gossip/chain traffic)

**This is where most active development happens.** Goal: keep stacking safe, measurable tweaks
and validate each one with the benchmark tool (run benchmark before and after preset).

## Workflow
1. Run benchmark (vanilla) → get baseline
2. Apply preset → run benchmark again → measure delta
3. If delta is positive and stable → keep the tweak, increment preset version
4. Repeat, stacking more tweaks

## Version History Summary
- benchmark-v0.1/v0.2: early versions with tweaks baked in (don't use as measurement baseline)
- benchmark-v0.4: first clean mining sim (no live progress, no temp)
- benchmark-v0.5: added live progress + temp (but had subshell race condition)
- benchmark-v0.6: vanilla (no tweaks), reliable progress + AMD Tctl temp detection — best reference
- benchmark-v0.7: broke progress/temp/logging by capturing sysbench output to variable
- tao-os-presets-v0.1: governor + energy bias
- tao-os-presets-v0.2: added net buffers (rmem/wmem_max = 16MB)

## Roadmap (from README)
- v0.3 → Intel Arc optimizations (XPU freq/power, OpenVINO/SYCL, local LLM benchmarks)
- v0.4 → AI-generated tweak suggestions (Grok/Claude auto-test configs)
- v1.0 → One-click pre-tuned ISO + auto-updates for miners/validators
- v2.0+ → Full self-improving subnet (emissions for best tweaks, multi-vendor validation)

## Rules / Design Principles
- Benchmark tool: NEVER apply tweaks inside it. Vanilla only.
- Preset tool: ALL tweaks must be temporary by default (reset on reboot or --undo).
- Always back up original state before applying presets.
- Always validate a new tweak with before/after benchmark runs.
- Keep the two tools versioned separately.
- Target AMD CPU + Intel Arc first — NVIDIA is not the primary focus.
- Keep scripts simple, readable bash — no complex dependencies.
