import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  actionClasses, assignmentPreview, assignmentView, commercialStates, entitlementDetailView, isModuleCode, iso, moduleActionAllowed, moduleCodes,
  schoolEntitlementsView, type EntitlementDetailRow
} from '../src/entitlements-model.js';
import { moduleNotEntitled } from '../src/entitlements.js';

const at = new Date('2026-11-14T10:00:00.000Z');
const assignment = (modules: string[], patch: Partial<{ id: string; effectiveAt: string; offerName: string }> = {}) => ({
  id: patch.id ?? randomUUID(), offerId: randomUUID(), offerName: patch.offerName ?? 'Essentiel', effectiveAt: patch.effectiveAt ?? '2026-11-01T08:00:00.000+00:00', modules });
const moduleRow = (code: string, inOffer: boolean, entitled: boolean, adjustment: EntitlementDetailRow['modules'][number]['adjustment'] = null) => ({ code, inOffer, entitled, adjustment });
const notConfigured: EntitlementDetailRow = {
  state: 'NOT_CONFIGURED', assignment: null, scheduled: null, modules: [moduleRow('MESSAGING', false, true), moduleRow('COLLECTIVE_COURSES', false, true)],
  version: 1, nextChangeAt: null, assignments: [], adjustments: []
};

describe('catalogue et classes d’action', () => {
  it('le catalogue ne contient que les deux modules réellement livrés, dans l’ordre', () => {
    expect([...moduleCodes]).toEqual(['MESSAGING', 'COLLECTIVE_COURSES']);
    expect(isModuleCode('MESSAGING')).toBe(true);
    for (const unknown of ['PAYMENTS', 'GPS', 'messaging', '', null, undefined, 3, {}]) expect(isModuleCode(unknown), String(unknown)).toBe(false);
    expect([...commercialStates]).toEqual(['NOT_CONFIGURED', 'OFFER_ACTIVE']);
  });

  it('seul l’usage nouveau exige le droit : l’historique et l’engagement en cours restent permis après un retrait', () => {
    expect([...actionClasses]).toEqual(['READ_HISTORY', 'COMPLETE_COMMITMENT', 'WRITE_NEW']);
    expect(moduleActionAllowed(true, 'WRITE_NEW')).toBe(true);
    expect(moduleActionAllowed(false, 'WRITE_NEW')).toBe(false);
    for (const entitled of [true, false]) {
      expect(moduleActionAllowed(entitled, 'READ_HISTORY'), `lecture, droit ${entitled}`).toBe(true);
      expect(moduleActionAllowed(entitled, 'COMPLETE_COMMITMENT'), `engagement, droit ${entitled}`).toBe(true);
    }
  });

  it('le refus d’un module non accordé est un 403 stable qui ne nomme que le module', () => {
    for (const code of moduleCodes) {
      const refusal = moduleNotEntitled(code);
      expect(refusal.status).toBe(403);
      expect(refusal.code).toBe('MODULE_NOT_ENTITLED');
      expect(refusal.message.length).toBeGreaterThan(10);
      expect(refusal.message).not.toMatch(/€|CHF|prix|tarif|essai|impay/i);
    }
    expect(moduleNotEntitled('MESSAGING').message).not.toBe(moduleNotEntitled('COLLECTIVE_COURSES').message);
  });
});

describe('projections', () => {
  it('ramène les horodatages de la base au format ISO du contrat', () => {
    expect(iso('2026-11-14T10:00:00.123+00:00')).toBe('2026-11-14T10:00:00.123Z');
    expect(iso(new Date('2026-11-14T10:00:00.000Z'))).toBe('2026-11-14T10:00:00.000Z');
    expect(iso(null)).toBeNull();
    expect(iso(undefined)).toBeNull();
    expect(assignmentView(null)).toBeNull();
    const row = assignment(['MESSAGING']);
    expect(assignmentView(row)).toEqual({ offerId: row.offerId, name: 'Essentiel', effectiveAt: '2026-11-01T08:00:00.000Z', modules: ['MESSAGING'] });
  });

  it('la vue d’une école sur ses droits ne porte ni offre, ni motif, ni auteur, ni historique', () => {
    const view = schoolEntitlementsView({
      state: 'OFFER_ACTIVE', version: 4, nextChangeAt: '2026-12-01T00:00:00.000+00:00',
      modules: [{ code: 'MESSAGING', entitled: true }, { code: 'COLLECTIVE_COURSES', entitled: false, offerName: 'Essentiel', reason: 'geste commercial' } as never]
    }, at);
    expect(view).toEqual({
      state: 'OFFER_ACTIVE', modules: [{ code: 'MESSAGING', entitled: true }, { code: 'COLLECTIVE_COURSES', entitled: false }], version: 4,
      nextChangeAt: '2026-12-01T00:00:00.000Z', computedAt: '2026-11-14T10:00:00.000Z'
    });
    expect(JSON.stringify(view)).not.toMatch(/offerName|reason|createdBy|assignment|adjustment/);
  });
});

