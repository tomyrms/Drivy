import { describe, expect, it } from 'vitest';
import type { Availability, Closure } from '../../school-api';
import { draftFromRule, ruleGroups, ruleProblems, weekRows } from './schedule-model';
import { isProvisional, projectAbsences, projectRules, sameFamilyFollowed, stillFollowed, visibleIntentions, type ScheduleIntention } from './schedule-projection';

const rule = (id: string, patch: Partial<Availability> = {}): Availability => ({ id, schoolId: 'school', version: 3, instructorMembershipId: 'a',
  weekdays: [1, 2, 3, 4, 5], localStart: '08:00', localEnd: '12:00', validFrom: '2026-10-01', validUntil: null, ...patch });
const closure = (id: string, patch: Partial<Closure> = {}): Closure => ({ id, schoolId: 'school', version: 2, instructorMembershipId: 'a',
  startsAt: '2026-11-10T07:00:00.000Z', endsAt: '2026-11-10T16:00:00.000Z', reason: null, ...patch });
const today = '2026-10-28';
const draft = (patch: Partial<ReturnType<typeof draftFromRule>> = {}) => ({ ...draftFromRule(null, today), ...patch });

describe('projection locale des horaires', () => {
  it('ajoute une ligne provisoire sans identifiant ni version de l’école, marquée « à confirmer »', () => {
    const intention: ScheduleIntention = { tag: 'rule:new', operationId: 'op-1', kind: 'rule-create', instructor: 'a', draft: draft({ weekdays: [6], start: '09:00', end: '11:00' }) };
    const { rules, marks } = projectRules([rule('r1')], [intention], 'a');
    expect(rules.map(item => item.id)).toEqual(['r1', 'pending:op-1']);
    const added = rules[1]!;
    expect(isProvisional(added.id)).toBe(true);
    expect(added.version).toBe(0);
    expect(added.schoolId).toBe('');
    expect(marks.get(added.id)).toBe('creating');
    expect(marks.has('r1')).toBe(false);
  });

  it('montre les valeurs voulues d’une modification sans toucher l’horaire confirmé', () => {
    const confirmed = [rule('r1')];
    const intention: ScheduleIntention = { tag: 'rule:r1', operationId: 'op-2', kind: 'rule-update', instructor: 'a', ruleId: 'r1', draft: draft({ weekdays: [1, 3], start: '10:00', end: '13:00', from: '2026-10-01' }) };
    const { rules, marks } = projectRules(confirmed, [intention], 'a');
    expect(rules[0]).toMatchObject({ id: 'r1', version: 3, weekdays: [1, 3], localStart: '10:00', localEnd: '13:00' });
    expect(marks.get('r1')).toBe('changing');
    // L’original n’est pas modifié : une lecture de l’école reste la seule source de la semaine type.
    expect(confirmed[0]).toMatchObject({ weekdays: [1, 2, 3, 4, 5], localStart: '08:00' });
  });

  it('garde une ligne retirée à l’écran, marquée : aucun créneau n’est ouvert avant le reçu', () => {
    const confirmed = [rule('r1'), rule('r2', { weekdays: [6], localStart: '09:00', localEnd: '12:00' })];
    const intention: ScheduleIntention = { tag: 'remove:r1', operationId: 'op-3', kind: 'rule-remove', instructor: 'a', ruleId: 'r1' };
    const { rules, marks } = projectRules(confirmed, [intention], 'a');
    expect(rules.map(item => item.id)).toEqual(['r1', 'r2']);
    expect(marks.get('r1')).toBe('removing');
    // La semaine type se lit sur les horaires de l’école, pas sur la projection : le lundi reste ouvert.
    expect(weekRows(confirmed, today)[0]!.ranges.map(range => range.id)).toEqual(['r1']);
    expect(ruleGroups(rules, today).current.map(item => item.id)).toEqual(['r1', 'r2']);
  });

  it('ne mélange pas les moniteurs et ignore une modification d’une ligne qui n’existe plus', () => {
    const intentions: ScheduleIntention[] = [
      { tag: 'rule:new', operationId: 'op-4', kind: 'rule-create', instructor: 'b', draft: draft() },
      { tag: 'rule:gone', operationId: 'op-5', kind: 'rule-update', instructor: 'a', ruleId: 'gone', draft: draft() },
    ];
    const { rules, marks } = projectRules([rule('r1'), rule('r9', { instructorMembershipId: 'b' })], intentions, 'a');
    expect(rules.map(item => item.id)).toEqual(['r1']);
    expect(marks.size).toBe(0);
  });

  it('un nouvel horaire provisoire compte pour la détection locale de chevauchement, le serveur reste le juge', () => {
    const intention: ScheduleIntention = { tag: 'rule:new', operationId: 'op-6', kind: 'rule-create', instructor: 'a', draft: draft({ weekdays: [1], start: '14:00', end: '16:00' }) };
    const { rules } = projectRules([], [intention], 'a');
    expect(ruleProblems(draft({ weekdays: [1], start: '15:00', end: '17:00' }), rules).overlap?.id).toBe('pending:op-6');
  });
});

