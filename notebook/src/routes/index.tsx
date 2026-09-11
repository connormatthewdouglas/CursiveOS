import { createFileRoute, Link } from "@tanstack/react-router";
import { PageHead, Stat } from "@/components/shell";
import { Badge } from "@/components/ui/badge";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { TesterPaste } from "@/components/tester-paste";
import { useCursive } from "@/lib/cursive/use-cursive";
import { fmtWhen, isoMs } from "@/lib/cursive/format";
import { machineDisplayName } from "@/lib/cursive/identity";
import { loopLabel, organismBlurb } from "@/lib/cursive/loop";

export const Route = createFileRoute("/")({ component: OrganismHome });

const PASSED = [
  {
    id: "v0.11",
    title: "Compressed swap + calmer swapping",
    body: "When memory is tight, the kernel uses compressed RAM instead of the disk. Confirmed on the laptop and the desktop.",
  },
  {
    id: "v0.12",
    title: "That stack is now the current genome",
    body: "Every new idea is tested against this. We do not keep a tweak unless it beats this on real hardware.",
  },
];

const FAILED = [
  {
    id: "page-cluster",
    title: "Read pages in bigger clumps",
    body: "Tried. Did not help on founder machines. Retired.",
  },
  {
    id: "vfs-cache",
    title: "Keep less file cache",
    body: "Tried. Result was noise / no gain. Retired.",
  },
  {
    id: "sched",
    title: "Scheduler concurrency tweak",
    body: "Observed only. Not part of the score. Not promoted.",
  },
];

