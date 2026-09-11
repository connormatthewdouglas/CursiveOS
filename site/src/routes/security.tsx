import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { PageHead } from "@/components/shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { Label, Select } from "@/components/ui/input";
import { useCursive } from "@/lib/cursive/use-cursive";
import {
  LIVE_USING_TRUE_HOLES,
  authorizeWrite,
  type PolicyAction,
  type PolicyActor,
  type PolicyTable,
} from "@/lib/cursive/policy";
import { authorizeOriginRequest } from "@/lib/cursive/origin";
import { LIVE_RLS_HOLES } from "@/lib/cursive/holes";
import { CANONICAL_LAPTOP, CANONICAL_STARDUST, machineDisplayName } from "@/lib/cursive/identity";
import { useOperator } from "@/lib/cursive/store";

export const Route = createFileRoute("/security")({ component: SecurityPage });

const CONTROLS = [
  {
    title: "Testers earn no lifetime fitness",
    body: "v3.3 structural kill for fake-machine farms. A spoof extracts at most a Fast-tier rebate.",
    state: "spec live",
    tone: "good" as const,
  },
  {
    title: "payout_eligible CHECK false",
    body: "Database constraint, not a UI label. Trust rows cannot become money without a migration that we should not run yet.",
    state: "enforced",
    tone: "good" as const,
  },
  {
    title: "Queue inject closed",
    body: "measurement_requests is privileged-author only. Anon may update status/updated_at, not invent work.",
    state: "enforced",
    tone: "good" as const,
  },
  {
    title: "Capability / job cross-writes",
    body: "USING(true) update policies remain on machine_capabilities and measurement_jobs. The engine here denies them. Origin RLS is the close.",
    state: "engine here",
    tone: "warn" as const,
  },
  {
    title: "Fail-closed network benches",
    body: "Without tc or iperf3 the harness exits before mutating sysctls or printing a stack delta.",
    state: "harness",
    tone: "good" as const,
  },
  {
    title: "HTML escaping on public dashboard",
    body: "Untrusted CursiveRoot fields are escaped. This console renders as React text nodes, not innerHTML.",
    state: "enforced",
    tone: "good" as const,
  },
  {
    title: "Hub API passwordless create",
    body: "Legacy /hub/accounts/create and /session/create stay disabled unless an explicit env flag is set.",
    state: "locked",
    tone: "good" as const,
  },
  {
    title: "Mainnet signing key in browser",
    body: "Never. This console will queue unsigned intents and refuse to invent a mainnet hash.",
    state: "enforced here",
    tone: "good" as const,
  },
  {
    title: "Key rotation / revocation",
    body: "Specified as a known limitation in hardening.md §2.11. Engine exists here; CursiveRoot policy does not.",
    state: "partial",
    tone: "warn" as const,
  },
  {
    title: "Operator origin writes",
    body: "GET is the only allowed CursiveRoot method. POST/PATCH/DELETE and payout_eligible flips are denied here even if live RLS is still USING(true).",
    state: "enforced here",
    tone: "good" as const,
  },
  {
    title: "Durability Action secrets",
    body: "Free-tier pause already dropped data once. Backup + keep-alive workflows exist; secrets must be present.",
    state: "verify",
    tone: "warn" as const,
  },
];

const ATTACKS = [
  ["Fake machines for lifetime fitness", "Structurally dead in v3.3 — testers get no equity."],
  ["Fake contributors vs metabolic sensor", "Must merge positive-fitness work. Garbage does not move R_meta."],
  ["Measurement fabrication", "Population confirmation + immune outliers. Plausible noise does not distort."],
  ["Contributor/tester collusion", "Dangerous below ~10 machines. Founder review still required at this fleet size."],
  ["Wallet compromise", "No organism-level recovery. Rotation policy is the close."],
  ["Fork-based exit", "Lifetime ledger is Bitcoin-anchored. A fork inherits obligations or starts at zero."],
];

