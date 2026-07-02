# Changelog — White Paper v2.6 + Framework Rename

**Date:** 2026-07-01

(Numbering note: CHANGELOG-v2.5 recorded the decision-grade sensor loop tooling
milestone; the white paper itself moves v2.4 → v2.6 here to keep changelog and
paper numbering aligned going forward.)

## Rename: manifesto → framework

`software-organisms-manifesto.md` is now `software-organisms-framework.md`
(file renamed 2026-06-30; subtitle now "A framework for governance by
measurement, and the first instance under construction"). Rationale: the term
"manifesto" carried an unintended ideological connotation that misrepresents
the document — it is an architectural framework derived from design work, not
a call to belief. "Framework" also matches how white-paper §11 already
described the document ("Relationship to the Software Organisms Framework").
All repository references updated; historical changelog prose left intact.
This entry records the rationale, completing the rename.

## White paper v2.6 — incorporate earned adversarial results

Four additions, each scoped to what has actually been run. None of them
loosens the existing honest-scoping discipline (§8, §10):

1. **§6.3 — acceptance boundary adversarially tested (H2 + V).** The paper
   previously argued the evaluation path was trustworthy by architectural
   separation alone. It now cites the H2 experiment: fabricated-delta, replay,
   and parsimony-gaming attacks were *initially accepted*, then rejected on
   rerun only after named production gates were added (evidence/provenance,
   replay fingerprint, genome-derived parsimony invariant); confirmation Sybil
   was deferred to the trust layer with real reward gated. The V follow-up
   prototyped recomputation, signed identity, a global replay index, and
   system-owned aggregation, and rejected a simulated funded adversary.
   Explicitly framed as a **local pass against a self-built attacker**, not
   proof against real adversaries in a decentralized deployment.
   References: `docs/experiments/H2-adversarial-tester-results.md`,
   `docs/experiments/V-verifier-hardening-results.md`.

2. **§6.3 — two-sided referee trust (Mode H).** New explicit statement that
   the verifier must both reject fraud *and* not wrongly reject honest
   contributions from noisy or uncommon hardware — false rejection kills a
   measurement market as surely as false acceptance. Mode H is now a
   registered test axis; in the V pass, zero registered honest controls were
   fraud-rejected (noted as small-sample and local).

3. **§10 — trust scales with stake.** The verifier's cleared bar is "rejects
   attacks profitable at current (placeholder) stakes." The funded-adversary
   bar applies when real BTC activates, which is why real reward stays gated
   until the V-prototyped mechanisms are production-hardened with key,
   hardware, and wallet independence. §10's "proved in principle" wording
   replaced with the earned-but-bounded formulation.

4. **§1 — structural incentive-gap framing.** Added (augmenting, not
   replacing, the individual-level framing): vendors are economically
   structured to neglect the long-tail of old/uncommon/custom hardware, which
   is where measured headroom persists and where per-target
   near-zero-marginal-cost measurement is most differentiated. Kernel/driver/
   firmware tuning framed as the far, explicitly aspirational end of the same
   axis.

## Also

- Fixed the last stale "manifesto" prose reference
  (`docs/specs/seed-organism-v0.1.md` — "validate the whole framework").

## Files changed

- `white-paper.md` (v2.4 → v2.6)
- `docs/specs/seed-organism-v0.1.md`
- `docs/CHANGELOG-v2.6.md` (this file)
