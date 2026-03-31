# Sprint Close Checklist (Fleet-Generic)

Use this before marking any performance/debug sprint done.

## 1) Reality check (state discipline)
- Task is only `running` if a real process/sub-agent is active.
- No speculative `running` in dashboard.

## 2) Ingest verification
- Run: `scripts/verify-run-ingest.sh <machine_id> [limit]`
- Confirm latest row has non-null required deltas:
  - `network_delta_pct`
  - `coldstart_delta_pct`
  - `sustained_delta_pct`

## 3) Telemetry capability snapshot
- Run: `scripts/probe-telemetry.sh`
- Capture whether expected sensors are present/readable.
- If power fields are null, confirm if sensors are actually absent vs read-path failure.

## 4) Guard-line sanity
- Check recent benchmark log for `[guard]` lines.
- Classify each as expected fallback vs bug signal.

## 5) Commit + push hygiene
- Commit only scoped files related to the sprint.
- Push to `main` only after passing checks above.

## 6) Mission Control write-through
- Update sprint task states to match reality.
- Add a concise `sprint_cli.py comms` summary of:
  - what changed
  - what validated
  - any known caveats

## 7) Close criteria
Sprint can be marked done only when:
- required ingest fields are populated on fresh run(s)
- regressions are not introduced on at least one additional machine/path
- blocked tasks are resolved or explicitly moved out with reason
