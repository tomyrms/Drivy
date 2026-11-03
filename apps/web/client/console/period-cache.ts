import { addDays } from '../agenda-model.js';
import type { ScopedReadCache } from './load-model.js';

/**
 * Une lecture d'agenda bornée par période (#107/#108). Ce module ne connaît ni React ni le réseau : il garde une projection
 * par période et par moniteur, décide ce qui peut être montré sans attendre, et n'applique que la réponse de la dernière
 * lecture de la clé concernée. Une journée se lit dans la projection de sa semaine : la période est le premier jour de la
 * fenêtre (le lundi de la semaine d'agenda).
 */
export type PeriodResource = 'lessons' | 'courses';

/** Une période affichée, filtrée par moniteur (`''` : tous les moniteurs). */
export type PeriodSelection = { readonly period: string; readonly instructor: string };

export type PeriodEntry<T> = {
  status: 'loading' | 'ready' | 'error';
  data: T | undefined;
  error: string | null;
  needsLogin?: boolean;
  /** Instant de la dernière lecture réussie qui a produit ces données. */
  readAt?: number;
};

/**
 * Périodes gardées en mémoire, par ressource : la période affichée, ses deux voisines préchargées, et de quoi revenir sur
 * deux semaines ou deux moniteurs récents. Au-delà, la plus anciennement touchée est évincée (elle quitte aussi le cache
 * de lecture de la portée) ; la période affichée ne l'est jamais.
 */
export const PERIOD_MEMORY_LIMIT = 8;
/** Une période lue il y a moins de trente secondes est montrée sans relancer de lecture (une relecture reste possible). */
export const PERIOD_FRESH_MS = 30_000;
/** Préchargement borné : au plus la période précédente et la suivante, jamais au-delà. */
export const PERIOD_NEIGHBOURS = 1;

/** La période précédente et la suivante d'une fenêtre d'agenda, dans l'ordre. */
export function neighbourPeriods(period: string): string[] {
  const periods: string[] = [];
  for (let offset = 1; offset <= PERIOD_NEIGHBOURS; offset++) periods.push(addDays(period, -7 * offset));
  for (let offset = 1; offset <= PERIOD_NEIGHBOURS; offset++) periods.push(addDays(period, 7 * offset));
  return periods;
}

export type PeriodReadsOptions<T> = {
  resource: PeriodResource;
  schoolId: string;
  accessEpoch: number;
  load: (selection: PeriodSelection) => Promise<T>;
  /** Cache de lecture de la portée (mémoire seulement, recréé avec la portée) : un retour sur l'agenda retrouve ses périodes. */
  store?: ScopedReadCache | undefined;
  limit?: number;
  freshFor?: number;
  now?: () => number;
  /** Message d'un échec ; le défaut ne dépend d'aucun module de rendu. */
  describe?: (error: unknown) => string;
};

type Retained<T> = { entry: PeriodEntry<T>; touchedAt: number };

const statusOf = (error: unknown): number => (error as { status?: number } | null)?.status ?? 0;

/**
 * Projections de l'agenda dans une portée autorisée (école, époque d'accès) : une instance neuve est une mémoire vide,
 * donc un changement de compte, d'école, d'époque ou de droits purge tout sans code de purge à oublier.
 */
export class PeriodReads<T> {
  private readonly resource: PeriodResource;
  private readonly schoolId: string;
  private readonly accessEpoch: number;
  private readonly load: (selection: PeriodSelection) => Promise<T>;
  private readonly limit: number;
  private readonly freshFor: number;
  private readonly now: () => number;
  private readonly describe: (error: unknown) => string;
  private readonly store: ScopedReadCache | undefined;
  private readonly entries = new Map<string, Retained<T>>();
  private readonly generations = new Map<string, number>();
  private readonly inFlight = new Set<string>();
  private readonly listeners = new Set<() => void>();
  private displayed: string | null = null;
  /** Incrémenté par `purge` : une réponse antérieure ne repeuple jamais une mémoire purgée. */
  private epoch = 0;
  private version = 0;

  constructor(options: PeriodReadsOptions<T>) {
    this.resource = options.resource;
    this.schoolId = options.schoolId;
    this.accessEpoch = options.accessEpoch;
    this.load = options.load;
    this.limit = Math.max(1, options.limit ?? PERIOD_MEMORY_LIMIT);
    this.freshFor = options.freshFor ?? PERIOD_FRESH_MS;
    this.now = options.now ?? Date.now;
    this.describe = options.describe ?? (error => error instanceof Error ? error.message : 'La lecture a échoué.');
    this.store = options.store;
  }

  /** Clé de lecture complète : ressource, école, époque d'accès, moniteur filtré, période. */
  private keyOf(selection: PeriodSelection): string {
    return `agenda/${this.resource}/${this.schoolId}/${this.accessEpoch}/${selection.instructor || '*'}/${selection.period}`;
  }

