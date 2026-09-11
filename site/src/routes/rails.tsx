import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { PageHead, Stat } from "@/components/shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { Input, Label, Select } from "@/components/ui/input";
import { StatusPill } from "@/components/status-pill";
import { useCursive } from "@/lib/cursive/use-cursive";
import { closeCycle, GENESIS_SPLIT_CURRENT, usdToSats } from "@/lib/cursive/economics";
import { claimAccrual, isBech32Address, railLabel, simulateConfirm } from "@/lib/cursive/rails";
import { closeIntoLedger } from "@/lib/cursive/ledger";
import { buildPsbtIntent } from "@/lib/cursive/psbt";
import { inspectHubSurface } from "@/lib/cursive/hub";
import { fmtNum, fmtSats, fmtWhen } from "@/lib/cursive/format";
import { useOperator } from "@/lib/cursive/store";
import type { RailMode } from "@/lib/cursive/types";

export const Route = createFileRoute("/rails")({ component: RailsPage });

function RailsPage() {
  const { snapshot } = useCursive();
  const policy = useOperator((s) => s.policy);
  const setPolicy = useOperator((s) => s.setPolicy);
  const setRailMode = useOperator((s) => s.setRailMode);
  const founderWallet = useOperator((s) => s.founderWallet);
  const setWallet = useOperator((s) => s.setWallet);
  const splitCurrent = useOperator((s) => s.splitCurrent);
  const setSplit = useOperator((s) => s.setSplit);
  const accruals = useOperator((s) => s.accruals);
  const addAccruals = useOperator((s) => s.addAccruals);
  const markClaimed = useOperator((s) => s.markClaimed);
  const transfers = useOperator((s) => s.transfers);
  const addTransfer = useOperator((s) => s.addTransfer);
  const updateTransfer = useOperator((s) => s.updateTransfer);
  const ledger = useOperator((s) => s.ledger);
  const setLedger = useOperator((s) => s.setLedger);
  const lastPsbt = useOperator((s) => s.lastPsbt);
  const setPsbt = useOperator((s) => s.setPsbt);
  const [fastUsers, setFastUsers] = useState(12);
  const [btcUsd, setBtcUsd] = useState(100_000);
  const [flash, setFlash] = useState<string | null>(null);

  const accepted = snapshot?.accepted ?? [];
  const lifetimeFitness = accepted.reduce((s, a) => s + Number(a.fitness_score ?? 0), 0);
  const lastFitness = Number(accepted[0]?.fitness_score ?? 0);
  const revenue = usdToSats(fastUsers * 2, btcUsd);
  const hub = inspectHubSurface({ path: "/hub/rewards/ledger", body: { pool: true, governance: true } });

  const preview = useMemo(
    () =>
      closeCycle({
        cycle_id: 7,
        revenue_sats: revenue,
        split_current: splitCurrent,
        merges: lastFitness
          ? [
              {
                contributor_wallet: founderWallet,
                variant_id: accepted[0]?.variant_id ?? "next",
                fitness_delta: lastFitness,
                prior_merge_count: accepted.length,
              },
            ]
          : [],
        lifetime: lifetimeFitness
          ? [{ contributor_wallet: founderWallet, fitness: lifetimeFitness - lastFitness }]
          : [],
        now_iso: new Date().toISOString(),
      }),
    [revenue, splitCurrent, lastFitness, lifetimeFitness, founderWallet, accepted],
  );

  const spent = transfers
    .filter((t) => t.tx_status !== "failed" && t.tx_status !== "blocked")
    .reduce((s, t) => s + t.amount_sats, 0);

  function runClose() {
    const merges = lastFitness
      ? [
          {
            contributor_wallet: founderWallet,
            variant_id: accepted[0]?.variant_id ?? "next",
            fitness_delta: lastFitness,
            prior_merge_count: accepted.length,
          },
        ]
      : [];
    const { ledger: next, closed } = closeIntoLedger(
      ledger,
      {
        cycle_id: 7,
        revenue_sats: revenue,
        split_current: splitCurrent,
        merges,
        lifetime: [],
        now_iso: new Date().toISOString(),
      },
      merges.map((m) => ({
        contributor_wallet: m.contributor_wallet,
        variant_id: m.variant_id,
        fitness_delta: m.fitness_delta,
      })),
      [{ wallet: "bc1qtesterplaceholder000000000000000000000", would_have_paid_usd: 2 }],
      btcUsd,
    );
    setLedger(next);
    addAccruals(closed.accruals);
    setSplit(closed.next_split_current);
    setFlash(
      `Cycle closed into v3.3 ledger: ${fmtSats(closed.revenue_sats)} · testers rebated, no fitness. Rail did not move Bitcoin.`,
    );
  }

  function claim(id: string) {
    const accrual = accruals.find((a) => a.accrual_id === id);
    if (!accrual) return;
    const res = claimAccrual({
      accrual,
      destination_wallet: founderWallet,
      now_iso: new Date().toISOString(),
      policy,
      spent_this_cycle_sats: spent,
    });
    if (!res.ok) {
      setFlash(res.message);
      return;
    }
    addTransfer(res.intent);
    const psbt = buildPsbtIntent({
      accrual,
      destination: founderWallet,
      policy,
      now_iso: new Date().toISOString(),
    });
    if (psbt.ok) setPsbt(psbt.intent);
    else setPsbt(null);
    if (res.intent.tx_status === "queued") {
      const confirmed = simulateConfirm(res.intent, new Date().toISOString());
      updateTransfer(res.intent.payout_id, confirmed);
      markClaimed(accrual.accrual_id, confirmed.created_at, confirmed.tx_hash);
      setFlash(`Claim ${confirmed.tx_status}. Hash ${confirmed.tx_hash ?? "none"}.`);
    } else {
      setFlash(res.intent.blocked_reason ?? "blocked");
    }
  }

  const chart = [
    { name: "current", sats: preview.current_stream_sats },
    { name: "lifetime", sats: preview.lifetime_stream_sats },
  ];

  return (
    <div>
      <PageHead
        kicker="v3.3 · engine ≠ rail"
        title="Bitcoin rails"
        lede="The decision engine decides who earned what. The rail decides how value moves. Signing keys never live in the browser. Mainnet is hard-gated until the trust spine is production-ready."
      />

      <div className="mb-4 flex flex-wrap gap-2">
        <Badge tone="warn">rail: {railLabel(policy.rail_mode)}</Badge>
        <Badge tone={policy.paused ? "bad" : "good"}>{policy.paused ? "paused" : "rail live (sim)"}</Badge>
        <Badge tone="warn">payout_eligible_production = false</Badge>
        <Badge tone={hub.allowed ? "good" : "bad"}>v3.1 hub {hub.allowed ? "clear" : "frozen"}</Badge>
      </div>

      <div className="mb-6 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="Fast users" value={fastUsers} hint="$2 / month each" />
        <Stat label="cycle revenue" value={fmtNum(revenue)} hint="sats at posted BTC price" />
        <Stat label="s_current" value={`${(splitCurrent * 100).toFixed(1)}%`} hint="genesis 20%" />
        <Stat label="ledger cycles" value={ledger.cycles.length} hint="v3.3 tables, local" />
      </div>

      <div className="grid gap-4 lg:grid-cols-[1.1fr_.9fr]">
        <Card>
          <CardTitle>Cycle close engine</CardTitle>
          <CardHint>
            Testers never enter this math. Fast-tier revenue splits by the metabolic sensor. Zero
            revenue produces zero accruals.
          </CardHint>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <div>
              <Label htmlFor="fast">Fast-tier users</Label>
              <Input
                id="fast"
                type="number"
                min={0}
                value={fastUsers}
                onChange={(e) => setFastUsers(Number(e.target.value))}
              />
            </div>
            <div>
              <Label htmlFor="btc">BTC price USD</Label>
              <Input
                id="btc"
                type="number"
                min={1}
                value={btcUsd}
                onChange={(e) => setBtcUsd(Number(e.target.value))}
              />
            </div>
          </div>
          <div className="mt-4 space-y-3">
            {chart.map((row) => {
              const max = Math.max(preview.current_stream_sats, preview.lifetime_stream_sats, 1);
              const pct = Math.round((row.sats / max) * 100);
              return (
                <div key={row.name}>
                  <div className="mb-1 flex justify-between text-xs text-muted">
                    <span>{row.name}</span>
                    <span className="font-mono tabular-nums">{fmtSats(row.sats)}</span>
                  </div>
                  <div className="h-2 overflow-hidden rounded-full bg-bg-elevated">
                    <div className="h-full bg-accent" style={{ width: `${pct}%` }} />
                  </div>
                </div>
              );
            })}
          </div>
          <dl className="mt-3 grid grid-cols-2 gap-2 text-sm">
            <div>
              <dt className="text-muted">current stream</dt>
              <dd className="font-mono tabular-nums">{fmtSats(preview.current_stream_sats)}</dd>
            </div>
            <div>
              <dt className="text-muted">lifetime stream</dt>
              <dd className="font-mono tabular-nums">{fmtSats(preview.lifetime_stream_sats)}</dd>
            </div>
            <div>
              <dt className="text-muted">next split</dt>
              <dd className="font-mono tabular-nums">
                {(preview.next_split_current * 100).toFixed(2)} /{" "}
                {(preview.next_split_lifetime * 100).toFixed(2)}
              </dd>
            </div>
            <div>
              <dt className="text-muted">R_meta</dt>
              <dd className="font-mono tabular-nums">
                {preview.r_meta == null
                  ? "n/a"
                  : Number.isFinite(preview.r_meta)
                    ? preview.r_meta.toFixed(3)
                    : "∞ (new-only)"}
              </dd>
            </div>
          </dl>
          <Button className="mt-4" onClick={runClose}>
            Close cycle into ledger
          </Button>
        </Card>

        <Card>
          <CardTitle>Rail controls</CardTitle>
          <CardHint>Switchable rails from the 2026-04-03 architecture note, wired to v3.3 rules.</CardHint>
          <div className="mt-4 space-y-3">
            <div>
              <Label htmlFor="mode">Rail mode</Label>
              <Select
                id="mode"
                value={policy.rail_mode}
                onChange={(e) => setRailMode(e.target.value as RailMode)}
              >
                <option value="internal_credits">internal_credits</option>
                <option value="crypto_testnet">crypto_testnet</option>
                <option value="crypto_mainnet">crypto_mainnet (hard-gated)</option>
              </Select>
            </div>
            <div>
              <Label htmlFor="wallet">Bound contributor wallet</Label>
              <Input id="wallet" value={founderWallet} onChange={(e) => setWallet(e.target.value)} />
              <p className="mt-1 text-xs text-muted">
                {isBech32Address(founderWallet, "main")
                  ? "bech32 mainnet shape ok"
                  : "not a mainnet bech32 address — internal credits still work"}
              </p>
            </div>
            <div>
              <Label htmlFor="cap">Per-cycle cap (sats)</Label>
              <Input
                id="cap"
                type="number"
                value={policy.per_cycle_cap_sats}
                onChange={(e) => setPolicy({ per_cycle_cap_sats: Number(e.target.value) })}
              />
            </div>
            <Button
              variant={policy.paused ? "primary" : "danger"}
              onClick={() => setPolicy({ paused: !policy.paused })}
            >
              {policy.paused ? "Lift emergency pause" : "Engage emergency pause"}
            </Button>
            <p className="text-sm text-muted">
              Genesis split {GENESIS_SPLIT_CURRENT * 100}/{100 - GENESIS_SPLIT_CURRENT * 100}. No pool, no
              token, no founder cut. Founder is paid as a standard contributor.
            </p>
            <p className="font-mono text-xs text-bad">{hub.reasons.join(" · ")}</p>
          </div>
        </Card>
      </div>

      {flash ? (
        <p className="mt-4 rounded-xl border border-border bg-surface px-4 py-3 text-sm">{flash}</p>
      ) : null}

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardTitle>Accruals</CardTitle>
          <CardHint>Unclaimed rows sit in the two-year window, then redistribute to active claimants.</CardHint>
          <div className="mt-3 space-y-2">
            {accruals.length === 0 ? (
              <p className="text-sm text-muted">Close a cycle to mint simulated accruals.</p>
            ) : (
              accruals.map((a) => (
                <article
                  key={a.accrual_id}
                  className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-border bg-bg-elevated p-3"
                >
                  <div>
                    <div className="font-mono text-sm tabular-nums">{fmtSats(a.amount_sats)}</div>
                    <div className="text-xs text-muted">
                      {a.stream_type} · deadline {fmtWhen(a.claim_deadline)}
                    </div>
                  </div>
                  {a.claimed_at ? (
                    <Badge tone="good">claimed</Badge>
                  ) : (
                    <Button size="sm" variant="secondary" onClick={() => claim(a.accrual_id)}>
                      Claim
                    </Button>
                  )}
                </article>
              ))
            )}
          </div>
        </Card>
        <Card>
          <CardTitle>Transfer intents</CardTitle>
          <CardHint>Queued / blocked / confirmed. Mainnet never fabricates a tx hash.</CardHint>
          <div className="mt-3 space-y-2">
            {transfers.length === 0 ? (
              <p className="text-sm text-muted">No rail intents yet.</p>
            ) : (
              transfers.map((t) => (
                <article key={t.payout_id} className="rounded-lg border border-border bg-bg-elevated p-3">
                  <div className="flex items-start justify-between gap-2">
                    <div className="font-mono text-sm tabular-nums">{fmtSats(t.amount_sats)}</div>
                    <StatusPill value={t.tx_status} />
                  </div>
                  <p className="mt-1 font-mono text-xs text-muted">
                    {railLabel(t.rail_mode)} · {t.tx_hash ?? t.blocked_reason ?? "queued"}
                  </p>
                </article>
              ))
            )}
          </div>
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardTitle>v3.3 ledger</CardTitle>
          <CardHint>l5_cycles, l5_lifetime_fitness, l5_tester_rebates — local rehearsal of the missing schema.</CardHint>
          {ledger.cycles.length === 0 ? (
            <p className="mt-3 text-sm text-muted">No closed cycles in this console yet.</p>
          ) : (
            <ul className="mt-3 space-y-2">
              {ledger.cycles.map((c) => (
                <li key={c.cycle_id} className="rounded-lg border border-border bg-bg-elevated p-3 text-sm">
                  <div className="flex justify-between gap-2">
                    <span>cycle {c.cycle_id}</span>
                    <Badge tone="info">{c.status}</Badge>
                  </div>
                  <p className="mt-1 font-mono text-xs text-muted">
                    {fmtSats(c.revenue_sats)} · s_current {(c.split_current * 100).toFixed(1)}% · fitness
                    rows {ledger.lifetime.length} · rebates {ledger.rebates.length}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card>
          <CardTitle>Unsigned PSBT intent</CardTitle>
          <CardHint>Claiming builds an intent document. The organism settlement key is not here. Nothing is broadcastable.</CardHint>
          {lastPsbt ? (
            <pre className="mt-3 overflow-x-auto rounded-md bg-bg-elevated p-3 font-mono text-[11px] leading-5 text-muted">
              {JSON.stringify(lastPsbt, null, 2)}
            </pre>
          ) : (
            <p className="mt-3 text-sm text-muted">Claim an accrual to mint an unsigned intent.</p>
          )}
        </Card>
      </div>
    </div>
  );
}
