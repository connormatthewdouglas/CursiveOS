# Submission enqueue ladder

How a public idea or sensor becomes eligible for the work queue.
This is the contract the `/ideas` and `/sensors` pages rehearse in-browser.
**Nothing on those pages writes the live ledger.** Live enqueue still waits on a
signed proposer rail.

`payout_eligible` is hard-false everywhere on this ladder. Acceptance is
sensor-scored fitness plus gates — not votes.

## Ladder (fail-closed)

```
draft → self_pending → self_clean → foreign_pending → public_eligible
                                                     ↘ refused
```

1. **draft** — Author fills the form. Files can be downloaded. No enqueue yet.
2. **self_pending** — "Submit to the wire" records a local browser stub and
   downloads an enqueue stub. Identity of the submitter machine must be known
   (or the advance is refused). Live `measurement_requests` is not touched.
3. **self_clean** — The same machine that submitted runs the candidate and
   reports a clean self-screen. A different machine cannot mark self-clean.
4. **foreign_pending** — Waiting for exactly one confirmer whose
   `machine_id` is not the submitter. Same-machine "confirmation" is refused.
5. **public_eligible** — Self-clean plus one foreign confirmer. Only then may a
   privileged signed proposer put the work on the public queue.
6. **refused** — Terminal. Identity mismatch, missing identity, or explicit
   refuse. Does not re-enter the public queue without a new draft.

## Identity rules (fail-closed)

- Missing submitter or confirmer identity → refuse, do not advance.
- Self-clean actor must equal submitter.
- Foreign confirmer must differ from submitter. Exactly one is required.
- Desktop panel/desk never submit. The public pages draft and stub; the
  Desktop remains a task manager.

## Draft vs wire

| Surface | Writes live DB? | What it produces |
| --- | --- | --- |
| Draft ("Draft the test") | No | Local review + downloadable description / script |
| Wire ("Submit to the wire") | No | Local `self_pending` record + enqueue stub JSON (`payout_eligible: false`) |
| Signed proposer rail (not this page) | Yes, when it exists | Privileged insert into `measurement_requests` |

Anon INSERT on `measurement_requests` stays denied. The stub is a file a
founder or future signed proposer can use by hand. It is not a live write.

## Page roles

| Page | Role |
| --- | --- |
| **/ideas** | Public variant (mutation) submissions. Draft + wire stub. |
| **/sensors** | Public measurement (sensor) submissions. Draft + wire stub. |
| **/queue** (Work) | Operator rehearsal of what is being tested. Short ladder note only — not a submission form. |
| **Desktop** | Task manager. Never a submission form. Stop / update / phase live here. |
| **/join** | Points people to Ideas (variants) and Sensors (measurements). |

## Acceptance

Public eligibility on this ladder only means "cleared for a privileged enqueue
attempt." Whether the variant or sensor is kept is decided later by
sensor-scored fitness and gates on real machines — never by votes.

## Hard rails

- `payout_eligible: false` on every stub, draft, and ladder record.
- No README claim changes accompany this ladder.
- Do not claim a live ledger write from Ideas or Sensors.