describe('projection locale des absences', () => {
  it('ajoute une absence provisoire en heure de l’école, y compris au passage été/hiver', () => {
    const intention: ScheduleIntention = { tag: 'absence:new', operationId: 'op-7', kind: 'absence-create', instructor: 'a', draft: { start: '2026-10-25T08:00', end: '2026-10-26T18:00', reason: ' Congé ' } };
    const { absences, marks } = projectAbsences([], [intention], 'a', 'Europe/Zurich');
    expect(absences).toHaveLength(1);
    // 25 octobre 2026 : fin de l’heure d’été à 03:00. 08:00 est en heure d’hiver (UTC+1 après le changement), pas la veille.
    expect(absences[0]).toMatchObject({ id: 'pending:op-7', startsAt: '2026-10-25T07:00:00.000Z', endsAt: '2026-10-26T17:00:00.000Z', reason: 'Congé', version: 0 });
    expect(marks.get('pending:op-7')).toBe('creating');
  });

  it('ne projette pas une absence dont une heure n’existe pas, et garde l’absence retirée marquée', () => {
    const skipped: ScheduleIntention = { tag: 'absence:new', operationId: 'op-8', kind: 'absence-create', instructor: 'a', draft: { start: '2026-03-29T02:30', end: '2026-03-29T10:00', reason: '' } };
    expect(projectAbsences([], [skipped], 'a', 'Europe/Zurich').absences).toEqual([]);
    const removing: ScheduleIntention = { tag: 'remove:c1', operationId: 'op-9', kind: 'absence-remove', instructor: 'a', closureId: 'c1' };
    const { absences, marks } = projectAbsences([closure('c1')], [removing], 'a', 'Europe/Zurich');
    expect(absences.map(item => item.id)).toEqual(['c1']);
    expect(marks.get('c1')).toBe('removing');
  });
});

describe('demande confirmée avant la relecture', () => {
  it('une création confirmée reste visible sans marqueur, un retrait confirmé disparaît aussitôt', () => {
    const created: ScheduleIntention = { tag: 'rule:new', operationId: 'op-c', kind: 'rule-create', instructor: 'a', draft: draft(), settledAt: 1000 };
    const removed: ScheduleIntention = { tag: 'remove:r1', operationId: 'op-d', kind: 'rule-remove', instructor: 'a', ruleId: 'r1', settledAt: 1000 };
    const { rules, marks } = projectRules([rule('r1')], [created, removed], 'a');
    expect(rules.map(item => item.id)).toEqual(['pending:op-c']);
    expect(marks.size).toBe(0);
    const gone: ScheduleIntention = { tag: 'remove:c1', operationId: 'op-e', kind: 'absence-remove', instructor: 'a', closureId: 'c1', settledAt: 1000 };
    expect(projectAbsences([closure('c1')], [gone], 'a', 'Europe/Zurich').absences).toEqual([]);
  });

  it('la projection se retire dès qu’une lecture plus récente que la confirmation est à l’écran', () => {
    const settled: ScheduleIntention = { tag: 'rule:new', operationId: 'op-f', kind: 'rule-create', instructor: 'a', draft: draft(), settledAt: 5000 };
    expect(visibleIntentions([settled], new Set(), 4000)).toHaveLength(1);
    expect(visibleIntentions([settled], new Set(), undefined)).toHaveLength(1);
    expect(visibleIntentions([settled], new Set(), 5000)).toHaveLength(0);
    expect(visibleIntentions([settled], new Set(), 6000)).toHaveLength(0);
  });
});

describe('intentions encore suivies', () => {
  const intentions: ScheduleIntention[] = [
    { tag: 'rule:new', operationId: 'op-a', kind: 'rule-create', instructor: 'a', draft: draft() },
    { tag: 'absence:new', operationId: 'op-b', kind: 'absence-create', instructor: 'a', draft: { start: '2026-11-03T08:00', end: '2026-11-03T12:00', reason: '' } },
  ];
  it('seules les demandes que le magasin suit encore restent provisoires', () => {
    expect(stillFollowed(intentions, new Set(['op-b'])).map(item => item.operationId)).toEqual(['op-b']);
    expect(stillFollowed(intentions, new Set())).toEqual([]);
    expect(visibleIntentions(intentions, new Set(['op-b']), undefined).map(item => item.operationId)).toEqual(['op-b']);
    // Une demande refusée ou abandonnée n’est plus suivie : elle ne laisse aucune ligne provisoire.
    expect(visibleIntentions(intentions, new Set(), undefined)).toEqual([]);
  });
  it('un horaire en cours n’attend pas une absence, ni un autre moniteur', () => {
    expect(sameFamilyFollowed(intentions, 'a', 'rules')).toBe(true);
    expect(sameFamilyFollowed(intentions, 'a', 'closures')).toBe(true);
    expect(sameFamilyFollowed(intentions.slice(0, 1), 'a', 'closures')).toBe(false);
    expect(sameFamilyFollowed(intentions, 'b', 'rules')).toBe(false);
  });
});
