import { describe, expect, it } from 'vitest';
import { createCommand } from '../client/command-core.js';
import { agendaCounts, agendaDays, agendaFacts } from '../client/console/agenda-projection.js';
import {
  agendaMarkLabels, isProvisionalLesson, lessonResendAllowed, lessonResendReason, stillFollowed, visibleIntentions,
  type LessonIntention, type PlannedLessonDraft,
} from '../client/console/agenda-intentions.js';
import type { LessonForm } from '../client/lesson-planning-model.js';
import type { Lesson } from '../client/school-api.js';

const options = { timeZone: 'Europe/Zurich', from: '2026-10-25T23:00:00Z', to: '2026-11-01T23:00:00Z', instructor: '', includeCourses: false };
const lesson = (id: string, plannedStart = '2026-10-26T10:00:00Z', patch: Partial<Lesson> = {}): Lesson => ({ id, plannedStart,
  plannedEnd: new Date(Date.parse(plannedStart) + 3600000).toISOString(), instructorMembershipId: 'a', schoolId: 'school', learnerId: 'learner',
  trainingId: 'training', version: 3, timeZone: 'Europe/Zurich', meetingPoint: 'Gare', status: 'PLANNED', ...patch });

const form: LessonForm = { learnerId: 'learner', trainingId: 'training', instructorId: 'a', localStart: '2026-10-26T11:00', duration: '60',
  buffer: '10', meetingPoint: 'Gare', productId: '', commercialChange: false, reason: '', agreement: true, localChoice: '' };
const draft = (patch: Partial<PlannedLessonDraft> = {}): PlannedLessonDraft => ({ learnerId: 'learner', trainingId: 'training', instructorMembershipId: 'a',
  learnerDisplayName: 'Élève A', instructorDisplayName: 'Moniteur B', meetingPoint: 'Gare', timeZone: 'Europe/Zurich',
  plannedStart: '2026-10-26T09:00:00Z', plannedEnd: '2026-10-26T10:00:00Z', form, ...patch });

describe('création : une ligne provisoire, jamais une leçon de l’école', () => {
  it('n’a ni identifiant, ni version, ni identité de l’école, et ne s’ouvre pas comme une leçon', () => {
    const intention: LessonIntention = { tag: 'lesson:new', operationId: 'op-create', kind: 'lesson-create', draft: draft() };
    const days = agendaDays([], [], { ...options, intentions: [intention] });
    const event = days[0]!.items[0]!;
    expect(event.kind).toBe('lesson');
    if (event.kind !== 'lesson') throw new Error('leçon attendue');
    expect(event.provisional).toBe(true);
    expect(isProvisionalLesson(event.lesson.id)).toBe(true);
    expect(event.lesson.schoolId).toBe('');
    expect(event.lesson.version).toBe(0);
    expect(event.mark).toBe('planning');
    expect(agendaMarkLabels[event.mark!]).toBe('Planification en cours');
    // Aucune identité de l'école ne circule : rien à ouvrir, rien à annuler.
    expect(event.lesson.id).not.toBe('op-create');
  });

  it('reste une ligne de la semaine, comptée une fois, et disparaît quand elle n’est plus suivie', () => {
    const intention: LessonIntention = { tag: 'lesson:new', operationId: 'op-create', kind: 'lesson-create', draft: draft() };
    expect(agendaCounts(agendaDays([], [], { ...options, intentions: [intention] }).flatMap(day => day.items))).toEqual({ lessons: 1, courses: 0 });
    // Refusée ou abandonnée : le magasin ne la suit plus, elle n'est plus projetée ; les autres rendez-vous restent.
    const kept = agendaDays([lesson('l1')], [], { ...options, intentions: visibleIntentions([intention], new Set(), 1000) });
    expect(kept.flatMap(day => day.items).map(event => event.key)).toEqual(['lesson:l1']);
  });

  it('une intention confirmée reste affichée sans marque jusqu’à une lecture plus récente', () => {
    const settled: LessonIntention = { tag: 'lesson:new', operationId: 'op-create', kind: 'lesson-create', draft: draft(), settledAt: 5000 };
    const before = agendaDays([], [], { ...options, intentions: visibleIntentions([settled], new Set(), 4000) });
    expect(before[0]!.items[0]!.kind === 'lesson' && before[0]!.items[0]!.mark).toBeUndefined();
    expect(visibleIntentions([settled], new Set(), 5000)).toEqual([]);
  });
});

