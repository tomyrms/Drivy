import { z } from 'zod';
import { useCommandSnapshot } from '../../command-store';
import { useConsole, useLoad } from '../../console/context';
import { RequestFailure } from '../../protocol';
import { readSchool } from '../../school-api';

/**
 * Lectures du pilotage (#373, T02 #375) : le web affiche ce que le serveur calcule, il ne recompte rien.
 * Les schémas ignorent les clés qu'ils ne lisent pas ; une forme inattendue est une lecture impossible, jamais un zéro.
 */
export type MetricDomain = 'activity' | 'finance';
const measureId = z.string().regex(/^[A-Z][0-9]{2}$/);
const unit = z.enum(['count', 'seconds', 'cents', 'permille']);
const coverage = z.object({
  status: z.enum(['COMPLETE', 'PARTIAL', 'UNAVAILABLE', 'NOT_APPLICABLE']),
  reasons: z.array(z.object({ code: z.string().max(60), count: z.number().int().nonnegative().optional() })).max(20),
});
const measure = z.object({ value: z.number().int().nullable(), unit, coverage, lineCount: z.number().int().nonnegative().optional() });
const comparisonValue = z.object({
  current: z.number().int().nullable(), base: z.number().int().nullable(), delta: z.number().int().nullable(),
  percentTenths: z.number().int().nullable(), percentReason: z.string().nullable(),
});
const civil = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

export const metricsSchema = z.object({
  schoolId: z.string().uuid(),
  domain: z.enum(['activity', 'finance']),
  timeZone: z.string().max(100),
  computedAt: z.string().max(40),
  dataSince: civil.nullable(),
  period: z.object({ from: civil, toExclusive: civil, days: z.number().int().positive() }),
  scope: z.object({ kind: z.enum(['school', 'self']) }),
  measures: z.record(measureId, measure),
  comparison: z.object({
    mode: z.enum(['FULL_MONTH', 'MONTH_TO_DATE', 'EQUIVALENT_PERIOD']),
    base: z.object({ from: civil, toExclusive: civil, days: z.number().int().positive(), clipped: z.boolean() }),
    measures: z.record(measureId, comparisonValue),
  }).optional(),
});
export type MetricsAnswer = z.infer<typeof metricsSchema>;
export type MetricMeasure = z.infer<typeof measure>;

export const definitionsSchema = z.object({
  definitionsVersion: z.string().max(40),
  measures: z.array(z.object({
    id: measureId, domain: z.enum(['activity', 'finance']), unit, label: z.string().max(200), formula: z.string().max(600), snapshot: z.boolean(),
  })).max(100),
});
export type MetricDefinition = z.infer<typeof definitionsSchema>['measures'][number];

/** Dictionnaire des mesures : libellés et formules servis par le serveur, lus une fois par ouverture de page. */
export function useMetricDefinitions() {
  const { schoolId } = useConsole();
  const loaded = useLoad(async () => {
    const answer = await readSchool(schoolId, 'metrics/definitions', definitionsSchema);
    return new Map(answer.measures.map(item => [item.id, item] as const));
  }, [schoolId]);
  return loaded;
}

export interface MetricsRequest {
  domain: MetricDomain;
  from: string;
  toExclusive: string;
  instructor?: string | undefined;
  compare?: 'previous-month' | 'equivalent-period' | undefined;
}

/**
 * Cartes d'un domaine pour une période. La portée de lecture inclut les filtres : changer de période ou de moniteur
 * efface les chiffres précédents au lieu de les montrer sous un autre titre. Une réponse qui ne correspond pas à la demande est refusée.
 */
export function useMetrics(request: MetricsRequest) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const scope = [schoolId, request.domain, request.from, request.toExclusive, request.instructor ?? '', request.compare ?? ''].join('/');
  return useLoad(async () => {
    const answer = await readSchool(schoolId, 'metrics', metricsSchema, {
      domain: request.domain, from: request.from, toExclusive: request.toExclusive,
      ...(request.instructor ? { instructorMembershipId: request.instructor } : {}),
      ...(request.compare ? { compare: request.compare } : {}),
    });
    if (answer.schoolId !== schoolId || answer.domain !== request.domain || answer.period.from !== request.from || answer.period.toExclusive !== request.toExclusive) {
      throw new RequestFailure('INVALID_RESPONSE');
    }
    return answer;
  }, [schoolId, revision, scope], scope);
}

export const seriesSchema = z.object({
  schoolId: z.string().uuid(),
  period: z.object({ from: civil, toExclusive: civil, days: z.number().int().positive() }),
  granularity: z.enum(['day', 'week', 'month']),
  buckets: z.array(z.object({
    from: civil, toExclusive: civil, partial: z.boolean(),
    measures: z.record(measureId, z.object({ value: z.number().int().nullable(), coverage: coverage.optional() })),
  })).max(400),
});
export type SeriesAnswer = z.infer<typeof seriesSchema>;

export interface SeriesRequest {
  from: string;
  toExclusive: string;
  granularity: 'day' | 'week' | 'month';
  measures: readonly string[];
  instructor?: string | undefined;
}

/** Série d'une ou plusieurs mesures par intervalle ; mêmes règles de portée et de correspondance que les cartes. */
export function useMetricSeries(request: SeriesRequest) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const measures = request.measures.join(',');
  const scope = ['series', schoolId, request.from, request.toExclusive, request.granularity, measures, request.instructor ?? ''].join('/');
  return useLoad(async () => {
    const answer = await readSchool(schoolId, 'metrics/series', seriesSchema, {
      from: request.from, toExclusive: request.toExclusive, granularity: request.granularity, measures,
      ...(request.instructor ? { instructorMembershipId: request.instructor } : {}),
    });
    if (answer.schoolId !== schoolId || answer.period.from !== request.from || answer.period.toExclusive !== request.toExclusive || answer.granularity !== request.granularity) {
      throw new RequestFailure('INVALID_RESPONSE');
    }
    return answer;
  }, [schoolId, revision, scope], scope);
}
