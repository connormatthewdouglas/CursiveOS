import { createFileRoute } from "@tanstack/react-router";
import { PageHead } from "@/components/shell";
import { Badge } from "@/components/ui/badge";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { useCursive } from "@/lib/cursive/use-cursive";
import { loopLabel } from "@/lib/cursive/loop";
import { fmtWhen } from "@/lib/cursive/format";

export const Route = createFileRoute("/workflows")({ component: WorkflowsPage });

const STAGES = [
  {
    id: "propose",
    title: "1. Propose",
    owner: "propose.ts + organism_proposer.py",
    now: "Live seed_bundles archive. Empty-neighbor mutation of v0.11. pagecluster/vfs skipped.",
    tone: "good" as const,
  },
  {
    id: "enqueue",
    title: "2. Privileged enqueue",
    owner: "signed proposer (local_sim cannot production-enqueue)",
    now: "This console drafts locally. Live INSERT still needs service role or an active proposer key.",
    tone: "warn" as const,
  },
  {
    id: "claim",
    title: "3. Daemon claim",
    owner: "contributor_daemon.py",
    now: "Linux bare-metal only. Heartbeats last seen 2026-07-07. Queue currently empty.",
    tone: "warn" as const,
  },
  {
    id: "screen",
    title: "4. Screen",
    owner: "cursiveos-full-test-v1.4.sh",
    now: "Five channels. Fail-closed network benches when tc/iperf3 missing. Concurrency weight 0.",
    tone: "good" as const,
  },
  {
    id: "upload",
    title: "5. Upload + trust rows",
    owner: "seed_organism.py",
    now: "Writes seed_bundles plus os0 identity / artifact / evaluation. payout_eligible forced false.",
    tone: "good" as const,
  },
  {
    id: "aggregate",
    title: "6. Independent aggregation",
    owner: "recompute.ts (origin still missing)",
    now: "Engine hashes payloads and fails closed when they are absent. CursiveRoot does not host it yet.",
    tone: "warn" as const,
  },
  {
    id: "verdict",
    title: "7. Verdict",
    owner: "sensor array",
    now: "Accept / reject / honest null. Cycles 5 and 6 were honest nulls. Do not promote them.",
    tone: "good" as const,
  },
  {
    id: "pay",
    title: "8. Accrue / claim / rail",
    owner: "ledger.ts + psbt.ts",
    now: "v3.3 ledger rehearsal + unsigned intents. Mainnet cannot sign.",
    tone: "warn" as const,
  },
];

function WorkflowsPage() {
  const { snapshot, openRequests, activeJobs, loop } = useCursive();
  const lastReq = snapshot?.requests?.[0];

  return (
    <div>
      <PageHead
        kicker="OS.0 loop"
        title="Workflows"
        lede="One path from a proposed knob to a Bitcoin accrual. Anything that skips a box is how the founder ended up back in the middle."
      />

      <div className="mb-4 flex flex-wrap gap-2">
        <Badge tone={loop.state === "running" ? "good" : "warn"}>{loopLabel(loop.state)}</Badge>
        <Badge tone={openRequests ? "good" : "muted"}>{openRequests} open requests</Badge>
        <Badge tone={activeJobs ? "warn" : "muted"}>{activeJobs} active jobs</Badge>
        <Badge tone="info">parent v0.12</Badge>
        {lastReq ? <Badge tone="muted">last: {lastReq.candidate_variant_id}</Badge> : null}
      </div>

      <Card className="mb-4">
        <CardTitle>Revival playbook</CardTitle>
        <CardHint>
          Last heartbeat {fmtWhen(loop.last_heartbeat_at)}
          {loop.heartbeat_age_hours != null ? ` · ${loop.heartbeat_age_hours}h ago` : ""}.
        </CardHint>
        <ol className="mt-3 grid gap-2 md:grid-cols-5">
          {loop.playbook.map((step) => (
            <li key={step.id} className="rounded-lg border border-border bg-bg-elevated p-3">
              <div className="flex items-center justify-between gap-2">
                <div className="text-sm font-medium">{step.title}</div>
                <Badge tone={step.ready ? "good" : "warn"}>{step.ready ? "ready" : "wait"}</Badge>
              </div>
              <p className="mt-1 font-mono text-[11px] text-muted">{step.owner}</p>
              <p className="mt-1 text-xs text-muted">{step.note}</p>
            </li>
          ))}
        </ol>
      </Card>

      <ol className="grid gap-3 md:grid-cols-2">
        {STAGES.map((s) => (
          <li key={s.id}>
            <Card>
              <div className="flex items-start justify-between gap-2">
                <CardTitle>{s.title}</CardTitle>
                <Badge tone={s.tone}>{s.tone === "good" ? "built" : "partial"}</Badge>
              </div>
              <p className="mt-1 font-mono text-xs text-muted">{s.owner}</p>
              <CardHint>{s.now}</CardHint>
            </Card>
          </li>
        ))}
      </ol>

      <Card className="mt-4">
        <CardTitle>What “the loop runs itself” actually means</CardTitle>
        <p className="mt-3 max-w-3xl text-sm text-muted">
          Cycle 5 proved proposal, claim, screen, upload, and an honest null can happen without a
          manual screen step. Enqueue is still founder-gated by design. Money is still simulated by
          design. The next honest move is not another vfs knob — it is origin-side aggregation plus a
          QD-grounded proposer, then signed auto-enqueue.
        </p>
      </Card>
    </div>
  );
}
