import { addDays, weekStart } from '../../../agenda-model';
import { ids, previewId, today } from '../fixtures';
import type { PreviewFamily } from '../family';

/**
 * Pilotage (#373) : lectures synthétiques du dictionnaire, des cartes et des séries, pour juger la composition des pages.
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
  ['L05', 'activity', 'count', 'À vérifier', 'Leçons planifiées dont l’heure est passée, sans départ ni constat.'],
  ['L06', 'activity', 'count', 'En cours', 'Leçons démarrées dont la fin prévue n’est pas atteinte.'],
  ['L07', 'activity', 'count', 'À finaliser', 'Leçons démarrées dont la fin prévue est passée, sans constat de fin.'],
  ['L08', 'activity', 'count', 'Total des leçons', 'Somme des états ci-dessus ; contrôle de cohérence.'],
  ['H01', 'activity', 'seconds', 'Heures programmées', 'Durée prévue des leçons planifiées ou réalisées.'],
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
type Sample = { value: number | null; coverage?: unknown };
/** Une période d'un mois ou plus. */
const period: Record<string, Sample> = {
  L01: { value: 38 }, L02: { value: 17 }, L03: { value: 3 }, L04: { value: 1 }, L05: { value: 2 }, L06: { value: 0 }, L07: { value: 2 }, L08: { value: 63 },
  H01: { value: 148_500 }, H02: { value: 107_400, coverage: { status: 'PARTIAL', reasons: [{ code: 'DURATION_UNKNOWN', count: 2 }] } }, H03: { value: 45_900 },
  P01: { value: 21 }, C01: { value: 6 }, C06: { value: 14 }, C09: { value: 450 },
  A01: { value: 2 }, A02: { value: 1 }, A03: { value: 0 },
  F01: { value: 361_000 }, F02: { value: 161_500 }, F03: { value: 522_500 }, F04: { value: 28_500 }, F05: { value: 45_000 },
  F07: { value: null, coverage: { status: 'UNAVAILABLE', reasons: [{ code: 'COURSE_PRICE_SOURCE_MISSING' }] } },
};
/** Une journée : les mesures non listées reprennent celles de la période. */
const day: Record<string, Sample> = {
  L01: { value: 2 }, L02: { value: 3 }, L03: { value: 0 }, L04: { value: 0 }, L05: { value: 0 }, L06: { value: 1 }, L07: { value: 1 }, L08: { value: 7 },
  H01: { value: 19_800 }, C01: { value: 1 },
};
const days = (from: string, toExclusive: string) => Math.round((Date.parse(`${toExclusive}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);
const half = (value: number) => Math.round(value / 2);

/** Jour civil de la série : les leçons passées sont réalisées, les autres à venir, avec une variation lisible. */
function seriesDay(civil: string, filtered: boolean) {
  const index = Number(civil.slice(8)), weekday = new Date(`${civil}T12:00:00Z`).getUTCDay();
  const volume = weekday === 0 ? 0 : (index * 7 + weekday * 3) % 5 + 1;
  const value = filtered ? half(volume) : volume;
  return civil < today ? { L01: value, L02: 0 } : civil === today ? { L01: half(value), L02: value - half(value) } : { L01: 0, L02: value };
}

export const metricsFamily: PreviewFamily = {
  name: 'metrics',
  read(request, tools) {
    if (request.path === 'metrics/definitions') {
      return tools.reply(200, tools.envelope({
        definitionsVersion: '2026-10-31.1',
        measures: dictionary.map(([id, domain, unit, label, formula, snapshot]) => ({ id, domain, unit, label, formula, snapshot: snapshot ?? false })),
      }));
    }
    const from = request.query.get('from') ?? '', toExclusive = request.query.get('toExclusive') ?? '';
    const filtered = ['instructorMembershipId', 'categoryCode', 'productKey'].some(key => Boolean(request.query.get(key)));
    if (request.path === 'metrics/series') {
      const requested = request.query.get('granularity');
      const granularity = requested === 'week' || requested === 'month' ? requested : 'day';
      const buckets: { from: string; toExclusive: string; partial: boolean; measures: { L01: { value: number }; L02: { value: number } } }[] = [];
      for (let civil = from; civil < toExclusive; civil = addDays(civil, 1)) {
        const start = granularity === 'week' ? weekStart(civil) : granularity === 'month' ? `${civil.slice(0, 8)}01` : civil;
        const values = seriesDay(civil, filtered), last = buckets[buckets.length - 1];
        if (last && (granularity === 'day' ? false : (granularity === 'week' ? weekStart(last.from) : `${last.from.slice(0, 8)}01`) === start)) {
          last.toExclusive = addDays(civil, 1); last.measures.L01.value += values.L01; last.measures.L02.value += values.L02;
        } else buckets.push({ from: civil, toExclusive: addDays(civil, 1), partial: start < from, measures: { L01: { value: values.L01 }, L02: { value: values.L02 } } });
      }
      return tools.reply(200, tools.envelope({ schoolId: ids.school, period: { from, toExclusive, days: days(from, toExclusive) }, granularity, buckets }));
    }
    if (request.path !== 'metrics') return undefined;
    const domain = request.query.get('domain') === 'finance' ? 'finance' : 'activity';
    const length = days(from, toExclusive);
    const sample = (id: string) => (length === 1 ? day[id] : undefined) ?? period[id]!;
    const scaled = (id: string, unit: Unit, value: number | null) => value === null || !filtered || unit === 'permille' || id.startsWith('A') ? value : half(value);
    const measures = Object.fromEntries(dictionary.filter(entry => entry[1] === domain).map(([id, , unit]) => {
      const { value, coverage } = sample(id);
      return [id, { value: scaled(id, unit, value), unit, coverage: coverage ?? complete }];
    }));
    const answer: Record<string, unknown> = {
      schoolId: ids.school, domain, timeZone: 'Europe/Zurich', computedAt: new Date().toISOString(), dataSince: null,
      period: { from, toExclusive, days: length }, scope: { kind: 'school' }, measures,
    };
    const by = request.query.get('breakdown');
    if (by === 'instructor' || by === 'category' || by === 'product') {
      const shares: readonly (readonly [key: string, label: string | null, share: number])[] = by === 'instructor'
        ? [[ids.instructor, 'Marie Dupont', 0.45], [previewId(6), 'Simon Favre', 0.35], [ids.admin, 'Luc Martin', 0.2]]
        : by === 'category' ? [['B', 'B', 0.8], ['A1', 'A1', 0.2]] : [['conduite-b', 'Leçon de conduite', 0.9], ['UNRESOLVED', null, 0.1]];
      answer.breakdown = { by, groups: shares.map(([key, label, share]) => ({ key, label, measures: Object.fromEntries(dictionary.filter(entry => entry[1] === domain).map(([id, , unit]) => {
        const { value, coverage } = sample(id);
        const scaledValue = value === null ? null : unit === 'permille' || id.startsWith('A') ? value : Math.round(scaled(id, unit, value)! * share);
        return [id, { value: scaledValue, unit, coverage: coverage ?? complete }];
      })) })) };
    }
    if (request.query.get('compare') === 'previous-month' || request.query.get('compare') === 'equivalent-period') {
      const previous = new Date(`${from}T12:00:00Z`); previous.setUTCMonth(previous.getUTCMonth() - 1);
      const base = previous.toISOString().slice(0, 8) + '01';
      answer.comparison = {
        mode: 'MONTH_TO_DATE', base: { from: base, toExclusive: addDays(base, length), days: length, clipped: false },
        measures: Object.fromEntries(['L01', 'H02'].map(id => {
          const current = scaled(id, id === 'H02' ? 'seconds' : 'count', period[id]!.value)!, before = Math.round(current * 0.8);
          return [id, { current, base: before, delta: current - before, percentTenths: before === 0 ? null : Math.round(((current - before) * 1000) / before), percentReason: before === 0 ? 'BASE_ZERO' : null }];
        })),
      };
    }
    return tools.reply(200, tools.envelope(answer));
  },
};
