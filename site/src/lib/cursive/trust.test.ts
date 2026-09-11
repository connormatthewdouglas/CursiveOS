import assert from "node:assert/strict";
import { test } from "node:test";
import { evaluateTrust, revokeKey, rotateKey, signatureAcceptable } from "./trust.ts";
import type { IdentityKey } from "./types.ts";

const base = {
  recompute_ok: true,
  signed_identity_ok: true,
  replay_ok: true,
  independent_aggregation_ok: true,
  key_status: "active" as const,
  trust_scope: "simulated_not_payout_eligible" as const,
  linux_bare_metal: true,
  hardware_wallet_independent: true,
  key_not_revoked: true,
};

test("even a perfect bundle is not payout eligible", () => {
  const ev = evaluateTrust(base);
  assert.equal(ev.selection_truth_eligible, true);
  assert.equal(ev.payout_eligible, false);
});

test("local-sim identity cannot become selection truth", () => {
  const ev = evaluateTrust({ ...base, key_status: "local_sim" });
  assert.equal(ev.selection_truth_eligible, false);
  assert.equal(ev.gate_status, "blocked_unsigned_identity");
});

test("missing independent aggregation waits rather than fraud-rejects", () => {
  const ev = evaluateTrust({ ...base, independent_aggregation_ok: false });
  assert.equal(ev.gate_status, "awaiting_independent_aggregation");
  assert.equal(ev.payout_eligible, false);
});

test("key rotation supersedes the old key and registers an active one", () => {
  const now = "2026-09-10T00:00:00.000Z";
  const keys: IdentityKey[] = [
    {
      identity_public_key: "old",
      machine_id: "42e7c7257af11f46",
      key_scheme: "cursiveos-local-sim-signed-nonce-v0.1",
      key_status: "local_sim",
      trust_scope: "simulated_not_payout_eligible",
      first_seen_at: now,
      last_seen_at: now,
    },
  ];
  const rotated = rotateKey(keys, "42e7c7257af11f46", "old", "new-ed25519", now);
  assert.equal(rotated.ok, true);
  if (!rotated.ok) return;
  assert.equal(rotated.keys.find((k) => k.identity_public_key === "old")?.key_status, "superseded");
  assert.equal(rotated.keys.find((k) => k.identity_public_key === "new-ed25519")?.key_status, "active");
  assert.equal(signatureAcceptable(rotated.keys.find((k) => k.identity_public_key === "old")), false);
  assert.equal(signatureAcceptable(rotated.keys.find((k) => k.identity_public_key === "new-ed25519")), true);
});

test("revoked keys cannot rotate and cannot sign", () => {
  const now = "2026-09-10T00:00:00.000Z";
  const keys: IdentityKey[] = [
    {
      identity_public_key: "k",
      machine_id: "m",
      key_scheme: "cursiveos-ed25519-sshsig-v0.2",
      key_status: "active",
      trust_scope: "simulated_not_payout_eligible",
      first_seen_at: now,
      last_seen_at: now,
    },
  ];
  const revoked = revokeKey(keys, "k", now);
  assert.equal(revoked.ok, true);
  if (!revoked.ok) return;
  assert.equal(signatureAcceptable(revoked.keys[0]), false);
  const again = rotateKey(revoked.keys, "m", "k", "k2", now);
  assert.equal(again.ok, false);
});
