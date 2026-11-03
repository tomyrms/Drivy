import { describe, expect, it } from 'vitest';
import {
  PeriodReads, PERIOD_FRESH_MS, PERIOD_MEMORY_LIMIT, neighbourPeriods, type PeriodSelection,
} from '../client/console/period-cache.js';
import { ScopedReadCache } from '../client/console/load-model.js';
import { addDays } from '../client/agenda-model.js';
import { agendaCounts, agendaDays, agendaFacts } from '../client/console/agenda-projection.js';
import { visibleIntentions, type LessonIntention, type PlannedLessonDraft } from '../client/console/agenda-intentions.js';
import type { LessonForm } from '../client/lesson-planning-model.js';
import type { Lesson } from '../client/school-api.js';

const lessonsScope = { resource: 'lessons' as const, schoolId: '11111111-1111-4111-8111-111111111111', accessEpoch: 4 };
const weekA = '2026-10-26';
const weekB = '2026-11-02';
const selection = (period: string, instructor = ''): PeriodSelection => ({ period, instructor });
const tick = () => new Promise<void>(resolve => setTimeout(resolve, 0));

/** Transport simulé et compté : une lecture par appel, aucune écriture. */
function countedTransport(answer: (selection: PeriodSelection) => string[] = item => [`${item.period}|${item.instructor}`]) {
  const calls: PeriodSelection[] = [];
  const load = async (item: PeriodSelection): Promise<string[]> => { calls.push(item); return answer(item); };
  return { calls, load };
}

/** Transport manuel : chaque lecture attend d'être résolue par le test, pour produire un ordre choisi. */
function deferredTransport() {
  const calls: PeriodSelection[] = [];
  const waiting: { item: PeriodSelection; resolve: (value: string[]) => void; reject: (error: unknown) => void }[] = [];
  const load = (item: PeriodSelection) => {
    calls.push(item);
    return new Promise<string[]>((resolve, reject) => { waiting.push({ item, resolve, reject }); });
  };
  return { calls, waiting, load };
}

describe('période déjà lue : affichage immédiat, jamais celle d’une autre période', () => {
  it('revient sur une semaine lue sans squelette, avec une relecture discrète', async () => {
    let now = 1_000_000;
    const transport = countedTransport();
    const reads = new PeriodReads<string[]>({ ...lessonsScope, load: transport.load, now: () => now });
    reads.show(selection(weekA));
    // Jamais lue : squelette honnête, aucune donnée d'une autre période.
    expect(reads.entry(selection(weekA))).toMatchObject({ status: 'loading', data: undefined, error: null });
    await tick();
    expect(reads.entry(selection(weekA))).toMatchObject({ status: 'ready', data: [`${weekA}|`], readAt: now });

    // Semaine suivante, jamais lue : squelette, et jamais les leçons de la semaine précédente.
    reads.show(selection(weekB));
    expect(reads.entry(selection(weekB))).toMatchObject({ status: 'loading', data: undefined });
    await tick();

    // Retour : données tout de suite, sans attendre, et moins de 30 s après la lecture ⇒ aucune lecture relancée.
    now += 5_000;
    const callsBefore = transport.calls.length;
    reads.show(selection(weekA));
    expect(reads.entry(selection(weekA))).toMatchObject({ status: 'ready', data: [`${weekA}|`] });
    expect(transport.calls.length).toBe(callsBefore);

    // Passé le délai de fraîcheur : les données restent affichées pendant la relecture discrète.
    now += PERIOD_FRESH_MS;
    const statusBefore = reads.entry(selection(weekA));
    reads.show(selection(weekA));
    expect(reads.entry(selection(weekA))).toBe(statusBefore);
    expect(reads.entry(selection(weekA))?.status).toBe('ready');
    expect(reads.entry(selection(weekA))?.data).toEqual([`${weekA}|`]);
    expect(transport.calls.length).toBe(callsBefore + 1);
    await tick();
    expect(reads.entry(selection(weekA))?.readAt).toBe(now);
  });

  it('ne montre jamais la période d’un autre moniteur', async () => {
    const transport = countedTransport();
    const reads = new PeriodReads<string[]>({ ...lessonsScope, load: transport.load });
    reads.show(selection(weekA, 'moniteur-a'));
    await tick();
    expect(reads.entry(selection(weekA, 'moniteur-a'))?.data).toEqual([`${weekA}|moniteur-a`]);
    reads.show(selection(weekA, 'moniteur-b'));
    expect(reads.entry(selection(weekA, 'moniteur-b'))).toMatchObject({ status: 'loading', data: undefined });
    await tick();
    expect(reads.entry(selection(weekA, 'moniteur-b'))?.data).toEqual([`${weekA}|moniteur-b`]);
    // Retour sur le filtre déjà lu : immédiat, sans lecture.
    reads.show(selection(weekA, 'moniteur-a'));
    expect(reads.entry(selection(weekA, 'moniteur-a'))?.data).toEqual([`${weekA}|moniteur-a`]);
    expect(transport.calls.map(item => item.instructor)).toEqual(['moniteur-a', 'moniteur-b']);
  });
});

