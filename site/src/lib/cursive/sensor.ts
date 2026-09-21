const NAME_RE = /^.{1,80}$/;

export type SensorFamily =
  | "performance"
  | "regression"
  | "immune"
  | "behavioral"
  | "metabolic";

export type SensorInput = {
  name: string;
  family: SensorFamily;
  measures: string;
  how_to_run: string;
  score_mode: "numeric" | "pass_fail";
  hardware_needs: string;
  hypothesis: string;
  package_notes: string;
};

export type SensorReview = {
  ok: boolean;
  reasons: string[];
  sensor_id: string;
  json: string | null;
  payout_eligible: false;
};

export function slugSensor(name: string) {
  return (
    name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 32) || "untitled"
  );
}

export function reviewSensor(input: SensorInput): SensorReview {
  const reasons: string[] = [];
  const name = input.name.trim();
  const measures = input.measures.trim();
  const how_to_run = input.how_to_run.trim();
  const hardware_needs = input.hardware_needs.trim();
  const hypothesis = input.hypothesis.trim();
  const package_notes = input.package_notes.trim();
  const family = input.family;
  const score_mode = input.score_mode;

  if (!name || !NAME_RE.test(name)) reasons.push("Give the sensor a short name.");
  if (!hypothesis) reasons.push("Say what you think this will detect or measure, in plain language.");
  if (!measures) reasons.push("Say what it measures.");
  if (!how_to_run) reasons.push("Say how to run it on a Linux machine.");
  if (!hardware_needs) reasons.push("Say what hardware it needs (or \"any Linux\").");
  if (!["performance", "regression", "immune", "behavioral", "metabolic"].includes(family)) {
    reasons.push("Pick a sensor family.");
  }
  if (score_mode !== "numeric" && score_mode !== "pass_fail") {
    reasons.push("Say whether the score is numeric fitness or a pass/fail gate.");
  }
  if (family === "regression" && score_mode === "numeric") {
    reasons.push("Regression sensors are pass/fail gates, not numeric fitness.");
  }
  if (family === "performance" && score_mode === "pass_fail") {
    reasons.push("Performance sensors report a numeric delta, not a bare pass/fail.");
  }

  const sensor_id = `sensor-${slugSensor(name)}`;
  if (reasons.length) {
    return { ok: false, reasons, sensor_id, json: null, payout_eligible: false };
  }

  const json =
    JSON.stringify(
      {
        schema_version: "seed-organism.sensor.v0.1",
        sensor_id: `candidate-${sensor_id}`,
        name,
        family,
        measures,
        how_to_run,
        score_mode,
        hardware_needs,
        hypothesis,
        package_notes: package_notes || null,
        contributor_id: "community-sensor",
        proposed_by: "community-sensor-rail",
        evaluation_role: "candidate_screen",
        fitness_eligible: family === "performance",
        gate_eligible: family === "regression",
        payout_eligible: false,
        trust_scope: "simulated_not_payout_eligible",
        origin_write: false,
        live_ledger_write: false,
      },
      null,
      2,
    ) + "\n";

  return { ok: true, reasons: [], sensor_id, json, payout_eligible: false };
}
