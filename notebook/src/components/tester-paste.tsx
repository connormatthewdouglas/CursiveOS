import { useState } from "react";
import { Button } from "@/components/ui/button";
import { LINUX_TESTER_PASTE } from "@/lib/cursive/tester-paste";

export function TesterPaste({ compact = false }: { compact?: boolean }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(LINUX_TESTER_PASTE);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div>
      {compact ? null : (
        <p className="mb-3 text-sm text-muted">
          Linux only. First install on a machine you control. Later updates happen in the CursiveOS window,
          not by pasting this again. This website cannot change your computer.
        </p>
      )}
      <pre className="overflow-x-auto rounded-lg border border-border bg-bg-elevated p-3 font-mono text-xs leading-relaxed text-muted">
        {LINUX_TESTER_PASTE}
      </pre>
      <Button type="button" size="sm" className="mt-3 min-h-11" onClick={copy}>
        {copied ? "Copied" : "Copy command"}
      </Button>
    </div>
  );
}
