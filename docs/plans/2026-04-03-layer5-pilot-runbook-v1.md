# Layer 5 Pilot Runbook v1 (3-Cycle Controlled Cohort)

Owner: Copper Sage
Operator: Connor
Duration: 3 consecutive cycles
Goal: prove Layer 5 can run without manual firefighting

## Entry criteria
- Migrations applied through:
  - layer5-v1 schema
  - runtime
  - payouts
  - appeals
  - oracle
  - non-delta rubric
  - cycle runner
  - admin controls
- Fast burn path verified (done)
- Oracle and non-delta settlement paths verified (done)

## Cohort for pilot
- 2-5 known operators only (curated)
- At least:
  - 1 Fast consumer machine
  - 1 validator-quality machine
  - 1 contributor submission in scope

## Cycle procedure (repeat for cycle N, N+1, N+2)

### 1) Pre-cycle checks
Run SQL:
1. `select * from v_l5_pool_balance;`
2. `select key, value_numeric from l5_params order by key;`
3. `select count(*) from l5_machine_entitlements where plan='fast';`

Pass if:
- pool balance non-negative
- params in expected ranges
- at least one fast entitlement active

### 2) Intake evidence
- record oracle verdicts for contributor submissions
- record non-delta review for non-performance contributions
- open appeal windows where policy requires

### 3) Close appeal windows for eligible submissions
- only settle submissions whose appeal deadline is passed and no open appeals remain

### 4) Run cycle
Run:
- `select l5_run_cycle(<cycle_id>, <pool_open_if_new>);`

### 5) Post-cycle verification
Run SQL:
1. `select cycle_id,pool_open,inflow_total,outflow_total,burn_total,pool_close,status from l5_pool_cycles where cycle_id=<cycle_id>;`
2. `select event_type,bucket,amount,idempotency_key from l5_credit_ledger where cycle_id=<cycle_id> order by event_time desc;`
3. `select * from v_l5_cycle_reconciliation where cycle_id=<cycle_id>;`

Pass if:
- status = closed
- reconciliation drift = 0
- expected event families appear (fast_burn_inflow and any eligible settlements)

### 6) Nightly review note
Capture:
- cycle id
- settled counts (oracle + nondelta)
- blocked counts and reasons
- any manual intervention required
- one parameter change (if needed) with reason

## Go/No-Go gates after 3 cycles

## GO if all true
1) 3 consecutive cycles closed successfully
2) no reconciliation drift failures
3) no unresolved stuck settlements older than one cycle
4) no severe abuse spike (duplicate-risk or appeal spam)
5) max one minor manual intervention per cycle

## NO-GO if any true
1) cycle close fails twice
2) payout logic requires ad hoc SQL patching
3) recurrent false-positive holds with no resolution path
4) pool-floor breaches under normal pilot load

## Parameter tuning policy during pilot
- Max 1 tuning change per day
- Must use:
  - `l5_set_param(...)` or `l5_set_nondelta_band_value(...)`
- Must include reason and metadata ticket
- Never change formula families during pilot

## Daily operator update format (short)
- Cycle X: closed/failed
- Fast burn inflow total
- Oracle settlements: settled/blocked
- Non-delta settlements: settled/blocked
- Drift: value
- Action tomorrow: one sentence
