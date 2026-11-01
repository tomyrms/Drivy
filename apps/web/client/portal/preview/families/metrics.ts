import { ids } from '../fixtures';
import type { PreviewFamily } from '../family';

/**
 * Pilotage (#373) : lectures synthétiques du dictionnaire et des cartes, pour juger la composition des pages.
 * Les valeurs sont inventées pour l'aperçu ; elles suivent la forme de l'API (T02 #375), jamais ses calculs.
 * Un filtre moniteur divise les valeurs par deux, pour que l'effet du filtre se voie ; rien d'autre n'est simulé.
 */
type Unit = 'count' | 'seconds' | 'cents' | 'permille';
type Entry = readonly [id: string, domain: 'activity' | 'finance', unit: Unit, label: string, formula: string, snapshot?: boolean];
const dictionary: readonly Entry[] = [
  ['L01', 'activity', 'count', 'Leçons réalisées', 'Leçons au statut réalisé, rattachées à leur début réel.'],
  ['L02', 'activity', 'count', 'Leçons à venir', 'Leçons planifiées dont le début prévu est futur et qui n’ont pas démarré.'],
  ['L03', 'activity', 'count', 'Leçons annulées', 'Leçons annulées, rattachées à leur début prévu.'],
  ['L04', 'activity', 'count', 'Absences', 'Absences constatées, rattachées à leur début prévu.'],
  ['H02', 'activity', 'seconds', 'Heures réalisées (durées connues)', 'Somme des durées réelles connues ; une durée manquante n’est ni zéro ni la durée prévue.'],
  ['H03', 'activity', 'seconds', 'Heures à venir', 'Durée prévue des leçons à venir.'],
  ['P01', 'activity', 'count', 'Élèves ayant eu une activité', 'Élèves distincts ayant une leçon réalisée ou une présence à une séance de cours.'],
  ['C01', 'activity', 'count', 'Séances de cours', 'Séances des cours publiés (hors brouillons et cours annulés).'],
  ['C06', 'activity', 'count', 'Inscriptions actives', 'Inscriptions actives des cours publiés, une fois par cours.', true],
  ['C09', 'activity', 'permille', 'Remplissage des cours à venir', 'Places occupées sur capacité des cours publiés dont la première séance est future et dans la période.', true],
  ['A01', 'activity', 'count', 'Leçons à finaliser', 'Leçons démarrées sans constat de fin, sans borne de période.', true],
  ['A02', 'activity', 'count', 'Appels à renseigner', 'Séances passées sans appel complet, sans borne de période.', true],
  ['A03', 'activity', 'count', 'Leçons à vérifier', 'Leçons dont l’heure est passée, jamais démarrées, sans borne de période.', true],
  ['F01', 'finance', 'cents', 'Valeur des leçons réalisées', 'Prix convenus à la réservation des leçons réalisées ; pas une preuve d’encaissement.'],
  ['F02', 'finance', 'cents', 'Valeur des leçons à venir', 'Prix convenus des réservations confirmées futures.'],
  ['F03', 'finance', 'cents', 'Total attendu selon le planning', 'Réalisé plus à venir ; ni prévision garantie ni encaissement.'],
  ['F04', 'finance', 'cents', 'Valeur en attente de constat', 'Leçons à vérifier, en cours ou à finaliser ; hors du total attendu.'],
  ['F05', 'finance', 'cents', 'Règlements de cours enregistrés', 'Saisies de règlements de cours sur place non annulées, par date de saisie ; pas un rapprochement bancaire.'],
  ['F07', 'finance', 'cents', 'Valeur des cours collectifs', 'Indisponible : un cours n’a ni prix ni lien produit.'],
];
const complete = { status: 'COMPLETE', reasons: [] };
const sample: Record<string, { value: number | null; coverage?: unknown }> = {
  L01: { value: 38 }, L02: { value: 17 }, L03: { value: 3 }, L04: { value: 1 },
  H02: { value: 107_400, coverage: { status: 'PARTIAL', reasons: [{ code: 'DURATION_UNKNOWN', count: 2 }] } }, H03: { value: 45_900 },
  P01: { value: 21 }, C01: { value: 6 }, C06: { value: 14 }, C09: { value: 450 },
  A01: { value: 2 }, A02: { value: 1 }, A03: { value: 0 },
  F01: { value: 361_000 }, F02: { value: 161_500 }, F03: { value: 522_500 }, F04: { value: 28_500 }, F05: { value: 45_000 },
  F07: { value: null, coverage: { status: 'UNAVAILABLE', reasons: [{ code: 'COURSE_PRICE_SOURCE_MISSING' }] } },
};
const days = (from: string, toExclusive: string) => Math.round((Date.parse(`${toExclusive}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);

export const metricsFamily: PreviewFamily = {
  name: 'metrics',
  read(request, tools) {
    if (request.path === 'metrics/definitions') {
      return tools.reply(200, tools.envelope({
        definitionsVersion: '2026-10-31.1',
        measures: dictionary.map(([id, domain, unit, label, formula, snapshot]) => ({ id, domain, unit, label, formula, snapshot: snapshot ?? false })),
      }));
    }
    if (request.path !== 'metrics') return undefined;
    const domain = request.query.get('domain') === 'finance' ? 'finance' : 'activity';
    const from = request.query.get('from') ?? '', toExclusive = request.query.get('toExclusive') ?? '';
    const filtered = Boolean(request.query.get('instructorMembershipId'));
    const measures = Object.fromEntries(dictionary.filter(entry => entry[1] === domain).map(([id, , unit]) => {
      const { value, coverage } = sample[id]!;
      const shown = value === null || !filtered || unit === 'permille' || id.startsWith('A') ? value : Math.round(value / 2);
      return [id, { value: shown, unit, coverage: coverage ?? complete }];
    }));
    return tools.reply(200, tools.envelope({
      schoolId: ids.school, domain, timeZone: 'Europe/Zurich', computedAt: new Date().toISOString(), dataSince: null,
      period: { from, toExclusive, days: days(from, toExclusive) }, scope: { kind: 'school' }, measures,
    }));
  },
};
