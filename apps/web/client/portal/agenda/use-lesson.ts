import { useEffect, useRef, useState } from 'react';
import { commandMessage, createCommand } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { assignmentSchema, catalogPolicySchema, learnerSchema, memberSchema, offeringSchema, readAll, readSchool, termsSchema, trainingSchema } from '../../school-api';
import { applicableProducts, assignmentCovers, canEditPlannedLesson, initialLessonForm, individualCancellationDeadline, lessonCommercial, lessonInterval, lessonLocalInstants,
  lessonWriteBody, planningLessonSchema, planningProductSchema, planningTrainingLabel, slotAvailabilitySchema, type LessonForm, type PlanningLesson } from '../../lesson-planning-model';
import { readError, useCommandRunner, useConsole, useLoad, useUnsavedChanges } from '../../console/context';
import { distinctLabel, homonymReferences } from '../../person-reference';
import { RequestFailure } from '../../protocol';

export async function readPlanningCatalogue(schoolId: string) {
  const [learners, members, offerings, policies, products, terms] = await Promise.all([
    readAll(schoolId, 'learners', learnerSchema), readAll(schoolId, 'members', memberSchema), readAll(schoolId, 'offerings', offeringSchema),
    readAll(schoolId, 'policy-versions', catalogPolicySchema), readAll(schoolId, 'service-products', planningProductSchema), readAll(schoolId, 'commercial-terms', termsSchema),
  ]);
  return { learners: learners.items, members: members.items, offerings: offerings.items, policies: policies.items, products: products.items, terms: terms.items,
    truncated: [learners, members, offerings, policies, products, terms].some(list => list.truncated) };
}
export type PlanningCatalogue = Awaited<ReturnType<typeof readPlanningCatalogue>>;

export function useLesson(lessonId: string | null, onSaved: () => void) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    if (!lessonId) return null;
    const lesson = await readSchool(schoolId, `lessons/${lessonId}`, planningLessonSchema);
    if (lesson.id !== lessonId || lesson.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return lesson;
  }, [schoolId, lessonId, revision], `${schoolId}/${lessonId ?? 'new'}`, `planning-lesson/${lessonId ?? 'new'}`);
  const [editing, setEditing] = useState(!lessonId);
  const [confirmedVersion, setConfirmedVersion] = useState(0);
  const refreshing = Boolean(lessonId && confirmedVersion > 0 && (!loaded.data || loaded.data.version <= confirmedVersion));
  const saved = (previous?: PlanningLesson | null) => { setConfirmedVersion(previous?.version ?? 0); loaded.reload(); onSaved(); };
  return { loaded, editing, setEditing, refreshing, saved };
}

