# hub-api is frozen

**Status:** frozen v3.1 scaffolding. Not the economics interface.

Do not add pool, governance, validator, Babylon, staking, or yield endpoints.
Do not treat `/hub/rewards/ledger` as Layer 5 v3.3.

The operator-facing surface is:

1. Live CursiveRoot (measurement queue, trust spine, fleet)
2. The OS.0 operator console (`operator/` in this repo)
3. Layer 5 v3.3 engine (`operator/engine/economics.ts`, `tools/layer5_economics_v33.py`)

Passwordless `/hub/accounts/create` and `/hub/session/create` stay disabled.
CORS stays deny-by-default.

This freeze is load-bearing: the seven-tab hub rebuild is what nearly killed the project.