describe('déplacement : une seule identité logique', () => {
  const moving: LessonIntention = { tag: 'lesson:l1', operationId: 'op-move', kind: 'lesson-move', lessonId: 'l1',
    draft: draft({ plannedStart: '2026-10-27T13:00:00Z', plannedEnd: '2026-10-27T14:00:00Z' }) };

  it('garde le fait confirmé à sa place d’origine et marque la proposition à la cible', () => {
    const days = agendaDays([lesson('l1')], [], { ...options, intentions: [moving] });
    const [origin, target] = [days[0]!.items[0]!, days[1]!.items[0]!];
    expect(origin.key).toBe('lesson:l1');
    expect(origin.kind === 'lesson' && origin.mark).toBe('moving');
    expect(origin.kind === 'lesson' && origin.provisional).toBeUndefined();
    expect(target.key).toBe('move:op-move');
    expect(target.kind === 'lesson' && target.mark).toBe('move-proposal');
    expect(target.kind === 'lesson' && target.provisional).toBe(true);
    expect(target.kind === 'lesson' && target.logicalKey).toBe(origin.logicalKey);
    expect(agendaMarkLabels['move-proposal']).toBe('Nouveau créneau proposé');
  });

  it('ne compte jamais deux fois dans les totaux de la semaine', () => {
    const days = agendaDays([lesson('l1')], [], { ...options, intentions: [moving] });
    expect(agendaCounts(days.flatMap(day => day.items))).toEqual({ lessons: 1, courses: 0 });
    // Chaque jour montre sa ligne, mais le total de la semaine reste une leçon.
    expect(days.map(day => day.items.length)).toEqual([1, 1]);
  });

  it('après confirmation, la position confirmée est la cible ; l’ancienne place n’est plus montrée', () => {
    const settled = { ...moving, settledAt: 6000 } as LessonIntention;
    const days = agendaDays([lesson('l1')], [], { ...options, intentions: visibleIntentions([settled], new Set(), 5000) });
    expect(days.flatMap(day => day.items).map(event => event.key)).toEqual(['move:op-move']);
    const event = days[0]!.items[0]!;
    expect(event.kind === 'lesson' && event.mark).toBeUndefined();
    // Le créneau confirmé n'est pas encore relu : la ligne reste provisoire, donc non ouvrable.
    expect(event.kind === 'lesson' && event.provisional).toBe(true);
  });

  it('le déplacement d’une leçon hors de la fenêtre ne montre que la proposition', () => {
    const away = agendaDays([lesson('l1', '2026-11-20T10:00:00Z')], [], { ...options, intentions: [moving] });
    expect(away.flatMap(day => day.items).map(event => event.key)).toEqual(['move:op-move']);
  });
});

describe('annulation demandée : la leçon reste, le créneau n’est pas libéré', () => {
  const cancelling: LessonIntention = { tag: 'lesson:l1:cancel', operationId: 'op-cancel', kind: 'lesson-cancel', lessonId: 'l1' };

  it('garde la leçon à sa place, marquée « Annulation en cours »', () => {
    const days = agendaDays([lesson('l1')], [], { ...options, intentions: [cancelling] });
    const event = days[0]!.items[0]!;
    expect(event.key).toBe('lesson:l1');
    expect(event.kind === 'lesson' && event.mark).toBe('cancelling');
    expect(agendaMarkLabels.cancelling).toBe('Annulation en cours');
    // Rien n'est libéré : la journée n'est pas vide et la leçon compte toujours.
    expect(days[0]!.items).toHaveLength(1);
    expect(agendaCounts(days.flatMap(day => day.items))).toEqual({ lessons: 1, courses: 0 });
  });

  it('une annulation confirmée ne retire pas la leçon avant la relecture', () => {
    const settled = { ...cancelling, settledAt: 7000 } as LessonIntention;
    const days = agendaDays([lesson('l1')], [], { ...options, intentions: visibleIntentions([settled], new Set(), 6000) });
    expect(days[0]!.items.map(event => event.key)).toEqual(['lesson:l1']);
    expect(days[0]!.items[0]!.kind === 'lesson' && days[0]!.items[0]!.mark).toBeUndefined();
  });
});

