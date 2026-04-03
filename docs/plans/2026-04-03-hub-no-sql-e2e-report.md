# Hub No-SQL E2E Report (MVP-5)

Date: 2026-04-03
Runner: Copper Sage
Method: Hub API endpoints only (no direct SQL editor use)

## Goal
Verify a single user can execute core loop actions through product interfaces.

## Actions executed through API
1) GET /health -> ok true
2) POST /hub/contributions -> created submission (auto-selected contributor account)
3) GET /hub/contributions -> submission visible in list
4) POST /hub/governance/appeals -> created open appeal for that submission
5) POST /hub/governance/votes -> vote recorded on appeal
6) GET /hub/governance/appeals -> appeal visible/open with deadline
7) GET /hub/governance/votes -> vote visible

## Concrete IDs from run
- submission_hash: hub-e2e-1775176058
- submission_id: aa669610-7fca-4883-84b2-f104c3535fe1
- appeal_id: b22a0666-d461-40e6-91dd-c9561e57637c
- vote_id: 78eb2dfd-81b5-4d66-9832-ab4ea2ea4aa8

## Result
PASS for MVP-5 baseline: no-SQL user journey works for submission + appeal + vote.

## Remaining gaps before external pilot gate
- Add auth scoping (currently broad-read endpoints)
- Add wallet identity binding UX
- Add cleaner operator-friendly error messages in UI
- Add cycle countdown/next-settlement timing card in Hub
- Add safe role checks on write endpoints (currently minimal)