/** Domain state and effects only: presentation never owns an alternate command queue. */
export function useLessonEditor(loadedOriginal: PlanningLesson | undefined, learnerId: string | undefined, catalogue: PlanningCatalogue, onSaved: () => void) {
  const { schoolId, school, membership } = useConsole();
  const [original, setOriginal] = useState(loadedOriginal);
  const initial = useRef(initialLessonForm(original, learnerId));
  const [form, setForm] = useState(initial.current);
  const [step, setStep] = useState<'people' | 'appointment' | 'review'>(original ? 'appointment' : 'people');
  const [review, setReview] = useState<Record<string, unknown> | null>(null);
  const [checking, setChecking] = useState(false), [problem, setProblem] = useState('');
  const requestInFlight = useRef(false), submitInFlight = useRef(false), mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const runner = useCommandRunner(onSaved);
  const wasPending = useRef(false);
  useEffect(() => {
    if (runner.pending) wasPending.current = true;
    else if (wasPending.current && !runner.busy) { wasPending.current = false; submitInFlight.current = false; setReview(null); setStep('appointment'); }
  }, [runner.pending, runner.busy]);
  const locked = runner.busy || Boolean(runner.pending) || checking;
  const dirty = JSON.stringify(form) !== JSON.stringify(initial.current);
  const release = useUnsavedChanges(dirty);
  const change = <K extends keyof LessonForm>(key: K, value: LessonForm[K]) => {
    if (requestInFlight.current || submitInFlight.current) return;
    setForm(previous => ({ ...previous, [key]: value })); setProblem(''); setReview(null); runner.clearOutcome();
  };
  const trainingRead = useLoad(async () => form.learnerId ? readAll(schoolId, 'trainings', trainingSchema, { learnerId: form.learnerId }) : { items: [], truncated: false },
    [schoolId, form.learnerId], `${schoolId}/${form.learnerId}`, `planning-trainings/${form.learnerId}`);
  const assignmentRead = useLoad(async () => form.trainingId ? readAll(schoolId, `trainings/${form.trainingId}/assignments`, assignmentSchema) : { items: [], truncated: false },
    [schoolId, form.trainingId], `${schoolId}/${form.trainingId}`, `planning-assignments/${form.trainingId}`);
  const trainings = (trainingRead.data?.items ?? []).filter(item => item.status === 'ACTIVE' && item.learnerId === form.learnerId);
  const training = trainings.find(item => item.id === form.trainingId);
  const trainingLabels = trainings.map(item => ({ id: item.id, label: planningTrainingLabel(item, catalogue.offerings.find(offer => offer.id === item.offeringId)) }));
  const trainingReferences = homonymReferences(trainingLabels);
  const offering = catalogue.offerings.find(item => item.id === training?.offeringId && item.enabled);
  const policy = catalogue.policies.find(item => item.id === offering?.policyVersionId && item.approved);
  const interval = lessonInterval(form, school.timeZone);
  const cancellationDeadline = !original && interval ? individualCancellationDeadline(interval.plannedStart, policy?.cancellationRules) : null;
  const localInstants = lessonLocalInstants(form.localStart, school.timeZone);
  const instructors = catalogue.members.filter(item => item.status === 'ACTIVE' && item.roles.includes('INSTRUCTOR')
    && (membership.roles.includes('ADMIN') || item.id === membership.membershipId)
    && assignmentRead.data?.items.some(assignment => assignment.instructorMembershipId === item.id && assignment.trainingId === form.trainingId
      && (interval ? assignmentCovers(assignment, interval.plannedStart, interval.plannedEnd) : Date.parse(assignment.validFrom) <= Date.now() && (!assignment.validUntil || Date.parse(assignment.validUntil) > Date.now()))));
  const learners = catalogue.learners.filter(item => !item.archivedAt);
  const learnerReferences = homonymReferences(learners.map(item => ({ id: item.id, label: item.displayName })));
  const instructorReferences = homonymReferences(instructors.map(item => ({ id: item.id, label: item.displayName })));
  const learnerOptions = learners.map(item => ({ value: item.id, label: distinctLabel(item.displayName, learnerReferences.get(item.id)) }));
  const trainingOptions = trainingLabels.map(item => ({ value: item.id, label: distinctLabel(item.label, trainingReferences.get(item.id)) }));
  const instructorOptions = instructors.map(item => ({ value: item.id, label: distinctLabel(item.displayName, instructorReferences.get(item.id)) }));
  const products = applicableProducts(catalogue.products, catalogue.terms, offering?.categoryCode ?? '', form.localStart.slice(0, 10), Number(form.duration));
  const product = products.find(item => item.id === form.productId);
  const terms = catalogue.terms.find(item => item.id === (original && !form.commercialChange ? original.commercialSelection.acceptedTermsVersionId : product?.termsVersionId));
  const usesNewTerms = !original || form.commercialChange;
  const price = usesNewTerms ? product ? lessonCommercial(product, Number(form.duration)).agreedPriceCents : null : original.priceCentsSnapshot;
  const complete = trainingRead.status === 'ready' && assignmentRead.status === 'ready' && !catalogue.truncated && !trainingRead.data?.truncated && !assignmentRead.data?.truncated;
  const chooseLearner = (id: string) => { if (requestInFlight.current || submitInFlight.current) return; change('learnerId', id); setForm(previous => ({ ...previous, trainingId: '', instructorId: '', productId: '' })); };
  const chooseTraining = (id: string) => {
    if (requestInFlight.current || submitInFlight.current) return;
    const chosen = trainings.find(item => item.id === id), offer = catalogue.offerings.find(item => item.id === chosen?.offeringId);
    change('trainingId', id); setForm(previous => ({ ...previous, instructorId: '', productId: '', duration: offer ? String(offer.defaultDurationMinutes) : '' }));
  };
  const next = () => {
    if (!complete || !training || !offering || !policy || !instructors.some(item => item.id === form.instructorId) || !learners.some(item => item.id === form.learnerId)) {
      setProblem('Choisissez une formation active et un moniteur affecté. Les lectures doivent être complètes.'); return;
    }
    setProblem(''); setStep('appointment');
  };
  const verify = async () => {
    if (requestInFlight.current || submitInFlight.current || runner.pending) return;
    setProblem(''); runner.clearOutcome();
    if (original && !canEditPlannedLesson(original)) { setProblem('Cette leçon a commencé ou est terminée. Revenez à sa fiche.'); return; }
    if (!complete || !training || !offering || !policy || !instructors.some(item => item.id === form.instructorId) || !learners.some(item => item.id === form.learnerId)) { setProblem('Choisissez une formation active et un moniteur affecté pour tout ce créneau. Les lectures doivent être complètes.'); return; }
    try {
      const body = lessonWriteBody(form, school.timeZone, policy.id, product, original);
      if (!interval) throw new Error('Ce créneau n’est pas valide dans le fuseau de l’école.');
      requestInFlight.current = true; setChecking(true);
      const availability = await readSchool(schoolId, 'lessons/availability', slotAvailabilitySchema, {
        trainingId: form.trainingId, instructorMembershipId: form.instructorId, plannedStart: interval.plannedStart, plannedEnd: interval.plannedEnd,
        timeZone: school.timeZone, bufferMinutes: String(original?.bufferMinutesSnapshot ?? interval.bufferMinutes), ...(original ? { excludeLessonId: original.id } : {}),
      });
      if (!mounted.current) return;
      if (!availability.available) setProblem(availability.reasonCode === 'SLOT_CONFLICT' ? 'Ce créneau chevauche un rendez-vous. Choisissez une autre heure.' : 'Ce créneau est en dehors des disponibilités du moniteur.');
      else { setReview(body); setStep('review'); }
    } catch (error) { if (mounted.current) setProblem(error instanceof RequestFailure ? error.status === 401 || error.status === 0 ? readError(error) : commandMessage(error.code) : error instanceof Error ? error.message : 'Vérification impossible. Réessayez.'); }
    finally { requestInFlight.current = false; if (mounted.current) setChecking(false); }
  };
  const submit = async () => {
    if (!review || submitInFlight.current || requestInFlight.current || runner.pending) return;
    submitInFlight.current = true;
    const result = await runner.run(createCommand({ schoolId, kind: original ? 'moveLesson' : 'createLesson', path: original ? `lessons/${original.id}/move` : 'lessons',
      body: review, resourceVersion: original?.version ?? 0, ...(original ? { ifMatch: original.version, resourceId: original.id } : {}) }), original ? 'La leçon est déplacée.' : 'La leçon est planifiée.');
    if (!mounted.current) return;
    if (result.status === 'rejected') { submitInFlight.current = false; setReview(null); setStep('appointment'); }
    if (result.status === 'pending') window.requestAnimationFrame(() => document.getElementById('pending-title')?.focus());
  };
  const rereadVersion = async () => {
    if (!original || requestInFlight.current || submitInFlight.current) return;
    requestInFlight.current = true; setChecking(true);
    try {
      const current = await readSchool(schoolId, `lessons/${original.id}`, planningLessonSchema);
      if (!mounted.current) return;
      if (current.id !== original.id || current.schoolId !== schoolId || current.trainingId !== original.trainingId) throw new RequestFailure('INVALID_RESPONSE');
      setOriginal(current); setReview(null); setStep('appointment'); runner.clearOutcome();
      setForm(previous => ({ ...previous, buffer: String(current.bufferMinutesSnapshot), duration: previous.commercialChange ? previous.duration : String((Date.parse(current.plannedEnd) - Date.parse(current.plannedStart)) / 60_000), agreement: false }));
      setProblem('Version actuelle relue. Votre proposition est conservée ; relisez les conditions et confirmez de nouveau l’accord.');
    } catch (error) { if (mounted.current) setProblem(readError(error)); }
    finally { requestInFlight.current = false; if (mounted.current) setChecking(false); }
  };
  return { original, school, form, change, step, setStep, review, checking, problem, runner, locked, dirty, release, trainingRead, assignmentRead,
    learners, trainings, instructors, offering, policy, interval, cancellationDeadline, localInstants, learnerOptions, trainingOptions, instructorOptions,
    products, terms, usesNewTerms, price, complete, chooseLearner, chooseTraining, next, verify, submit, rereadVersion };
}
