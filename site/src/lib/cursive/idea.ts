import { MINED_OUT_KEYS, type KnobChannel } from "./propose.ts";

const KEY_RE = /^[a-z][a-z0-9_.-]{1,80}$/i;
const VAL_RE = /^[A-Za-z0-9._:/-]{1,64}$/;

export type IdeaInput = {
  title: string;
  key: string;
  value: string;
  undo: string;
  channel: KnobChannel;
  hypothesis: string;
};

export type IdeaReview = {
  ok: boolean;
  reasons: string[];
  variant_id: string;
  json: string | null;
  preset_sh: string | null;
  payout_eligible: false;
};

export function slugIdea(title: string) {
  return (
    title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 32) || "untitled"
  );
}

export function reviewIdea(input: IdeaInput): IdeaReview {
  const reasons: string[] = [];
  const title = input.title.trim();
  const key = input.key.trim();
  const value = input.value.trim();
  const undo = input.undo.trim();
  const hypothesis = input.hypothesis.trim();
  const channel = input.channel;

  if (!title) reasons.push("Give the idea a short name.");
  if (!hypothesis) reasons.push("Say what you think this will change, in plain language.");
  if (!key) reasons.push("Name the Linux setting (for example vm.swappiness).");
  else if (!KEY_RE.test(key)) reasons.push("Setting names can only use letters, numbers, dots, and dashes.");
  if (!value) reasons.push("Say what to set it to.");
  else if (!VAL_RE.test(value)) reasons.push("Keep the new value a simple number or word.");
  if (!undo) reasons.push("Say how to undo it (the previous value).");
  else if (!VAL_RE.test(undo)) reasons.push("Keep the undo value a simple number or word.");
  if (value && undo && value === undo) {
    reasons.push("Undo has to be different from the new value, or it isn't reversible.");
  }
  if (MINED_OUT_KEYS.has(key)) {
    reasons.push("That setting was already tested and did not help. Try something else.");
  }

  const variant_id = `v0.14-idea-${slugIdea(title)}`;
  if (reasons.length) {
    return { ok: false, reasons, variant_id, json: null, preset_sh: null, payout_eligible: false };
  }

  const json = JSON.stringify(
    {
      schema_version: "seed-organism.variant.v0.1",
      variant_id: `candidate-${variant_id}`,
      parent_variant_id: "parent-baseline-v0.12",
      contributor_id: "community-idea",
      preset_version: variant_id,
      evaluation_role: "candidate_screen",
      fitness_eligible: true,
      proposed_by: "community-idea-rail",
      declared_scope: `The v0.12 stack plus one reversible setting: ${key}=${value} (undo ${undo}). Channel: ${channel}.`,
      hypothesis,
      rollback_method: `Restores ${key}=${undo}, then the v0.12 undo.`,
      payout_eligible: false,
      trust_scope: "simulated_not_payout_eligible",
      origin_write: false,
    },
    null,
    2,
  ) + "\n";

  const preset_sh = `#!/usr/bin/env bash
# Community idea ${variant_id}
# ${key}=${value}  undo=${undo}
# ${hypothesis}
set -uo pipefail
ACTION="\${1:---help}"
KEY="${key}"
VAL="${value}"
UNDO="${undo}"
if [[ -z "\${TAO_SUDO_PASS:-}" ]]; then
    if ! sudo -n true 2>/dev/null; then
        read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
    fi
fi
export TAO_SUDO_PASS
s() {
    if [[ -n "\${TAO_SUDO_PASS:-}" ]]; then echo "$TAO_SUDO_PASS" | sudo -S "$@" 2>/dev/null;
    else sudo -n "$@" 2>/dev/null; fi
}
echo "CursiveOS idea ${variant_id}"
case "$ACTION" in
  --help) echo "Usage: $0 --apply-temp | --undo | --dry-run" ;;
  --dry-run) echo "  would set $KEY=$VAL (undo $UNDO)" ;;
  --apply-temp)
    if s sysctl -w "$KEY=$VAL" >/dev/null 2>&1; then echo "OK $KEY=$VAL"; else echo "failed to set $KEY"; exit 1; fi
    ;;
  --undo)
    if s sysctl -w "$KEY=$UNDO" >/dev/null 2>&1; then echo "OK $KEY restored to $UNDO"; else echo "failed to undo $KEY"; exit 1; fi
    ;;
  *) echo "Unknown option: $ACTION"; exit 1 ;;
esac
`;

  return { ok: true, reasons: [], variant_id, json, preset_sh, payout_eligible: false };
}