describe('détail des droits d’une fiche', () => {
  it('sans offre en vigueur, tout le catalogue reste accordé (périmètre inchangé) et rien n’est ajustable', () => {
    const detail = entitlementDetailView(notConfigured, at);
    expect(detail.state).toBe('NOT_CONFIGURED');
    expect(detail.offer).toBeNull();
    expect(detail.scheduledOffer).toBeNull();
    expect(detail.modules.map(item => [item.code, item.entitled, item.inOffer])).toEqual([['MESSAGING', true, false], ['COLLECTIVE_COURSES', true, false]]);
    expect(detail.version).toBe(1);
  });

  it('classe chaque attribution (en vigueur, programmée, remplacée, annulée) et chaque ajustement (actif, terminé, levé)', () => {
    const inForce = assignment(['MESSAGING'], { effectiveAt: '2026-11-10T08:00:00.000+00:00' });
    const old = assignment(['MESSAGING', 'COLLECTIVE_COURSES'], { effectiveAt: '2026-10-01T08:00:00.000+00:00', offerName: 'Complet' });
    const future = assignment(['COLLECTIVE_COURSES'], { effectiveAt: '2026-12-01T08:00:00.000+00:00', offerName: 'Cours' });
    const cancelled = assignment(['MESSAGING'], { effectiveAt: '2026-12-15T08:00:00.000+00:00' });
    const author = { createdAt: '2026-11-10T09:00:00.000+00:00', createdByName: 'Camille Exemple' };
    const row: EntitlementDetailRow = {
      state: 'OFFER_ACTIVE', assignment: inForce, scheduled: future,
      modules: [moduleRow('MESSAGING', true, true), moduleRow('COLLECTIVE_COURSES', false, true, { id: randomUUID(), effect: 'GRANT', reason: 'Essai de la formation', ...author })],
      version: 9, nextChangeAt: future.effectiveAt,
      assignments: [
        { ...cancelled, status: 'CANCELLED', createdAt: author.createdAt, createdByName: author.createdByName, cancelledAt: '2026-11-11T09:00:00.000+00:00' },
        { ...future, status: 'ACTIVE', createdAt: author.createdAt, createdByName: author.createdByName, cancelledAt: null },
        { ...inForce, status: 'ACTIVE', createdAt: author.createdAt, createdByName: author.createdByName, cancelledAt: null },
        { ...old, status: 'ACTIVE', createdAt: author.createdAt, createdByName: author.createdByName, cancelledAt: null }
      ],
      adjustments: [
        { id: randomUUID(), assignmentId: inForce.id, moduleCode: 'COLLECTIVE_COURSES', effect: 'GRANT', reason: 'Essai de la formation', ...author, liftedAt: null, liftedByName: null, liftReason: null },
        { id: randomUUID(), assignmentId: old.id, moduleCode: 'MESSAGING', effect: 'REVOKE', reason: 'Pause demandée', ...author, liftedAt: null, liftedByName: null, liftReason: null },
        { id: randomUUID(), assignmentId: inForce.id, moduleCode: 'MESSAGING', effect: 'REVOKE', reason: 'Levé après erreur', ...author,
          liftedAt: '2026-11-12T09:00:00.000+00:00', liftedByName: 'Camille Exemple', liftReason: 'Erreur de saisie' }
      ]
    };
    const detail = entitlementDetailView(row, at);
    expect(detail.assignments.map(item => item.phase)).toEqual(['CANCELLED', 'SCHEDULED', 'IN_FORCE', 'SUPERSEDED']);
    expect(detail.adjustments.map(item => item.phase)).toEqual(['ACTIVE', 'ENDED', 'LIFTED']);
    // L'historique garde l'instantané de chaque attribution, le motif et l'auteur ; rien n'est supprimé.
    expect(detail.assignments[3]).toMatchObject({ offerName: 'Complet', modules: ['MESSAGING', 'COLLECTIVE_COURSES'] });
    expect(detail.adjustments[2]).toMatchObject({ liftReason: 'Erreur de saisie', liftedByName: 'Camille Exemple', reason: 'Levé après erreur' });
    expect(detail.modules[1]!.adjustment).toMatchObject({ effect: 'GRANT', reason: 'Essai de la formation', createdByName: 'Camille Exemple' });
    expect(detail.scheduledOffer).toMatchObject({ name: 'Cours', modules: ['COLLECTIVE_COURSES'] });
    expect(detail.nextChangeAt).toBe('2026-12-01T08:00:00.000Z');
  });
});

