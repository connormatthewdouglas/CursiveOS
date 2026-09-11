import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { PageHead } from "@/components/shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { StatusPill } from "@/components/status-pill";
import { useCursive } from "@/lib/cursive/use-cursive";
import { fmtWhen, shortId, variantLabel } from "@/lib/cursive/format";
import {
  CANONICAL_LAPTOP,
  CANONICAL_STARDUST,
  independentConfirmations,
  machineDisplayName,
} from "@/lib/cursive/identity";
import { evaluateTrust, revokeKey, rotateKey, signatureAcceptable } from "@/lib/cursive/trust";
import { REQUIRED_ARTIFACT_KINDS, recomputeBundle, sha256Hex } from "@/lib/cursive/recompute";
import { useOperator } from "@/lib/cursive/store";
import type { IdentityKey } from "@/lib/cursive/types";

export const Route = createFileRoute("/trust")({ component: TrustPage });

function TrustPage() {
  const { snapshot, canon, physical, gates } = useCursive();
  const localKeys = useOperator((s) => s.localKeys);
  const setKeys = useOperator((s) => s.setKeys);
  const lastRecompute = useOperator((s) => s.lastRecompute);
  const setRecompute = useOperator((s) => s.setRecompute);
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (localKeys.length === 0 && snapshot?.identity_keys.length) {
      setKeys(snapshot.identity_keys);
    }
  }, [localKeys.length, snapshot, setKeys]);

  const keys = localKeys.length ? localKeys : (snapshot?.identity_keys ?? []);
  const trust = snapshot?.trust ?? [];

  const independence = useMemo(() => {
    const witnesses = (snapshot?.jobs ?? [])
      .filter((j) => j.status === "complete")
      .map((j) => {
        const key = keys.find((k) => k.machine_id === canon(j.machine_id));
        return {
          machine_id: j.machine_id,
          wallet: "local-founder",
          identity_public_key: key?.identity_public_key,
        };
      });
    return independentConfirmations(witnesses, snapshot?.aliases ?? [], physical.length);
  }, [snapshot, keys, canon, physical.length]);

  function rotate(machineId: string, oldKey: string) {
    const res = rotateKey(keys, machineId, oldKey, `ed25519-${machineId.slice(0, 6)}-${Date.now().toString(36)}`, new Date().toISOString());
    if (!res.ok) setMsg(res.reason);
    else {
      setKeys(res.keys);
      setMsg("Rotated locally. CursiveRoot is unchanged.");
    }
  }

  function revoke(publicKey: string) {
    const res = revokeKey(keys, publicKey, new Date().toISOString());
    if (!res.ok) setMsg(res.reason);
    else {
      setKeys(res.keys);
      setMsg("Revoked locally. Production still needs a CursiveRoot policy.");
    }
  }

  const demoEval = evaluateTrust({
    recompute_ok: true,
    signed_identity_ok: true,
    replay_ok: true,
    independent_aggregation_ok: false,
    key_status: keys[0]?.key_status ?? "local_sim",
    trust_scope: "simulated_not_payout_eligible",
    linux_bare_metal: true,
    hardware_wallet_independent: independence.ok,
    key_not_revoked: true,
  });

  async function runRecompute(withPayloads: boolean) {
    setBusy(true);
    try {
      const row = trust[0];
      const witnesses = (snapshot?.jobs ?? [])
        .filter((j) => j.status === "complete")
        .slice(0, 3)
        .map((j, i) => ({
          machine_id: j.machine_id,
          wallet: i === 0 ? "local-founder" : `wallet-${i}`,
          identity_public_key: `key-${j.machine_id}`,
        }));
      const artifacts = [];
      for (const kind of REQUIRED_ARTIFACT_KINDS) {
        const payload = withPayloads ? `${kind}:${row?.bundle_hash ?? "empty"}` : null;
        const sha256 = payload ? await sha256Hex(payload) : "unhashed";
        artifacts.push({
          kind,
          sha256,
          bytes: payload?.length ?? 0,
          payload,
          claimed_digest: sha256,
        });
      }
      let bundle_hash = row?.bundle_hash ?? "missing";
      if (withPayloads) {
        const parts = [];
        for (const a of artifacts) {
          if (a.payload) parts.push(`${a.kind}:${a.sha256}`);
        }
        bundle_hash = await sha256Hex(parts.sort().join("|"));
      }
      const report = await recomputeBundle({
        bundle_hash,
        variant_id: row?.variant_id ?? "unknown",
        parent_variant_id: "v0.12",
        candidate_variant_id: row?.variant_id ?? "unknown",
        claimed_metrics: { coldstart_pct: -1 },
        expected_channels: ["coldstart_pct"],
        artifacts,
        witnesses,
        aliases: snapshot?.aliases ?? [],
        fleet_size: physical.length,
      });
      setRecompute(report);
    } finally {
      setBusy(false);
    }
  }

  async function runLiveArtifacts() {
    setBusy(true);
    try {
      const arts = snapshot?.artifacts ?? [];
      const row = trust[0];
      const artifacts = arts.map((a) => ({
        kind: a.artifact_kind,
        sha256: a.artifact_sha256 || "missing",
        bytes: 0,
        payload: null,
        claimed_digest: a.artifact_sha256,
      }));
      const report = await recomputeBundle({
        bundle_hash: arts[0]?.bundle_hash || row?.bundle_hash || "",
        variant_id: arts[0]?.variant_id || row?.variant_id || "unknown",
        parent_variant_id: "v0.12",
        candidate_variant_id: arts[0]?.variant_id || row?.variant_id || "unknown",
        claimed_metrics: {},
        expected_channels: ["coldstart_pct", "memory_refault_s"],
        artifacts,
        witnesses: [],
        aliases: snapshot?.aliases ?? [],
        fleet_size: physical.length,
        replay_index: (snapshot?.trust ?? []).map((t) => ({
          bundle_hash: t.bundle_hash,
          artifact_sha256s: arts
            .filter((a) => a.bundle_hash === t.bundle_hash)
            .map((a) => a.artifact_sha256 || ""),
        })),
      });
      setRecompute(report);
      setMsg(
        artifacts.length
          ? "Live index has hashes, not payloads. Fail-closed is the correct origin answer."
          : "No artifact index rows on this snapshot.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <PageHead
        kicker="G4"
        title="Trust spine"
        lede="Every uploaded bundle writes identity, raw-artifact, and evaluation rows. payout_eligible is check-constrained false until origin-side recompute, independence, and key policy exist."
      />

      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-5">
        <Mini label="recompute" value={`${gates.recompute}/${gates.total}`} />
        <Mini label="signed identity" value={`${gates.signed_identity}/${gates.total}`} />
        <Mini label="replay" value={`${gates.replay}/${gates.total}`} />
        <Mini label="aggregation" value={`${gates.independent_aggregation}/${gates.total}`} />
        <Mini label="payout true" value={`${gates.payout_true}/${gates.total}`} />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardTitle>Evaluations</CardTitle>
          <CardHint>Live CursiveRoot rows. Independent aggregation is the blocking gate on every recent screen.</CardHint>
          <div className="mt-4 space-y-3">
            {trust.map((t) => (
              <article key={t.bundle_hash} className="rounded-lg border border-border bg-bg-elevated p-3">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <div className="font-medium">{variantLabel(t.variant_id)}</div>
                    <div className="font-mono text-xs text-muted">
                      {shortId(t.bundle_hash, 16)} · {machineDisplayName(canon(t.machine_id))}
                    </div>
                  </div>
                  <StatusPill value={t.gate_status} />
                </div>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  <Check ok={t.recompute_ok} label="recompute" />
                  <Check ok={t.signed_identity_ok} label="signed identity" />
                  <Check ok={t.replay_ok} label="replay" />
                  <Check ok={t.independent_aggregation_ok} label="aggregation" />
                  <Check ok={t.selection_truth_eligible} label="selection-truth" />
                  <Badge tone="warn">payout hard-false</Badge>
                </div>
                <p className="mt-2 font-mono text-xs text-muted">
                  {t.decision} · {fmtWhen(t.evaluated_at)}
                </p>
                {t.reasons?.length ? (
                  <p className="mt-1 text-xs text-warn">{t.reasons.slice(0, 2).join(" · ")}</p>
                ) : null}
              </article>
            ))}
          </div>
        </Card>

        <div className="space-y-4">
          <Card>
            <CardTitle>Origin-side recompute</CardTitle>
            <CardHint>
              Live CursiveRoot stores caller-attested hashes. Without immutable payloads this engine fails
              closed — that is the hole. Synthetic payloads prove the hash path; they still cannot pay.
            </CardHint>
            <div className="mt-3 flex flex-wrap gap-2">
              <Button size="sm" variant="secondary" disabled={busy} onClick={() => runRecompute(false)}>
                Recompute as origin sees it
              </Button>
              <Button size="sm" variant="secondary" disabled={busy} onClick={() => runRecompute(true)}>
                Recompute with synthetic payloads
              </Button>
              <Button size="sm" variant="secondary" disabled={busy} onClick={() => runLiveArtifacts()}>
                Recompute live artifact index
              </Button>
            </div>
            {lastRecompute ? (
              <div className="mt-3">
                <p className="font-mono text-sm">{lastRecompute.reasons[0] ?? "hashed"}</p>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  <Check ok={lastRecompute.recompute_ok} label="recompute" />
                  <Check ok={lastRecompute.replay_ok} label="replay" />
                  <Check ok={lastRecompute.independent_aggregation_ok} label="aggregation" />
                  <Badge tone="warn">payout {String(lastRecompute.payout_eligible)}</Badge>
                </div>
                <p className="mt-2 font-mono text-xs text-muted">
                  independent {lastRecompute.independent_count}/{lastRecompute.required} ·{" "}
                  {lastRecompute.reasons.join(" · ") || "clean"}
                </p>
              </div>
            ) : null}
          </Card>

          <Card>
            <CardTitle>Identity keys</CardTitle>
            <CardHint>
              Rotation and revocation run in this console only. Production still shows local-sim keys.
            </CardHint>
            {msg ? <p className="mt-2 text-sm text-warn">{msg}</p> : null}
            <div className="mt-3 space-y-3">
              {keys.map((k) => (
                <KeyRow key={k.identity_public_key} k={k} onRotate={rotate} onRevoke={revoke} />
              ))}
            </div>
          </Card>

          <Card>
            <CardTitle>Hardware / wallet independence</CardTitle>
            <CardHint>
              Required confirmations N = max(1, min(5, floor(sqrt(fleet)))). Same physical host, wallet, or
              key does not count twice.
            </CardHint>
            <p className="mt-3 font-mono text-sm">
              independent {independence.independent_count} / required {independence.required}{" "}
              <Badge tone={independence.ok ? "good" : "warn"}>{independence.ok ? "meets N" : "short"}</Badge>
            </p>
            <ul className="mt-2 space-y-1 text-sm text-muted">
              {independence.rejected.slice(0, 6).map((r, i) => (
                <li key={i} className="font-mono text-xs">
                  {r.reason} · {machineDisplayName(r.witness.machine_id)}
                </li>
              ))}
            </ul>
            <p className="mt-3 text-sm text-muted">
              Founder fleet today: {machineDisplayName(CANONICAL_LAPTOP)} and{" "}
              {machineDisplayName(CANONICAL_STARDUST)}. Both jobs in cycle 5 used the founder wallet, so
              they are not independent for money.
            </p>
          </Card>

          <Card>
            <CardTitle>What a live bundle evaluates to here</CardTitle>
            <p className="mt-2 font-mono text-sm">{demoEval.gate_status}</p>
            <p className="mt-1 text-sm text-muted">
              selection-truth {String(demoEval.selection_truth_eligible)} · payout{" "}
              {String(demoEval.payout_eligible)}
            </p>
            <p className="mt-2 font-mono text-xs text-muted">{demoEval.reasons.join(" · ") || "no reasons"}</p>
          </Card>
        </div>
      </div>
    </div>
  );
}

function Mini({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-border bg-surface p-3">
      <div className="text-xs uppercase tracking-wider text-muted">{label}</div>
      <div className="mt-1 font-mono text-xl tabular-nums">{value}</div>
    </div>
  );
}

function Check({ ok, label }: { ok: boolean | null | undefined; label: string }) {
  const tone = ok === true ? "good" : ok === false ? "bad" : "warn";
  const mark = ok === true ? "pass" : ok === false ? "fail" : "n/a";
  return (
    <Badge tone={tone}>
      {mark} {label}
    </Badge>
  );
}

function KeyRow({
  k,
  onRotate,
  onRevoke,
}: {
  k: IdentityKey;
  onRotate: (machineId: string, oldKey: string) => void;
  onRevoke: (publicKey: string) => void;
}) {
  const signable = signatureAcceptable(k);
  return (
    <article className="rounded-lg border border-border bg-bg-elevated p-3">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="font-mono text-xs">{shortId(k.identity_public_key, 28)}</div>
          <div className="mt-1 text-sm text-muted">{machineDisplayName(k.machine_id)}</div>
        </div>
        <StatusPill value={k.key_status} />
      </div>
      <p className="mt-2 font-mono text-xs text-muted">
        {k.key_scheme} · signable {String(signable)}
      </p>
      <div className="mt-3 flex flex-wrap gap-2">
        <Button size="sm" variant="secondary" onClick={() => onRotate(k.machine_id, k.identity_public_key)}>
          Rotate
        </Button>
        <Button size="sm" variant="danger" onClick={() => onRevoke(k.identity_public_key)}>
          Revoke
        </Button>
      </div>
    </article>
  );
}
