#!/usr/bin/env bash
# tao-forge-status.sh
# Pull and display all run data from the tao-forge database.
# Usage: ./tao-forge-status.sh

SUPABASE_URL="https://iovvktpuoinmjdgfxgvm.supabase.co"
SUPABASE_KEY="sb_publishable_4WefsfMl0sNNo9O2c_lxnA_q2VQ01jn"
H=(-H "apikey: $SUPABASE_KEY" -H "Authorization: Bearer $SUPABASE_KEY")

echo ""
echo "tao-forge database status — $(date +%Y-%m-%d)"
echo "======================================================"

python3 - <<PYEOF
import json, subprocess

url = "$SUPABASE_URL"
key = "$SUPABASE_KEY"
headers = ["-H", f"apikey: {key}", "-H", f"Authorization: Bearer {key}"]

def fetch(endpoint):
    r = subprocess.run(["curl", "-s", f"{url}/rest/v1/{endpoint}"] + headers, capture_output=True, text=True)
    return json.loads(r.stdout)

machines = fetch("machines?order=created_at.asc")
runs = fetch("runs?order=created_at.desc")

print(f"\nMachines in database: {len(machines)}")
print(f"Total runs logged:    {len(runs)}\n")

for m in machines:
    m_runs = [r for r in runs if r["machine_id"] == m["machine_id"]]
    print(f"  ── {m['cpu']} | {m['gpu']}")
    print(f"     ID: {m['machine_id']}")
    print(f"     Runs: {len(m_runs)}")
    if m_runs:
        latest = m_runs[0]
        net = latest.get("network_delta_pct")
        cold = latest.get("coldstart_delta_pct")
        pwr = latest.get("power_delta_w")
        print(f"     Latest ({latest['run_date']} | preset {latest['preset_version']}):")
        print(f"       Network:    {f'+{net:.1f}%' if net else 'N/A'}")
        print(f"       Cold-start: {f'{cold:.2f}%' if cold else 'N/A'}")
        print(f"       Power:      {f'+{pwr:.1f}W' if pwr else 'N/A'}")
    print()
PYEOF