describe('réponses hors ordre : seule la dernière demande de la clé affichée est appliquée', () => {
  it('une réponse ancienne pour une autre semaine ne touche pas la semaine affichée', async () => {
    const transport = deferredTransport();
    const reads = new PeriodReads<string[]>({ ...lessonsScope, load: transport.load });
    reads.show(selection(weekA));
    reads.show(selection(weekB));
    expect(transport.waiting).toHaveLength(2);

    transport.waiting[1]!.resolve([`${weekB}|récente`]);
    await tick();
    const shown = reads.entry(selection(weekB));
    expect(shown?.data).toEqual([`${weekB}|récente`]);

    // L'ancienne réponse de la semaine A arrive après : elle ne remplace rien à l'écran.
    transport.waiting[0]!.resolve([`${weekA}|ancienne`]);
    await tick();
    expect(reads.entry(selection(weekB))).toBe(shown);
    expect(reads.entry(selection(weekA))?.data).toEqual([`${weekA}|ancienne`]);
  });

  it('une réponse antérieure à une purge ne repeuple pas une mémoire vidée', async () => {
    const transport = deferredTransport();
    const reads = new PeriodReads<string[]>({ ...lessonsScope, load: transport.load });
    reads.show(selection(weekA));
    reads.purge();
    expect(reads.entry(selection(weekA))).toBeUndefined();
    reads.show(selection(weekA));
    expect(transport.waiting).toHaveLength(2);

    transport.waiting[1]!.resolve(['après purge']);
    await tick();
    transport.waiting[0]!.resolve(['avant purge']);
    await tick();
    expect(reads.entry(selection(weekA))?.data).toEqual(['après purge']);
  });
});

describe('préchargement borné et mémoire bornée', () => {
  it('ne précharge que la période précédente et la suivante, et seulement après l’affichage', async () => {
    const transport = countedTransport();
    const reads = new PeriodReads<string[]>({ ...lessonsScope, load: transport.load });
    reads.show(selection(weekA, 'moniteur-a'));
    // Pendant le chargement, aucun préchargement.
    reads.prefetchNeighbours(selection(weekA, 'moniteur-a'));
    expect(transport.calls).toHaveLength(1);
    await tick();

    reads.prefetchNeighbours(selection(weekA, 'moniteur-a'));
    expect(transport.calls.map(item => item.period)).toEqual([weekA, addDays(weekA, -7), addDays(weekA, 7)]);
    expect(transport.calls.every(item => item.instructor === 'moniteur-a')).toBe(true);
    expect(neighbourPeriods(weekA)).toEqual([addDays(weekA, -7), addDays(weekA, 7)]);

    // Une seconde demande dans la fenêtre de fraîcheur ne relit pas les voisines.
    await tick();
    reads.prefetchNeighbours(selection(weekA, 'moniteur-a'));
    expect(transport.calls).toHaveLength(3);
  });

  it('ne garde qu’un nombre limité de périodes et ne perd jamais celle qui est affichée', async () => {
    const transport = countedTransport();
    const reads = new PeriodReads<string[]>({ ...lessonsScope, load: transport.load });
    const periods = Array.from({ length: PERIOD_MEMORY_LIMIT + 3 }, (_, index) => addDays('2026-09-07', index * 7));
    for (const period of periods) { reads.show(selection(period)); await tick(); }
    expect(reads.size).toBe(PERIOD_MEMORY_LIMIT);
    const displayed = periods.at(-1)!;
    expect(reads.entry(selection(displayed))?.data).toBeDefined();
    expect(reads.entry(selection(periods[0]!))).toBeUndefined();
  });
});

