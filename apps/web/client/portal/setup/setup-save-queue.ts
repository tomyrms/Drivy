import type { SetupContent, SetupStep } from '../../setup-model';

/**
 * Enregistrement coalescé du brouillon de préparation (#123). Le même principe que les préférences de notifications :
 * un seul PUT en vol, la dernière saisie part après la réponse avec la version que l'école vient de renvoyer, et rien
 * n'est envoyé pour une saisie identique à celle que l'école détient déjà.
 *
 * Ce module est pur : aucun DOM, aucun réseau, aucune minuterie. L'appelant fournit `send` ; la file ne connaît que des
 * versions et des brouillons, ne garde aucun contenu hors mémoire et ne décide d'aucun droit.
 */
export interface SetupDraftBody {
  readonly currentStep: SetupStep;
  readonly content: SetupContent;
}

export interface SetupSaveRequest {
  /** Version que l'école doit encore détenir (`If-Match`). */
  readonly ifMatch: number;
  readonly body: SetupDraftBody;
}

export type SetupSaveOutcome =
  | { readonly status: 'confirmed'; readonly version: number; readonly body: SetupDraftBody }
  /** Refus définitif : rien n'a été écrit, la même saisie peut être renvoyée telle quelle. */
  | { readonly status: 'refused'; readonly message: string }
  /** Version périmée : l'école détient un autre brouillon ; la saisie locale n'a pas été écrite. */
  | { readonly status: 'conflict' }
  /** Résultat non établi : la demande reste suivie ailleurs, rien ne doit être renvoyé ici. */
  | { readonly status: 'unknown'; readonly message: string };

export type SetupSaveSend = (request: SetupSaveRequest) => Promise<SetupSaveOutcome>;

export type SetupSavePhase = 'idle' | 'saving' | 'refused' | 'conflict' | 'unknown';

export interface SetupSaveSnapshot {
  readonly phase: SetupSavePhase;
  readonly message: string | null;
  /** Un PUT est en vol. */
  readonly saving: boolean;
  /** Le brouillon de l'école est le brouillon local et aucun envoi n'est en vol : la revue peut s'ouvrir. */
  readonly synced: boolean;
  /** Brouillon que l'école détient, tel que lu ou confirmé. */
  readonly held: SetupDraftBody | null;
  readonly heldVersion: number | null;
  /** Étape dont l'enregistrement a rencontré une autre version : « à relire ». */
  readonly conflictStep: SetupStep | null;
}

export interface SetupSaveHooks {
  /** L'école a confirmé ce brouillon ; `body` est exactement ce qu'elle détient désormais. */
  confirmed?(body: SetupDraftBody, version: number): void;
  /** La version a changé à l'école : la saisie locale est gardée, le brouillon doit être relu. */
  conflict?(body: SetupDraftBody): void;
}

interface Entry {
  readonly body: SetupDraftBody;
  /** Saisie seule : deux brouillons au même contenu sont la même saisie, même à une étape différente. */
  readonly contentKey: string;
  /** Brouillon complet : contenu et étape mémorisée. */
  readonly key: string;
}

const canonical = (value: unknown): unknown => {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    const source = value as Record<string, unknown>;
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(source).sort()) if (source[key] !== undefined) sorted[key] = canonical(source[key]);
    return sorted;
  }
  return value;
};

/** Empreinte stable d'une saisie, indépendante de l'ordre des clés et des champs absents. */
export function contentKey(content: SetupContent): string {
  return JSON.stringify(canonical(content));
}

const entryOf = (body: SetupDraftBody): Entry => ({
  body, contentKey: contentKey(body.content), key: JSON.stringify(canonical(body)),
});

const UNSAVED = 'Enregistrement non confirmé. Vérifiez son résultat avant de réessayer.';

export class SetupSaveQueue {
  private readonly listeners = new Set<() => void>();
  private readonly waiters: Array<(snapshot: SetupSaveSnapshot) => void> = [];
  private snapshot: SetupSaveSnapshot = { phase: 'idle', message: null, saving: false, synced: false, held: null, heldVersion: null, conflictStep: null };
  private held: { version: number; entry: Entry } | null = null;
  private latest: Entry | null = null;
  private pending: Entry | null = null;
  private flight: Entry | null = null;
  private phase: SetupSavePhase = 'idle';
  private message: string | null = null;
  private conflictStep: SetupStep | null = null;
  private generation = 0;
  private pumping = false;
  private disposed = false;

  constructor(private readonly options: { send: SetupSaveSend } & SetupSaveHooks) {}

