# Changelog — White Paper v2.2

## Summary

v2.2 is an additive update to v2.1. The Layer 5 economics specification (v3.3) is unchanged. Two new components are introduced to the project's architecture and vision:

1. **A public roadmap** (`ROADMAP.md`) organized around a four-transition arc from tweak stack to substrate, specifying flagship features by release.
2. **A local agent architecture** (`docs/architecture/agent-architecture.md`) split into a fully-specified measurement daemon and an architecturally-sketched natural-language shell that will be the flagship feature of the v1.0 release.

No architectural components from v2.1 are deprecated or changed. Nothing in the sensor array, testers, hardening, or Layer 5 economics specifications is edited.

## What Changed

### Added

- `ROADMAP.md` at repo root — four-transition roadmap with milestones and flagship-per-release
- `docs/architecture/agent-architecture.md` — measurement daemon specification plus natural-language shell architectural sketch
- Two biological-mapping entries in `biological-architecture.md` (autonomic nervous system, communication/voice)
- `docs/CHANGELOG-v2.2.md` (this file)

### Edited

- `white-paper.md`: version bump from v2.1 to v2.2; abstract gains one paragraph on the natural-language shell direction; section 9 (Roadmap) rewritten to reference the four-transition arc and link to ROADMAP.md; brief mention of the agent layer added to section 2 (The CursiveOS Stack)
- `README.md`: short vision paragraph added about v1.0's natural-language shell; roadmap section updated to reflect v3.3 status and flagship features by release; documentation index updated with roadmap and agent architecture links

### Unchanged

- `docs/specs/layer5-economics-v3.3.md`
- `docs/architecture/sensor-array.md`
- `docs/architecture/testers.md`
- `docs/architecture/hardening.md`
- Hub code, Phase 0 code, benchmark scripts, preset scripts, operational scripts
- Archived files

## Why These Additions

**The roadmap.** v2.1 had a Roadmap section at the end of the white paper consisting of a flat "Done / Next / Later" list. This was adequate for internal reference but not adequate as a north-star document for contributors, external observers, or the project's own strategic orientation. A standalone roadmap organized around the four transitions communicates where CursiveOS is going in a form that makes the architectural choices legible — each architectural decision is sized for the end state, and seeing the end state makes the current overbuilt-looking choices recognizable as sensible.

**The agent architecture.** The architecture has always assumed that sensors are measured by something; v2.1 left this implicit. v2.2 makes it explicit by specifying the measurement daemon as a distinct component with its own trust boundary, privacy model, and failure modes. More consequentially, v2.2 introduces the natural-language shell as the flagship v1.0 feature. This is a large commitment — the shell has not yet been implemented — but it is the commitment that reframes CursiveOS from "a Linux distribution for specific operator categories" to "the Linux distribution on which human-machine interaction fundamentally changes." The positioning implication is significant and it is intentional.

**Why flag the shell this publicly, this early.** The natural-language-native OS direction is a category-defining claim. Other projects could implement something similar if they moved quickly. The moat is execution quality — permission scoping, integration with organism state, the measurement pipeline that gives the agent real system context, the biological framing that gives the whole thing coherence. These are hard to copy in weeks. Announcing the direction before shipping a demo creates a commitment that forces execution focus. Shipping a demo before announcing the direction is also reasonable but means running the risk that someone else announces first.

## What This Changelog Is Not

This is not a promise that v1.0 ships on any specific date. The roadmap is a north star, not a contract. The sequence of transitions is stable; the timing adapts to what the project encounters.

This is also not the final architecture. Each transition will surface design questions that require additional specification. Those will be versioned and documented as they land.

---

*CursiveOS is a new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure.*
