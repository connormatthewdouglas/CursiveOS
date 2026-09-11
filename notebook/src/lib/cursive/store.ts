import { create } from "zustand";
import type { Accrual, IdentityKey, MeasurementRequest, RailMode, TransferIntent } from "./types";
import { DEFAULT_RAILS_POLICY, type RailsPolicy } from "./rails";
import { EMPTY_LEDGER, type Ledger } from "./ledger";
import type { Proposal } from "./propose";
import type { PolicyDecision, WriteAttempt } from "./policy";
import type { RecomputeReport } from "./recompute";
import type { PsbtIntent } from "./psbt";
import type { Material } from "./materialize";
import type { IdeaReview } from "./idea";

export type OperatorState = {
  localRequests: MeasurementRequest[];
  localKeys: IdentityKey[];
  accruals: Accrual[];
  transfers: TransferIntent[];
  policy: RailsPolicy;
  founderWallet: string;
  splitCurrent: number;
  ledger: Ledger;
  proposals: Proposal[];
  writeLog: Array<{ attempt: WriteAttempt; decision: PolicyDecision; at: string }>;
  lastRecompute: RecomputeReport | null;
  lastPsbt: PsbtIntent | null;
  lastMaterial: Material | null;
  ideas: Array<IdeaReview & { title: string; at: string }>;
  addRequest: (r: MeasurementRequest) => void;
  setKeys: (keys: IdentityKey[]) => void;
  setPolicy: (patch: Partial<RailsPolicy>) => void;
  setRailMode: (mode: RailMode) => void;
  setWallet: (w: string) => void;
  setSplit: (n: number) => void;
  addAccruals: (rows: Accrual[]) => void;
  markClaimed: (accrualId: string, claimedAt: string, txId: string | null) => void;
  addTransfer: (t: TransferIntent) => void;
  updateTransfer: (payoutId: string, patch: Partial<TransferIntent>) => void;
  setLedger: (ledger: Ledger) => void;
  addProposal: (p: Proposal) => void;
  addWrite: (attempt: WriteAttempt, decision: PolicyDecision, at: string) => void;
  setRecompute: (r: RecomputeReport | null) => void;
  setPsbt: (p: PsbtIntent | null) => void;
  setMaterial: (m: Material | null) => void;
  addIdea: (idea: IdeaReview & { title: string; at: string }) => void;
};

export const useOperator = create<OperatorState>()((set) => ({
  localRequests: [],
  localKeys: [],
  accruals: [],
  transfers: [],
  policy: DEFAULT_RAILS_POLICY,
  founderWallet: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
  splitCurrent: 0.2,
  ledger: EMPTY_LEDGER,
  proposals: [],
  writeLog: [],
  lastRecompute: null,
  lastPsbt: null,
  lastMaterial: null,
  ideas: [],
  addRequest: (r) => set((s) => ({ localRequests: [r, ...s.localRequests] })),
  setKeys: (keys) => set({ localKeys: keys }),
  setPolicy: (patch) => set((s) => ({ policy: { ...s.policy, ...patch } })),
  setRailMode: (mode) => set((s) => ({ policy: { ...s.policy, rail_mode: mode } })),
  setWallet: (w) => set({ founderWallet: w }),
  setSplit: (n) => set({ splitCurrent: n }),
  addAccruals: (rows) => set((s) => ({ accruals: [...rows, ...s.accruals] })),
  markClaimed: (accrualId, claimedAt, txId) =>
    set((s) => ({
      accruals: s.accruals.map((a) =>
        a.accrual_id === accrualId ? { ...a, claimed_at: claimedAt, claim_tx_id: txId } : a,
      ),
    })),
  addTransfer: (t) => set((s) => ({ transfers: [t, ...s.transfers] })),
  updateTransfer: (payoutId, patch) =>
    set((s) => ({
      transfers: s.transfers.map((t) => (t.payout_id === payoutId ? { ...t, ...patch } : t)),
    })),
  setLedger: (ledger) => set({ ledger }),
  addProposal: (p) => set((s) => ({ proposals: [p, ...s.proposals] })),
  addWrite: (attempt, decision, at) =>
    set((s) => ({ writeLog: [{ attempt, decision, at }, ...s.writeLog].slice(0, 12) })),
  setRecompute: (r) => set({ lastRecompute: r }),
  setPsbt: (p) => set({ lastPsbt: p }),
  setMaterial: (m) => set({ lastMaterial: m }),
  addIdea: (idea) => set((s) => ({ ideas: [idea, ...s.ideas].slice(0, 20) })),
}));
