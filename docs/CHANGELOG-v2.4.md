# Changelog - White Paper v2.4

**Date:** 2026-05-25

v2.4 incorporates the first real Phase 0 baseline measurement and narrows the project's performance claims to match the evidence.

## Changed

- Recorded the Vega genesis baseline as characterization, not a mutation acceptance.
- Made the measured `+3.2W` v0.8 idle-power cost explicit.
- Clarified that the network result comes from loopback WAN simulation, not a production internet path.
- Added the parent-versus-candidate and repeat/counterbalance requirement for mutation selection.
- Updated benchmark coverage to include structured multi-sample idle-power telemetry.
- Labeled the benchmark baseline honestly as a canonical untuned reference and added early-exit restoration of captured pre-test network/CPU/GPU controls.

## Implementation Pair

- `presets/cursiveos-presets-v0.9-network-efficient.sh` is the first narrow candidate prompted by the power result.
- `seed-mutation-linux-test.sh` runs a single v0.8-versus-candidate screen; one screen cannot create fitness acceptance or a payout.
