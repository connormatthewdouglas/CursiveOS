# CursiveOS Hub API (MVP)

Minimal backend for Hub tabs using Supabase SQL API.

**Status note (2026-05-25):** This API is legacy v3.1-era MVP scaffolding and is not an implementation of the authoritative v3.3 economics specification or the Phase 0 seed bundle path. It still exposes pool/governance-shaped endpoints. Do not treat it as the active payout or fitness interface until it is replaced or migrated.

## Setup
1) cd hub-api
2) cp .env.example .env
3) Fill SUPABASE_ACCESS_TOKEN
4) npm install
5) npm start

## Endpoints
- GET /health
- GET /hub/cycle/latest
- GET /hub/machines
- GET /hub/rewards/ledger?limit=50
- GET /hub/contributions
- GET /hub/governance/appeals
- POST /hub/machines/:machineId/plan   body: {"plan":"fast"|"stable"}

## Notes
- This is MVP scaffolding for internal pilot.
- Next step: add auth and account scoping (only show the operator's own data by default).
