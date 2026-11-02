import type { CommandKind, SchoolCommand } from './command-core.js';

/**
 * Several independent intentions of one section, each followed on its own (#106/#107 for the invitations, schedule, dossiers,
 * school settings and catalogue). The command store stays the only engine: it keeps the request, its idempotency key, its
 * recovery and the conflicts between aggregates. A lane only remembers, per intention (a tag), whether its request is being sent,
 * is followed for a result still unknown, or ended with an outcome to show. Nothing here is a right, a price or a fact:
 * it disappears with its result and no body ever enters its state.
 *
 * No DOM, no network, no relative import beyond command-core: type-checked for the browser and for Node.
 */
export type LaneResult =
  | { status: 'confirmed'; body: unknown; via: 'response' | 'receipt' }
  | { status: 'rejected'; code: string; message: string; needsLogin: boolean }
  | { status: 'pending'; message: string };

export type LaneOutcome = { tone: 'success' | 'error' | 'warning'; title: string; message: string; code?: string; needsLogin?: boolean };

/** The part of the command store a lane uses. */
export interface LaneStore {
  submit(command: SchoolCommand, csrf: string): Promise<LaneResult>;
  /** The request the store follows for this operation, if any (admitted and not yet settled). */
  get(schoolId: string, operationId?: string): unknown;
  getSnapshot(): { readonly entries: ReadonlyMap<string, unknown>; readonly confirmations: readonly { readonly operationId: string }[] };
}

export interface LaneIntent {
  readonly tag: string;
  readonly operationId: string;
  readonly kind: CommandKind;
  readonly success: string;
  /** `sending` until the store's first answer; `followed` while the result is unknown and the store owns the recovery. */
  readonly status: 'sending' | 'followed';
  readonly startedAt: number;
}

export interface LaneSnapshot {
  readonly intents: ReadonlyMap<string, LaneIntent>;
  readonly outcomes: ReadonlyMap<string, LaneOutcome>;
}

export interface LaneHooks {
  csrf(): string;
  /** The school confirmed an intention of this lane: by its response (`result`) or, after a lost reply, by an AP72 receipt (`null`). */
  confirmed?(intent: LaneIntent, result: LaneResult | null): void;
}

const refusal = (code: string, message: string): LaneResult => ({ status: 'rejected', code, message, needsLogin: false });

/** What the person sees for a refusal: a local wait is not a refusal of the school, and the typed content is always kept. */
export function refusalOutcome(result: Extract<LaneResult, { status: 'rejected' }>): LaneOutcome {
  return { tone: 'error', title: result.code.startsWith('LOCAL_COMMAND_') ? 'Modification en attente' : 'Modification refusée',
    message: result.needsLogin ? result.message : `${result.message} Votre saisie est conservée.`, code: result.code, needsLogin: result.needsLogin };
}

export class CommandLane {
  private snapshot: LaneSnapshot = { intents: new Map(), outcomes: new Map() };
  private readonly listeners = new Set<() => void>();
  private disposed = false;
  constructor(private readonly store: LaneStore, private readonly hooks: () => LaneHooks) {}