  /** Une période rangée dans le cache de la portée (retour sur l'agenda) est adoptée, sans lecture. */
  private adopt(key: string): void {
    if (this.entries.has(key)) return;
    const stored = this.store?.peek<T>(key);
    if (!stored) return;
    this.entries.set(key, { entry: { status: 'ready', data: stored.value, error: null, readAt: stored.readAt }, touchedAt: this.now() });
    this.trim();
  }

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  };

  /** Numéro de version lu par `useSyncExternalStore` : il change à chaque écriture de la mémoire. */
  getVersion = (): number => this.version;

  /** Nombre de périodes retenues ; visible pour vérifier la borne mémoire. */
  get size(): number { return this.entries.size; }

  entry(selection: PeriodSelection): PeriodEntry<T> | undefined {
    const key = this.keyOf(selection);
    const retained = this.entries.get(key);
    if (retained) return retained.entry;
    // Retour sur l'agenda : la période est encore dans le cache de la portée, elle s'affiche sans attendre.
    const stored = this.store?.peek<T>(key);
    return stored ? { status: 'ready', data: stored.value, error: null, readAt: stored.readAt } : undefined;
  }

  /**
   * Affiche une période : une période déjà lue apparaît tout de suite, une période jamais lue est honnêtement en
   * chargement. Une période en échec n'est pas relancée d'elle-même : « Réessayer » est explicite.
   */
  show(selection: PeriodSelection): void {
    const key = this.keyOf(selection);
    this.displayed = key;
    this.adopt(key);
    if (this.inFlight.has(key)) return;
    const retained = this.entries.get(key);
    if (!retained) { this.start(selection, key, 'blocking'); return; }
    if (retained.entry.status === 'error') return;
    if (retained.entry.readAt !== undefined && this.now() - retained.entry.readAt < this.freshFor) return;
    this.start(selection, key, retained.entry.data !== undefined ? 'silent' : 'blocking');
  }

  /** Relecture discrète : ce qui est affiché reste à l'écran jusqu'à la réponse. */
  refresh(selection: PeriodSelection): void {
    const key = this.keyOf(selection);
    this.displayed = key;
    this.start(selection, key, 'silent', true);
  }

  /** « Réessayer » : lecture explicite ; les données déjà affichées restent si la lecture échoue encore. */
  reload(selection: PeriodSelection): void {
    const key = this.keyOf(selection);
    this.displayed = key;
    this.start(selection, key, this.entries.get(key)?.entry.data !== undefined ? 'silent' : 'blocking', true);
  }

  /** Au plus la période précédente et la suivante, et seulement une fois la période affichée sur l'écran. */
  prefetchNeighbours(selection: PeriodSelection): void {
    const key = this.keyOf(selection);
    if (this.displayed !== key || this.entries.get(key)?.entry.status !== 'ready') return;
    for (const period of neighbourPeriods(selection.period)) {
      const neighbour: PeriodSelection = { period, instructor: selection.instructor };
      const neighbourKey = this.keyOf(neighbour);
      if (this.inFlight.has(neighbourKey)) continue;
      const retained = this.entries.get(neighbourKey);
      if (retained?.entry.status === 'error') continue;
      if (retained?.entry.readAt !== undefined && this.now() - retained.entry.readAt < this.freshFor) continue;
      this.start(neighbour, neighbourKey, 'silent');
    }
  }

  /** Tout oublier ; les réponses encore en vol ne repeuplent rien. */
  purge(): void {
    this.epoch++;
    if (this.store) for (const key of this.entries.keys()) this.store.invalidate(key);
    this.entries.clear();
    this.inFlight.clear();
    this.generations.clear();
    this.displayed = null;
    this.emit();
  }

  private start(selection: PeriodSelection, key: string, mode: 'blocking' | 'silent', force = false): void {
    if (this.inFlight.has(key)) return;
    const retained = this.entries.get(key);
    if (!force && mode === 'silent' && retained?.entry.readAt !== undefined && this.now() - retained.entry.readAt < this.freshFor) return;
    const generation = (this.generations.get(key) ?? 0) + 1;
    this.generations.set(key, generation);
    const epoch = this.epoch;
    const previous = retained?.entry;
    this.inFlight.add(key);
    // Une seule chose montre un squelette : l'absence de données. Une relecture ne vide jamais l'écran.
    if (previous?.data === undefined) this.put(key, { status: 'loading', data: undefined, error: null });
    const request = this.store ? this.store.read(key, () => this.load(selection)) : this.load(selection);
    request.then(data => {
      if (this.epoch !== epoch || this.generations.get(key) !== generation) return;
      this.inFlight.delete(key);
      // Évincée pendant la lecture : elle ne revient ni dans la fenêtre ni dans le cache de la portée.
      if (!this.entries.has(key)) { this.store?.invalidate(key); return; }
      this.put(key, { status: 'ready', data, error: null, readAt: this.now() });
    }, error => {
      if (this.epoch !== epoch || this.generations.get(key) !== generation) return;
      this.inFlight.delete(key);
      if (!this.entries.has(key)) { this.store?.invalidate(key); return; }
      const status = statusOf(error);
      const kept = [401, 403, 404].includes(status) ? undefined : previous?.data;
      this.put(key, { status: 'error', data: kept, error: this.describe(error),
        ...(status === 401 ? { needsLogin: true } : {}),
        ...(kept !== undefined && previous?.readAt !== undefined ? { readAt: previous.readAt } : {}) });
    });
  }

  private put(key: string, entry: PeriodEntry<T>): void {
    this.entries.set(key, { entry, touchedAt: this.now() });
    this.trim();
    this.emit();
  }

  /** Borne mémoire : la plus anciennement touchée sort, jamais la période affichée ; sa clé quitte aussi le cache de la portée. */
  private trim(): void {
    while (this.entries.size > this.limit) {
      const victim = [...this.entries].filter(([candidate]) => candidate !== this.displayed)
        .sort((a, b) => a[1].touchedAt - b[1].touchedAt)[0];
      if (!victim) break;
      this.entries.delete(victim[0]);
      this.generations.delete(victim[0]);
      this.store?.invalidate(victim[0]);
    }
  }

  private emit(): void {
    this.version++;
    for (const listener of this.listeners) listener();
  }
}