function OrganismHome() {
  const { snapshot, physical, caps, openRequests, isPending, loop } = useCursive();
  const lastBundle = snapshot?.accepted?.[0] ?? snapshot?.bundles?.find((b) => b.decision === "accepted");
  const genome = "v0.12";
  const recent = (snapshot?.bundles ?? []).slice(0, 6);

  return (
    <div>
      <PageHead
        kicker="CursiveOS"
        title="This is the organism."
        lede="It keeps Linux tweaks that measurably help real computers, and throws the rest away. You should be able to read this page without knowing the internals."
      />

      <Card className="mb-6">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>Latest screens</CardTitle>
            <CardHint>What was tried, and whether it stuck. Results only — not whether a person’s PC is busy.</CardHint>
          </div>
        </div>
        {recent.length ? (
          <ol className="mt-4 space-y-2">
            {recent.map((row) => (
              <li key={row.bundle_hash || `${row.variant_id}-${row.created_at}`} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-border bg-bg-elevated px-3 py-2 text-sm">
                <span>
                  {row.variant_id}
                  <span className="text-muted"> · {fmtWhen(row.created_at)}</span>
                </span>
                <Badge tone={row.decision === "accepted" ? "good" : "warn"}>
                  {plainDecision(row.decision)}
                </Badge>
              </li>
            ))}
          </ol>
        ) : (
          <p className="mt-3 text-sm text-muted">{isPending ? "Loading…" : "No screens on record yet."}</p>
        )}
      </Card>

      <Card className="mb-6">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>How it is doing</CardTitle>
            <CardHint>{organismBlurb(loop.state)}</CardHint>
          </div>
          <Badge tone={loop.state === "running" ? "good" : "warn"}>{loopLabel(loop.state)}</Badge>
        </div>
        <p className="mt-3 text-sm text-muted">
          Last machine check-in {fmtWhen(loop.last_heartbeat_at)}
          {loop.heartbeat_age_hours != null ? ` (${hoursPlain(loop.heartbeat_age_hours)})` : ""}.
        </p>
      </Card>

      <div className="mb-6 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="machines" value={isPending ? "…" : physical.length} hint="real computers, not aliases" />
        <Stat label="tests on record" value={isPending ? "…" : snapshot?.run_count ?? "—"} hint="measurements kept" />
        <Stat label="waiting" value={isPending ? "…" : openRequests} hint="ideas in line to be tested" />
        <Stat label="kept" value={isPending ? "…" : snapshot?.accepted.length ?? 0} hint="adaptations that stuck" />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <div className="flex items-start justify-between gap-3">
            <div>
              <CardTitle>Current genome</CardTitle>
              <CardHint>The living stack. New ideas must beat this, not a fantasy baseline.</CardHint>
            </div>
            <Badge tone="good">{genome}</Badge>
          </div>
          <p className="mt-3 text-sm text-muted">
            Compressed RAM swap (zram) and less aggressive swapping. Memory under pressure is the channel that
            actually moved. Speed claims from a single quiet desktop do not promote a change.
          </p>
          {lastBundle ? (
            <p className="mt-3 text-xs text-muted">
              Last kept result: {lastBundle.variant_id} · {fmtWhen(lastBundle.created_at)}
            </p>
          ) : null}
        </Card>

        <Card>
          <CardTitle>Machines</CardTitle>
          <CardHint>What has checked in, and how recently.</CardHint>
          <ul className="mt-4 space-y-3">
            {physical.length === 0 && isPending ? <li className="text-sm text-muted">Loading…</li> : null}
            {physical.map((m) => {
              const cap = caps.find((c) => c.canonical_machine_id === m.machine_id || c.machine_id === m.machine_id);
              const ageH = cap?.last_seen_at
                ? (Date.now() - isoMs(cap.last_seen_at)) / 36e5
                : null;
              const fresh = ageH != null && ageH < 24;
              return (
                <li key={m.machine_id} className="flex items-start justify-between gap-3">
                  <div>
                    <div className="font-medium">{machineDisplayName(m.machine_id)}</div>
                    <div className="text-xs text-muted">{shortGpu(m.gpu)}</div>
                  </div>
                  <Badge tone={fresh ? "good" : "warn"}>
                    {cap?.last_seen_at ? (fresh ? "seen today" : fmtWhen(cap.last_seen_at)) : "never"}
                  </Badge>
                </li>
              );
            })}
          </ul>
          <Button asChild variant="secondary" size="sm" className="mt-4 min-h-11">
            <Link to="/fleet">All machines</Link>
          </Button>
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardTitle>What passed</CardTitle>
          <CardHint>Kept because it helped on more than one machine.</CardHint>
          <ul className="mt-4 space-y-3">
            {PASSED.map((row) => (
              <li key={row.id} className="rounded-lg border border-border bg-bg-elevated p-3">
                <div className="flex items-center justify-between gap-2">
                  <div className="font-medium">{row.title}</div>
                  <Badge tone="good">{row.id}</Badge>
                </div>
                <p className="mt-1 text-sm text-muted">{row.body}</p>
              </li>
            ))}
          </ul>
        </Card>
        <Card>
          <CardTitle>What did not stick</CardTitle>
          <CardHint>Tried, measured, not kept. That is the organism working.</CardHint>
          <ul className="mt-4 space-y-3">
            {FAILED.map((row) => (
              <li key={row.id} className="rounded-lg border border-border bg-bg-elevated p-3">
                <div className="font-medium">{row.title}</div>
                <p className="mt-1 text-sm text-muted">{row.body}</p>
              </li>
            ))}
          </ul>
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardTitle>Become a tester</CardTitle>
          <CardHint>Linux computer you control. Windows can watch, not test.</CardHint>
          <TesterPaste compact />
          <Button asChild variant="secondary" size="sm" className="mt-3 min-h-11">
            <Link to="/join">How joining works</Link>
          </Button>
        </Card>
        <Card>
          <CardTitle>Have an idea?</CardTitle>
          <CardHint>
            Suggest a reversible Linux setting. We will turn it into a test ticket. This site will not change
            anyone’s computer for you.
          </CardHint>
          <p className="mt-3 text-sm text-muted">
            Name the setting, the new value, and how to undo it. Retired experiments (page cluster, vfs cache)
            are refused.
          </p>
          <Button asChild size="sm" className="mt-4 min-h-11">
            <Link to="/ideas">Suggest an adaptation</Link>
          </Button>
        </Card>
      </div>
    </div>
  );
}

function hoursPlain(h: number) {
  if (h < 1) return "minutes ago";
  if (h < 24) return `${Math.round(h)} hours ago`;
  return `${Math.round(h / 24)} days ago`;
}

function plainDecision(d: string | null | undefined) {
  if (d === "accepted") return "kept";
  if (d === "rejected_negative_fitness") return "did not help";
  if (d === "inconclusive") return "too close to call";
  if (d === "rejected_unverified_evidence") return "not verified";
  return d || "pending";
}

function shortGpu(gpu: string | null | undefined) {
  if (!gpu) return "GPU unknown";
  if (/A750/i.test(gpu)) return "Intel Arc A750";
  if (/1650/i.test(gpu)) return "NVIDIA GTX 1650";
  return gpu.length > 48 ? `${gpu.slice(0, 48)}…` : gpu;
}