describe('échec de relecture : les données restent, « Réessayer » relit', () => {
  it('une panne garde la période affichée et sa date de lecture ; un refus la retire', async () => {
    let now = 2_000_000;
    let failure: { status: number } | null = null;
    let calls = 0;
    const reads = new PeriodReads<string[]>({ ...lessonsScope, now: () => now,
      load: async item => { calls++; if (failure) throw failure; return [`${item.period}|lue`]; },
      describe: error => (error as { status: number }).status === 403 ? 'Accès refusé' : 'Connexion interrompue' });
    reads.show(selection(weekA));
    await tick();
    const readAt = reads.entry(selection(weekA))?.readAt;
    expect(readAt).toBe(now);

    failure = { status: 503 };
    now += PERIOD_FRESH_MS + 1;
    reads.refresh(selection(weekA));
    await tick();
    expect(reads.entry(selection(weekA))).toMatchObject({ status: 'error', data: [`${weekA}|lue`], error: 'Connexion interrompue', readAt });

    // « Réessayer » garde aussi les données tant que la lecture n'a pas répondu.
    failure = null;
    const before = calls;
    reads.reload(selection(weekA));
    expect(reads.entry(selection(weekA))?.data).toEqual([`${weekA}|lue`]);
    expect(calls).toBe(before + 1);
    await tick();
    expect(reads.entry(selection(weekA))).toMatchObject({ status: 'ready', error: null });

    // Un refus d'accès retire les données : elles ne sont plus autorisées.
    failure = { status: 403 };
    reads.reload(selection(weekA));
    await tick();
    expect(reads.entry(selection(weekA))).toMatchObject({ status: 'error', data: undefined, error: 'Accès refusé' });
  });

  it('une période en échec n’est pas relancée d’elle-même au retour', async () => {
    let failure = true;
    const calls: string[] = [];
    const reads = new PeriodReads<string[]>({ ...lessonsScope,
      load: async item => { calls.push(item.period); if (failure) throw { status: 500 }; return [item.period]; } });
    reads.show(selection(weekA));
    await tick();
    failure = false;
    reads.show(selection(weekB));
    await tick();
    reads.show(selection(weekA));
    await tick();
    expect(calls.filter(period => period === weekA)).toEqual([weekA]);
    expect(reads.entry(selection(weekA))?.status).toBe('error');
  });
});

