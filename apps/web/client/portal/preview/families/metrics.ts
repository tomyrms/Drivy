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
  ['F06', 'finance', 'cents', 'Saisies annulées et corrections', 'Saisies annulées et corrections postérieures ; annuler une saisie n’est pas un remboursement.'],
  ['F07', 'finance', 'cents', 'Valeur des cours collectifs', 'Indisponible : un cours n’a ni prix ni lien produit.'],
];
const complete = { status: 'COMPLETE', reasons: [] };
type Sample = { value: number | null; coverage?: unknown };
const notApplicableWhenFiltered: ReadonlySet<string> = new Set(['F05', 'F06']);
/** Une période d'un mois ou plus. */
const period: Record<string, Sample> = {
  L01: { value: 38 }, L02: { value: 17 }, L03: { value: 3 }, L04: { value: 1 }, L05: { value: 2 }, L06: { value: 0 }, L07: { value: 2 }, L08: { value: 63 },
  H01: { value: 148_500 }, H02: { value: 107_400, coverage: { status: 'PARTIAL', reasons: [{ code: 'DURATION_UNKNOWN', count: 2 }] } }, H03: { value: 45_900 },
  P01: { value: 21 }, C01: { value: 6 }, C06: { value: 14 }, C09: { value: 450 },
  A01: { value: 2 }, A02: { value: 1 }, A03: { value: 0 },
  F01: { value: 361_000 }, F02: { value: 161_500 }, F03: { value: 522_500 }, F04: { value: 28_500 }, F05: { value: 45_000 }, F06: { value: 5_000 },
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

/** Valeur d'un jour de série : des leçons pour L01 et L02, des centimes pour F01 et F02 (95 CHF la leçon), des règlements les jours de cours. */
function amountOf(id: string, lessons: { L01: number; L02: number }, civil: string): number {
  if (id === 'L01' || id === 'L02') return lessons[id];
  if (id === 'F01') return lessons.L01 * 9_500;
  if (id === 'F02') return lessons.L02 * 9_500;
  return new Date(`${civil}T12:00:00Z`).getUTCDay() === 2 ? 15_000 : 0;
}

/** Nombre de lignes qui composent chaque mesure listable, égal à la valeur de sa carte pour que le total du détail concorde. */
const lineCounts: Record<string, number> = { L01: 38, L02: 17, L03: 3, L04: 1, L05: 2, L07: 2, C01: 6, F01: 38, F02: 17, F03: 55, F04: 3, F05: 3, F06: 1 };
const learnerNames = ['Éloïse Müller', 'Bruno Blanc', 'Jade Perrin', 'Sami Dubois', 'Léa Rochat', 'Noah Meier'];
const staffNames = [[ids.instructor, 'Marie Dupont'], [previewId(6), 'Simon Favre'], [ids.admin, 'Luc Martin']] as const;
const lessonStatus: Record<string, string> = { L01: 'COMPLETED', L02: 'PLANNED', L03: 'CANCELLED', L04: 'NO_SHOW', L05: 'PLANNED', L07: 'PLANNED', F01: 'COMPLETED', F02: 'PLANNED', F03: 'COMPLETED', F04: 'PLANNED' };
const unitCents: Record<string, number> = { F01: 9_500, F02: 9_500, F03: 9_500, F04: 9_500, F05: 15_000, F06: 5_000 };

/** Les lignes synthétiques d'une mesure pour une période : mêmes valeurs à chaque lecture, un filtre en retire la moitié. */
function syntheticLines(measure: string, from: string, toExclusive: string, filtered: boolean) {
  const count = filtered ? half(lineCounts[measure] ?? 0) : lineCounts[measure] ?? 0, length = Math.max(1, days(from, toExclusive));
  return Array.from({ length: count }, (_, index) => {
    const civil = addDays(from, index % length), [staffId, staffName] = staffNames[index % staffNames.length]!;
    const course = measure === 'C01', payment = measure === 'F05' || measure === 'F06';
    return {
      kind: course ? 'COURSE_OCCURRENCE' : payment ? 'COURSE_PAYMENT' : 'LESSON',
      id: previewId(5_000 + index + (measure.charCodeAt(0) + Number(measure.slice(1))) * 100), eventAt: `${civil}T${String(8 + (index % 9)).padStart(2, '0')}:00:00+01:00`,
      status: course || payment ? 'PUBLISHED' : lessonStatus[measure] ?? 'PLANNED', instructorMembershipId: staffId, instructorLabel: staffName,
      learnerLabel: course ? null : learnerNames[index % learnerNames.length]!, categoryCode: 'B', productKey: 'conduite-b', quantity: course || payment ? null : 1,
      durationSeconds: course || payment ? null : 2_700, amountCents: unitCents[measure] ?? null,
      courseTypeLabel: course ? 'Sensibilisation' : null, markedCount: course ? 6 : null, missingMarks: course ? (index === 0 ? 2 : 0) : null,
      enrollmentId: null, seriesId: course || payment ? previewId(700) : null, voidedAt: measure === 'F06' ? `${civil}T10:00:00+01:00` : null,
    };
  });
}

export const metricsFamily: PreviewFamily = {
  name: 'metrics',
  read(request, tools) {
    if (request.path === 'metrics/definitions') {
      return tools.reply(200, tools.envelope({
        definitionsVersion: '2026-10-31.1',
        measures: dictionary.map(([id, domain, unit, label, formula, snapshot]) => ({ id, domain, unit, label, formula, snapshot: snapshot ?? false, details: lineCounts[id] !== undefined })),
      }));
    }
    const from = request.query.get('from') ?? '', toExclusive = request.query.get('toExclusive') ?? '';
    const filtered = ['instructorMembershipId', 'categoryCode', 'productKey'].some(key => Boolean(request.query.get(key)));
    if (request.path === 'metrics/details') {
      const measure = request.query.get('measure') ?? '';
      const lines = syntheticLines(measure, from, toExclusive, filtered);
      const offset = request.query.get('cursor') === 'page-2' ? 50 : 0, page = lines.slice(offset, offset + 50);
      const amounts = lines.flatMap(line => line.amountCents === null ? [] : [line.amountCents]);
      return tools.reply(200, tools.envelope({
        schoolId: ids.school, measure, timeZone: 'Europe/Zurich', computedAt: new Date().toISOString(), period: { from, toExclusive },
        total: { lineCount: lines.length, amountCents: amounts.length ? amounts.reduce((sum, value) => sum + value, 0) : null, durationSeconds: null },
        drift: null, lines: page, page: { limit: 50, nextCursor: offset + 50 < lines.length ? 'page-2' : null },
      }));
    }
    if (request.path === 'metrics/series') {
      const requested = request.query.get('granularity');
      const granularity = requested === 'week' || requested === 'month' ? requested : 'day';
      const buckets: { from: string; toExclusive: string; partial: boolean; measures: Record<string, { value: number }> }[] = [];
      const wanted = (request.query.get('measures') ?? 'L01,L02').split(',');
      for (let civil = from; civil < toExclusive; civil = addDays(civil, 1)) {
        const start = granularity === 'week' ? weekStart(civil) : granularity === 'month' ? `${civil.slice(0, 8)}01` : civil;
        const values = seriesDay(civil, filtered), last = buckets[buckets.length - 1];
        const point = Object.fromEntries(wanted.map(id => [id, { value: amountOf(id, values, civil) }]));
        if (last && (granularity === 'day' ? false : (granularity === 'week' ? weekStart(last.from) : `${last.from.slice(0, 8)}01`) === start)) {
          last.toExclusive = addDays(civil, 1);
          for (const id of wanted) last.measures[id]!.value += point[id]!.value;
        } else buckets.push({ from: civil, toExclusive: addDays(civil, 1), partial: start < from, measures: point });
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
      if (filtered && notApplicableWhenFiltered.has(id)) return [id, { value: null, unit, coverage: { status: 'NOT_APPLICABLE', reasons: [] } }];
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
  /** Fichier CSV synthétique : mêmes lignes que le détail, sans nom d'élève, avec le bloc de métadonnées en tête (7.7). */
  download(request) {
    if (request.path !== 'metrics/exports') return undefined;
    const body = request.body, measure = String(body.measure ?? ''), from = String(body.from ?? ''), toExclusive = String(body.toExclusive ?? '');
    const lines = syntheticLines(measure, from, toExclusive, Boolean(body.instructorMembershipId || body.categoryCode || body.productKey));
    const rows = lines.map(line => [line.kind, line.id, line.eventAt, line.status, line.instructorMembershipId, line.instructorLabel, line.categoryCode, line.productKey,
      line.quantity ?? '', line.durationSeconds ?? '', line.amountCents ?? '', line.amountCents === null ? '' : 'CHF'].join(';'));
    const csv = ['\ufeff#definitionsVersion;2026-10-31.1', `#measure;${measure}`, `#period;${from}/${toExclusive}`, '#timeZone;Europe/Zurich', '#complete;true', '#notAnAccountingDocument;true',
      'line_kind;line_id;event_at;status;instructor_id;instructor_name;category_code;product_key;quantity;duration_seconds;amount_cents;currency', ...rows].join('\r\n') + '\r\n';
    return new Response(csv, { status: 200, headers: { 'Content-Type': 'text/csv; charset=utf-8' } });
  },
};
