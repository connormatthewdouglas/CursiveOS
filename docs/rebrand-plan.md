# CursiveOS Rebrand Plan
**Status:** EXECUTED — 2026-03-25
**Prepared:** 2026-03-23
**Executed:** 2026-03-25
**Chosen name:** CursiveOS (recursive → cursive: the self-improving data flywheel is literally recursive)

---

## What Changed

### TAO-OS → CursiveOS
| Old | New |
|-----|-----|
| `TAO-OS` (display name) | `CursiveOS` |
| GitHub repo: `TAO-OS` | `CursiveOS` (rename to follow separately) |
| White paper title | "CursiveOS: AI-Guided Linux Optimization for Local Compute" |
| White paper version | v0.4 → v0.4.1 |

### What Did NOT Change
- `CursiveRoot` database name — board decision: keep the brand equity
- Script filenames (`tao-os-*.sh`, `benchmark-*.sh`) — benchmark history is sacred
- `machine_id` values in CursiveRoot — hardware fingerprints stay
- Benchmark methodology — nothing scientific changes
- `.openclaw/` config — Copper's runtime, not project-facing
- Archive scripts — left as-is, they're history

---

## Files Updated (2026-03-25)

### Docs / Markdown
| File | Change |
|------|--------|
| `README.md` | Title, clone URL, all display name refs → CursiveOS |
| `white-paper.md` | Full rebrand, v0.4.1, CursiveOS identity throughout |
| `docs/action-plan.md` | Project name refs, task #6 marked COMPLETE |
| `references/CLAUDE.md` | Project name, rebrand section updated, last updated date |
| `references/README.md` | Project name refs |
| `references/CHANGELOG.md` | v0.4.1 entry added at top |
| `docs/rebrand-plan.md` | This file — status updated to EXECUTED |
| `external-tester-guide.md` | Project name refs |
| `references/ONBOARDING_EXTERNAL.md` | Project name refs |
| `references/BENCHMARK-INTEGRATION-v1.5.md` | Project name refs |
| `docs/RESEARCH.md` | Project name refs |
| All benchmark .sh headers | TAO-OS → CursiveOS in comments/echo |

### Script Headers (content only — filenames unchanged)
| File | Change |
|------|--------|
| `benchmarks/benchmark-network-v0.1.sh` | Header comment, sudo prompt, log echo |
| `benchmarks/benchmark-inference-v0.3.sh` | Header comment, sudo prompt, log echo |
| `benchmarks/benchmark-inference-v0.4.sh` | Header comment, sudo prompt, log echo |
| `benchmarks/benchmark-inference-v0.1.sh` | Header comment, sudo prompt |
| `tao-os-full-test-v1.4.sh` | Header/echo refs (script filename preserved) |
| `tao-os-presets-v0.8.sh` | Header/echo refs (script filename preserved) |

---

## GitHub (separate action)
- [ ] Rename GitHub repo `TAO-OS` → `CursiveOS` in settings
- [ ] Update repo description
- [ ] Update README one-liner clone URL is already updated in README.md

---

## Notes
- GitHub repo rename automatically redirects old clone URLs for ~1 year
- `~/TAO-OS` workspace dir rename is optional — not renamed (scripts use `$HOME/TAO-OS` internally)
- This was a one-shot clean commit: `rebrand: TAO-OS → CursiveOS (v0.4.1)`
