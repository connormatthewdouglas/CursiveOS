import { createFileRoute, Link } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { PageHead } from "@/components/shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { Select } from "@/components/ui/input";
import { StatusPill } from "@/components/status-pill";
import { useCursive } from "@/lib/cursive/use-cursive";
import { fmtWhen, isoMs, variantLabel } from "@/lib/cursive/format";
import { availableLibrary, enqueueSigned, proposeNext, signProposal } from "@/lib/cursive/propose";
import { materializeProposal } from "@/lib/cursive/materialize";
import { machineDisplayName } from "@/lib/cursive/identity";
import { useOperator } from "@/lib/cursive/store";

export const Route = createFileRoute("/queue")({ component: QueuePage });

function download(name: string, body: string) {
  const blob = new Blob([body], { type: "text/plain" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}

function QueuePage() {
  const { snapshot, requests: allRequests, archive, elites } = useCursive();
  const localRequests = useOperator((s) => s.localRequests);
  const addRequest = useOperator((s) => s.addRequest);
  const addProposal = useOperator((s) => s.addProposal);
  const lastMaterial = useOperator((s) => s.lastMaterial);
  const setMaterial = useOperator((s) => s.setMaterial);
  const [attachSlug, setAttachSlug] = useState("");
  const [source, setSource] = useState<"qd" | "library">("qd");
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string[] | null>(null);

  const requests = useMemo(() => {
    const live = snapshot?.requests ?? [];
    return [...localRequests, ...live].sort(
      (a, b) => isoMs(b.updated_at || b.created_at) - isoMs(a.updated_at || a.created_at),
    );
  }, [snapshot, localRequests]);

  const jobs = snapshot?.jobs ?? [];
  const taken = allRequests.map((r) => r.candidate_variant_id);
  const leftovers = availableLibrary(taken);

  function onPropose() {
    setError(null);
    const proposal = proposeNext({
      parent_variant_id: "v0.12",
      taken,
      source,
      elites,
      opt_in_slug: attachSlug || undefined,
      cycle_id: 7,
    });
    addProposal(proposal);
    const parentCell = archive.parent_cell ?? elites[0]?.cell ?? null;
    const material = materializeProposal({
      proposal,
      parentCell,
      attachSlug: attachSlug || undefined,
      taken,
    });
    setMaterial(material);
    if (proposal.source === "refused") {
      setMsg(proposal.notes);
      return;
    }
    const signed = signProposal(proposal, { requested_by: "local-operator", key_status: "local_sim" });
    if (!material.files_ok) {
      setMsg(
        "Named the next experiment, but there is no reversible setting to attach yet. Files not written. Live ledger not touched.",
      );
      return;
    }
    const enq = enqueueSigned(signed, new Date().toISOString(), requests.map((r) => r.request_key));
    if (!enq.ok) {
      setError(enq.reasons);
      return;
    }
    addRequest(enq.request);
    setMsg("Drafted locally. Not sent to the live ledger. Download the script if you want a machine to run it.");
  }

  return (
    <div>
      <PageHead
        kicker="Work"
        title="What is being tested."
        lede="What the organism is testing, and what it already asked for. Drafts stay on this browser. The desktop loop writes results to the live ledger; this page does not."
      />

      <Card className="mb-4">
        <CardTitle>Ask for the next experiment</CardTitle>
        <CardHint>
          Default: pick the next unused reversible leftover. Retired experiments (page cluster, vfs cache) cannot
          come back. A leftover setting is optional.
        </CardHint>
        <div className="mt-4 flex flex-wrap items-end gap-3">
          <Select value={source} onChange={(e) => setSource(e.target.value as "qd" | "library")}>
            <option value="qd">From the living archive</option>
            <option value="library">From leftover settings (opt-in)</option>
          </Select>
          <Select value={attachSlug} onChange={(e) => setAttachSlug(e.target.value)}>
            <option value="">No extra setting</option>
            {leftovers.map((k) => (
              <option key={k.slug} value={k.slug}>
                {k.key}={k.value}
              </option>
            ))}
          </Select>
          <Button type="button" className="min-h-11" onClick={onPropose}>
            Draft next test
          </Button>
        </div>
        {msg ? <p className="mt-3 text-sm text-muted">{msg}</p> : null}
        {error ? (
          <ul className="mt-3 list-disc pl-5 text-sm text-warn">
            {error.map((r) => (
              <li key={r}>{r}</li>
            ))}
          </ul>
        ) : null}
        {lastMaterial ? (
          <div className="mt-4 rounded-lg border border-border bg-bg-elevated p-4">
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone={lastMaterial.files_ok ? "good" : "warn"}>
                {lastMaterial.files_ok ? "script ready" : "hypothesis only"}
              </Badge>
              <span className="font-mono text-sm">{lastMaterial.proposal.candidate_variant_id || "none"}</span>
            </div>
            <p className="mt-2 text-sm text-muted">{lastMaterial.proposal.notes}</p>
            {lastMaterial.files_ok ? (
              <div className="mt-3 flex flex-wrap gap-2">
                <Button
                  type="button"
                  size="sm"
                  className="min-h-11"
                  onClick={() =>
                    download(`${lastMaterial.proposal.candidate_variant_id}.json`, lastMaterial.variant_json)
                  }
                >
                  Download description
                </Button>
                {lastMaterial.preset_sh ? (
                  <Button
                    type="button"
                    variant="secondary"
                    size="sm"
                    className="min-h-11"
                    onClick={() =>
                      download(
                        `cursiveos-presets-${lastMaterial.proposal.candidate_variant_id}.sh`,
                        lastMaterial.preset_sh || "",
                      )
                    }
                  >
                    Download undoable script
                  </Button>
                ) : null}
              </div>
            ) : null}
          </div>
        ) : null}
        <p className="mt-4 text-sm text-muted">
          Want a person to join the fleet? That lives on{" "}
          <Link to="/join" className="underline">
            Join
          </Link>
          .
        </p>
      </Card>

      <Card className="overflow-hidden">
        <CardTitle>Queue</CardTitle>
        <CardHint>Live work plus anything drafted in this browser.</CardHint>
        <div className="mt-4 -mx-4 overflow-x-auto md:-mx-5">
          <table className="min-w-[640px] w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wider text-muted">
              <tr>
                <th className="px-5 py-2 font-medium">status</th>
                <th className="px-3 py-2 font-medium">candidate</th>
                <th className="px-3 py-2 font-medium">parent</th>
                <th className="px-5 py-2 text-right font-medium">updated</th>
              </tr>
            </thead>
            <tbody>
              {requests.length === 0 ? (
                <tr>
                  <td className="px-5 py-4 text-muted" colSpan={4}>
                    Nothing waiting. That is rest, not a crash.
                  </td>
                </tr>
              ) : (
                requests.map((r) => (
                  <tr key={r.request_id || r.request_key} className="border-t border-border">
                    <td className="px-5 py-2.5">
                      <StatusPill value={r.status} />
                    </td>
                    <td className="px-3 py-2.5">{variantLabel(r.candidate_variant_id)}</td>
                    <td className="px-3 py-2.5 text-muted">{r.parent_variant_id}</td>
                    <td className="px-5 py-2.5 text-right text-muted">{fmtWhen(r.updated_at || r.created_at)}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </Card>

      <Card className="mt-4 overflow-hidden">
        <CardTitle>Jobs on machines</CardTitle>
        <div className="mt-4 -mx-4 overflow-x-auto md:-mx-5">
          <table className="min-w-[640px] w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wider text-muted">
              <tr>
                <th className="px-5 py-2 font-medium">status</th>
                <th className="px-3 py-2 font-medium">machine</th>
                <th className="px-5 py-2 text-right font-medium">updated</th>
              </tr>
            </thead>
            <tbody>
              {jobs.length === 0 ? (
                <tr>
                  <td className="px-5 py-4 text-muted" colSpan={3}>
                    No machine is running a test right now.
                  </td>
                </tr>
              ) : (
                jobs.map((j) => (
                  <tr key={j.job_id} className="border-t border-border">
                    <td className="px-5 py-2.5">
                      <StatusPill value={j.status} />
                    </td>
                    <td className="px-3 py-2.5">{machineDisplayName(j.machine_id)}</td>
                    <td className="px-5 py-2.5 text-right text-muted">{fmtWhen(j.last_heartbeat_at || j.claimed_at)}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