describe('retour sur l’agenda et cache de la portée', () => {
  it('un remontage retrouve la période lue sans aucune lecture, puis la relit discrètement', async () => {
    let now = 5_000_000;
    const store = new ScopedReadCache(40, 120_000, () => now);
    let calls = 0;
    const load = async (item: PeriodSelection) => { calls++; return [`${item.period}|relue`]; };
    const first = new PeriodReads<string[]>({ ...lessonsScope, store, load, now: () => now });
    first.show(selection(weekA));
    await tick();
    expect(calls).toBe(1);

    // Nouvelle instance : l'agenda a été quitté puis rouvert dans la même portée.
    const second = new PeriodReads<string[]>({ ...lessonsScope, store, load, now: () => now });
    expect(second.entry(selection(weekA))).toMatchObject({ status: 'ready', data: [`${weekA}|relue`] });
    second.show(selection(weekA));
    await tick();
    expect(calls).toBe(1);
    expect(second.entry(selection(weekA))?.status).toBe('ready');

    now += PERIOD_FRESH_MS + 1;
    second.show(selection(weekA));
    expect(second.entry(selection(weekA))?.status).toBe('ready');
    await tick();
    expect(calls).toBe(2);
  });

  it('une période évincée quitte le cache de la portée et n’est pas retrouvée au remontage', async () => {
    let now = 6_000_000;
    const store = new ScopedReadCache(40, 120_000, () => now);
    const reads = new PeriodReads<string[]>({ ...lessonsScope, store, limit: 2, now: () => now,
      load: async item => [item.period] });
    for (const period of [weekA, weekB, '2026-11-09'] as const) { reads.show(selection(period)); await tick(); }
    expect(reads.size).toBe(2);
    const reopened = new PeriodReads<string[]>({ ...lessonsScope, store, limit: 2, now: () => now, load: async item => [item.period] });
    expect(reopened.entry(selection(weekA))).toBeUndefined();
    expect(reopened.entry(selection('2026-11-09'))?.data).toEqual(['2026-11-09']);
  });

  it('une purge retire aussi les périodes du cache de la portée', async () => {
    const store = new ScopedReadCache();
    const reads = new PeriodReads<string[]>({ ...lessonsScope, store, load: async item => [item.period] });
    reads.show(selection(weekA));
    await tick();
    reads.purge();
    expect(new PeriodReads<string[]>({ ...lessonsScope, store, load: async () => ['neuf'] }).entry(selection(weekA))).toBeUndefined();
  });

  it('compte les lectures de la séquence : ouvrir, semaine suivante, revenir, changer de moniteur', async () => {
    const store = new ScopedReadCache();
    const calls: string[] = [];
    const load = (tag: string) => async (item: PeriodSelection) => { calls.push(`${tag}:${item.period}:${item.instructor}`); return [tag]; };
    const lessons = new PeriodReads<string[]>({ ...lessonsScope, store, load: load('lessons') });
    const courses = new PeriodReads<string[]>({ ...lessonsScope, resource: 'courses', store, load: load('courses') });
    const displayed = (): [string, string] => [lessons.entry(selection(weekA))?.status ?? '', courses.entry(selection(weekA, ''))?.status ?? ''];

    // Ouvrir : deux lectures affichées, puis les deux voisines de chaque ressource.
    lessons.show(selection(weekA)); courses.show(selection(weekA, ''));
    expect(displayed()).toEqual(['loading', 'loading']);
    await tick();
    lessons.prefetchNeighbours(selection(weekA)); courses.prefetchNeighbours(selection(weekA, ''));
    await tick();
    expect(calls).toHaveLength(6);

    // Avancer d'une semaine : déjà préchargée, elle s'affiche sans attendre ; le préchargement vise C, A est fraîche.
    lessons.show(selection(weekB)); courses.show(selection(weekB, ''));
    expect(lessons.entry(selection(weekB))?.status).toBe('ready');
    await tick();
    lessons.prefetchNeighbours(selection(weekB)); courses.prefetchNeighbours(selection(weekB, ''));
    await tick();
    expect(calls).toHaveLength(8);

    // Revenir : rien à lire dans la fenêtre de fraîcheur.
    lessons.show(selection(weekA)); courses.show(selection(weekA, ''));
    expect(lessons.entry(selection(weekA))?.status).toBe('ready');
    await tick();
    lessons.prefetchNeighbours(selection(weekA)); courses.prefetchNeighbours(selection(weekA, ''));
    await tick();
    expect(calls).toHaveLength(8);

    // Changer de moniteur : la clé change (leçons seules), la semaine et ses deux voisines sont lues une fois.
    lessons.show(selection(weekA, 'moniteur-a'));
    expect(lessons.entry(selection(weekA, 'moniteur-a'))?.status).toBe('loading');
    await tick();
    lessons.prefetchNeighbours(selection(weekA, 'moniteur-a'));
    await tick();
    expect(calls).toHaveLength(11);
    expect(calls.filter(call => call.startsWith('courses:'))).toHaveLength(4);

    // Revenir à « Tous les moniteurs » : immédiat, sans lecture.
    lessons.show(selection(weekA));
    expect(lessons.entry(selection(weekA))?.status).toBe('ready');
    await tick();
    expect(calls).toHaveLength(11);
  });
});

describe('purge au changement de portée', () => {
  it('une instance neuve (autre compte, école, époque ou droits) est vide', async () => {
    const transport = countedTransport();
    const first = new PeriodReads<string[]>({ ...lessonsScope, load: transport.load });
    first.show(selection(weekA));
    await tick();
    expect(first.size).toBe(1);
    const second = new PeriodReads<string[]>({ ...lessonsScope, accessEpoch: 5, load: transport.load });
    expect(second.size).toBe(0);
    expect(second.entry(selection(weekA))).toBeUndefined();
    first.purge();
    expect(first.size).toBe(0);
    expect(first.entry(selection(weekA))).toBeUndefined();
  });
});

