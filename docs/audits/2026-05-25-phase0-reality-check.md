# Phase 0 Reality Check - 2026-05-25

## Confirmed State

- CursiveRoot contains one real seed bundle: `genesis-baseline-v0.8` on machine fingerprint `bda4bd63b3564822`, decision `measured_baseline`.
- The bundle was reconstructed from the operator's terminal summary after CursiveRoot was unavailable during the original upload; the provenance is retained.
- There are no accepted mutation bundles and no payout reports. The fake revenue mechanism remains a simulation only.
- The v3.3 economic architecture is a specification. `hub-api/` is older v3.1-shaped MVP scaffolding and is not the active fitness or payment implementation.
- Phase 0 seed tables currently allow public insert/read for controlled testing. Authentication and server-side validation are required before wider rollout.

## Baseline Evidence

| Metric | Canonical untuned baseline | v0.8 | Reported delta |
| --- | ---: | ---: | ---: |
| Network throughput, loopback WAN simulation | 205.8 Mbit/s | 1266.1 Mbit/s | +515.20% |
| Cold-start latency | 793.7ms | 769.0ms | -3.11% |
| Sustained inference | 154.17 tok/s | 153.61 tok/s | -0.36% |
| Idle power draw | 14.88W | 18.11W | +3.2W |

Interpretation: the network signal is large in the controlled transport test. The v0.8 phenotype is not an unqualified improvement: it incurred higher idle power and slightly worse sustained inference in this run.

## Benchmark Method Review

What is useful now:

- Network benchmark runs five passes under repeatable `tc netem` conditions and logs throughput, retransmits, RTT, and range.
- Cold-start benchmark logs load duration, TTFT, cold total, GPU frequency before request, and range.
- Sustained inference benchmark logs throughput, TTFT, range, and whether Ollama used GPU or CPU.
- The full-test result records hardware fingerprint, kernel, thermal headroom, stability and CursiveRoot submission.

Corrections made in this pass:

- Results now store the actual preset version instead of always labeling runs `v0.8`.
- Idle power is now a median of up to five readings per condition with raw samples in the machine-readable result.
- Seed bundle metrics preserve benchmark context and telemetry from native results.
- Benchmark helpers capture and restore pre-test network/CPU/GPU values on normal completion or early exit; their baseline is explicitly a canonical untuned reference, not necessarily a user's original tuning.
- Candidate screening compares the tuned current parent to the tuned candidate. A canonical-baseline-versus-preset measurement remains characterization only.
- One screen is forced to remain below selection confidence; a positive-looking screen needs repeat and counterbalanced execution before acceptance.

Useful next telemetry additions:

- Promote network retransmits, RTT and min/max values from log-only fields into structured submitted data.
- Promote cold-start load time, TTFT, GPU frequency before call and min/max values into structured submitted data.
- Promote sustained inference TTFT, min/max and processor classification into structured submitted data.
- Add CPU/GPU temperature and frequency snapshots around each measured condition and a longer-duration stability soak for promising candidates.

## Next Experiment

The first candidate is `v0.9-network-efficient`. It retains the TCP/queue/buffer tunings responsible for the network hypothesis and excludes v0.8 CPU C-state, governor, GPU-frequency, scheduler and memory changes. The question is simple: can the controlled network throughput signal persist while idle power moves back toward its pre-test level?

The Linux screen runs parent then candidate as two full sessions. If it is promising, repeat it with reversed order before allowing the sensor loop to consider acceptance.
