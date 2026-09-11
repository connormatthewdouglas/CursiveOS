import { createFileRoute } from "@tanstack/react-router";
import { PageHead, Stat } from "@/components/shell";
import { Badge } from "@/components/ui/badge";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { useCursive } from "@/lib/cursive/use-cursive";
import { fmtWhen, shortId } from "@/lib/cursive/format";
import {
  confirmationThreshold,
  fingerprintCount,
  HISTORICAL_FX_STARDUST,
  machineDisplayName,
} from "@/lib/cursive/identity";

export const Route = createFileRoute("/fleet")({ component: FleetPage });

function FleetPage() {
  const { snapshot, physical, caps } = useCursive();
  const aliases = snapshot?.aliases ?? [];
  const n = confirmationThreshold(physical.length);

  return (
    <div>
      <PageHead
        kicker="Machines"
        title="The fleet."
        lede="Real computers the organism has met. Names are collapsed so the same laptop does not count as five machines."
      />

      <div className="mb-6 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="physical" value={physical.length} hint="alias rows excluded" />
        <Stat label="fingerprints" value={aliases.length + physical.length} hint="canonical + aliases" />
        <Stat label="confirmation N" value={n} hint="max(1, min(5, floor(sqrt(fleet))))" />
        <Stat label="daemons seen" value={caps.length} hint="collapsed heartbeats" />
      </div>

      <Card className="overflow-hidden">
        <CardTitle>Physical machines</CardTitle>
        <div className="mt-4 -mx-4 overflow-x-auto md:-mx-5">
          <table className="min-w-[720px] w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wider text-muted">
              <tr>
                <th className="px-5 py-2 font-medium">host</th>
                <th className="px-3 py-2 font-medium">machine id</th>
                <th className="px-3 py-2 font-medium">CPU</th>
                <th className="px-3 py-2 font-medium">GPU</th>
                <th className="px-5 py-2 text-right font-medium">fingerprints</th>
              </tr>
            </thead>
            <tbody>
              {physical.map((m) => (
                <tr key={m.machine_id} className="border-t border-border">
                  <td className="px-5 py-2.5">
                    {machineDisplayName(m.machine_id)}
                    {m.machine_id === HISTORICAL_FX_STARDUST ? (
                      <span className="ml-2">
                        <Badge tone="warn">do not collapse</Badge>
                      </span>
                    ) : null}
                  </td>
                  <td className="px-3 py-2.5 font-mono text-xs">{shortId(m.machine_id, 16)}</td>
                  <td className="px-3 py-2.5 text-muted">{m.cpu}</td>
                  <td className="px-3 py-2.5 text-muted">{m.gpu}</td>
                  <td className="px-5 py-2.5 text-right font-mono tabular-nums">
                    {fingerprintCount(m.machine_id, aliases)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardTitle>Aliases</CardTitle>
          <CardHint>Legacy slugs, v1 hashes, rebuild fingerprints, and the no-newline daemon bug.</CardHint>
          <ul className="mt-3 space-y-2">
            {aliases.map((a) => (
              <li key={a.alias} className="flex items-start justify-between gap-3 text-sm">
                <span className="font-mono text-xs text-muted">{shortId(a.alias, 18)}</span>
                <span className="text-right">
                  <span className="block">{machineDisplayName(a.machine_id)}</span>
                  <span className="text-xs text-muted">{a.alias_kind}</span>
                </span>
              </li>
            ))}
          </ul>
        </Card>
        <Card>
          <CardTitle>Daemon heartbeats</CardTitle>
          <CardHint>Last seen July 7 on founder rigs. Stale is the current honesty, not a render bug.</CardHint>
          <div className="mt-3 space-y-3">
            {caps.map((c) => (
              <article key={c.canonical_machine_id} className="rounded-lg border border-border bg-bg-elevated p-3">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <div className="font-medium">{machineDisplayName(c.canonical_machine_id)}</div>
                    <div className="text-sm text-muted">{c.os_name || c.platform}</div>
                  </div>
                  <Badge tone="info">{c.daemon_version || "daemon"}</Badge>
                </div>
                <p className="mt-2 text-sm text-muted">{c.cpu}</p>
                <p className="mt-1 font-mono text-xs text-muted">last seen {fmtWhen(c.last_seen_at)}</p>
              </article>
            ))}
          </div>
        </Card>
      </div>
    </div>
  );
}
