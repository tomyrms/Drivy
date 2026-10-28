import { z } from 'zod';
import { instantToSchoolTime, schoolTimeToInstant } from './command-core.js';
import { lessonSchema, productSchema, type CommercialTerms, type Assignment, type Training, type Offering } from './school-api.js';

export const commercialSelectionSchema = z.object({ mode: z.enum(['UNIT_PRICE', 'ENTITLEMENT']), serviceProductVersionId: z.string().uuid(), quantity: z.number().int().positive(), entitlementLotId: z.string().uuid().nullable(), acceptedTermsVersionId: z.string().uuid() });
export const planningLessonSchema = lessonSchema.extend({
  actualStart: z.string().datetime({ offset: true }).nullable(), actualEnd: z.string().datetime({ offset: true }).nullable(),
  learnerDisplayName: z.string(), instructorDisplayName: z.string(), priceCentsSnapshot: z.number().int().nonnegative(),
  bufferMinutesSnapshot: z.number().int().nonnegative(), commercialSelection: commercialSelectionSchema, commercialRevisionVersion: z.number().int().positive(),
});
export const planningProductSchema = productSchema.extend({ current: z.boolean(), siteId: z.string().uuid().nullable() });
export const slotAvailabilitySchema = z.object({ available: z.boolean(), reasonCode: z.string().nullable() });
export type PlanningLesson = z.infer<typeof planningLessonSchema>;
export type PlanningProduct = z.infer<typeof planningProductSchema>;
/** Échéance informative, jamais une décision de frais. Une règle historique absente ne peut pas être déduite du texte. */
export function individualCancellationDeadline(plannedStart:string,rules:{cancellationHours:number|null;lateAction:'CONTACT'|'NO_FEE'}|null|undefined):string|null {
  if(rules?.lateAction!=='CONTACT'||rules.cancellationHours===null||!Number.isInteger(rules.cancellationHours)||rules.cancellationHours<0||rules.cancellationHours>8760)return null;
  const start=Date.parse(plannedStart);
  if(!Number.isFinite(start))return null;
  const deadline=new Date(start-rules.cancellationHours*3600_000);
  return Number.isNaN(deadline.getTime())?null:deadline.toISOString();
}
export function planningTrainingLabel(training: Training, offering?: Offering): string {
  const category = training.categoryCode ?? offering?.categoryCode;
  return `${category ? `Permis ${category}` : 'Formation'}${offering?.label?.trim() ? ` · ${offering.label.trim()}` : ''}`;
}
export interface LessonForm {
  learnerId: string; trainingId: string; instructorId: string; localStart: string; duration: string; buffer: string;
  meetingPoint: string; productId: string; commercialChange: boolean; reason: string; agreement: boolean; localChoice: string;
}
export function initialLessonForm(lesson?: PlanningLesson, learnerId = ''): LessonForm {
  return { learnerId: lesson?.learnerId ?? learnerId, trainingId: lesson?.trainingId ?? '', instructorId: lesson?.instructorMembershipId ?? '',
    localStart: lesson ? instantToSchoolTime(lesson.plannedStart, lesson.timeZone) ?? '' : '',
    duration: lesson ? String((Date.parse(lesson.plannedEnd) - Date.parse(lesson.plannedStart)) / 60_000) : '',
    buffer: String(lesson?.bufferMinutesSnapshot ?? 0), meetingPoint: lesson?.meetingPoint ?? '', productId: '', commercialChange: false, reason: '', agreement: false, localChoice: lesson?.plannedStart ?? '' };
}
/** Explicit occurrence when a local clock hour repeats. No silent DST adjustment. */
export function lessonLocalInstants(local: string, timeZone: string): string[] {
  const base = schoolTimeToInstant(local, timeZone);
  if (!base) return [];
  const wall = Date.parse(local + ':00Z'), instants = new Set<string>();
  for (const hours of [-24, -12, 0, 12, 24]) {
    const probe = Date.parse(base) + hours * 3600_000;
    const offset = Date.parse(instantToSchoolTime(new Date(probe).toISOString(), timeZone) + ':00Z') - probe;
    const candidate = new Date(wall - offset).toISOString();
    if (instantToSchoolTime(candidate, timeZone) === local) instants.add(candidate);
  }
  return [...instants].sort();
}
export function lessonInterval(form: LessonForm, timeZone: string, now = Date.now()) {
  const instants = lessonLocalInstants(form.localStart, timeZone);
  const plannedStart = instants.length === 1 ? instants[0] : instants.find(instant => instant === form.localChoice), duration = Number(form.duration), bufferMinutes = Number(form.buffer);
  if (!plannedStart || Date.parse(plannedStart) <= now || !form.duration.trim() || !Number.isInteger(duration) || duration < 1 || duration > 480
    || !form.buffer.trim() || !Number.isInteger(bufferMinutes) || bufferMinutes < 0 || bufferMinutes > 240) return null;
  return { plannedStart, plannedEnd: new Date(Date.parse(plannedStart) + duration * 60_000).toISOString(), timeZone, bufferMinutes };
}
export function assignmentCovers(assignment: Assignment, start: string, end: string, now = Date.now()): boolean {
  return Date.parse(assignment.validFrom) <= Math.min(now, Date.parse(start))
    && (assignment.validUntil === null || Date.parse(assignment.validUntil) > now && Date.parse(assignment.validUntil) >= Date.parse(end));
}
export function applicableProducts(products: PlanningProduct[], terms: CommercialTerms[], category: string, localDay: string, duration: number) {
  return products.filter(product => {
    const conditions = terms.find(item => item.id === product.termsVersionId);
    const quantity = product.durationMinutes ? duration / product.durationMinutes : 0;
    return product.current && product.enabled && product.type === 'INDIVIDUAL_LESSON' && product.siteId === null && product.categoryCode === category
      && product.validFrom <= localDay && (!product.validUntil || localDay <= product.validUntil)
      && quantity >= 1 && quantity <= 100 && Number.isInteger(quantity) && conditions?.approved === true
      && conditions.validFrom <= localDay && (!conditions.validUntil || localDay <= conditions.validUntil);
  });
}
export function lessonCommercial(product: PlanningProduct, duration: number) {
  const quantity = product.durationMinutes ? duration / product.durationMinutes : 0;
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > 100) throw new Error('La durée ne correspond pas à cette prestation.');
  const agreedPriceCents = quantity * product.unitPriceCents;
  if (!Number.isSafeInteger(agreedPriceCents)) throw new Error('Montant invalide.');
  return { agreedPriceCents, commercialSelection: { mode: 'UNIT_PRICE' as const, serviceProductVersionId: product.id, quantity, entitlementLotId: null, acceptedTermsVersionId: product.termsVersionId } };
}
export function lessonWriteBody(form: LessonForm, timeZone: string, policyVersionId: string, product?: PlanningProduct, original?: PlanningLesson, now = Date.now()): Record<string, unknown> {
  const interval = lessonInterval(form, timeZone, now);
  if (!interval || !form.trainingId || !form.instructorId) throw new Error('Choisissez une formation, un moniteur et un créneau futur valide.');
  const { bufferMinutes, ...dates } = interval;
  const common = { ...dates, instructorMembershipId: form.instructorId, meetingPoint: form.meetingPoint.trim() };
  if (original) {
    if (!form.agreement) throw new Error('Confirmez l’accord pour ce déplacement.');
    if (!form.commercialChange && Number(form.duration) !== (Date.parse(original.plannedEnd) - Date.parse(original.plannedStart)) / 60_000) throw new Error('Un changement de durée nécessite un nouveau tarif explicite.');
    if (form.commercialChange && (!product || !form.reason.trim())) throw new Error('Choisissez le nouveau tarif et indiquez le motif.');
    return { ...common, agreementConfirmed: true, reason: form.reason.trim() || null,
      ...(form.commercialChange && product ? { commercialChange: { ...lessonCommercial(product, Number(form.duration)), expectedAccountVersion: null, reason: form.reason.trim() } } : {}) };
  }
  if (!product || !policyVersionId) throw new Error('Choisissez les conditions applicables à cette leçon.');
  return { ...common, trainingId: form.trainingId, bufferMinutes, policyVersionId, ...lessonCommercial(product, Number(form.duration)) };
}
export function canEditPlannedLesson(lesson: PlanningLesson): boolean { return lesson.status === 'PLANNED' && lesson.actualStart === null && lesson.actualEnd === null; }
