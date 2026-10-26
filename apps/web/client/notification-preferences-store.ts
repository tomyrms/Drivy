import { acknowledgeFields, projectFields, type FieldIntention } from './command-projection.js';
import { type Choices, type NotificationPreferences, type SaveOutcome } from './notification-preferences-model.js';

type Key = keyof Choices;
type Intentions = Partial<Record<Key, FieldIntention<boolean>>>;
type Flight = { base: NotificationPreferences; body: Choices; intentions: Intentions };
export type PreferencePhase = 'loading' | 'ready' | 'saving' | 'uncertain' | 'conflict' | 'unavailable' | 'rejected';
export interface PreferenceSnapshot {
  value: NotificationPreferences | null;
  phase: PreferencePhase;
  pendingKeys: readonly Key[];
  message: string | null;
  readAt?: number;
}
export interface PreferenceTransport {
  read(): Promise<{ personId: string; value: NotificationPreferences }>;
  write(personId: string, choices: Choices, version: number): Promise<SaveOutcome>;
}

/** One versioned object, independent field intentions. Kept in memory only for this page. */
export class NotificationPreferenceStore {
  private readonly listeners = new Set<() => void>();
  private snapshot: PreferenceSnapshot = { value: null, phase: 'loading', pendingKeys: [], message: null };
  private confirmed: NotificationPreferences | null = null;
  private personId: string | null = null;
  private intentions: Intentions = {};
  private flight: Flight | null = null;
  private revision = 0;
  private generation = 0;
  private working = false;
  private reading: Promise<void> | null = null;
  private refreshAfterWrite = false;
  constructor(private readonly transport: PreferenceTransport) {}
  getSnapshot = () => this.snapshot;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };

  private publish(phase: PreferencePhase, message: string | null = null) {
    this.snapshot = { ...this.snapshot, phase, message,
      value: this.confirmed ? projectFields(this.confirmed, this.intentions) : null,
      pendingKeys: Object.keys(this.intentions) as Key[] };
    for (const listener of this.listeners) listener();
  }

  /** Bfcache/account departure: old callbacks cannot reintroduce the previous person's values. */
  clear() {
    this.generation++; this.working = false; this.reading = null; this.refreshAfterWrite = false; this.rebased = false;
    this.confirmed = null; this.personId = null; this.intentions = {}; this.flight = null;
    this.snapshot = { value: null, phase: 'loading', pendingKeys: [], message: null };
    for (const listener of this.listeners) listener();
  }

  async refresh(): Promise<void> {
    if (this.reading) return this.reading;
    if (this.working) { this.refreshAfterWrite = true; return; }
    const generation = this.generation;
    const work = this.readAndReconcile(generation);
    this.reading = work;
    try { await work; } finally {
      if (this.reading === work) {
        this.reading = null;
        if (this.snapshot.phase === 'ready') void this.pump();
      }
    }
  }

  private async readAndReconcile(generation: number) {
    const unresolved = this.flight;
    if (!this.confirmed) this.publish('loading');
    try {
      const read = await this.transport.read();
      if (generation !== this.generation) return;
      if (this.personId !== null && this.personId !== read.personId) {
        this.clear(); this.personId = read.personId; this.confirmed = read.value;
        this.snapshot = { ...this.snapshot, readAt: Date.now() }; this.publish('ready'); return;
      }
      this.personId = read.personId;
      this.confirmed = read.value;
      this.snapshot = { ...this.snapshot, readAt: Date.now() };
      if (unresolved) {
        const sentKeys = Object.keys(unresolved.intentions) as Key[];
        const reflected = sentKeys.every(key => read.value[key] === unresolved.body[key]);
        if (read.value.version > unresolved.base.version && reflected) {
          this.intentions = acknowledgeFields<Choices>(this.intentions, unresolved.intentions);
          this.flight = null;
        } else if (read.value.version > unresolved.base.version) {
          this.publish('conflict', 'Ces préférences ont changé ailleurs. Vérifiez vos choix avant de les appliquer.'); return;
        } else {
          // A read at the old version does not prove that a previous PUT can no longer commit.
          // Retry the exact body and If-Match: the API accepts this version only once.
          this.publish('uncertain', 'Modification non confirmée. Vous pouvez renvoyer les mêmes choix.'); return;
        }
      }
      this.publish('ready');
      void this.pump();
    } catch (error) {
      if (generation !== this.generation) return;
      if ([401,403].includes((error as { status?: number } | null)?.status ?? 0)) {
        this.clear(); this.publish('unavailable', 'Reconnectez-vous pour consulter vos préférences.'); return;
      }
      this.publish(unresolved ? 'uncertain' : 'unavailable', 'Préférences indisponibles. Vos choix en attente restent dans cette page.');
    }
  }

  choose(key: Key, value: boolean) {
    if (!this.confirmed) return;
    this.intentions = { ...this.intentions, [key]: { value, revision: ++this.revision } };
    // Choosing again cannot resolve a request whose result is unknown.
    if (this.flight && !this.working) { this.publish(this.snapshot.phase, this.snapshot.message); return; }
    this.publish(this.working ? 'saving' : 'ready');
    void this.pump();
  }

  /** Explicit retry preserves the initial body/version until its result is resolved. */
  async retry() {
    if (this.working) return;
    if (this.snapshot.phase === 'conflict') {
      // The user has reviewed the fresh confirmed base. Only their intended fields are applied.
      this.flight = null; this.publish('ready'); await this.pump(); return;
    }
    if (this.flight) { await this.send(this.flight); return; }
    await this.refresh();
  }

  useConfirmed() {
    if (this.working || !this.confirmed || this.snapshot.phase !== 'conflict') return;
    this.intentions = {}; this.flight = null; this.publish('ready');
  }

  private async pump() {
    if (this.working || this.reading || this.flight || !this.confirmed || !this.personId) return;
    // Choices that already equal the confirmed state need no PUT.
    for (const key of Object.keys(this.intentions) as Key[]) if (this.intentions[key]?.value === this.confirmed[key]) delete this.intentions[key];
    if (!Object.keys(this.intentions).length) { this.publish('ready'); return; }
    const { version: _version, ...body } = projectFields(this.confirmed, this.intentions);
    await this.send({ base: this.confirmed, body, intentions: { ...this.intentions } });
  }

  private async send(flight: Flight) {
    if (!this.personId || this.working) return;
    const generation = this.generation;
    this.working = true; this.flight = flight; this.publish('saving');
    let outcome: SaveOutcome;
    try { outcome = await this.transport.write(this.personId, flight.body, flight.base.version); }
    catch { outcome = { ok: false, conflict: false, kind: 'uncertain' }; }
    if (generation !== this.generation) return;
    this.working = false;
    if (outcome.ok) {
      this.confirmed = outcome.value;
      this.intentions = acknowledgeFields<Choices>(this.intentions, flight.intentions);
      this.flight = null; this.snapshot = { ...this.snapshot, readAt: Date.now() };
      this.publish('ready');
      if (this.refreshAfterWrite) { this.refreshAfterWrite = false; await this.refresh(); } else await this.pump();
      return;
    }
    if (outcome.kind === 'contextChanged') { this.clear(); await this.refresh(); return; }
    if (outcome.kind === 'uncertain') { this.publish('uncertain', 'Modification non confirmée. Vérifiez son résultat avant de réessayer.'); return; }
    if (outcome.kind === 'rejected') {
      this.flight = null;
      // Only roll back the rejected generations, preserving choices made during the request.
      this.intentions = acknowledgeFields<Choices>(this.intentions, flight.intentions);
      this.publish('rejected', 'La modification a été refusée. Les autres choix sont conservés.');
      if (Object.keys(this.intentions).length) await this.pump();
      return;
    }
    // A definite 412 did not write. Rebase changes on other fields; same-field changes require review.
    try {
      const read = await this.transport.read();
      if (generation !== this.generation) return;
      if (read.personId !== this.personId) { this.clear(); await this.refresh(); return; }
      this.confirmed = read.value; this.snapshot = { ...this.snapshot, readAt: Date.now() };
      const conflicts = (Object.keys(flight.intentions) as Key[]).filter(key =>
        read.value[key] !== flight.base[key] && this.intentions[key]?.value !== read.value[key]);
      if (conflicts.length) { this.publish('conflict', 'Ces préférences ont changé ailleurs. Vérifiez vos choix avant de les appliquer.'); return; }
      this.flight = null; this.publish('ready');
      // One bounded automatic rebase. Further conflicts are left for explicit review.
      if (this.rebased) { this.flight = flight; this.publish('conflict', 'Les préférences changent sur un autre appareil. Vérifiez vos choix.'); return; }
      this.rebased = true; await this.pump(); this.rebased = false;
    } catch { if (generation === this.generation) this.publish('conflict', 'Préférences modifiées ailleurs. Leur nouvelle valeur est indisponible.'); }
  }
  private rebased = false;
}