describe('aperçu des conséquences d’une attribution', () => {
  const inOffer = (modules: string[], granted: string[] = modules) => entitlementDetailView({
    state: 'OFFER_ACTIVE', assignment: assignment(modules), scheduled: null, version: 5, nextChangeAt: null, assignments: [], adjustments: [],
    modules: moduleCodes.map(code => moduleRow(code, modules.includes(code), granted.includes(code)))
  }, at);
  const usage = { MESSAGING: { conversations: 12 }, COLLECTIVE_COURSES: { publishedSeries: 2, activeEnrollments: 31, upcomingSessions: 6 } };
  const target = (modules: string[]) => ({ id: randomUUID(), name: 'Cible', modules });

  it('dit pour chaque module ce qui est gagné, perdu, gardé ou resté éteint, et ne détaille que ce que le retrait laisse en place', () => {
    const preview = assignmentPreview({ current: inOffer(['MESSAGING']), offer: target(['COLLECTIVE_COURSES']), effectiveAt: null, usage });
    expect(preview.modules).toEqual([
      { code: 'MESSAGING', before: true, after: false, kind: 'LOSES', existing: { conversations: 12 } },
      { code: 'COLLECTIVE_COURSES', before: false, after: true, kind: 'GAINS', existing: null }
    ]);
    expect(preview.immediate).toBe(true);
    expect(preview.version).toBe(5);
    const keeping = assignmentPreview({ current: inOffer(['MESSAGING']), offer: target(['MESSAGING']), effectiveAt: null, usage });
    expect(keeping.modules.map(item => item.kind)).toEqual(['KEEPS', 'STAYS_OFF']);
    expect(keeping.modules.every(item => item.existing === null)).toBe(true);
  });

  it('une école sans offre part d’un périmètre complet : une offre plus étroite retire ce qu’elle ne contient pas', () => {
    const preview = assignmentPreview({ current: entitlementDetailView(notConfigured, at), offer: target(['MESSAGING']), effectiveAt: '2026-12-01T08:00:00.000Z', usage });
    expect(preview.modules.map(item => [item.code, item.kind])).toEqual([['MESSAGING', 'KEEPS'], ['COLLECTIVE_COURSES', 'LOSES']]);
    expect(preview.modules[1]!.existing).toEqual({ publishedSeries: 2, activeEnrollments: 31, upcomingSessions: 6 });
    expect(preview.immediate).toBe(false);
    expect(preview.effectiveAt).toBe('2026-12-01T08:00:00.000Z');
  });

  it('annonce les ajustements actifs qui prendront fin et l’attribution programmée qui sera remplacée', () => {
    const adjustment = { id: randomUUID(), effect: 'GRANT' as const, reason: 'Geste', createdAt: '2026-11-10T09:00:00.000+00:00', createdByName: null };
    const scheduled = assignment(['COLLECTIVE_COURSES'], { effectiveAt: '2026-12-01T08:00:00.000+00:00', offerName: 'Cours' });
    const current = entitlementDetailView({
      state: 'OFFER_ACTIVE', assignment: assignment(['MESSAGING']), scheduled, version: 6, nextChangeAt: scheduled.effectiveAt,
      modules: [moduleRow('MESSAGING', true, true), moduleRow('COLLECTIVE_COURSES', false, true, adjustment)], assignments: [],
      adjustments: [{ id: adjustment.id, assignmentId: 'x', moduleCode: 'COLLECTIVE_COURSES', effect: 'GRANT', reason: 'Geste', createdAt: adjustment.createdAt, createdByName: null,
        liftedAt: null, liftedByName: null, liftReason: null }]
    }, at);
    // Seuls les ajustements dont l'attribution est en vigueur sont « actifs » ; ici l'attribution de test n'est pas liée, donc aucun n'est annoncé.
    expect(assignmentPreview({ current, offer: target(['MESSAGING']), effectiveAt: null, usage }).endingAdjustments).toEqual([]);
    expect(assignmentPreview({ current, offer: target(['MESSAGING']), effectiveAt: null, usage }).replacesScheduled).toMatchObject({ name: 'Cours' });
    const linked = { ...current, adjustments: current.adjustments.map(item => ({ ...item, phase: 'ACTIVE' as const })) };
    expect(assignmentPreview({ current: linked, offer: target(['MESSAGING']), effectiveAt: null, usage }).endingAdjustments)
      .toEqual([{ id: adjustment.id, moduleCode: 'COLLECTIVE_COURSES', effect: 'GRANT' }]);
  });

  it('n’expose jamais de contenu : seulement des volumes nombrés', () => {
    const preview = assignmentPreview({ current: inOffer(['MESSAGING', 'COLLECTIVE_COURSES']), offer: target([]), effectiveAt: null, usage });
    for (const item of preview.modules) for (const value of Object.values(item.existing ?? {})) expect(Number.isInteger(value)).toBe(true);
    expect(Object.keys(preview).sort()).toEqual(['effectiveAt', 'endingAdjustments', 'immediate', 'modules', 'offer', 'replacesScheduled', 'version']);
    expect(Object.keys(preview.modules[0]!).sort()).toEqual(['after', 'before', 'code', 'existing', 'kind']);
  });
});
