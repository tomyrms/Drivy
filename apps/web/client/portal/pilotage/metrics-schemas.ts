import { z } from 'zod';

/**
 * Formes lues des réponses de pilotage (#373) : zod seulement, sans React ni réseau, pour que l'API puisse les confronter à ses vraies réponses.
 * Elles ignorent les clés qu'elles ne lisent pas ; une forme inattendue est une lecture impossible, jamais un zéro.
 */
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
  breakdown: z.object({
    by: z.enum(['instructor', 'category', 'product']),
    groups: z.array(z.object({ key: z.string().max(120), label: z.string().nullable(), measures: z.record(measureId, measure) })).max(500),
  }).optional(),
});
export type MetricsAnswer = z.infer<typeof metricsSchema>;
export type MetricMeasure = z.infer<typeof measure>;

export const definitionsSchema = z.object({
  definitionsVersion: z.string().max(40),
  measures: z.array(z.object({
    id: measureId, domain: z.enum(['activity', 'finance']), unit, label: z.string().max(200), formula: z.string().max(600), snapshot: z.boolean(),
    /** Vrai si les lignes qui composent la mesure peuvent être listées. */
    details: z.boolean().optional(),
  })).max(100),
});
export type MetricDefinition = z.infer<typeof definitionsSchema>['measures'][number];


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

const optionalText = z.string().nullable().optional();
const optionalCount = z.number().int().nullable().optional();

export const detailLineSchema = z.object({
  kind: z.enum(['LESSON', 'COURSE_OCCURRENCE', 'COURSE_PAYMENT']),
  id: z.string().uuid(),
  eventAt: z.string().max(40),
  status: z.string().max(40),
  instructorMembershipId: optionalText, instructorLabel: optionalText, learnerLabel: optionalText, categoryCode: optionalText, productKey: optionalText,
  quantity: optionalCount, durationSeconds: optionalCount, amountCents: optionalCount,
  courseTypeLabel: optionalText, markedCount: optionalCount, missingMarks: optionalCount, enrollmentId: optionalText, seriesId: optionalText, voidedAt: optionalText,
});
export type DetailLineRecord = z.infer<typeof detailLineSchema>;

export const detailsSchema = z.object({
  schoolId: z.string().uuid(),
  measure: z.string().regex(/^[A-Z][0-9]{2}$/),
  timeZone: z.string().max(100),
  computedAt: z.string().max(40),
  period: z.object({ from: civil, toExclusive: civil }),
  total: z.object({ lineCount: z.number().int().nonnegative(), amountCents: optionalCount, durationSeconds: optionalCount }),
  drift: z.object({
    lineCount: z.object({ expected: z.number().int(), actual: z.number().int() }).optional(),
    amountCents: z.object({ expected: z.number().int(), actual: z.number().int().nullable() }).optional(),
  }).nullable().optional(),
  lines: z.array(detailLineSchema).max(100),
  page: z.object({ limit: z.number().int(), nextCursor: z.string().nullable() }),
});
export type DetailsAnswer = z.infer<typeof detailsSchema>;
