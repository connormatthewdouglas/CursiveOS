import { createFileRoute } from "@tanstack/react-router";
import { PageHead } from "@/components/shell";
import { Badge } from "@/components/ui/badge";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { GAPS, type GapSeverity } from "@/lib/cursive/gaps";

export const Route = createFileRoute("/gaps")({ component: GapsPage });

const ORDER: GapSeverity[] = ["hard-gate", "now", "next", "later"];

const TONE: Record<string, "bad" | "warn" | "info" | "muted" | "good"> = {
  "hard-gate": "bad",
  now: "warn",
  next: "info",
  later: "muted",
  open: "warn",
  partial: "info",
  "shipped-here": "good",
};

function GapsPage() {
  return (
    <div>
      <PageHead
        kicker="This sprint"
        title="What is actually missing"
        lede="Not a brainstorm. These are the load-bearing holes between a measurement apparatus that has begun to run itself and an organism that can take external testers or real sats."
      />

      {ORDER.map((sev) => {
        const rows = GAPS.filter((g) => g.severity === sev);
        return (
          <section key={sev} className="mb-6">
            <h2 className="mb-3 text-lg font-medium tracking-tight">
              {sev === "hard-gate" ? "Hard gates before money" : sev}
            </h2>
            <div className="grid gap-3 md:grid-cols-2">
              {rows.map((g) => (
                <Card key={g.id}>
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <CardTitle>{g.title}</CardTitle>
                    <div className="flex gap-1.5">
                      <Badge tone={TONE[g.severity]}>{g.severity}</Badge>
                      <Badge tone={TONE[g.status]}>{g.status}</Badge>
                    </div>
                  </div>
                  <p className="mt-2 text-xs uppercase tracking-wider text-muted">{g.area}</p>
                  <CardHint>{g.why}</CardHint>
                  <p className="mt-2 font-mono text-xs text-muted">{g.evidence}</p>
                </Card>
              ))}
            </div>
          </section>
        );
      })}

      <Card>
        <CardTitle>Shipped in this console</CardTitle>
        <ul className="mt-3 list-disc space-y-1 pl-5 text-sm text-muted">
          <li>Live CursiveRoot read path with snapshot fallback (146 runs, 3 physical hosts).</li>
          <li>v3.3 cycle-close engine + local ledger (cycles, lifetime fitness, tester rebates).</li>
          <li>Unsigned PSBT intents. Pause, per-cycle cap, bech32, mainnet hard-gate.</li>
          <li>Origin-side recompute engine: hash payloads, fail closed if missing, never pay.</li>
          <li>QD-default proposer that refuses mined-out vfs/page-cluster cousins.</li>
          <li>Identity-gated write policy (USING(true) denied). Key rotation/revocation locally.</li>
          <li>Loop watchdog + revival playbook instead of a fake “all systems go” dashboard.</li>
          <li>v3.1 hub-api shapes frozen as a non-economics interface.</li>
        </ul>
      </Card>
    </div>
  );
}
