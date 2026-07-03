# CursiveOS Hub API (MVP)

Minimal backend for Hub tabs using Supabase SQL API.

**Status note (2026-07-03):** This API is legacy v3.1-era MVP scaffolding and is not an implementation of the authoritative v3.3 economics specification or the OS.0/CursiveRoot measurement queue path. It still exposes pool/governance-shaped endpoints. Do not treat it as the active payout or fitness interface until it is replaced or migrated.

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
- Auth/account scoping is password-session based. Public bootstrap no longer enumerates account UUIDs; authenticated non-admin users see only themselves; admins see the pilot account list.
- Passwordless legacy endpoints (`/hub/accounts/create`, `/hub/session/create`) are disabled by default. Use `/hub/auth/register` and `/hub/auth/login`. Only set `HUB_ENABLE_LEGACY_PASSWORDLESS_ACCOUNTS=true` for isolated throwaway simulations.
- CORS is deny-by-default outside localhost unless `HUB_CORS_ORIGINS` explicitly includes the origin. Keep `SUPABASE_ACCESS_TOKEN` server-only and never expose it to `hub/` or `dashboard/`.
