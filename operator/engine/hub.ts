/** Freeze the v3.1 hub-api so it cannot be mistaken for v3.3 economics. */

export const HUB_API_STATUS = "frozen-v3.1-scaffolding" as const;

export const V31_FORBIDDEN = [
  "pool",
  "governance",
  "validators",
  "babylon",
  "staking",
  "yield",
  "vote",
  "appeal",
] as const;

export type HubCheck = {
  frozen: boolean;
  allowed: boolean;
  reasons: string[];
};

export function inspectHubSurface(input: { path?: string; body?: unknown; notes?: string }): HubCheck {
  const hay = `${input.path ?? ""} ${JSON.stringify(input.body ?? {})} ${input.notes ?? ""}`.toLowerCase();
  const reasons = V31_FORBIDDEN.filter((k) => hay.includes(k)).map((k) => `v31_shape:${k}`);
  if (hay.includes("l5_pool") || hay.includes("lifetime_votes")) {
    reasons.push("v31_table_name");
  }
  return {
    frozen: true,
    allowed: reasons.length === 0,
    reasons: reasons.length
      ? reasons
      : ["hub-api is frozen scaffolding; operator surface is this console + CursiveRoot"],
  };
}

export function economicsInterface(): "cursive-root-operator" | "hub-api-v31" {
  return "cursive-root-operator";
}
