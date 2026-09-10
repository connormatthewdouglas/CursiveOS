import { isoMs } from "./format.ts";
import type { MachineCapability, MeasurementJob, MeasurementRequest } from "./types.ts";

/** Selection-loop watchdog. Honest idle is a state, not a green dashboard. */

export const HEARTBEAT_STALE_MS = 24 * 60 * 60 * 1000;

export type LoopState = "running" | "queued" | "idle" | "stale" | "blocked";

export type LoopStep = {
  id: string;
  title: string;
  owner: string;
  ready: boolean;
  note: string;
};

export type LoopReport = {
  state: LoopState;
  open_requests: number;
  active_jobs: number;
  last_heartbeat_at: string | null;
  heartbeat_age_hours: number | null;
  reasons: string[];
  playbook: LoopStep[];
};

export function loopStatus(input: {
  requests: MeasurementRequest[];
  jobs: MeasurementJob[];
  capabilities: MachineCapability[];
  now_iso: string;
  independent_aggregation_ok: boolean;
}): LoopReport {
  const now = Date.parse(input.now_iso);
  const open = input.requests.filter((r) => r.status === "open");
  const active = input.jobs.filter((j) => j.status === "claimed" || j.status === "running");
  const beats = input.capabilities
    .map((c) => c.last_seen_at)
    .filter(Boolean)
    .sort((a, b) => isoMs(b) - isoMs(a));
  const last = beats[0] ?? null;
  const age = last ? now - isoMs(last) : null;
  const stale = age == null || age > HEARTBEAT_STALE_MS;

  const reasons: string[] = [];
  if (open.length === 0) reasons.push("queue_empty");
  if (active.length === 0) reasons.push("no_active_jobs");
  if (stale) reasons.push("daemon_heartbeat_stale");
  if (!input.independent_aggregation_ok) reasons.push("trust_awaiting_independent_aggregation");

  let state: LoopState = "idle";
  if (active.length > 0 && !stale) state = "running";
  else if (open.length > 0 && !stale) state = "queued";
  else if (stale) state = "stale";
  else if (!input.independent_aggregation_ok) state = "blocked";

  const playbook: LoopStep[] = [
    {
      id: "wake-daemons",
      title: "Wake founder daemons",
      owner: "operator on laptop + Stardust",
      ready: !stale,
      note: stale
        ? "Heartbeats last landed in July. git pull on both rigs, start contributor_daemon.py."
        : "Daemons are fresh.",
    },
    {
      id: "propose",
      title: "Propose from QD, not vfs cousins",
      owner: "organism_proposer / this console",
      ready: false,
      note: "Default source is the QD archive. Library leftovers are operator opt-in.",
    },
    {
      id: "enqueue",
      title: "Privileged enqueue",
      owner: "signed proposer or founder SQL",
      ready: open.length > 0,
      note: open.length ? "Open work exists." : "No open request. Draft locally; do not POST to CursiveRoot from here.",
    },
    {
      id: "screen",
      title: "Daemon claim + screen",
      owner: "contributor_daemon.py",
      ready: active.length > 0,
      note: "Linux bare-metal only. Windows/WSL is observe-only.",
    },
    {
      id: "aggregate",
      title: "Origin-side recompute",
      owner: "CursiveRoot origin",
      ready: input.independent_aggregation_ok,
      note: "Still the hard gate. This console can recompute when payloads are present.",
    },
  ];

  return {
    state,
    open_requests: open.length,
    active_jobs: active.length,
    last_heartbeat_at: last,
    heartbeat_age_hours: age == null ? null : Math.round((age / 36e5) * 10) / 10,
    reasons,
    playbook,
  };
}

export function loopLabel(state: LoopState) {
  if (state === "running") return "loop running";
  if (state === "queued") return "queued, waiting for claim";
  if (state === "stale") return "daemons stale";
  if (state === "blocked") return "blocked on trust";
  return "selection loop idle";
}
