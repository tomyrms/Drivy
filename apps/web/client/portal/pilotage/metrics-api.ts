import { useCommandSnapshot } from '../../command-store';
import { useConsole, useLoad } from '../../console/context';
import { RequestFailure } from '../../protocol';
import { readSchool } from '../../school-api';
import { definitionsSchema, metricsSchema, seriesSchema, type MetricsAnswer } from './metrics-schemas';

export type { MetricDefinition, MetricMeasure, MetricsAnswer, SeriesAnswer } from './metrics-schemas';

/**
 * Lectures du pilotage (#373, T02 #375) : le web affiche ce que le serveur calcule, il ne recompte rien.
 * Les schémas ignorent les clés qu'ils ne lisent pas ; une forme inattendue est une lecture impossible, jamais un zéro.
 */
export type MetricDomain = 'activity' | 'finance';
/** Dictionnaire des mesures : libellés et formules servis par le serveur, lus une fois par ouverture de page. */
export function useMetricDefinitions() {
  const { schoolId } = useConsole();
  const loaded = useLoad(async () => {
    const answer = await readSchool(schoolId, 'metrics/definitions', definitionsSchema);
    return new Map(answer.measures.map(item => [item.id, item] as const));
  }, [schoolId]);
  return loaded;
}

/** Filtres communs des lectures : moniteur, catégorie de permis (code) et prestation (clé). Un filtre inapplicable rend la mesure « non applicable ». */
export interface MetricFilters { instructor?: string | undefined; category?: string | undefined; product?: string | undefined }
export const filterQuery = (filters: MetricFilters) => ({
  ...(filters.instructor ? { instructorMembershipId: filters.instructor } : {}),
  ...(filters.category ? { categoryCode: filters.category } : {}),
  ...(filters.product ? { productKey: filters.product } : {}),
});
const filterScope = (filters: MetricFilters) => [filters.instructor ?? '', filters.category ?? '', filters.product ?? ''].join('/');

export interface MetricsRequest extends MetricFilters {
  domain: MetricDomain;
  from: string;
  toExclusive: string;
  compare?: 'previous-month' | 'equivalent-period' | undefined;
  breakdown?: 'instructor' | 'category' | 'product' | undefined;
}

async function readMetrics(schoolId: string, request: MetricsRequest): Promise<MetricsAnswer> {
  const answer = await readSchool(schoolId, 'metrics', metricsSchema, {
    domain: request.domain, from: request.from, toExclusive: request.toExclusive, ...filterQuery(request),
    ...(request.compare ? { compare: request.compare } : {}),
    ...(request.breakdown ? { breakdown: request.breakdown } : {}),
  });
  if (answer.schoolId !== schoolId || answer.domain !== request.domain || answer.period.from !== request.from || answer.period.toExclusive !== request.toExclusive) {
    throw new RequestFailure('INVALID_RESPONSE');
  }
  return answer;
}
const requestScope = (schoolId: string, request: MetricsRequest) =>
  [schoolId, request.domain, request.from, request.toExclusive, filterScope(request), request.compare ?? '', request.breakdown ?? ''].join('/');

/**
 * Cartes d'un domaine pour une période. La portée de lecture inclut les filtres : changer de période ou de moniteur
 * efface les chiffres précédents au lieu de les montrer sous un autre titre. Une réponse qui ne correspond pas à la demande est refusée.
 */
export function useMetrics(request: MetricsRequest) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const scope = requestScope(schoolId, request);
  return useLoad(() => readMetrics(schoolId, request), [schoolId, revision, scope], scope);
}

/** Même lecture, déclenchée seulement quand une demande existe : sans demande, aucun appel et aucune donnée. */
export function useOptionalMetrics(request: MetricsRequest | null) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const scope = request ? requestScope(schoolId, request) : 'none';
  return useLoad(async () => request ? readMetrics(schoolId, request) : null, [schoolId, revision, scope], scope);
}


export interface SeriesRequest extends MetricFilters {
  from: string;
  toExclusive: string;
  granularity: 'day' | 'week' | 'month';
  measures: readonly string[];
}

/** Série d'une ou plusieurs mesures par intervalle ; mêmes règles de portée et de correspondance que les cartes. */
export function useMetricSeries(request: SeriesRequest) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const measures = request.measures.join(',');
  const scope = ['series', schoolId, request.from, request.toExclusive, request.granularity, measures, filterScope(request)].join('/');
  return useLoad(async () => {
    const answer = await readSchool(schoolId, 'metrics/series', seriesSchema, {
      from: request.from, toExclusive: request.toExclusive, granularity: request.granularity, measures, ...filterQuery(request),
    });
    if (answer.schoolId !== schoolId || answer.period.from !== request.from || answer.period.toExclusive !== request.toExclusive || answer.granularity !== request.granularity) {
      throw new RequestFailure('INVALID_RESPONSE');
    }
    return answer;
  }, [schoolId, revision, scope], scope);
}
