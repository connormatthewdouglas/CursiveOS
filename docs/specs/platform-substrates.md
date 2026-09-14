# Platform substrates

Status: research class. Not an implementation spec.
Written: 2026-09-14.
Does not change the canonical parent (v0.12), the Linux selection loop, or Transition 1 (amd64 remix ISO).

## Decision

CursiveOS is one organism and several substrates.

The portable contract is: named hardware class, reversible candidate, paired measurement on channels that bind **on that class**, signed upload to CursiveRoot, accept / reject / honest-null, local control surface, public science surface kept apart.

The non-portable artifact is the distro. `presets/cursiveos-presets-v0.12.sh`, BBR, zram+swappiness, the bash harness, and an amd64 ISO are GNU/Linux workstation facts. They are not a phone OS.

**Do not** ship "CursiveOS Mobile ISO."
**Do not** promote v0.12 (or any desktop parent) from a phone or tablet row.
**Do not** treat iOS / iPadOS as an OS target.
**Do not** let mobile work block the amd64 alpha image.

Related: `docs/research/mobile-local-compute-2026-09-14.md`.

## Why the desktop genome does not move to a pocket

Accepted desktop wins so far are memory-pressure (zram + `vm.swappiness=60`) and, on real links, CUBIC\u2192BBR. Phones already run compressed anonymous memory and an OEM thermal/power HAL that will undo or ignore most of the audited sysctl library on the next wakeup.

Stock Android is a Linux kernel with a vendor kernel, SELinux, Project Treble HALs, and a locked bootloader. Root (Magisk / KernelSU / APatch) plus apps like SysctlGUI can write some sysctls. That is not the same control plane as `./presets/cursiveos-presets-v0.12.sh --undo` on Mint. Vendor thermal governors have been observed to floor GPU frequency mid-inference and abort the run.

iOS does not expose a CursiveOS-shaped daemon, paired kernel A/B, or reversible preset. An inference *app* can exist there later. The organism cannot live there as an OS.

## Substrate table

| Substrate | Selection-truth? | What it is | When |
| --- | --- | --- | --- |
| `linux-x86_64-workstation` | **yes \u2014 only current truth** | Founder fleet, ISO 0.9 target | now |
| `linux-arm64-sbc` | later, own parent | Pi / RK3588 class; same userspace contract | after amd64 alpha exists |
| `linux-arm64-phone` | later, own parent | postmarketOS / Droidian / Ubuntu Touch / AVF Debian VM | invited device only |
| `android-qcom` / `android-tensor` / `android-exynos` | measure-only until N>1 and a mobile parent exists | App \u00b1 Shizuku/root daemon | research client |
| `ios-apple-silicon` | never selection-truth for the Linux genome | Optional measurement app | not scheduled |

A phone reject must not move the desktop parent. Transition 3 already wants preset families by workload. Add a **platform axis** the same way.

## Ledger fields (additive, do not change `machine_id`)

`docs/os0-machine-identity-contract.md` stays the v2 fingerprint. New rows should also carry:

- `platform` \u2014 one of the substrate ids above
- `arch` \u2014 `x86_64` / `aarch64` / \u2026
- `soc` \u2014 example `sm8750`, `intel-alder-lake`, `apple-m-class`
- `accelerator` \u2014 `arc-a750` / `hexagon-v79` / `adreno` / `ane` / `cpu`
- `runtime` \u2014 `ollama+llama.cpp` / `executorch-qnn` / `mlc` / `genie` / \u2026
- `selection_scope` \u2014 remain `linux` for current truth; mobile uploads `observe_only_not_payout_eligible` until a mobile parent is declared

Existing founder rows are `linux-x86_64-workstation`. Backfill is optional and must not rewrite fingerprints.

## Mobile channels (do not reuse the desktop five as-is)

Desktop harness v1.4.x: network gate-only, cold-start, sustained tok/s, idle power, memory-pressure.

On a phone the binding constraints are thermal envelope, battery, LMK, and backend phase split. Peak tok/s from the first 30 seconds is not a channel.

Required if a mobile client ever uploads:

1. Prefill tok/s and decode tok/s, **separate**, with named runtime and backend (CPU / GPU / NPU).
2. Time-to-first-token after a cold start **and** after an app-switch / memory-pressure start.
3. Sustained decode at +5 / +15 / +30 minutes, or until the OS thermal-floors the accelerator. Record skin or SoC temp if readable.
4. tok/J or battery percent per fixed token budget (not only tok/s).
5. LMK / context eviction count.
6. Offload ratio: NPU vs GPU vs CPU (trust the runtime log, not the marketing name of the app).

Literature to treat as measurement warnings, not as CursiveRoot numbers: NPU prefill can dominate CPU while CPU decode wins; framework gaps on the same Hexagon backend have been measured in the multiple-X range; naive sustained Android GPU inference has been observed collapsing under an OS frequency floor. See the research note.

## Allowed mobile shapes (ranked)

1. **Android measurement client (first, if mobile is touched at all).** Opt-in. Fail-closed enqueue. No genome promotion. Measure local inference (llama.cpp / MLC / ExecuTorch-QNN / vendor runtime). Without root: measure and recommend. With Shizuku/root: a *small* knob set only (cpuset, performance hints, a documented sysctl allowlist). Not a ROM.
2. **Linux-on-phone as `linux-arm64-phone`.** Same organism contract as desktop, different parent and sensors. postmarketOS 26.06-class devices, Halium Ubuntu Touch, or Android Virtualization Framework Debian on a Pixel are closer to CursiveOS than stock Android. Market is tiny. Science can be honest.
3. **Custom Android ROM named CursiveOS.** Device-tree work. Unlocks deeper knobs and explodes support surface. Do not start here.
4. **One ISO for Ryzen and Galaxy.** Forbidden. That is how the seven-tab hub dies again.

Natural-language shell is a client. It does not require the phone to be CursiveOS. Daemon stays deterministic; shell stays optional chrome.

## Safety

- `payout_eligible` stays hard-false.
- Anon still cannot INSERT `measurement_requests`.
- Occupancy stays local. A phone \u201cbusy inferencing\u201d bit does not go to CursiveRoot.
- Stop / undo live on the device, not on the website.
- Model weights on-device are an integrity surface (see CursiveResearch security chapter). Hash before load.
- llama.cpp-class Android JNI has had real memory-safety CVEs. A mobile client is a new attack surface, not a skin.

## Sequencing

Now: tag new CursiveRoot writes with `platform` / `soc` / `accelerator` when touching schema. amd64 ISO spike proceeds.

Not now: APK, ROM, iOS app, aarch64 ISO, promoting any v0.13-class knob from a pocket.

Unblock mobile selection-truth only when: an invited device produces paired deltas on the mobile channels above, N is not 1, a mobile parent is named, and desktop v0.12 cannot be moved by those rows.
