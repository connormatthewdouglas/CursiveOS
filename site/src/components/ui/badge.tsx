import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

const tones = {
  good: "text-good border-good/30 bg-good/10",
  warn: "text-warn border-warn/30 bg-warn/10",
  bad: "text-bad border-bad/30 bg-bad/10",
  info: "text-info border-info/30 bg-info/10",
  muted: "text-muted border-border bg-surface",
} as const;

export function Badge({
  tone = "muted",
  className,
  children,
}: {
  tone?: keyof typeof tones;
  className?: string;
  children: ReactNode;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium tracking-wide",
        tones[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}
