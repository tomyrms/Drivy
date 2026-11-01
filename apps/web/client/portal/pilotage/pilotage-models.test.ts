import { describe, expect, test } from 'vitest';
import { describeComparison, describeReason, formatDuration, formatFrancsShort, formatMeasure } from './measure-format';
import { canOpenStatistics, metricRights } from './rights';
import { currentMonth, periodLabel, resolvePeriod } from './period-model';

const today = '2026-11-01';

describe('période du pilotage', () => {
  test('sans choix, le mois en cours va du premier au dernier jour, fin exclue', () => {
    const { period } = resolvePeriod({}, today);
    expect(period).toMatchObject({ choice: 'month', from: '2026-11-01', toExclusive: '2026-12-01', lastDay: '2026-11-30', days: 30 });
    expect(currentMonth('2026-02-10')).toMatchObject({ from: '2026-02-01', toExclusive: '2026-03-01', days: 28 });
  });

  test('le mois dernier passe par le changement d’année', () => {
    expect(resolvePeriod({ period: 'previous-month' }, today).period).toMatchObject({ from: '2026-10-01', toExclusive: '2026-11-01', days: 31 });
    expect(resolvePeriod({ period: 'previous-month' }, '2026-01-15').period).toMatchObject({ from: '2025-12-01', toExclusive: '2026-01-01' });
  });

  test('l’année couvre 365 ou 366 jours, jamais plus que la limite du serveur', () => {
    expect(resolvePeriod({ period: 'year' }, today).period).toMatchObject({ from: '2026-01-01', toExclusive: '2027-01-01', days: 365 });
    expect(resolvePeriod({ period: 'year' }, '2028-03-01').period).toMatchObject({ days: 366 });
  });

  test('une période libre garde sa dernière journée et envoie une fin exclue', () => {
    expect(resolvePeriod({ period: 'custom', start: '2026-10-05', end: '2026-10-12' }, today).period)
      .toMatchObject({ from: '2026-10-05', toExclusive: '2026-10-13', lastDay: '2026-10-12', days: 8 });
    expect(resolvePeriod({ period: 'custom', start: '2026-10-05', end: '2026-10-05' }, today).period).toMatchObject({ days: 1 });
  });

  test('une période libre refusée dit pourquoi, sans choisir une période à la place', () => {
    expect(resolvePeriod({ period: 'custom', start: '2026-10-05' }, today)).toEqual({ period: null, problem: 'INCOMPLETE' });
    expect(resolvePeriod({ period: 'custom' }, today)).toEqual({ period: null, problem: 'INCOMPLETE' });
    expect(resolvePeriod({ period: 'custom', start: '2026-10-12', end: '2026-10-05' }, today)).toEqual({ period: null, problem: 'ORDER' });
    expect(resolvePeriod({ period: 'custom', start: '2025-01-01', end: '2026-12-31' }, today)).toEqual({ period: null, problem: 'TOO_LARGE' });
    expect(resolvePeriod({ period: 'custom', start: '1999-12-30', end: '2000-01-02' }, today)).toEqual({ period: null, problem: 'OUT_OF_RANGE' });
  });

  test('le libellé nomme la période choisie', () => {
    expect(periodLabel(currentMonth(today))).toBe('novembre 2026');
    expect(periodLabel(resolvePeriod({ period: 'year' }, today).period!)).toBe('2026');
    expect(periodLabel(resolvePeriod({ period: 'custom', start: '2026-10-05', end: '2026-10-12' }, today).period!)).toBe('du 5 octobre 2026 au 12 octobre 2026');
  });
});

describe('affichage des mesures', () => {
  test('les durées s’écrivent en heures et minutes, sans arrondir à la minute supérieure', () => {
    expect(formatDuration(13_080)).toBe('3 h 38 min');
    expect(formatDuration(3_600)).toBe('1 h 00 min');
    expect(formatDuration(2_519)).toBe('41 min');
    expect(formatDuration(0)).toBe('0 min');
  });

  test('une valeur absente est un tiret, jamais un zéro', () => {
    expect(formatMeasure(null, 'count')).toBe('—');
    expect(formatMeasure(null, 'cents')).toBe('—');
    expect(formatMeasure(0, 'count')).toBe('0');
    expect(formatMeasure(57_000, 'cents')).toMatch(/570/);
    expect(formatMeasure(57_000, 'cents')).toMatch(/CHF/);
    expect(formatMeasure(450, 'permille')).toMatch(/^45\s?%$/);
    expect(formatFrancsShort(522_500)).toMatch(/5\D?225\sCHF/);
    expect(formatFrancsShort(49)).toBe('0 CHF');
  });

  test('la comparaison dit le pourcentage quand le serveur le donne, sinon l’écart', () => {
    const base = { current: 5, base: 3, delta: 2, percentTenths: 667, percentReason: null };
    expect(describeComparison(base, 'count')).toMatch(/^\+66[.,]7\s?%$/);
    expect(describeComparison({ ...base, percentTenths: null, percentReason: 'BASE_ZERO', base: 0, delta: 5 }, 'count')).toBe('+5');
    expect(describeComparison({ ...base, delta: null, percentTenths: null, percentReason: 'PARTIAL_COVERAGE' }, 'count')).toBeNull();
    expect(describeComparison(undefined, 'count')).toBeNull();
  });

  test('les raisons de couverture ont un texte, même celles que le web ne connaît pas encore', () => {
    expect(describeReason('DURATION_UNKNOWN', 1)).toBe('1 leçon sans durée réelle connue');
    expect(describeReason('DURATION_UNKNOWN', 2)).toBe('2 leçons sans durée réelle connue');
    expect(describeReason('QUELQUE_CHOSE_DE_NOUVEAU')).toBe('Une partie des données n’est pas couverte');
  });
});

describe('droits d’affichage du pilotage', () => {
  test('un administrateur lit l’activité et les finances, mais n’exporte qu’avec le droit d’export', () => {
    expect(metricRights({ roles: ['ADMIN'], grants: [] })).toEqual({ activity: true, finance: true, export: false });
    expect(metricRights({ roles: ['ADMIN'], grants: ['EXPORT_MANAGEMENT'] }).export).toBe(true);
  });

  test('sans rôle d’administration, chaque domaine demande son droit', () => {
    expect(metricRights({ roles: ['INSTRUCTOR'], grants: [] })).toEqual({ activity: false, finance: false, export: false });
    expect(metricRights({ roles: ['INSTRUCTOR'], grants: ['VIEW_FINANCIAL_METRICS'] })).toMatchObject({ activity: false, finance: true });
    expect(canOpenStatistics(metricRights({ roles: ['INSTRUCTOR'], grants: [] }))).toBe(false);
    expect(canOpenStatistics(metricRights({ roles: ['INSTRUCTOR'], grants: ['VIEW_SCHOOL_METRICS'] }))).toBe(true);
  });
});
