#!/usr/bin/env bash
# ─── Layer 5 Multi-User Simulation ───────────────────────────────────────────
# 3-cycle pilot with 3 contributors and 2 validators, all new accounts.
# Usage: bash tools/sim_multiuser.sh

set -euo pipefail
BASE="http://localhost:8787"
H="Content-Type: application/json"
PYTHON=${PYTHON:-python}
RUN_ID=${RUN_ID:-$(date +%s)}
ADMIN_USERNAME=${ADMIN_USERNAME:-}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-}

ok()   { echo "  ✓ $1"; }
step() { echo ""; echo "══ $1 ══"; }
fail() { echo "  ✗ FAIL: $1"; exit 1; }

jq_val() {
  local json="$1" key="$2"
  echo "$json" | "$PYTHON" -c "import sys,json; d=json.load(sys.stdin); print(d.get('$key',''))" 2>/dev/null
}

check_ok() {
  local resp="$1" label="$2"
  local v
  v=$(echo "$resp" | "$PYTHON" -c "import sys,json; d=json.load(sys.stdin); print(d.get('ok','false'))" 2>/dev/null)
  if [ "$v" = "False" ] || [ "$v" = "false" ] || [ -z "$v" ]; then
    echo "  ✗ $label FAILED: $resp"
    exit 1
  fi
}

# ─── Phase 0: create accounts ────────────────────────────────────────────────
step "Phase 0: Creating accounts"

if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
  fail "set ADMIN_USERNAME and ADMIN_PASSWORD for an existing admin; passwordless /hub/session/create is intentionally disabled by default"
fi

admin_login=$(curl -sf -X POST "$BASE/hub/auth/login" -H "$H" -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}")
check_ok "$admin_login" "admin login"
ADMIN_TOK=$(jq_val "$admin_login" session_token)
ok "admin session opened"

make_account() {
  local role="$1" label="$2"
  local username="${label}-${RUN_ID}"
  local password="CursiveOS-${label}-${RUN_ID}!"
  local resp
  resp=$(curl -sf -X POST "$BASE/hub/auth/register" -H "$H" -d "{\"username\":\"$username\",\"password\":\"$password\",\"role\":\"$role\"}")
  check_ok "$resp" "create $label"
  echo "$(jq_val "$resp" account_id):$(jq_val "$resp" session_token)"
}

ALICE_PAIR=$(make_account contributor alice)
BOB_PAIR=$(make_account contributor bob)
CAROL_PAIR=$(make_account contributor carol)
VAL1_PAIR=$(make_account validator val1)
VAL2_PAIR=$(make_account validator val2)