  getSnapshot = (): SetupSaveSnapshot => this.snapshot;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };

  private publish() {
    const synced = this.held !== null && this.flight === null && this.pending === null
      && this.latest !== null && this.latest.contentKey === this.held.entry.contentKey;
    this.snapshot = { phase: this.phase, message: this.message, saving: this.phase === 'saving', synced,
      held: this.held?.entry.body ?? null, heldVersion: this.held?.version ?? null,
      conflictStep: this.phase === 'conflict' && !synced ? this.conflictStep : null };
    for (const listener of this.listeners) listener();
  }

  /**
   * Brouillon lu à l'école. Une lecture plus ancienne que la version détenue est ignorée : une réponse en retard ne
   * ramène jamais l'école en arrière. Aucun envoi n'est déclenché ici.
   */
  adopt(version: number, body: SetupDraftBody) {
    if (this.disposed) return;
    if (this.held !== null && version < this.held.version) return;
    this.held = { version, entry: entryOf(body) };
    if (this.latest === null) this.latest = this.held.entry;
    if (this.pending !== null && this.pending.contentKey === this.held.entry.contentKey) this.pending = null;
    // Un reçu a tranché un résultat inconnu : le brouillon relu est celui qui était parti.
    if (this.phase === 'unknown' && this.latest?.contentKey === this.held.entry.contentKey) { this.phase = 'idle'; this.message = null; }
    this.publish();
  }

  /** Saisie locale : sert à savoir si l'école détient déjà ce contenu. N'envoie rien. */
  track(body: SetupDraftBody) {
    if (this.disposed) return;
    const entry = entryOf(body);
    if (this.latest?.key === entry.key) return;
    this.latest = entry;
    this.publish();
  }

  /** « Enregistrer et continuer » : la dernière saisie est retenue ; un seul envoi à la fois. */
  enqueue(body: SetupDraftBody) {
    if (this.disposed) return;
    const entry = entryOf(body);
    this.latest = entry;
    this.pending = entry;
    this.conflictStep = null;
    if (this.phase !== 'saving') { this.phase = 'idle'; this.message = null; }
    this.publish();
    void this.pump();
  }

  /**
   * Enregistrement explicite attendu (« Enregistrer et quitter ») : la promesse se résout quand la file est au repos.
   * Un envoi déjà en vol n'est pas doublé : la même saisie attend sa réponse, une saisie plus récente part après elle.
   */
  flush(body: SetupDraftBody): Promise<SetupSaveSnapshot> {
    if (this.disposed) return Promise.resolve(this.snapshot);
    const settled = new Promise<SetupSaveSnapshot>(resolve => this.waiters.push(resolve));
    this.enqueue(body);
    this.settleWaiters();
    return settled;
  }

  /** Nouvel essai explicite après un refus ou un résultat non établi : la saisie retenue repart telle quelle. */
  retry() {
    if (this.disposed || (this.phase !== 'refused' && this.phase !== 'unknown')) return;
    this.phase = 'idle'; this.message = null; this.publish();
    void this.pump();
  }

  /** La personne quitte sans enregistrer : la saisie locale est abandonnée, pas la demande déjà partie. */
  forgetLocal() {
    if (this.disposed) return;
    this.pending = null;
    this.latest = this.held?.entry ?? null;
    if (this.phase !== 'saving') { this.phase = 'idle'; this.message = null; }
    this.publish();
  }

  /** Changement d'école, de compte ou d'époque d'accès : rien de cette portée ne peut être renvoyé ni rappelé. */
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.generation++;
    this.held = null; this.latest = null; this.pending = null; this.flight = null;
    this.phase = 'idle'; this.message = null; this.conflictStep = null;
    this.publish();
    this.listeners.clear();
    this.settleWaiters();
  }

  /** Plus rien ne partira tout seul : aucun envoi en vol, et aucune saisie en attente qui puisse encore être envoyée. */
  private quiescent() {
    return !this.pumping && this.flight === null
      && (this.pending === null || this.phase !== 'idle' || this.held === null);
  }

  private settleWaiters() {
    if (!this.quiescent()) return;
    while (this.waiters.length) this.waiters.shift()!(this.snapshot);
  }

  private async pump(): Promise<void> {
    if (this.disposed || this.pumping) return;
    this.pumping = true;
    try {
      while (!this.disposed && this.flight === null && this.pending !== null && this.held !== null && this.phase === 'idle') {
        // Saisie identique à celle que l'école détient déjà : aucune requête.
        if (this.pending.contentKey === this.held.entry.contentKey) { this.pending = null; this.publish(); break; }
        await this.sendOne();
      }
    } finally {
      this.pumping = false;
      this.settleWaiters();
    }
  }

  private async sendOne(): Promise<void> {
    const pending = this.pending!;
    const held = this.held!;
    const generation = this.generation;
    this.flight = pending;
    this.phase = 'saving'; this.message = null;
    this.publish();
    let outcome: SetupSaveOutcome;
    try { outcome = await this.options.send({ ifMatch: held.version, body: pending.body }); }
    catch { outcome = { status: 'refused', message: 'La préparation n’a pas pu être enregistrée.' }; }
    // Portée changée pendant l'envoi : la réponse n'est ni affichée ni rejouée.
    if (this.disposed || generation !== this.generation) return;
    this.flight = null;
    if (outcome.status === 'confirmed') {
      this.held = { version: outcome.version, entry: entryOf(outcome.body) };
      if (this.pending?.contentKey === this.held.entry.contentKey) this.pending = null;
      this.phase = 'idle'; this.message = null; this.conflictStep = null;
      this.publish();
      this.options.confirmed?.(outcome.body, outcome.version);
      return;
    }
    if (outcome.status === 'conflict') {
      // Le brouillon local reste la référence : rien n'est réécrit, l'école relue, l'étape marquée.
      this.pending = null;
      this.phase = 'conflict'; this.conflictStep = pending.body.currentStep;
      this.message = 'La préparation a changé à l’école. Votre saisie est conservée : relisez l’étape avant d’enregistrer.';
      this.publish();
      this.options.conflict?.(pending.body);
      return;
    }
    if (outcome.status === 'unknown') {
      this.phase = 'unknown'; this.message = outcome.message || UNSAVED; this.publish();
      return;
    }
    this.phase = 'refused'; this.message = outcome.message;
    this.publish();
  }
}