function SecurityPage() {
  const { gates, physical } = useCursive();
  const writeLog = useOperator((s) => s.writeLog);
  const addWrite = useOperator((s) => s.addWrite);
  const [table, setTable] = useState<PolicyTable>("measurement_jobs");
  const [action, setAction] = useState<PolicyAction>("update");
  const [actorKind, setActorKind] = useState<PolicyActor["kind"]>("anon");
  const [rowMachine, setRowMachine] = useState(CANONICAL_STARDUST);
  const [originMsg, setOriginMsg] = useState<string | null>(null);

  function run() {
    const attempt = {
      table,
      action,
      actor: {
        kind: actorKind,
        machine_id: actorKind === "claimed_machine" ? CANONICAL_LAPTOP : null,
        key_status: actorKind === "claimed_machine" ? "active" : actorKind === "proposer" ? "local_sim" : null,
      },
      row_machine_id: rowMachine,
      fields: action === "update" && table === "measurement_requests" ? ["status", "updated_at"] : ["status"],
    };
    const decision = authorizeWrite(attempt);
    addWrite(attempt, decision, new Date().toISOString());
  }

  return (
    <div>
      <PageHead
        kicker="Hardening"
        title="Security posture"
        lede="Name the load-bearing risks instead of pretending they are gone. Bootstrap founder-commitment is still real. Fleet size is still below the collusion threshold."
      />

      <div className="mb-4 flex flex-wrap gap-2">
        <Badge tone="warn">{physical.length} physical machines</Badge>
        <Badge tone={gates.independent_aggregation === gates.total && gates.total > 0 ? "good" : "warn"}>
          aggregation {gates.independent_aggregation}/{gates.total}
        </Badge>
        <Badge tone="good">payout true {gates.payout_true}</Badge>
        <Badge tone="warn">USING(true) holes: {LIVE_USING_TRUE_HOLES.join(", ")}</Badge>
      </div>

      <Card className="mb-4">
        <CardTitle>Live RLS catalog</CardTitle>
        <CardHint>
          Named holes from the production schema. The identity-gated SQL draft drops the UPDATE USING(true)
          policies. Do not apply it while keys are still local_sim.
        </CardHint>
        <ul className="mt-3 space-y-2">
          {LIVE_RLS_HOLES.map((h) => (
            <li key={`${h.table}-${h.action}`} className="rounded-lg border border-border bg-bg-elevated p-3">
              <div className="flex items-center justify-between gap-2">
                <div className="font-mono text-xs">
                  {h.table} {h.action}
                </div>
                <Badge tone={h.severity === "open" ? "warn" : "good"}>{h.severity}</Badge>
              </div>
              <p className="mt-1 text-sm text-muted">{h.note}</p>
            </li>
          ))}
        </ul>
      </Card>

      <Card className="mb-4">
        <CardTitle>Write-policy simulator</CardTitle>
        <CardHint>
          Live CursiveRoot still has USING(true) on capabilities and jobs. This engine denies that. Try
          anon cross-writing Stardust from the laptop — it must fail.
        </CardHint>
        <div className="mt-4 grid gap-3 md:grid-cols-4">
          <div>
            <Label htmlFor="table">Table</Label>
            <Select id="table" value={table} onChange={(e) => setTable(e.target.value as PolicyTable)}>
              <option value="measurement_requests">measurement_requests</option>
              <option value="measurement_jobs">measurement_jobs</option>
              <option value="machine_capabilities">machine_capabilities</option>
              <option value="os0_identity_keys">os0_identity_keys</option>
              <option value="l5_accruals">l5_accruals</option>
            </Select>
          </div>
          <div>
            <Label htmlFor="action">Action</Label>
            <Select id="action" value={action} onChange={(e) => setAction(e.target.value as PolicyAction)}>
              <option value="insert">insert</option>
              <option value="update">update</option>
              <option value="delete">delete</option>
            </Select>
          </div>
          <div>
            <Label htmlFor="actor">Actor</Label>
            <Select
              id="actor"
              value={actorKind}
              onChange={(e) => setActorKind(e.target.value as PolicyActor["kind"])}
            >
              <option value="anon">anon</option>
              <option value="claimed_machine">claimed machine (laptop, active key)</option>
              <option value="proposer">proposer (local_sim)</option>
              <option value="service_role">service role</option>
            </Select>
          </div>
          <div>
            <Label htmlFor="row">Row machine</Label>
            <Select id="row" value={rowMachine} onChange={(e) => setRowMachine(e.target.value)}>
              <option value={CANONICAL_LAPTOP}>{machineDisplayName(CANONICAL_LAPTOP)}</option>
              <option value={CANONICAL_STARDUST}>{machineDisplayName(CANONICAL_STARDUST)}</option>
            </Select>
          </div>
        </div>
        <div className="mt-4 flex flex-wrap gap-2">
          <Button size="sm" onClick={run}>
            Authorize write
          </Button>
          <Button
            size="sm"
            variant="secondary"
            onClick={() => {
              const d = authorizeOriginRequest({
                method: "POST",
                table: "measurement_requests",
                using_true: true,
                payout_eligible: true,
              });
              setOriginMsg(`${d.allowed ? "allowed" : "denied"} · ${d.reasons.join(" · ")}`);
            }}
          >
            Try POST to CursiveRoot
          </Button>
        </div>
        {originMsg ? <p className="mt-3 text-sm text-warn">{originMsg}</p> : null}
        <ul className="mt-3 space-y-2">
          {writeLog.map((row, i) => (
            <li key={`${row.at}-${i}`} className="rounded-lg border border-border bg-bg-elevated p-3 text-sm">
              <div className="flex items-center justify-between gap-2">
                <span className="font-mono text-xs">
                  {row.attempt.actor.kind} → {row.attempt.action} {row.attempt.table}
                </span>
                <Badge tone={row.decision.ok ? "good" : "bad"}>{row.decision.ok ? "allow" : "deny"}</Badge>
              </div>
              <p className="mt-1 text-xs text-muted">{row.decision.reason}</p>
            </li>
          ))}
        </ul>
      </Card>

      <div className="grid gap-3 md:grid-cols-2">
        {CONTROLS.map((c) => (
          <Card key={c.title}>
            <div className="flex items-start justify-between gap-2">
              <CardTitle>{c.title}</CardTitle>
              <Badge tone={c.tone}>{c.state}</Badge>
            </div>
            <CardHint>{c.body}</CardHint>
          </Card>
        ))}
      </div>

      <Card className="mt-4">
        <CardTitle>Attack surface (named, not solved by vibe)</CardTitle>
        <ul className="mt-3 space-y-3">
          {ATTACKS.map(([t, b]) => (
            <li key={t}>
              <div className="font-medium">{t}</div>
              <p className="text-sm text-muted">{b}</p>
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
