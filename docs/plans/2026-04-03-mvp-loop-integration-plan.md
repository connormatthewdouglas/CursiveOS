# CursiveOS MVP Loop Integration Plan (Cohesion Reset)

Owner: Copper Sage
Requested by: Connor
Date: 2026-04-03

## Core decision (locked)
Do NOT run external pilot as a Layer 1-3 test.
Run external pilot only when users can see and touch the full MVP loop.

## What we already have (backend pieces)
1) Fast/Stable entitlement logic
2) Credit ledger + pool accounting + reconciliation
3) Validator payout path
4) Contributor settlement path (performance/oracle)
5) Non-delta settlement path (security/driver/reliability)
6) Appeals guardrail
7) Cycle runner orchestration
8) Admin tuning + audit log

## What is missing (user-facing MVP pieces)
A) Operator Hub (single UI)
- download/install entry
- account/wallet identity binding
- machine enrollment + plan status (Fast/Stable)
- cycle clock + next cycle visibility
- reward balance + payout history
- submission status and appeal state
- voting panel (for disputes/governance actions)

B) Operator onboarding path
- one flow from "new user" -> "machine enrolled" -> "first cycle complete"

C) Unified cycle UX
- clear cycle start/end + settlement windows + appeal countdown

## MVP Definition (external-pilot ready)
External pilot can start only when all are true:
1) User can install/download from Hub
2) User can connect identity/wallet in Hub
3) User can see their machine, plan, rewards, and cycle status
4) User can submit/track contribution and view settlement result
5) User can vote/appeal in Hub
6) Cycle executes and updates UI state without manual DB inspection

## Hosting decision (board-approved)
- Selected stack: Balanced stack
- Frontend: Vercel
- Backend API: small VPS (Hetzner/DO class)
- Database: Supabase (current)
- Auth: Supabase Auth now + wallet identity binding in API

## Build order (work backward from user touchpoints)

### Phase 1: MVP Hub skeleton
Goal: one place users can see state
Build:
- simple web app (auth-lite) + read views for:
  - machine status
  - cycle status
  - ledger/reward history
  - current plan

### Phase 2: Write actions in Hub
Goal: users can do key actions
Build:
- set plan Fast/Stable
- enroll machine
- submit contribution metadata
- open appeal
- cast vote

### Phase 3: Cycle visibility + automation panel
Goal: users understand timing and outcomes
Build:
- next cycle countdown
- last cycle result cards
- pending settlement queue + deadlines

### Phase 4: External pilot gate
Goal: test full loop with real users
Build:
- operator invite flow
- support docs + troubleshooting panel
- pilot metrics dashboard

## Immediate execution tasks (next)
1) Define Hub data contract (what tables/views map to each UI panel)
2) Create API endpoints on top of Layer 5 functions
3) Build minimal Hub UI with 5 tabs:
   - Install
   - Machines
   - Rewards
   - Contributions
   - Governance
4) Wire cycle runner outputs to Hub status cards
5) Dry-run full user journey on one account end-to-end

## What Connor should expect now
- We are no longer optimizing isolated backend modules.
- We are integrating into a coherent operator product loop.
- Next milestone is not "another SQL function"; it is "an operator can complete the loop without SQL editor access."
