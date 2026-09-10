import assert from "node:assert/strict";
import { test } from "node:test";
import {
  CANONICAL_LAPTOP,
  CANONICAL_STARDUST,
  LENOVO_HW_TUPLE,
  OLD_DAEMON_LAPTOP,
  activeJobCount,
  canonicalizer,
  confirmationThreshold,
  fingerprintCount,
  fullTestFingerprint,
  independentConfirmations,
  physicalMachines,
} from "./identity.ts";

const aliases = [
  {
    alias: OLD_DAEMON_LAPTOP,
    machine_id: CANONICAL_LAPTOP,
    alias_kind: "daemon_pre_b52df82_no_newline_fingerprint",
  },
];

test("fingerprint v2 matches the Lenovo wrapper contract", async () => {
  const id = await fullTestFingerprint(LENOVO_HW_TUPLE);
  assert.equal(id, CANONICAL_LAPTOP);
  assert.notEqual(id, OLD_DAEMON_LAPTOP);
});

test("canonicalizer collapses aliases and physical count excludes them", () => {
  const canon = canonicalizer(aliases);
  assert.equal(canon(OLD_DAEMON_LAPTOP), CANONICAL_LAPTOP);
  assert.equal(canon(CANONICAL_STARDUST), CANONICAL_STARDUST);
  const physical = physicalMachines(
    [
      { machine_id: CANONICAL_LAPTOP, cpu: null, gpu: null, os: null },
      { machine_id: OLD_DAEMON_LAPTOP, cpu: null, gpu: null, os: null },
      { machine_id: CANONICAL_STARDUST, cpu: null, gpu: null, os: null },
    ],
    aliases,
  );
  assert.deepEqual(
    physical.map((m) => m.machine_id),
    [CANONICAL_LAPTOP, CANONICAL_STARDUST],
  );
  assert.equal(fingerprintCount(CANONICAL_LAPTOP, aliases), 2);
});

test("only claimed and running jobs count as active", () => {
  assert.equal(
    activeJobCount([
      { status: "planned" },
      { status: "claimed" },
      { status: "running" },
      { status: "complete" },
    ] as never),
    2,
  );
});

test("independence rejects same machine, wallet, or identity key", () => {
  const r = independentConfirmations(
    [
      { machine_id: CANONICAL_LAPTOP, wallet: "bc1qaaa", identity_public_key: "k1" },
      { machine_id: OLD_DAEMON_LAPTOP, wallet: "bc1qbbb", identity_public_key: "k2" },
      { machine_id: CANONICAL_STARDUST, wallet: "bc1qaaa", identity_public_key: "k3" },
      { machine_id: CANONICAL_STARDUST, wallet: "bc1qccc", identity_public_key: "k1" },
    ],
    aliases,
    3,
  );
  assert.equal(r.independent_count, 1);
  assert.equal(r.required, 1);
  assert.ok(r.rejected.some((x) => x.reason === "same_physical_machine"));
  assert.ok(r.rejected.some((x) => x.reason === "same_wallet"));
});

test("confirmation threshold scales with fleet size", () => {
  assert.equal(confirmationThreshold(1), 1);
  assert.equal(confirmationThreshold(4), 2);
  assert.equal(confirmationThreshold(25), 5);
  assert.equal(confirmationThreshold(100), 5);
});
