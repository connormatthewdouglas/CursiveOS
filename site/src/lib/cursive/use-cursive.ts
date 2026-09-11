import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { loadSnapshot } from "./client";
import {
  activeJobCount,
  canonicalizer,
  collapseCapabilities,
  physicalMachines,
} from "./identity";
import { liveGateSummary } from "./trust";
import { loopStatus } from "./loop";
import { buildArchive, mergesFromAccepted, underCoveredElites } from "./qd";
import { metabolicR } from "./economics";
import { useOperator } from "./store";

export function useCursive() {
  const query = useQuery({
    queryKey: ["cursive-root"],
    queryFn: loadSnapshot,
    staleTime: 10_000,
    refetchInterval: 15_000,
    retry: 1,
  });
  const data = query.data;
  const localRequests = useOperator((s) => s.localRequests);
  const aliases = data?.aliases ?? [];
  const canon = canonicalizer(aliases);
  const physical = data ? physicalMachines(data.machines, aliases) : [];
  const caps = data ? collapseCapabilities(data.capabilities, canon) : [];
  const requests = useMemo(
    () => [...localRequests, ...(data?.requests ?? [])],
    [localRequests, data],
  );
  const openRequests = requests.filter((r) => r.status === "open").length;
  const activeJobs = activeJobCount(data?.jobs);
  const gates = liveGateSummary(data?.trust ?? []);
  const archive = useMemo(() => buildArchive(data?.bundles ?? []), [data]);
  const elites = useMemo(() => underCoveredElites(archive), [archive]);
  const loop = loopStatus({
    requests,
    jobs: data?.jobs ?? [],
    capabilities: caps,
    now_iso: new Date().toISOString(),
    independent_aggregation_ok: gates.independent_aggregation > 0 && gates.independent_aggregation === gates.total,
    qd_elites: elites.length,
  });
  const merges = useMemo(
    () => mergesFromAccepted(data?.accepted?.length ? data.accepted : (data?.bundles ?? [])),
    [data],
  );
  const rMeta = useMemo(() => metabolicR(merges), [merges]);
  return {
    ...query,
    snapshot: data,
    canon,
    physical,
    caps,
    openRequests,
    activeJobs,
    gates,
    loop,
    requests,
    archive,
    elites,
    rMeta,
    merges,
  };
}
