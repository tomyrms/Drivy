import { describe, expect, test } from 'vitest';
import { expectedFromCard, exportErrorMessage, exportFileName, lineStatus, lineTitle, measureDomain, measureParts, shownAmount, totalText, type DetailLine } from './detail-model';
import { exportBody } from './details-api';
import { detailsSchema } from './metrics-schemas';

const line = (extra: Partial<DetailLine> = {}): DetailLine => ({ kind: 'LESSON', id: 'a', eventAt: '2026-11-02T09:00:00+01:00', status: 'COMPLETED', ...extra });

describe('détail d’une mesure', () => {
  test('le domaine suit l’identifiant du dictionnaire', () => {
    expect(['L01', 'H02', 'C01', 'A02', 'P01'].map(measureDomain)).toEqual(['activity', 'activity', 'activity', 'activity', 'activity']);
    expect(['F01', 'F05'].map(measureDomain)).toEqual(['finance', 'finance']);
  });

  test('statut et titre se lisent sans inventer : un statut inconnu reste tel quel, un élève absent n’est pas nommé', () => {
    expect(lineStatus(line())).toBe('Réalisée');
    expect(lineStatus(line({ status: 'NO_SHOW' }))).toBe('Absence');
    expect(lineStatus(line({ status: 'AUTRE' }))).toBe('AUTRE');
    expect(lineStatus(line({ kind: 'COURSE_PAYMENT', status: 'ACTIVE' }))).toBe('Enregistré');
    expect(lineStatus(line({ kind: 'COURSE_PAYMENT', voidedAt: '2026-11-03T10:00:00+01:00' }))).toBe('Saisie annulée');
    expect(lineStatus(line({ kind: 'COURSE_OCCURRENCE', missingMarks: 2 }))).toBe('Appel : 2 à renseigner');
    expect(lineStatus(line({ kind: 'COURSE_OCCURRENCE', missingMarks: 0 }))).toBe('Appel renseigné');
    expect(lineTitle(line({ learnerLabel: ' Éloïse Müller ' }))).toBe('Éloïse Müller');
    expect(lineTitle(line({ learnerLabel: null }))).toBe('Leçon');
    expect(lineTitle(line({ kind: 'COURSE_PAYMENT', learnerLabel: '' }))).toBe('Règlement de cours');
    expect(lineTitle(line({ kind: 'COURSE_OCCURRENCE', courseTypeLabel: 'Sensibilisation' }))).toBe('Sensibilisation');
  });

  test('la somme affichée n’existe que pour des lignes qui portent un montant', () => {
    expect(shownAmount([line(), line()])).toBeNull();
    expect(shownAmount([line({ amountCents: 9_500 }), line({ amountCents: null }), line({ amountCents: 9_500 })])).toBe(19_000);
    expect(shownAmount([])).toBeNull();
  });

  test('le total dit les lignes, puis le montant ou la durée quand le serveur en donne un', () => {
    expect(totalText({ lineCount: 1 })).toBe('1 ligne');
    expect(totalText({ lineCount: 12 })).toBe('12 lignes');
    expect(totalText({ lineCount: 3, amountCents: 28_500 })).toMatch(/^3 lignes · .*285/);
    expect(totalText({ lineCount: 3, durationSeconds: 8_100 })).toBe('3 lignes · 2 h 15 min');
  });

  test('les valeurs de la carte partent au serveur pour qu’un écart soit signalé', () => {
    expect(expectedFromCard({ value: 38, unit: 'count', lineCount: 38 })).toEqual({ lineCount: 38 });
    expect(expectedFromCard({ value: 361_000, unit: 'cents', lineCount: 38 })).toEqual({ lineCount: 38, amountCents: 361_000 });
    expect(expectedFromCard({ value: null, unit: 'cents' })).toEqual({});
  });

  test('le nom du fichier ne contient ni école ni personne', () => {
    expect(exportFileName('F01', undefined, '2026-11-01', '2026-12-01')).toBe('drivy-F01-2026-11-01_2026-12-01.csv');
    expect(exportFileName('F06', 'a', '2026-11-01', '2026-12-01')).toBe('drivy-F06a-2026-11-01_2026-12-01.csv');
  });

  test('F06 se détaille en deux listes, qui portent chacune leur partie', () => {
    expect(measureParts.F06?.map(item => item.part)).toEqual(['a', 'b']);
    expect(measureParts.F01).toBeUndefined();
  });

  test('chaque refus d’export a son message, jamais un fichier partiel', () => {
    expect(exportErrorMessage('EXPORT_TOO_LARGE')).toMatch(/10 000 lignes/);
    expect(exportErrorMessage('ACCESS_REVOKED')).toMatch(/droits ont changé/);
    expect(exportErrorMessage('QUELQUE_CHOSE')).toMatch(/Aucun export partiel/);
  });
});

describe('échanges du détail', () => {
  test('l’export reprend la sélection affichée : mesure, période, filtres posés et valeurs de la carte', () => {
    expect(exportBody({ measure: 'F01', from: '2026-11-01', toExclusive: '2026-12-01' }, {})).toEqual({ measure: 'F01', from: '2026-11-01', toExclusive: '2026-12-01' });
    expect(exportBody({ measure: 'F06', part: 'b', from: '2026-11-01', toExclusive: '2026-12-01' }, {})).toEqual({ measure: 'F06', part: 'b', from: '2026-11-01', toExclusive: '2026-12-01' });
    expect(exportBody({ measure: 'L03', from: '2026-11-01', toExclusive: '2026-12-01', instructor: 'm1', category: 'B', product: 'conduite-b' }, { lineCount: 3, amountCents: 28_500 }))
      .toEqual({ measure: 'L03', from: '2026-11-01', toExclusive: '2026-12-01', instructorMembershipId: 'm1', categoryCode: 'B', productKey: 'conduite-b', expectedLineCount: 3, expectedAmountCents: 28_500 });
  });

  const answer = {
    schoolId: '31100000-0000-4000-8000-000000000001', measure: 'F01', timeZone: 'Europe/Zurich', computedAt: '2026-11-02T10:00:00.000Z',
    period: { from: '2026-11-01', toExclusive: '2026-12-01' }, total: { lineCount: 1, amountCents: 9_500, durationSeconds: null }, drift: null,
    lines: [{ kind: 'LESSON', id: '31100000-0000-4000-8000-000000000080', eventAt: '2026-11-02T09:00:00+01:00', status: 'COMPLETED', amountCents: 9_500 }],
    page: { limit: 50, nextCursor: null },
  };
  test('une réponse sans les champs facultatifs est lue, un identifiant mal formé est refusé', () => {
    expect(detailsSchema.safeParse(answer).success).toBe(true);
    expect(detailsSchema.safeParse({ ...answer, lines: [{ ...answer.lines[0], id: 'pas-un-uuid' }] }).success).toBe(false);
    expect(detailsSchema.safeParse({ ...answer, lines: [{ ...answer.lines[0], kind: 'INCONNU' }] }).success).toBe(false);
    expect(detailsSchema.safeParse({ ...answer, measure: 'f01' }).success).toBe(false);
  });
});
