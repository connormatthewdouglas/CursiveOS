import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { PageHead } from "@/components/shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { Input, Label, Select, Textarea } from "@/components/ui/input";
import {
  buildEnqueueStub,
  createLadderDraft,
  submitToWire,
} from "@/lib/cursive/enqueue-ladder";
import { reviewSensor, type SensorFamily, type SensorReview } from "@/lib/cursive/sensor";
import { useOperator } from "@/lib/cursive/store";

export const Route = createFileRoute("/sensors")({ component: SensorsPage });

function download(name: string, body: string) {
  const blob = new Blob([body], { type: "text/plain" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}

function SensorsPage() {
  const sensors = useOperator((s) => s.sensors);
  const addSensor = useOperator((s) => s.addSensor);
  const wireSubmissions = useOperator((s) => s.wireSubmissions);
  const addWireSubmission = useOperator((s) => s.addWireSubmission);
  const [review, setReview] = useState<SensorReview | null>(null);
  const [title, setTitle] = useState("");
  const [submitterId, setSubmitterId] = useState("");
  const [wireMsg, setWireMsg] = useState<string | null>(null);
  const [wireErr, setWireErr] = useState<string | null>(null);

  function onSubmit(form: FormData) {
    const nextTitle = String(form.get("name") || "");
    const result = reviewSensor({
      name: nextTitle,
      family: String(form.get("family") || "performance") as SensorFamily,
      measures: String(form.get("measures") || ""),
      how_to_run: String(form.get("how_to_run") || ""),
      score_mode: String(form.get("score_mode") || "numeric") as "numeric" | "pass_fail",
      hardware_needs: String(form.get("hardware_needs") || ""),
      hypothesis: String(form.get("hypothesis") || ""),
      package_notes: String(form.get("package_notes") || ""),
    });
    setReview(result);
    setTitle(nextTitle);
    setWireMsg(null);
    setWireErr(null);
    if (result.ok) {
      addSensor({ ...result, title: nextTitle || result.sensor_id, at: new Date().toISOString() });
    }
  }

  function onSubmitToWire() {
    setWireMsg(null);
    setWireErr(null);
    if (!review?.ok || !review.json) {
      setWireErr("Draft a valid sensor first.");
      return;
    }
    const draft = createLadderDraft({ id: review.sensor_id, kind: "sensor" });
    const res = submitToWire(draft, submitterId);
    if (!res.ok) {
      setWireErr(res.reason);
      return;
    }
    const stubName = `${review.sensor_id}.enqueue-stub.json`;
    const stub = buildEnqueueStub({
      kind: "sensor",
      id: review.sensor_id,
      title: title || review.sensor_id,
      submitter_machine_id: res.record.submitter_machine_id || submitterId.trim(),
      body: JSON.parse(review.json) as Record<string, unknown>,
    });
    download(stubName, stub);
    addWireSubmission({
      kind: "sensor",
      title: title || review.sensor_id,
      at: new Date().toISOString(),
      ladder: res.record,
      stub_name: stubName,
    });
    setWireMsg(
      "Saved on this browser at self_pending and downloaded an enqueue stub. Not a live ledger write. The live measurement_requests table still waits on a signed proposer rail. Payouts stay off.",
    );
  }

  const sensorWires = wireSubmissions.filter((w) => w.kind === "sensor");

  return (
    <div>
      <PageHead
        kicker="Measurements"
        title="Propose a sensor."
        lede="Sensors decide what keeps and what goes. This page drafts a measurement definition on your computer. It does not change founder machines, and it does not send money."
      />

      <Card className="mb-4">
        <CardTitle>The rules</CardTitle>
        <ul className="mt-3 list-disc space-y-2 pl-5 text-sm text-muted">
          <li>Say what it measures, how to run it, and what hardware it needs.</li>
          <li>Performance sensors score numeric fitness. Regression sensors are pass/fail gates.</li>
          <li>Acceptance is sensor-scored fitness plus gates — not votes.</li>
          <li>
            Nothing here is applied remotely.{" "}
            <code className="font-mono text-xs">payout_eligible</code> stays false.
          </li>
        </ul>
      </Card>

      <Card className="mb-4">
        <CardTitle>Enqueue ladder</CardTitle>
        <CardHint>
          Same ladder as Ideas: self-clean on the submitter machine, then exactly one foreign
          confirmer, then public work-queue eligible. This page only drafts and stubs.
        </CardHint>
        <ol className="mt-3 list-decimal space-y-1.5 pl-5 text-sm text-muted">
          <li>
            <span className="font-medium text-fg">draft</span> — form + download on this browser
          </li>
          <li>
            <span className="font-medium text-fg">self_pending</span> — stub downloaded; wait for
            self-clean
          </li>
          <li>
            <span className="font-medium text-fg">foreign confirmer</span> — one other machine
          </li>
          <li>
            <span className="font-medium text-fg">public_eligible</span> — signed proposer may
            enqueue later; not from here
          </li>
        </ol>
      </Card>

      <Card>
        <CardTitle>Sensor</CardTitle>
        <CardHint>Plain language first. Family and score mode second.</CardHint>
        <form
          className="mt-4 grid gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            onSubmit(new FormData(e.currentTarget));
          }}
        >
          <div>
            <Label htmlFor="name">Name</Label>
            <Input id="name" name="name" placeholder="Sustained tok/s" required />
          </div>
          <div>
            <Label htmlFor="hypothesis">What do you think it will detect or prove?</Label>
            <Textarea
              id="hypothesis"
              name="hypothesis"
              placeholder="Detect scheduler and cache effects once the model is warm."
              required
            />
          </div>
          <div>
            <Label htmlFor="measures">What it measures</Label>
            <Textarea
              id="measures"
              name="measures"
              placeholder="Steady-state tokens per second on a warm local model."
              required
            />
          </div>
          <div>
            <Label htmlFor="how_to_run">How to run</Label>
            <Textarea
              id="how_to_run"
              name="how_to_run"
              placeholder="./benchmarks/benchmark-inference-v0.1.sh --sustained"
              required
            />
          </div>
          <div className="grid gap-3 md:grid-cols-3">
            <div>
              <Label htmlFor="family">Family</Label>
              <Select id="family" name="family" defaultValue="performance">
                <option value="performance">Performance</option>
                <option value="regression">Regression (gate)</option>
                <option value="immune">Immune</option>
                <option value="behavioral">Behavioral</option>
                <option value="metabolic">Metabolic</option>
              </Select>
            </div>
            <div>
              <Label htmlFor="score_mode">Score vs pass/fail</Label>
              <Select id="score_mode" name="score_mode" defaultValue="numeric">
                <option value="numeric">Numeric fitness</option>
                <option value="pass_fail">Pass / fail gate</option>
              </Select>
            </div>
            <div>
              <Label htmlFor="hardware_needs">Hardware needs</Label>
              <Input
                id="hardware_needs"
                name="hardware_needs"
                placeholder="GPU + local inference"
                required
              />
            </div>
          </div>
          <div>
            <Label htmlFor="package_notes">Package notes (optional)</Label>
            <Textarea
              id="package_notes"
              name="package_notes"
              placeholder="Needs Ollama on 127.0.0.1:11435"
            />
          </div>
          <Button type="submit" className="min-h-11 w-fit">
            Draft the sensor
          </Button>
        </form>

        {review ? (
          <div className="mt-5 rounded-lg border border-border bg-bg-elevated p-4">
            {review.ok ? (
              <>
                <div className="flex flex-wrap items-center gap-2">
                  <Badge tone="good">ready to download</Badge>
                  <span className="font-mono text-sm">{review.sensor_id}</span>
                </div>
                <p className="mt-2 text-sm text-muted">
                  Saved on this browser only. Not sent to the live ledger. Payouts stay off.
                </p>
                <div className="mt-3 flex flex-wrap gap-2">
                  <Button
                    type="button"
                    size="sm"
                    className="min-h-11"
                    onClick={() => download(`${review.sensor_id}.json`, review.json || "")}
                  >
                    Download description
                  </Button>
                </div>

                <div className="mt-5 border-t border-border pt-4">
                  <p className="text-sm font-medium">Submit to the wire</p>
                  <p className="mt-1 text-sm text-muted">
                    Creates a local <span className="font-mono text-xs">self_pending</span> record
                    and downloads an enqueue stub. Does not write the live database. Live ledger
                    enqueue waits on a signed proposer rail.
                  </p>
                  <div className="mt-3 grid gap-3 md:grid-cols-[1fr_auto] md:items-end">
                    <div>
                      <Label htmlFor="submitter">Submitter machine id</Label>
                      <Input
                        id="submitter"
                        value={submitterId}
                        onChange={(e) => setSubmitterId(e.target.value)}
                        placeholder="16-char fingerprint from your Linux host"
                      />
                    </div>
                    <Button type="button" className="min-h-11" onClick={onSubmitToWire}>
                      Submit to the wire
                    </Button>
                  </div>
                  {wireMsg ? <p className="mt-3 text-sm text-muted">{wireMsg}</p> : null}
                  {wireErr ? <p className="mt-3 text-sm text-warn">{wireErr}</p> : null}
                </div>
              </>
            ) : (
              <>
                <Badge tone="warn">not accepted yet</Badge>
                <ul className="mt-2 list-disc pl-5 text-sm text-muted">
                  {review.reasons.map((r) => (
                    <li key={r}>{r}</li>
                  ))}
                </ul>
              </>
            )}
          </div>
        ) : null}
      </Card>

      {sensors.length ? (
        <Card className="mt-4">
          <CardTitle>Drafts on this browser</CardTitle>
          <ul className="mt-3 space-y-2 text-sm">
            {sensors.map((sensor) => (
              <li key={sensor.at} className="flex items-center justify-between gap-3">
                <span className="font-medium">{sensor.title}</span>
                <span className="font-mono text-xs text-muted">{sensor.sensor_id}</span>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}

      {sensorWires.length ? (
        <Card className="mt-4">
          <CardTitle>Wire stubs on this browser</CardTitle>
          <CardHint>Local only. Stage starts at self_pending. Not live enqueue.</CardHint>
          <ul className="mt-3 space-y-2 text-sm">
            {sensorWires.map((w) => (
              <li key={w.at} className="flex flex-wrap items-center justify-between gap-2">
                <span className="font-medium">{w.title}</span>
                <span className="flex items-center gap-2">
                  <Badge tone="info">{w.ladder.stage}</Badge>
                  <span className="font-mono text-xs text-muted">{w.ladder.id}</span>
                </span>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
    </div>
  );
}
