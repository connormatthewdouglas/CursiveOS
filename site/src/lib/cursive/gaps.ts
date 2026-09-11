export type GapSeverity = "hard-gate" | "now" | "next" | "later";
export type GapArea =
  | "trust"
  | "rails"
  | "hub"
  | "infra"
  | "workflow"
  | "security"
  | "measurement";

export type Gap = {
  id: string;
  area: GapArea;
  severity: GapSeverity;
  title: string;
  why: string;
  status: "open" | "partial" | "shipped-here";
  evidence: string;
};

export const GAPS: Gap[] = [
  {
    id: "g4-recompute",
    area: "trust",
    severity: "hard-gate",
    title: "Origin-side raw recompute for remote bundles",
    why: "Live trust rows still have independent_aggregation_ok = false. This console now hashes payloads itself and fails closed when they are missing. CursiveRoot origin still needs to host that engine.",
    status: "partial",
    evidence: "operator/engine/recompute.ts; os0_trust_evaluations still awaiting_independent_aggregation",
  },
  {
    id: "g4-keys",
    area: "trust",
    severity: "hard-gate",
    title: "Key rotation and revocation in production",
    why: "Public identity keys are still local-sim. Rotation/revoke engine is local. Stolen keys stay permanent on origin until a policy lands.",
    status: "partial",
    evidence: "os0_identity_keys.key_status = local_sim",
  },
  {
    id: "g4-independence",
    area: "trust",
    severity: "hard-gate",
    title: "Hardware / wallet independence before money",
    why: "Two confirmations from aliased fingerprints or the same wallet must not count. Specified and executed here; not enforced on origin.",
    status: "partial",
    evidence: "independentConfirmations() + recomputeBundle witnesses",
  },
  {
    id: "g5-money",
    area: "rails",
    severity: "hard-gate",
    title: "Real BTC payouts",
    why: "payout_eligible is CHECK-constrained false. Unsigned PSBT intents exist. Mainnet cannot sign.",
    status: "partial",
    evidence: "psbt.ts signing_key_present=false; supabase CHECK payout_eligible is false",
  },
  {
    id: "v33-schema",
    area: "rails",
    severity: "now",
    title: "v3.3 ledger tables are not the live schema",
    why: "Engine now has l5_cycles / lifetime / accruals / tester rebates. SQL draft is not applied. Production still uses seed_payout_reports.",
    status: "partial",
    evidence: "operator/sql/20260910_l5_v33_ledger_DRAFT.sql — do not apply yet",
  },
  {
    id: "hub-bidirectional",
    area: "hub",
    severity: "now",
    title: "Bidirectional operator surface",
    why: "Queue drafts, proposer, cycle close, and write-policy simulator run here. origin.ts denies every POST/PATCH/DELETE. Live CursiveRoot is still read-only from this console.",
    status: "partial",
    evidence: "origin.ts authorizeOriginRequest; dashboard/README.md remains read-only",
  },
  {
    id: "legacy-hub",
    area: "hub",
    severity: "now",
    title: "Freeze or archive the v3.1 hub-api",
    why: "hub-api still exposes pool/governance-shaped endpoints. This console refuses those shapes as the economics interface.",
    status: "partial",
    evidence: "hub.ts inspectHubSurface; hub-api/HUB_FROZEN.md",
  },
  {
    id: "loop-idle",
    area: "workflow",
    severity: "now",
    title: "Selection loop is idle",
    why: "Watchdog names the state: empty queue + July heartbeats = stale. Revival playbook is in the console. Rigs still have to be woken by an operator.",
    status: "partial",
    evidence: "loop.ts; machine_capabilities.last_seen_at",
  },
  {
    id: "qd-proposer",
    area: "workflow",
    severity: "now",
    title: "QD-archive-grounded proposer",
    why: "Default propose() reads the live seed_bundles archive and mutates the accepted parent toward an empty neighboring cell. Materializer writes a reversible preset only when an operator-opt-in leftover matches the changed axis. Cold-start neighbors are hypothesis-only — no audited leftover maps there. Production auto-enqueue is still unsigned.",
    status: "partial",
    evidence: "qd.ts + materialize.ts; tools/qd_archive.py",
  },
  {
    id: "auto-enqueue",
    area: "workflow",
    severity: "next",
    title: "Signed proposer auto-enqueue",
    why: "local_sim can draft locally. Production auto-enqueue still needs an active Ed25519 proposer identity on origin.",
    status: "partial",
    evidence: "signProposal auto_enqueue_ok requires key_status=active",
  },
  {
    id: "queue-rls",
    area: "security",
    severity: "now",
    title: "Tighten OS.0 write policies before external testers",
    why: "Policy engine denies USING(true) cross-writes. Live RLS on capabilities/jobs is still open. SQL draft at operator/sql/20260911_os0_identity_gated_writes_DRAFT.sql — do not apply while keys are local_sim.",
    status: "partial",
    evidence: "policy.ts; origin.ts; holes.ts; 20260911_os0_identity_gated_writes_DRAFT.sql",
  },
  {
    id: "origin-writes",
    area: "security",
    severity: "now",
    title: "Operator console never writes CursiveRoot",
    why: "GET is the only allowed origin method. Writes, USING(true), and payout_eligible flips are denied in-engine even if live RLS is still loose.",
    status: "shipped-here",
    evidence: "origin.ts; live anon key is treated as read-only",
  },
  {
    id: "backup-secrets",
    area: "infra",
    severity: "now",
    title: "Confirm durability Action secrets",
    why: "Free-tier auto-pause already dropped data once. Daily encrypted backup + keep-alive exist as workflows but require SUPABASE_DB_URL and BACKUP_PASSPHRASE.",
    status: "open",
    evidence: "docs/specs/cursiveroot-data-durability-v1.md; .github/workflows/db-backup.yml",
  },
  {
    id: "tokenomics-cli",
    area: "rails",
    severity: "next",
    title: "Retire v3.1 tokenomics playground",
    why: "v3.1 CLI now prints a freeze warning. v3.3 engine lives in operator/engine and tools/layer5_economics_v33.py.",
    status: "partial",
    evidence: "tools/layer5_tokenomics_cli.py header; tools/layer5_economics_v33.py",
  },
  {
    id: "stardust-arc",
    area: "measurement",
    severity: "now",
    title: "Clean Stardust Arc idle benchmark",
    why: "SYCL instance exists on :11435 with 23/23 layers offloaded, but no clean idle number. Sustained channel stays voided on Stardust until that lands.",
    status: "open",
    evidence: "HANDOVER.md next #1",
  },
  {
    id: "nvidia-smi",
    area: "measurement",
    severity: "next",
    title: "Laptop GPU power channel",
    why: "Harness still lacks nvidia-smi power on the GTX 1650 path, so load-power stays observe-only on the laptop.",
    status: "open",
    evidence: "HANDOVER.md next #5",
  },
  {
    id: "bbr-multiflow",
    area: "measurement",
    severity: "next",
    title: "BBR multi-flow fairness",
    why: "Public network copy is still gated on the Ch09 multi-flow/retransmit experiment. Giant lab percentages must stay labeled lab-only.",
    status: "open",
    evidence: "action-plan Benchmark Limitations; dashboard honesty box",
  },
  {
    id: "external-testers",
    area: "workflow",
    severity: "later",
    title: "v1.5 gate — machines we do not control",
    why: "Five external machines, clean safety record, auto-submit from hardware we don't own. Blocked on daemon + trust, not marketing.",
    status: "open",
    evidence: "docs/action-plan.md v1.5 Gate Checklist",
  },
  {
    id: "iso",
    area: "infra",
    severity: "later",
    title: "Installable ISO (Transition 1)",
    why: "CursiveOS is still a tweak stack on Ubuntu/Mint, not a distribution. live-build/Cubic pipeline is unstarted.",
    status: "open",
    evidence: "ROADMAP.md Transition 1",
  },
];

export function gapsBySeverity(severity: GapSeverity) {
  return GAPS.filter((g) => g.severity === severity);
}
