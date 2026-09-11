import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { PageHead } from "@/components/shell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { Input, Label, Select, Textarea } from "@/components/ui/input";
import { reviewIdea, type IdeaReview } from "@/lib/cursive/idea";
import type { KnobChannel } from "@/lib/cursive/propose";
import { useOperator } from "@/lib/cursive/store";

export const Route = createFileRoute("/ideas")({ component: IdeasPage });

function download(name: string, body: string) {
  const blob = new Blob([body], { type: "text/plain" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}

function IdeasPage() {
  const ideas = useOperator((s) => s.ideas);
  const addIdea = useOperator((s) => s.addIdea);
  const [review, setReview] = useState<IdeaReview | null>(null);

  function onSubmit(form: FormData) {
    const result = reviewIdea({
      title: String(form.get("title") || ""),
      key: String(form.get("key") || ""),
      value: String(form.get("value") || ""),
      undo: String(form.get("undo") || ""),
      channel: (String(form.get("channel") || "memory") as KnobChannel),
      hypothesis: String(form.get("hypothesis") || ""),
    });
    setReview(result);
    if (result.ok) {
      addIdea({ ...result, title: String(form.get("title") || result.variant_id), at: new Date().toISOString() });
    }
  }

  return (
    <div>
      <PageHead
        kicker="Adaptations"
        title="Suggest a mutation."
        lede="If you have an idea, put it on the work wire as a reversible Linux setting. This page drafts files on your computer. It does not change founder machines, and it does not send money."
      />

      <Card className="mb-4">
        <CardTitle>The rules</CardTitle>
        <ul className="mt-3 list-disc space-y-2 pl-5 text-sm text-muted">
          <li>Must undo. If you cannot name the previous value, it is not a test.</li>
          <li>Settings we already retired (page cluster, vfs cache pressure) are refused.</li>
          <li>Nothing here is applied remotely. You download a script and run it on Linux, or a founder does.</li>
        </ul>
      </Card>

      <Card>
        <CardTitle>Idea</CardTitle>
        <CardHint>Plain language first. The setting name second.</CardHint>
        <form
          className="mt-4 grid gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            onSubmit(new FormData(e.currentTarget));
          }}
        >
          <div>
            <Label htmlFor="title">Name</Label>
            <Input id="title" name="title" placeholder="Start reclaiming memory sooner" required />
          </div>
          <div>
            <Label htmlFor="hypothesis">What do you think will happen?</Label>
            <Textarea
              id="hypothesis"
              name="hypothesis"
              placeholder="Under memory pressure, the machine should recover faster without hurting idle."
              required
            />
          </div>
          <div className="grid gap-3 md:grid-cols-3">
            <div>
              <Label htmlFor="key">Linux setting</Label>
              <Input id="key" name="key" placeholder="vm.watermark_scale_factor" required />
            </div>
            <div>
              <Label htmlFor="value">New value</Label>
              <Input id="value" name="value" placeholder="200" required />
            </div>
            <div>
              <Label htmlFor="undo">Undo value</Label>
              <Input id="undo" name="undo" placeholder="10" required />
            </div>
          </div>
          <div>
            <Label htmlFor="channel">Which kind of improvement?</Label>
            <Select id="channel" name="channel" defaultValue="memory">
              <option value="memory">Memory under pressure</option>
              <option value="coldstart">First response after idle</option>
              <option value="sustained">Sustained AI speed</option>
              <option value="network">Network</option>
              <option value="idle">Idle power</option>
            </Select>
          </div>
          <Button type="submit" className="min-h-11 w-fit">
            Draft the test
          </Button>
        </form>

        {review ? (
          <div className="mt-5 rounded-lg border border-border bg-bg-elevated p-4">
            {review.ok ? (
              <>
                <div className="flex flex-wrap items-center gap-2">
                  <Badge tone="good">ready to download</Badge>
                  <span className="font-mono text-sm">{review.variant_id}</span>
                </div>
                <p className="mt-2 text-sm text-muted">
                  Saved on this browser only. Not sent to the live ledger. Payouts stay off.
                </p>
                <div className="mt-3 flex flex-wrap gap-2">
                  <Button
                    type="button"
                    size="sm"
                    className="min-h-11"
                    onClick={() => download(`${review.variant_id}.json`, review.json || "")}
                  >
                    Download description
                  </Button>
                  <Button
                    type="button"
                    variant="secondary"
                    size="sm"
                    className="min-h-11"
                    onClick={() => download(`cursiveos-presets-${review.variant_id}.sh`, review.preset_sh || "")}
                  >
                    Download undoable script
                  </Button>
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

      {ideas.length ? (
        <Card className="mt-4">
          <CardTitle>Drafts on this browser</CardTitle>
          <ul className="mt-3 space-y-2 text-sm">
            {ideas.map((idea) => (
              <li key={idea.at} className="flex items-center justify-between gap-3">
                <span className="font-medium">{idea.title}</span>
                <span className="font-mono text-xs text-muted">{idea.variant_id}</span>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
    </div>
  );
}
