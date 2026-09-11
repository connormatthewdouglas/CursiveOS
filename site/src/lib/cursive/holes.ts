/**
 * Live CursiveRoot RLS holes, named so they cannot be forgotten.
 * Catalog only — this file does not apply SQL.
 */

export type RlsHole = {
  table: string;
  action: "insert" | "update" | "select";
  clause: string;
  severity: "open" | "contained";
  note: string;
};

export const LIVE_RLS_HOLES: RlsHole[] = [
  {
    table: "machine_capabilities",
    action: "update",
    clause: "USING (true) WITH CHECK (true)",
    severity: "open",
    note: "Any anon client can heartbeat-spoof Stardust from the laptop.",
  },
  {
    table: "measurement_jobs",
    action: "update",
    clause: "USING (true) WITH CHECK (true)",
    severity: "open",
    note: "Cross-machine job mutation. Identity-gated policy is the close.",
  },
  {
    table: "machine_capabilities",
    action: "insert",
    clause: "WITH CHECK (true)",
    severity: "open",
    note: "Anon insert of capability rows.",
  },
  {
    table: "measurement_jobs",
    action: "insert",
    clause: "WITH CHECK (true)",
    severity: "open",
    note: "Anon insert of jobs.",
  },
  {
    table: "seed_bundles",
    action: "insert",
    clause: "WITH CHECK (true)",
    severity: "open",
    note: "Uploads are open. Trust spine must reject unverified evidence — it does.",
  },
  {
    table: "os0_raw_artifact_index",
    action: "insert",
    clause: "WITH CHECK (true)",
    severity: "open",
    note: "Caller-attested hashes. Origin recompute is the close.",
  },
  {
    table: "measurement_requests",
    action: "update",
    clause: "status + updated_at only, scoped trust/selection",
    severity: "contained",
    note: "Anon cannot invent work. Body mutations are denied.",
  },
];

export function openWriteHoles() {
  return LIVE_RLS_HOLES.filter((h) => h.severity === "open" && h.action !== "select");
}