ALICE=${ALICE_PAIR%%:*}; ALICE_TOK=${ALICE_PAIR#*:}
BOB=${BOB_PAIR%%:*}; BOB_TOK=${BOB_PAIR#*:}
CAROL=${CAROL_PAIR%%:*}; CAROL_TOK=${CAROL_PAIR#*:}
VAL1=${VAL1_PAIR%%:*}; VAL1_TOK=${VAL1_PAIR#*:}
VAL2=${VAL2_PAIR%%:*}; VAL2_TOK=${VAL2_PAIR#*:}

ok "alice = $ALICE"
ok "bob   = $BOB"
ok "carol = $CAROL"
ok "val1  = $VAL1"
ok "val2  = $VAL2"

# Account registration returns the session tokens; no passwordless session bypass is used.
ok "all contributor/validator sessions opened"

# ─── Phase 0c: dispense test credits ─────────────────────────────────────────
step "Phase 0c: Dispensing test credits (admin)"

dispense() {
  local to="$1" usd="$2"
  local resp
  resp=$(curl -sf -X POST "$BASE/hub/admin/dispense" \
    -H "$H" -H "x-session-token: $ADMIN_TOK" \
    -d "{\"account_id\":\"$to\",\"amount_usd\":$usd,\"note\":\"sim seed\"}")
  check_ok "$resp" "dispense \$$usd → $to"
  ok "dispensed \$$usd → ${to:0:8}..."
}

dispense "$ALICE" 20
dispense "$BOB"   20
dispense "$CAROL" 20

# ─── Helpers ─────────────────────────────────────────────────────────────────

submit_contribution() {
  local tok="$1" hash="$2" title="$3"
  local resp
  resp=$(curl -sf -X POST "$BASE/hub/contributions" \
    -H "$H" -H "x-session-token: $tok" \
    -d "{\"submission_hash\":\"$hash\",\"title\":\"$title\"}")
  check_ok "$resp" "submit $title"
  jq_val "$resp" submission_id
}

cast_votes() {
  local tok="$1" cycle_id="$2" allocs_json="$3"
  local resp
  resp=$(curl -sf -X POST "$BASE/hub/contributions/votes" \
    -H "$H" -H "x-session-token: $tok" \
    -d "{\"cycle_id\":$cycle_id,\"allocations\":$allocs_json}")
  check_ok "$resp" "vote in cycle $cycle_id"
  echo "$resp"
}

# ─── Run cycles ───────────────────────────────────────────────────────────────

run_cycle() {
  local N="$1" FAST_USERS="$2"
  step "Cycle $N (fast_users=$FAST_USERS)"

  # Open cycle
  OPEN=$(curl -sf -X POST "$BASE/hub/cycle/run-v31" \
    -H "$H" -H "x-session-token: $ADMIN_TOK" \
    -d "{\"cycle_id\":$N,\"fast_user_count\":$FAST_USERS}")
  check_ok "$OPEN" "open cycle $N"
  ok "cycle $N opened  pot=$(jq_val "$OPEN" payout_pot_btc) BTC  principal=$(jq_val "$OPEN" pool_principal_btc) BTC"

  # Generate unique hashes per cycle per contributor
  TS=$(date +%s)

  # Alice submits 2 contributions
  SA1=$(submit_contribution "$ALICE_TOK" "alice-c${N}a-$TS" "Alice work $N-A")
  SA2=$(submit_contribution "$ALICE_TOK" "alice-c${N}b-$TS" "Alice work $N-B")
  ok "alice: $SA1  $SA2"

  # Bob submits 1
  SB=$(submit_contribution "$BOB_TOK" "bob-c${N}-$TS" "Bob work $N")
  ok "bob:   $SB"

  # Carol submits 1
  SC=$(submit_contribution "$CAROL_TOK" "carol-c${N}-$TS" "Carol work $N")
  ok "carol: $SC"

  # Validator 1: favors alice
  cast_votes "$VAL1_TOK" "$N" \
    "[{\"submission_id\":\"$SA1\",\"points\":35},{\"submission_id\":\"$SA2\",\"points\":25},{\"submission_id\":\"$SB\",\"points\":25},{\"submission_id\":\"$SC\",\"points\":15}]" \
    > /dev/null
  ok "val1 voted"

  # Validator 2: spread more evenly, favors bob
  cast_votes "$VAL2_TOK" "$N" \
    "[{\"submission_id\":\"$SA1\",\"points\":20},{\"submission_id\":\"$SA2\",\"points\":15},{\"submission_id\":\"$SB\",\"points\":40},{\"submission_id\":\"$SC\",\"points\":25}]" \
    > /dev/null
  ok "val2 voted"

  # Close cycle
  CLOSE=$(curl -sf -X POST "$BASE/hub/cycle/close-v31" \
    -H "$H" -H "x-session-token: $ADMIN_TOK" \
    -d "{\"cycle_id\":$N}")
  check_ok "$CLOSE" "close cycle $N"
  ok "cycle $N closed"

  echo ""
  echo "  Payout breakdown:"
  echo "$CLOSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'    total_cycle_votes : {d.get(\"total_cycle_votes\",\"?\")}')
print(f'    payout_pot_btc    : {d.get(\"payout_pot_btc\",\"?\")}')
print(f'    cycle_yield_btc   : {d.get(\"cycle_yield_btc\",\"?\")}')
for p in d.get('payouts', []):
  acct = p.get('account_id','?')[:8]
  title = p.get('submission_id','?')[:16]
  pct  = p.get('vote_share_pct','?')
  pay  = p.get('payout_btc','0')
  roy  = p.get('royalty_btc','0')
  ltv  = p.get('lifetime_votes_after','?')
  print(f'    {acct}... sub={title}... share={pct}%  payout={pay}  royalty={roy}  ltv={ltv}')
" 2>/dev/null || echo "    (could not parse payouts)"
}

# Check if there are existing cycles 1-3 and handle conflict
for N in 1 2 3; do
  CHECK=$(curl -sf "$BASE/hub/pool/cycles" -H "x-session-token: $ADMIN_TOK" 2>/dev/null || echo '{}')
  EXISTING=$(echo "$CHECK" | python3 -c "import sys,json; d=json.load(sys.stdin); ids=[r['cycle_id'] for r in d.get('data',[])]; print($N in ids)" 2>/dev/null || echo "False")
  if [ "$EXISTING" = "True" ]; then
    echo ""
    echo "  ℹ  Cycle $N already exists in DB — skipping (prior run data preserved)"
  fi
done

# Use timestamp-based cycle IDs so re-runs don't collide with prior sim data
BASE_CYCLE=$(( ($(date +%s) / 10) % 900000 + 100000 ))
run_cycle $((BASE_CYCLE))   5
run_cycle $((BASE_CYCLE+1)) 8
run_cycle $((BASE_CYCLE+2)) 12

# ─── Final report ─────────────────────────────────────────────────────────────
step "Final: Lifetime vote ledger"
curl -sf "$BASE/hub/contributors/lifetime-votes" \
  -H "x-session-token: $ADMIN_TOK" | python3 -c "
import sys, json
d = json.load(sys.stdin)
rows = sorted(d.get('data', []), key=lambda r: -float(r.get('lifetime_votes',0)))
print(f'  {'Account':<36}  {'LTV':>8}  {'Share':>7}  {'Payout BTC':>14}  {'Royalty BTC':>14}')
for row in rows:
  acct  = row.get('account_id','?')
  votes = row.get('lifetime_votes', 0)
  share = row.get('lifetime_share_pct','?')
  pay   = row.get('total_payout_btc', 0)
  roy   = row.get('total_royalty_btc', 0)
  print(f'  {acct:<36}  {float(votes):>8.2f}  {share:>6}%  {float(pay):>14.8f}  {float(roy):>14.8f}')
" 2>/dev/null

step "Final: Pool state"
curl -sf "$BASE/hub/pool/state" -H "x-session-token: $ADMIN_TOK" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  principal_btc : {d.get(\"pool_principal_btc\",\"?\")}')
print(f'  total_cycles  : {d.get(\"total_cycles\",\"?\")}')
print(f'  cycle_status  : {d.get(\"cycle_status\",\"?\")}')
" 2>/dev/null

step "Final: Contributor balances"
for pair in "alice:$ALICE:$ALICE_TOK" "bob:$BOB:$BOB_TOK" "carol:$CAROL:$CAROL_TOK"; do
  name="${pair%%:*}"; rest="${pair#*:}"; acct="${rest%%:*}"; tok="${rest#*:}"
  bal=$(curl -sf "$BASE/hub/rewards/my-balance" \
    -H "x-session-token: $tok" -H "x-account-id: $acct" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('balance_btc','?'))" 2>/dev/null)
  ok "$name  balance: $bal BTC"
done

echo ""
echo "══ Simulation complete ══"
