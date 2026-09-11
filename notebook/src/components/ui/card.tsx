import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

export function Card({
  className,
  children,
}: {
  className?: string;
  children: ReactNode;
}) {
  return (
    <section
      className={cn(
        "rounded-xl border border-border bg-surface p-4 shadow-soft md:p-5",
        className,
      )}
    >
      {children}
    </section>
  );
}

export function CardTitle({
  className,
  children,
}: {
  className?: string;
  children: ReactNode;
}) {
  return <h2 className={cn("text-base font-medium tracking-tight", className)}>{children}</h2>;
}

export function CardHint({ children }: { children: ReactNode }) {
  return <p className="mt-1 text-sm text-muted">{children}</p>;
}