describe('intentions de planification et identité d’écran à travers une relecture', () => {
  const lesson = (id: string, plannedStart = '2026-10-26T10:00:00Z'): Lesson => ({ id, plannedStart,
    plannedEnd: new Date(Date.parse(plannedStart) + 3600000).toISOString(), instructorMembershipId: 'a', schoolId: 'school',
    learnerId: 'learner', trainingId: 'training', version: 3, timeZone: 'Europe/Zurich', meetingPoint: 'Gare', status: 'PLANNED' });
  const form: LessonForm = { learnerId: 'learner', trainingId: 'training', instructorId: 'a', localStart: '2026-10-26T11:00', duration: '60',
    buffer: '10', meetingPoint: 'Gare', productId: '', commercialChange: false, reason: '', agreement: true, localChoice: '' };
  const draft = (patch: Partial<PlannedLessonDraft> = {}): PlannedLessonDraft => ({ learnerId: 'learner', trainingId: 'training',
    instructorMembershipId: 'a', learnerDisplayName: 'Élève A', instructorDisplayName: 'Moniteur B', meetingPoint: 'Gare',
    timeZone: 'Europe/Zurich', plannedStart: '2026-10-26T09:00:00Z', plannedEnd: '2026-10-26T10:00:00Z', form, ...patch });
  const window = { timeZone: 'Europe/Zurich', from: '2026-10-25T23:00:00Z', to: '2026-11-01T23:00:00Z', instructor: '', includeCourses: false };
  const intentions: LessonIntention[] = [
    { tag: 'lesson:new', operationId: 'op-create', kind: 'lesson-create', draft: draft() },
    { tag: 'lesson:l1', operationId: 'op-move', kind: 'lesson-move', lessonId: 'l1',
      draft: draft({ plannedStart: '2026-10-27T13:00:00Z', plannedEnd: '2026-10-27T14:00:00Z' }) },
  ];

  it('les créations provisoires et les déplacements restent projetés après une relecture discrète', async () => {
    let now = 3_000_000;
    let reading = 0;
    const reads = new PeriodReads<Lesson[]>({ ...lessonsScope, now: () => now,
      load: async () => (reading++ === 0 ? [lesson('l1')] : [lesson('l1'), lesson('l2', '2026-10-28T10:00:00Z')]) });
    reads.show(selection(weekA));
    await tick();
    const first = agendaDays(reads.entry(selection(weekA))!.data!, [], { ...window, intentions });
    // Relecture discrète : de nouveaux faits arrivent, les intentions restent suivies (le magasin n'a pas répondu).
    now += PERIOD_FRESH_MS + 1;
    reads.refresh(selection(weekA));
    await tick();
    const second = agendaDays(reads.entry(selection(weekA))!.data!, [], { ...window, intentions });

    for (const [index, days] of [first, second].entries()) {
      const events = days.flatMap(day => day.items);
      expect(events.filter(event => event.kind === 'lesson' && event.provisional === true).map(event => event.key))
        .toEqual(['create:op-create', 'move:op-move']);
      expect(events.find(event => event.key === 'lesson:l1' && event.kind === 'lesson' && event.mark === 'moving')).toBeDefined();
      // Les intentions ne changent aucun fait ni aucun total : seuls les faits lus font le compte.
      expect(agendaFacts(events).some(event => event.kind === 'lesson' && event.provisional === true)).toBe(false);
      expect(agendaCounts(events)).toEqual({ lessons: index === 0 ? 2 : 3, courses: 0 });
    }
    // Les faits lus ont bien été remplacés par la relecture.
    expect(second[2]!.items.map(event => event.key)).toEqual(['lesson:l2']);
  });

  it('mêmes clés d’événement avant et après la relecture : rien n’est remonté à l’écran', async () => {
    const reads = new PeriodReads<Lesson[]>({ ...lessonsScope, load: async () => [lesson('l1')] });
    reads.show(selection(weekA));
    await tick();
    const before = agendaDays(reads.entry(selection(weekA))!.data!, [], { ...window, intentions }).flatMap(day => day.items).map(event => event.key);
    reads.refresh(selection(weekA));
    await tick();
    const after = agendaDays(reads.entry(selection(weekA))!.data!, [], { ...window, intentions }).flatMap(day => day.items).map(event => event.key);
    expect(after).toEqual(before);
  });

  it('une intention confirmée n’est retirée que par une lecture plus récente que sa confirmation', async () => {
    let now = 4_000_000;
    const reads = new PeriodReads<Lesson[]>({ ...lessonsScope, now: () => now, load: async () => [lesson('l1'), lesson('l2')] });
    reads.show(selection(weekA));
    await tick();
    const settled = intentions.map(intention => ({ ...intention, settledAt: now + 1_000 }));
    const readAt = reads.entry(selection(weekA))!.readAt;
    expect(visibleIntentions(settled, new Set(), readAt)).toHaveLength(2);
    now += 5_000;
    reads.refresh(selection(weekA));
    await tick();
    // La lecture est plus récente que la confirmation : le fait confirmé remplace l'intention, sans doublon.
    expect(visibleIntentions(settled, new Set(), reads.entry(selection(weekA))!.readAt)).toEqual([]);
    expect(agendaCounts(agendaDays(reads.entry(selection(weekA))!.data!, [], { ...window,
      intentions: visibleIntentions(settled, new Set(), reads.entry(selection(weekA))!.readAt) }).flatMap(day => day.items)))
      .toEqual({ lessons: 2, courses: 0 });
  });
});
