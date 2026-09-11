export function esc(s: unknown) {
  return String(s ?? "");
}

export function shortId(s: unknown, n = 12) {
  const v = String(s ?? "");
  return v ? v.slice(0, n) : "—";
}

export function variantLabel(id: unknown) {
  return String(id ?? "")
    .replace(/^candidate-/, "")
    .replace(/^parent-baseline-/, "") || "—";
}

export function fmtNum(v: unknown) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  if (!Number.isFinite(n)) return "—";
  return n.toLocaleString();
}

export function fmtPct(v: unknown, digits = 1) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  if (!Number.isFinite(n)) return "—";
  const sign = n > 0 ? "+" : "";
  return `${sign}${n.toFixed(digits)}%`;
}

export function fmtSats(v: unknown) {
  const n = Number(v ?? 0);
  if (!Number.isFinite(n)) return "—";
  return `${n.toLocaleString()} sats`;
}

export function fmtWhen(s: unknown) {
  if (!s) return "—";
  const d = new Date(String(s));
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function isoMs(value: unknown) {
  const t = Date.parse(String(value ?? ""));
  return Number.isFinite(t) ? t : 0;
}

export function statusTone(status: unknown): "good" | "warn" | "bad" | "info" {
  const s = String(status ?? "").toLowerCase();
  if (/complete|accepted|open|active|pass|confirmed/.test(s)) return "good";
  if (/fail|reject|cancel|ineligible|revoked|blocked|bad/.test(s)) return "bad";
  if (/claimed|running|queued|pending|await|local_sim|warn|inconclusive/.test(s))
    return "warn";
  return "info";
}

export function rewardLabel(value: unknown) {
  const sats = Number(value || 0);
  return sats > 0 ? `${fmtNum(sats)} placeholder sats` : "simulated reward only";
}

export function daysUntil(iso: string, now = Date.now()) {
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return null;
  return Math.round((t - now) / 86_400_000);
}