  getSnapshot = () => this.snapshot;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };

  private publish(intents: Map<string, LaneIntent>, outcomes: Map<string, LaneOutcome>) {
    this.snapshot = { intents, outcomes };
    for (const listener of this.listeners) listener();
  }
  private put(intent: LaneIntent) {
    const intents = new Map(this.snapshot.intents); intents.set(intent.tag, intent);
    const outcomes = new Map(this.snapshot.outcomes); outcomes.delete(intent.tag);
    this.publish(intents, outcomes);
  }
  private end(intent: LaneIntent, outcome?: LaneOutcome) {
    const intents = new Map(this.snapshot.intents); intents.delete(intent.tag);
    const outcomes = new Map(this.snapshot.outcomes);
    if (outcome) outcomes.set(intent.tag, outcome); else outcomes.delete(intent.tag);
    this.publish(intents, outcomes);
  }

  /**
   * Hands one command to the store for the intention `tag`. `admitted` is known at once: the store follows the request (the form can
   * be released, nothing is confirmed yet) or refused it locally (an intention of the same aggregate is still followed, a double press).
   * `result` settles with the school's answer, or with `pending` when the result stays to be verified.
   */
  start(command: SchoolCommand, success: string, tag: string): { admitted: boolean; result: Promise<LaneResult> } {
    if (this.disposed) return { admitted: false, result: Promise.resolve(refusal('LOCAL_LANE_CLOSED', 'Cette page a été quittée. Aucune demande n’a été envoyée.')) };
    if (this.snapshot.intents.has(tag)) return { admitted: false, result: Promise.resolve(refusal('LOCAL_COMMAND_CONFLICT', 'Cette demande est déjà en cours. Votre saisie est conservée.')) };
    const intent: LaneIntent = { tag, operationId: command.operationId, kind: command.kind, success, status: 'sending', startedAt: Date.now() };
    this.put(intent);
    // The store's admission (conflict, limit) is synchronous: what follows tells whether it follows this very request.
    // The same operation submitted twice is a double press: the store already follows it and refuses the second.
    const known = this.store.get(command.schoolId, command.operationId) !== undefined;
    const sent = this.store.submit(command, this.hooks().csrf());
    const admitted = !known && this.store.get(command.schoolId, command.operationId) !== undefined;
    const result = (async () => {
      try { return this.settle(intent, await sent); } catch (error) { if (this.snapshot.intents.get(tag)?.operationId === intent.operationId) this.end(intent); throw error; }
    })();
    return { admitted, result };
  }

  private settle(intent: LaneIntent, result: LaneResult): LaneResult {
    // A lane that was left keeps no state and calls nobody back: the store keeps the request and its recovery.
    if (this.disposed || this.snapshot.intents.get(intent.tag)?.operationId !== intent.operationId) return result;
    if (result.status === 'confirmed') {
      this.end(intent, { tone: 'success', title: 'Confirmé par l’école', message: intent.success });
      this.hooks().confirmed?.(intent, result);
    } else if (result.status === 'rejected') {
      this.end(intent, refusalOutcome(result));
    } else this.put({ ...intent, status: 'followed' });
    return result;
  }

  /**
   * Settles the intentions followed for an unknown result once the store has an answer for them: a receipt (confirmed), or no more
   * request to follow (stopped by the person, refused on a resend, school or account left). Called whenever the store changes.
   */
  reconcile() {
    if (this.disposed) return;
    const view = this.store.getSnapshot();
    const confirmed = new Set(view.confirmations.map(item => item.operationId));
    for (const intent of [...this.snapshot.intents.values()]) {
      if (intent.status !== 'followed') continue;
      if (confirmed.has(intent.operationId)) {
        // Settled by a receipt, which the panel of followed requests already announced: no second confirmation here.
        this.end(intent);
        this.hooks().confirmed?.(intent, null);
      } else if (!view.entries.has(intent.operationId)) this.end(intent);
    }
  }

  clearOutcome(tag?: string) {
    if (tag === undefined ? this.snapshot.outcomes.size === 0 : !this.snapshot.outcomes.has(tag)) return;
    const outcomes = new Map(this.snapshot.outcomes);
    if (tag === undefined) outcomes.clear(); else outcomes.delete(tag);
    this.publish(new Map(this.snapshot.intents), outcomes);
  }

  /** Account, school, membership or access epoch left: nothing of this lane may be shown or called back again. */
  dispose() {
    this.disposed = true;
    this.listeners.clear();
    this.snapshot = { intents: new Map(), outcomes: new Map() };
  }
}

export interface LaneView { readonly busy: boolean; readonly following: boolean; readonly outcome: LaneOutcome | null; readonly operationId: string | undefined }
export function laneView(snapshot: LaneSnapshot, tag: string): LaneView {
  const intent = snapshot.intents.get(tag);
  return { busy: intent?.status === 'sending', following: intent?.status === 'followed', outcome: snapshot.outcomes.get(tag) ?? null, operationId: intent?.operationId };
}
