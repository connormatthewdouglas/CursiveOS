import type { ReactNode } from "react";
import { useState } from "react";
import { Link, useRouterState } from "@tanstack/react-router";
import {
  Activity,
  GitBranch,
  LayoutGrid,
  ListChecks,
  Shield,
  Wallet,
  Waypoints,
  Cpu,
  Lightbulb,
  UserPlus,
  ChevronDown,
} from "lucide-react";
import { CursiveMark } from "@/components/mark";
import { Badge } from "@/components/ui/badge";
import { useCursive } from "@/lib/cursive/use-cursive";
import { loopLabel } from "@/lib/cursive/loop";
import { cn } from "@/lib/cn";

const PRIMARY = [
  { to: "/", label: "Organism", icon: LayoutGrid },
  { to: "/fleet", label: "Machines", icon: Cpu },
  { to: "/queue", label: "Work", icon: ListChecks },
  { to: "/ideas", label: "Ideas", icon: Lightbulb },
  { to: "/join", label: "Join", icon: UserPlus },
] as const;

const OPERATOR = [
  { to: "/trust", label: "Trust", icon: Shield },
  { to: "/rails", label: "Money (sim)", icon: Wallet },
  { to: "/workflows", label: "Workflows", icon: Waypoints },
  { to: "/security", label: "Security", icon: Activity },
  { to: "/gaps", label: "Gaps", icon: GitBranch },
] as const;

function isActive(pathname: string, to: string) {
  return to === "/" ? pathname === "/" : pathname.startsWith(to);
}

export function Shell({ children }: { children: ReactNode }) {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const { snapshot, physical, openRequests, gates, loop } = useCursive();
  const live = snapshot?.source === "live";
  const operatorHit = OPERATOR.some((item) => isActive(pathname, item.to));
  const [opsOpen, setOpsOpen] = useState(operatorHit);

  return (
    <div className="min-h-dvh bg-bg text-fg">
      <aside className="fixed inset-y-0 left-0 z-20 hidden w-56 flex-col border-r border-border bg-bg-elevated md:flex">
        <div className="flex items-center gap-2.5 px-4 py-5">
          <CursiveMark />
          <div>
            <div className="text-sm font-medium tracking-tight">CursiveOS</div>
            <div className="text-xs text-muted">a Linux organism</div>
          </div>
        </div>
        <nav className="flex flex-1 flex-col gap-0.5 px-2 pb-4">
          {PRIMARY.map((item) => {
            const Icon = item.icon;
            const active = isActive(pathname, item.to);
            return (
              <Link
                key={item.to}
                to={item.to}
                className={cn(
                  "flex h-11 items-center gap-2.5 rounded-md px-3 text-sm transition-colors duration-150",
                  active ? "bg-surface text-fg" : "text-muted hover:bg-surface hover:text-fg",
                )}
              >
                <Icon className="size-4" strokeWidth={1.75} />
                {item.label}
              </Link>
            );
          })}
          <button
            type="button"
            onClick={() => setOpsOpen((v) => !v)}
            className="mt-3 flex h-11 items-center justify-between rounded-md px-3 text-xs font-medium uppercase tracking-[0.12em] text-subtle hover:text-muted"
          >
            Operator
            <ChevronDown className={cn("size-3.5 transition-transform", opsOpen ? "rotate-180" : "")} />
          </button>
          {opsOpen
            ? OPERATOR.map((item) => {
                const Icon = item.icon;
                const active = isActive(pathname, item.to);
                return (
                  <Link
                    key={item.to}
                    to={item.to}
                    className={cn(
                      "flex h-11 items-center gap-2.5 rounded-md px-3 text-sm transition-colors duration-150",
                      active ? "bg-surface text-fg" : "text-muted hover:bg-surface hover:text-fg",
                    )}
                  >
                    <Icon className="size-4" strokeWidth={1.75} />
                    {item.label}
                  </Link>
                );
              })
            : null}
        </nav>
        <div className="border-t border-border px-4 py-4 text-xs text-muted">
          <div className="flex items-center gap-2">
            <span className={cn("size-1.5 rounded-full", live ? "bg-good" : "bg-warn")} />
            {live ? "live ledger" : "cached snapshot"}
          </div>
          <div className="mt-1">{physical.length} machines</div>
          <div className="mt-1">{loopLabel(loop.state)}</div>
        </div>
      </aside>

      <div className="md:pl-56">
        <header className="sticky top-0 z-10 border-b border-border bg-bg/90 backdrop-blur-sm">
          <div className="flex items-center justify-between gap-3 px-4 py-3 md:px-8">
            <div className="flex items-center gap-2 md:hidden">
              <CursiveMark className="size-6" />
              <span className="text-sm font-medium">CursiveOS</span>
            </div>
            <div className="hidden items-center gap-2 md:flex">
              <Badge tone="warn">not real money</Badge>
              <Badge tone="info">current stack v0.12</Badge>
              <Badge tone={loop.state === "running" ? "good" : "warn"}>{loopLabel(loop.state)}</Badge>
              {openRequests === 0 ? (
                <Badge tone="muted">no tests waiting</Badge>
              ) : (
                <Badge tone="good">{openRequests} tests waiting</Badge>
              )}
            </div>
            <div className="flex items-center gap-2 text-xs text-muted">
              <Badge tone={gates.payout_true ? "bad" : "warn"}>payouts off</Badge>
            </div>
          </div>
          <div className="flex gap-1 overflow-x-auto px-3 pb-3 md:hidden">
            {[...PRIMARY, ...(opsOpen || operatorHit ? OPERATOR : [])].map((item) => {
              const active = isActive(pathname, item.to);
              return (
                <Link
                  key={item.to}
                  to={item.to}
                  className={cn(
                    "inline-flex h-11 shrink-0 items-center rounded-full px-3 text-xs font-medium",
                    active ? "bg-accent text-accent-fg" : "bg-surface text-muted",
                  )}
                >
                  {item.label}
                </Link>
              );
            })}
          </div>
        </header>
        <main className="px-4 py-6 md:px-8 md:py-8">{children}</main>
      </div>
    </div>
  );
}

export function PageHead({
  kicker,
  title,
  lede,
}: {
  kicker?: string;
  title: string;
  lede: string;
}) {
  return (
    <header className="mb-6 max-w-3xl">
      {kicker ? (
        <p className="mb-2 text-xs font-medium uppercase tracking-[0.14em] text-muted">{kicker}</p>
      ) : null}
      <h1 className="text-3xl font-medium tracking-tight md:text-4xl">{title}</h1>
      <p className="mt-2 text-base text-muted">{lede}</p>
    </header>
  );
}

export function Stat({
  label,
  value,
  hint,
}: {
  label: string;
  value: ReactNode;
  hint?: string;
}) {
  return (
    <div className="rounded-xl border border-border bg-surface p-4">
      <div className="text-xs font-medium uppercase tracking-[0.12em] text-muted">{label}</div>
      <div className="mt-2 font-mono text-3xl tabular-nums tracking-tight">{value}</div>
      {hint ? <div className="mt-1 text-sm text-muted">{hint}</div> : null}
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="text-sm text-muted">{children}</p>;
}
