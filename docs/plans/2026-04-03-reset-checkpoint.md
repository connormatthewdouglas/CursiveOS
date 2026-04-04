# Reset Checkpoint — 2026-04-03

Owner: Copper Sage
Repo: https://github.com/connormatthewdouglas/CursiveOS
Branch: main

## Latest pushed checkpoint
- `bb6cb27` — feat(abuse): add account controls + anomaly monitoring
- `27a7d24` — feat(wallet): ship signature verification flow (EIP-191)
- `495f91a` — feat(auth): enforce strict token-only hub access
- `a46a1e3` — auth-lite sessions + rate limits + action trail
- `c22efa4` — MVP-6 identity rail + wallet bind placeholder + white paper update

## Current project state
External pilot status: GO for supervised rail-mode pilot.

Implemented and pushed:
1. Strict session-token auth for `/hub/*` (except bootstrap/create)
2. Role/ownership permission guards
3. Wallet bind flow + EIP-191 challenge/verify flow to `verified`
4. Rate limiting + action audit trail
5. Abuse controls v1: account control modes (`normal`/`slow`/`blocked`)
6. Anomaly stream + admin control/anomaly endpoints
7. Hub UI identity/status updates and wallet verify controls
8. White paper + pilot checklist updates

## Exact next work item when resuming
Next hardening block:
- Network-level abuse controls (IP/ASN/geo-style anomaly signals + temporary lockout policy)
- Then broader public rollout readiness re-evaluation.

## Notes
- There are untracked local binary artifacts in repo root (`libollama*.so`, `ollama`, etc.).
- These were intentionally NOT committed.
- No tracked code changes are pending; all important project work is already pushed.
