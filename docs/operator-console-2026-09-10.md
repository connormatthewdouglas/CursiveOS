# Operator console — 2026-09-10 sprint

The public dashboard stays read-only. The operator console is the nervous
system: it can see live CursiveRoot, draft work, rehearse economics, and refuse
unsafe money. It cannot write production rows and it cannot sign Bitcoin.

## Engines

See `operator/README.md`. 45 unit tests cover identity, queue, trust, economics,
rails, recompute, propose, policy, loop, ledger, psbt, hub freeze.

## Proposer change

`tools/organism_proposer.py` now skips mined-out honest nulls
(`pagecluster0`, `vfscache50`) even if their variant files are deleted.
Remaining library knobs print as leftovers, not QD-grounded proposals.

## Do not

- Apply `operator/sql/20260910_l5_v33_ledger_DRAFT.sql`
- Treat `hub-api/` as v3.3
- Run `tools/layer5_tokenomics_cli.py` as if it were current economics
- Promote v0.13-pagecluster0 or v0.13-vfscache50
