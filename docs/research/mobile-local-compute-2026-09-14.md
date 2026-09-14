# Mobile local compute \u2014 research note (2026-09-14)

Living research. Not selection-truth. Policy lives in `docs/specs/platform-substrates.md`.

Question: useful models will run on phones and tablets; some people will host them locally. Can CursiveOS be one OS on PC and mobile?

Answer used: **one organism, several substrates.** Not one ISO. Desktop genome stays Linux-x86_64 until a mobile parent exists.

## What changed since \u201cmobile is a dead end\u201d

The dead-end was correct about *control*: you cannot honestly A/B v0.12 on a stock Pixel the way Stardust A/Bs sysctl.

The dead-end is wrong about *workload existence*:

- Flagship Snapdragon 8 Gen 3 / 8 Elite class devices run 0.6B\u20133B (sometimes larger, quantized) locally via llama.cpp, MLC, ExecuTorch+QNN, and vendor GENIE stacks.
- PocketPal / Maid / Termux+Ollama / MLC Chat are already consumer paths. Most of those never touch the Hexagon NPU; \u201con-device\u201d often means CPU or Vulkan.
- ExecuTorch documents Llama 3.2 3B Instruct on Qualcomm AI Engine Direct with quantization, KV-cache compression, and model sharding.
- Community recipes report Qwen3-0.6B on Snapdragon 8 Gen 1 Hexagon v69 on the order of ~30 decode tok/s / ~100 ms TTFT in one published ExecuTorch+QNN setup \u2014 useful, not desktop-class, and model-size scoped.
- Budget Android (4 GB class) can host ~0.5B quants and still thermally punish a long session.
- postmarketOS 26.06 advertises 254 devices in testing and a small community-tier set (Fairphone 4, PinePhone, Librem 5, some Pixels). That is GNU/Linux on a phone, not Android-with-a-theme.
- Google\u2019s Android Virtualization Framework Debian VM on Pixel is a real apt userspace inside Android. Still not the host kernel CursiveOS tunes today.
- Ubuntu Touch / Halium ports (example: Nothing Phone 1 writeups) get CPU llama.cpp; Hexagon is usually unavailable without the vendor SDK.

iOS on-device genAI is real and closed. No CursiveOS daemon path.

## Measurement facts that break a naive port of harness v1.4.x

Desktop sustained tok/s + idle watts assume a tower that can hold a clock. Phones do not.

From \u201cIs Your NPU Ready for LLMs?\u201d (Cai et al., arXiv 2607.05475, devices SM8650/SM8750/SM8850):

- Phase split: NPUs win compute-bound **prefill**; CPUs can win memory-bound **decode**. Example cited in the HTML: Qwen2.5-1.5B on OnePlus 15, GENIE NPU ~23 tok/s decode vs llama.cpp CPU ~55.7 tok/s; NPU decode energy per token higher in that comparison.
- Same vendor backend, different frameworks: large prefill gaps (GENIE vs llama.cpp prefill cited ~1463 vs ~115 tok/s on that setup).
- Scheduling waste: thread layout, NPU sleep, CPU poll intervals \u2014 papers claim tens of percent energy left on the table; host CPU poll can be a large fraction of \u201cNPU\u201d energy.
- Protocol: they cool below 28 \u00b0C and kill radios before runs. CursiveOS must record whether a run was thermally primed or it will lie.

From sustained-load reporting on S24 Ultra / MLC-LLM (arXiv 2603.23640 and operator writeups):

- Peak first-30-second tok/s is the number vendors like. Sustained is the number operators feel.
- One S24 Ultra MLC-LLM GPU series: ~10 tok/s for a handful of iterations, then OS thermal governor floored GPU ~629\u2013680 MHz \u2192 231 MHz around 78 \u00b0C and ended representative inference.
- Adaptive thermal batch/thread control is claimed to hold a much larger fraction of peak at 30 minutes than a naive loop (operator blog numbers, not CursiveRoot).

Samsung\u2019s on-device genAI note (2026-09): battery + thermal envelope is a first-class limit; low-bit quant is how Llama-class models fit Exynos at all.

Security: Cyera / DEF CON 34 (2026) \u2014 llama.cpp Android JNI UAF (CVE-2026-70640 class). Local runtime is an attack surface. Weight-supply-chain issues already flagged in CursiveResearch Ch.16.

## Control-plane facts

- Sysctl on Android exists and is a root toy (SysctlGUI). Persistence across boot is a Magisk/KernelSU module problem, not `--undo`.
- SELinux + GPU ioctl hardening (Android 2025\u20132026) restricts profiling IOCTLs to shell/debuggable. A measurement app on stock may be blind to the counters a desktop harness expects.
- PowerHAL / Performance Hint API is the vendor-shaped knob (hint sessions, thermal status). That is closer to a mobile \u201cpreset\u201d than `vm.swappiness`.
- LMK will evict the model. Desktop zram wins do not predict that behavior.

## What we will not conclude from this note

- That CursiveOS should become GrapheneOS or Lineage.
- That Hexagon tok/s will ever be compared to Stardust 141.5 tok/s on Arc without a platform tag.
- That BBR/zram leftovers should be queued on a phone.
- That an APK is next sprint work.

## Sources (retrieved 2026-09-14)

- https://arxiv.org/html/2607.05475v1
- https://arxiv.org/html/2603.23640v1
- https://docs.pytorch.org/executorch/main/llm/build-run-llama3-qualcomm-ai-engine-direct-backend.html
- https://github.com/avisre/snapdragon-npu-llm
- https://m1k.tech/2026/07/local-llm-android-privacy-npu/
- https://mvpfactory.io/blog/thermal-throttling-and-sustained-on-device-llm-inference-on-android-cpu
- https://semiconductor.samsung.com/news-events/tech-blog/beyond-the-cloud-a-deep-dive-into-on-device-generative-ai/
- https://www.cyera.com/research/breaking-local-ai-runtimes-10-vulnerabilities-in-the-engine-behind-your-open-source-models
- https://github.com/Lennoard/SysctlGUI
- https://source.android.com/docs/security/features/selinux/compatibility
- https://www.techtimes.com/articles/318893/20260623/linux-phone-os-postmarketos-ships-2606-gnome-50-plymouth-254-devices.htm
- https://www.xda-developers.com/i-turned-my-old-phone-into-a-local-llm-server/
- https://www.makeuseof.com/i-turned-my-android-phone-into-a-real-linux-machine-with-debian/
