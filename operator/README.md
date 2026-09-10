# CursiveRoot operator console

The nervous system for OS.0: sense the measurement loop, route work, refuse unsafe money.

This directory is the portable source of truth for the engines that the live operator
console runs. The interactive UI lives in the Grok App Builder preview; the engines
here are what CursiveRoot origin should host next.

## Engines (`operator/engine/`)

| File | Job |
|---|---|
| `identity.ts` | Fingerprint v2, alias collapse, hardware/wallet independence |
| `queue.ts` | Fail-closed enqueue (Linux, parent ≠ candidate, payout false) |
| `trust.ts` | Gate evaluation. `payout_eligible` is always false |
| `economics.ts` | v3.3 cycle close: metabolic split, lossless sats, 2-year claims |
| `rails.ts` | Switchable rails, pause, cap, bech32, mainnet hard-gate |
| `recompute.ts` | Origin-side hash of payloads. Missing payload fails closed |
| `propose.ts` | QD-default proposer. pagecluster/vfs cousins refused |
| `qd.ts` | Live seed_bundles MAP-Elites archive + empty-neighbor elites |
| `origin.ts` | GET-only CursiveRoot adapter. Writes never leave this console |
| `policy.ts` | Identity-gated writes. `USING(true)` denied |
| `loop.ts` | Selection-loop watchdog + revival playbook |
| `ledger.ts` | `l5_cycles` / lifetime / tester rebates (local rehearsal) |
| `psbt.ts` | Unsigned payment intent. Signing key never present |
| `hub.ts` | Freeze v3.1 pool/governance shapes |

Tests: `*.test.ts` run with `node --experimental-strip-types --test`.

## What this is not

- Not a write path to live CursiveRoot
- Not a Bitcoin wallet
- Not a replacement for the contributor daemon or the harness
- Not permission to apply `operator/sql/20260910_l5_v33_ledger_DRAFT.sql`

## Next on origin

1. Host `recomputeBundle` against immutable artifacts
2. Key rotation/revocation policy on `os0_identity_keys`
3. Enforce `independentConfirmations` before selection-truth
4. Identity-gated RLS on `machine_capabilities` and `measurement_jobs`
5. Wire `qd_organism.py` to live fitness, then signed auto-enqueue
   (`operator/engine/qd.ts` already reads live `seed_bundles` in the console)