describe('aucune intention provisoire dans un total', () => {
  it('les faits confirmés excluent la création provisoire et la proposition de créneau', () => {
    const intentions: LessonIntention[] = [
      { tag: 'lesson:new', operationId: 'op-create', kind: 'lesson-create', draft: draft({ plannedStart: '2026-10-28T09:00:00Z', plannedEnd: '2026-10-28T10:00:00Z' }) },
      { tag: 'lesson:l1', operationId: 'op-move', kind: 'lesson-move', lessonId: 'l1', draft: draft({ plannedStart: '2026-10-29T09:00:00Z', plannedEnd: '2026-10-29T10:00:00Z' }) },
      { tag: 'lesson:l2:cancel', operationId: 'op-cancel', kind: 'lesson-cancel', lessonId: 'l2' },
    ];
    const events = agendaDays([lesson('l1'), lesson('l2')], [], { ...options, intentions }).flatMap(day => day.items);
    expect(events).toHaveLength(4);
    const facts = agendaFacts(events);
    // Le fait d'origine et la leçon annulée restent des faits ; la création et la proposition n'en sont pas.
    expect(facts.map(event => event.key).sort()).toEqual(['lesson:l1', 'lesson:l2']);
    expect(agendaCounts(facts)).toEqual({ lessons: 2, courses: 0 });
  });
});

describe('demandes encore suivies', () => {
  const intentions: LessonIntention[] = [
    { tag: 'lesson:new', operationId: 'op-a', kind: 'lesson-create', draft: draft() },
    { tag: 'lesson:l1', operationId: 'op-b', kind: 'lesson-move', lessonId: 'l1', draft: draft() },
  ];
  it('seules les demandes que le magasin suit encore ordonnent la suivante', () => {
    expect(stillFollowed(intentions, new Set(['op-b'])).map(item => item.operationId)).toEqual(['op-b']);
    expect(stillFollowed(intentions, new Set())).toEqual([]);
    expect(visibleIntentions(intentions, new Set(['op-b']), undefined).map(item => item.operationId)).toEqual(['op-b']);
  });
});

describe('renvoi d’une planification dont l’horaire est passé', () => {
  const schoolId = '11111111-1111-4111-8111-111111111111';
  const now = Date.parse('2026-10-26T09:30:00Z');
  const create = (plannedStart: string) => createCommand({ schoolId, kind: 'createLesson', path: 'lessons', resourceVersion: 0, body: { plannedStart } });
  const move = (plannedStart: string) => createCommand({ schoolId, kind: 'moveLesson', path: 'lessons/11111111-1111-4111-8111-222222222222/move',
    resourceId: '11111111-1111-4111-8111-222222222222', resourceVersion: 3, ifMatch: 3, body: { plannedStart } });

  it('un créneau futur reste renvoyable, un créneau passé ne l’est plus', () => {
    expect(lessonResendAllowed({ kind: 'createLesson', command: create('2026-10-26T10:00:00Z') }, now)).toBe(true);
    expect(lessonResendAllowed({ kind: 'createLesson', command: create('2026-10-26T09:00:00Z') }, now)).toBe(false);
    expect(lessonResendAllowed({ kind: 'moveLesson', command: move('2026-10-26T10:00:00Z') }, now)).toBe(true);
    expect(lessonResendAllowed({ kind: 'moveLesson', command: move('2026-10-26T09:00:00Z') }, now)).toBe(false);
    expect(lessonResendReason({ kind: 'moveLesson', command: move('2026-10-26T09:00:00Z') }, now)).toContain('passé');
    expect(lessonResendReason({ kind: 'moveLesson', command: move('2026-10-26T10:00:00Z') }, now)).toBeNull();
  });

  it('une commande restaurée sans corps n’est pas renvoyée : elle ne prouve pas que le créneau est devant', () => {
    expect(lessonResendAllowed({ kind: 'createLesson', command: null }, now)).toBe(false);
    expect(lessonResendAllowed({ kind: 'moveLesson', command: null }, now)).toBe(false);
  });

  it('tout autre type de commande garde son comportement', () => {
    const cancel = createCommand({ schoolId, kind: 'cancelLesson', path: 'lessons/11111111-1111-4111-8111-222222222222/cancel',
      resourceId: '11111111-1111-4111-8111-222222222222', resourceVersion: 3, ifMatch: 3, body: { reasonCode: 'OTHER' } });
    expect(lessonResendAllowed({ kind: 'cancelLesson', command: cancel }, now)).toBe(true);
    expect(lessonResendAllowed({ kind: 'createInvitation', command: null }, now)).toBe(true);
    expect(lessonResendReason({ kind: 'createInvitation', command: null }, now)).toBeNull();
  });
});
