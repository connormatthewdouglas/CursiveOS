import { Badge } from "@/components/ui/badge";
import { statusTone } from "@/lib/cursive/format";

export function StatusPill({ value }: { value: unknown }) {
  return <Badge tone={statusTone(value)}>{String(value ?? "—")}</Badge>;
}
