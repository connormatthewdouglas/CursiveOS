import { createFileRoute, Link } from "@tanstack/react-router";
import { PageHead } from "@/components/shell";
import { Card, CardHint, CardTitle } from "@/components/ui/card";
import { TesterPaste } from "@/components/tester-paste";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/join")({ component: JoinPage });

function JoinPage() {
  return (
    <div>
      <PageHead
        kicker="Testers"
        title="Add your Linux machine."
        lede="The organism only learns from computers people actually own. You run one command on your machine. This website never reaches in."
      />

      <Card className="mb-4">
        <CardTitle>What you get</CardTitle>
        <ul className="mt-3 list-disc space-y-2 pl-5 text-sm text-muted">
          <li>Your computer shows up under Machines after it checks in.</li>
          <li>It can pick up tests the organism asks for — on your hardware, under your control.</li>
          <li>Compensation, if any, is a Fast-shaped share of measured gain. Not Bitcoin. Payouts are off.</li>
        </ul>
      </Card>

      <Card className="mb-4">
        <CardTitle>Linux, first time</CardTitle>
        <CardHint>
          One command to put CursiveOS on the machine. After that, use the CursiveOS window on the Desktop —
          Update from GitHub, see what is running, Stop. Do not paste this every time.
        </CardHint>
        <div className="mt-4">
          <TesterPaste />
        </div>
      </Card>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardTitle>Windows</CardTitle>
          <p className="mt-3 text-sm text-muted">
            You can watch this page. You cannot join the test fleet from Windows or WSL. The genome is Linux
            kernel settings. That is not a slight — it is the product.
          </p>
        </Card>
        <Card>
          <CardTitle>Have something to contribute?</CardTitle>
          <p className="mt-3 text-sm text-muted">
            Variants go to Ideas — a reversible Linux setting with an undo. Measurements go to Sensors — what
            to run, how to score it, what hardware it needs. Both draft on this browser; live enqueue waits on
            a signed proposer rail.
          </p>
          <div className="mt-4 flex flex-wrap gap-2">
            <Button asChild variant="secondary" size="sm" className="min-h-11">
              <Link to="/ideas">Ideas (variants)</Link>
            </Button>
            <Button asChild variant="secondary" size="sm" className="min-h-11">
              <Link to="/sensors">Sensors (measurements)</Link>
            </Button>
          </div>
        </Card>
      </div>
    </div>
  );
}
