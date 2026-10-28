import { useEffect, useRef, useState } from 'react';
import { commandMessage, createCommand, formatCents } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { assignmentSchema, catalogPolicySchema, learnerSchema, memberSchema, offeringSchema, readAll, readSchool, termsSchema, trainingSchema } from '../school-api';
import { applicableProducts, assignmentCovers, canEditPlannedLesson, initialLessonForm, individualCancellationDeadline, lessonCommercial, lessonInterval, lessonLocalInstants, lessonWriteBody, planningLessonSchema, planningProductSchema, planningTrainingLabel, slotAvailabilitySchema, type LessonForm, type PlanningLesson } from '../lesson-planning-model';
import { CheckField, ConfirmDialog, Facts, Notice, SelectField, Symbol, TextArea, TextField, formatDateTime } from '../ui';
import { readError, useCommandRunner, useConsole, useLoad, useUnsavedChanges } from './context';
import { LoadState, OutcomeNotice } from './layout';
import { distinctLabel, homonymReferences } from '../person-reference';
import { RequestFailure } from '../protocol';
import './planning-workspace.css';

async function readPlanningCatalogue(schoolId: string) {
  const [learners, members, offerings, policies, products, terms] = await Promise.all([
    readAll(schoolId, 'learners', learnerSchema), readAll(schoolId, 'members', memberSchema), readAll(schoolId, 'offerings', offeringSchema),
    readAll(schoolId, 'policy-versions', catalogPolicySchema), readAll(schoolId, 'service-products', planningProductSchema), readAll(schoolId, 'commercial-terms', termsSchema),
  ]);
  return { learners: learners.items, members: members.items, offerings: offerings.items, policies: policies.items, products: products.items, terms: terms.items,
    truncated: [learners, members, offerings, policies, products, terms].some(list => list.truncated) };
}
type Catalogue = Awaited<ReturnType<typeof readPlanningCatalogue>>;

export function LessonWorkspace({ lessonId, learnerId, onClose, onSaved, onDossier }: {
  lessonId: string | null; learnerId?: string | undefined; onClose: () => void; onSaved: () => void; onDossier: (learnerId: string, lessonId: string) => void;
}) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    if (!lessonId) return null;
    const lesson = await readSchool(schoolId, `lessons/${lessonId}`, planningLessonSchema);
    if (lesson.id !== lessonId || lesson.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return lesson;
  }, [schoolId, lessonId, revision], `${schoolId}/${lessonId ?? 'new'}`, `planning-lesson/${lessonId ?? 'new'}`);
  const [edit, setEdit] = useState(!lessonId);
  const [awaitingVersion, setAwaitingVersion] = useState(0);
  const waitingForRead = !!lessonId && awaitingVersion > 0 && (!loaded.data || loaded.data.version <= awaitingVersion);
  const saved = (previous?: PlanningLesson | null) => { setAwaitingVersion(previous?.version ?? 0); loaded.reload(); onSaved(); };
  return <section className="section-stack lesson-workspace" aria-label={lessonId ? 'Fiche de la leçon' : 'Nouvelle leçon'}>
    {waitingForRead && <Notice tone="success" title="Modification confirmée, actualisation de la fiche…" />}
    <LoadState loaded={loaded} label="Lecture de la leçon…">{lesson => edit
      ? <LessonEditor key={lesson?.id ?? 'new'} original={lesson ?? undefined} learnerId={learnerId} onClose={() => lesson ? setEdit(false) : onClose()}
        onSaved={() => { setEdit(false); saved(lesson); if (!lesson) onClose(); }} />
      : lesson && <LessonDetail lesson={lesson} refreshing={waitingForRead} onEdit={() => setEdit(true)} onClose={onClose} onDossier={() => onDossier(lesson.learnerId, lesson.id)} onSaved={() => saved(lesson)} />}</LoadState>
    {loaded.status === 'error' && !loaded.data && <button type="button" className="button secondary" onClick={onClose}>Retour à l’agenda</button>}
  </section>;
}

function LessonDetail({ lesson, refreshing, onEdit, onClose, onDossier, onSaved }: { lesson: PlanningLesson; refreshing: boolean; onEdit: () => void; onClose: () => void; onDossier: () => void; onSaved: () => void }) {
  const { schoolId, membership } = useConsole();
  const [cancel, setCancel] = useState<PlanningLesson | null>(null), [reasonCode, setReasonCode] = useState('LEARNER_REQUEST'), [comment, setComment] = useState(''), [discard, setDiscard] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { heading.current?.focus(); }, []);
  const runner = useCommandRunner(() => { setCancel(null); setComment(''); setReasonCode('LEARNER_REQUEST'); onSaved(); });
  const locked = runner.busy || !!runner.pending;
  const dirty = comment.length > 0 || reasonCode !== 'LEARNER_REQUEST';
  useUnsavedChanges(!!cancel && dirty);
  const authorized = membership.roles.includes('ADMIN') || membership.roles.includes('INSTRUCTOR') && membership.membershipId === lesson.instructorMembershipId;
  const editable = authorized && canEditPlannedLesson(lesson);
  const cancelLesson = async () => {
    if (!cancel) return;
    const result = await runner.run(createCommand({ schoolId, kind: 'cancelLesson', path: `lessons/${cancel.id}/cancel`, ifMatch: cancel.version,
      resourceId: cancel.id, resourceVersion: cancel.version, body: { reasonCode, comment: comment.trim() || null } }), 'La leçon est annulée.');
    if (result.status === 'pending') {
      setCancel(null); // The global AP72 panel must remain reachable outside a modal.
      window.requestAnimationFrame(() => document.getElementById('pending-title')?.focus());
    }
  };
  return <>
    <div className="planning-page-heading"><button type="button" className="button quiet planning-back" onClick={onClose} disabled={locked}><Symbol kind="back" bare />Retour à l’agenda</button>
      <div className="section-head"><div><p className="eyebrow">Leçon</p><h2 tabIndex={-1} ref={heading}>{lesson.learnerDisplayName}</h2></div>
        {editable && <button type="button" className="button primary" onClick={onEdit} disabled={locked || refreshing}><Symbol kind="edit" bare />Modifier</button>}</div></div>
    <div className="planning-detail-card">
    <Facts items={[
      ['État', lesson.status === 'CANCELLED' ? 'Annulée' : lesson.status === 'COMPLETED' ? 'Terminée' : lesson.status === 'NO_SHOW' ? 'Absent' : lesson.actualStart ? 'Commencée' : 'Planifiée'],
      ['Début', formatDateTime(lesson.plannedStart, lesson.timeZone)], ['Fin', formatDateTime(lesson.plannedEnd, lesson.timeZone)],
      ['Moniteur', lesson.instructorDisplayName], ['Rendez-vous', lesson.meetingPoint || 'Non précisé'], ['Prix convenu', formatCents(lesson.priceCentsSnapshot)],
    ]} />
    </div>
    {lesson.permitWarning && <Notice tone="warning" title="Permis à vérifier" />}
    <OutcomeNotice outcome={runner.outcome} />
    <div className="form-actions">
      <button type="button" className="button secondary" onClick={onDossier} disabled={locked}>Ouvrir le dossier élève</button>
      {editable && <button type="button" className="button quiet danger" onClick={() => setCancel(lesson)} disabled={locked || refreshing}>Annuler la leçon</button>}
    </div>
    <ConfirmDialog open={!!cancel && !discard} title="Annuler cette leçon ?" confirmLabel="Confirmer l’annulation" busy={locked} disabledReason={runner.blockedReason} onCancel={() => dirty ? setDiscard(true) : setCancel(null)} onConfirm={() => void cancelLesson()}>
      <p>{cancel?.learnerDisplayName} · {cancel ? formatDateTime(cancel.plannedStart, cancel.timeZone) : ''}</p>
      <SelectField label="Motif" value={reasonCode} onChange={setReasonCode} disabled={locked} options={[
        { value: 'LEARNER_REQUEST', label: 'Demande de l’élève' }, { value: 'INSTRUCTOR_UNAVAILABLE', label: 'Moniteur indisponible' }, { value: 'SCHOOL_CLOSURE', label: 'Fermeture de l’école' }, { value: 'OTHER', label: 'Autre motif' },
      ]} />
      <TextArea label="Commentaire" value={comment} onChange={setComment} maxLength={1000} disabled={locked} />
      <OutcomeNotice outcome={runner.outcome} />
      {runner.outcome?.code === 'VERSION_CONFLICT' && <button type="button" className="button secondary" onClick={async () => {
        try { const current = await readSchool(schoolId, `lessons/${lesson.id}`, planningLessonSchema); if (current.id === lesson.id && current.schoolId === schoolId && canEditPlannedLesson(current)) { setCancel(current); runner.clearOutcome(); } } catch { /* Existing refusal and typed reason remain visible. */ }
      }}>Relire la leçon en conservant le motif</button>}
    </ConfirmDialog>
    <ConfirmDialog open={discard} title="Quitter sans conserver le motif ?" confirmLabel="Abandonner le motif" busy={false} onCancel={() => setDiscard(false)} onConfirm={() => { setDiscard(false); setCancel(null); setComment(''); setReasonCode('LEARNER_REQUEST'); }}><p>Le motif saisi sera perdu.</p></ConfirmDialog>
  </>;
}

function LessonEditor({ original, learnerId, onClose, onSaved }: { original?: PlanningLesson | undefined; learnerId?: string | undefined; onClose: () => void; onSaved: () => void }) {
  const { schoolId } = useConsole();
  const catalogue = useLoad(() => readPlanningCatalogue(schoolId), [schoolId], undefined, 'planning-catalogue');
  return <LoadState loaded={catalogue} label="Lecture des élèves et conditions…">{data => <LoadedLessonEditor original={original} learnerId={learnerId} catalogue={data} onClose={onClose} onSaved={onSaved} />}</LoadState>;
}

function LoadedLessonEditor({ original: loadedOriginal, learnerId, catalogue, onClose, onSaved }: { original?: PlanningLesson | undefined; learnerId?: string | undefined; catalogue: Catalogue; onClose: () => void; onSaved: () => void }) {
  const { schoolId, school, membership } = useConsole();
  // Hold the version reviewed by this form. A background refresh must not silently rebase a write.
  const [original, setOriginal] = useState(loadedOriginal);
  const initial = useRef(initialLessonForm(original, learnerId));
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { heading.current?.focus(); }, []);
  const [form, setForm] = useState(initial.current), [closing, setClosing] = useState(false), [review, setReview] = useState<Record<string, unknown> | null>(null);
  const [checking, setChecking] = useState(false), [problem, setProblem] = useState('');
  const mounted = useRef(true);
  useEffect(() => () => { mounted.current = false; }, []);
  const runner = useCommandRunner(onSaved);
  const locked = runner.busy || !!runner.pending || checking;
  const dirty = JSON.stringify(form) !== JSON.stringify(initial.current);
  const release = useUnsavedChanges(dirty);
  const close = () => { if (!locked) { if (dirty) setClosing(true); else { release(); onClose(); } } };
  const change = <K extends keyof LessonForm>(key: K, value: LessonForm[K]) => { setForm(previous => ({ ...previous, [key]: value })); setProblem(''); setReview(null); runner.clearOutcome(); };
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
  const learners = catalogue.learners.filter(item => !item.archivedAt), learnerReferences = homonymReferences(learners.map(item => ({ id: item.id, label: item.displayName })));
  const instructorReferences = homonymReferences(instructors.map(item => ({ id: item.id, label: item.displayName })));
  const products = applicableProducts(catalogue.products, catalogue.terms, offering?.categoryCode ?? '', form.localStart.slice(0, 10), Number(form.duration));
  const product = products.find(item => item.id === form.productId), terms = catalogue.terms.find(item => item.id === (original && !form.commercialChange ? original.commercialSelection.acceptedTermsVersionId : product?.termsVersionId));
  const usesNewTerms = !original || form.commercialChange;
  const price = usesNewTerms ? product ? lessonCommercial(product, Number(form.duration)).agreedPriceCents : null : original.priceCentsSnapshot;
  const complete = trainingRead.status === 'ready' && assignmentRead.status === 'ready' && !catalogue.truncated && !trainingRead.data?.truncated && !assignmentRead.data?.truncated;
  const verify = async () => {
    setProblem(''); runner.clearOutcome();
    if (original && !canEditPlannedLesson(original)) { setProblem('Cette leçon a commencé ou est terminée. Fermez le formulaire pour retrouver sa fiche.'); return; }
    if (!complete || !training || !offering || !policy || !instructors.some(item => item.id === form.instructorId) || !learners.some(item => item.id === form.learnerId)) { setProblem('Choisissez une formation active et un moniteur affecté pour tout ce créneau. Les lectures doivent être complètes.'); return; }
    try {
      const body = lessonWriteBody(form, school.timeZone, policy.id, product, original);
      if (!interval) throw new Error('Ce créneau n’est pas valide dans le fuseau de l’école.');
      setChecking(true);
      const availability = await readSchool(schoolId, 'lessons/availability', slotAvailabilitySchema, {
        trainingId: form.trainingId, instructorMembershipId: form.instructorId, plannedStart: interval.plannedStart, plannedEnd: interval.plannedEnd,
        timeZone: school.timeZone, bufferMinutes: String(original?.bufferMinutesSnapshot ?? interval.bufferMinutes), ...(original ? { excludeLessonId: original.id } : {}),
      });
      if (!mounted.current) return;
      if (!availability.available) setProblem(availability.reasonCode === 'SLOT_CONFLICT' ? 'Ce créneau chevauche un rendez-vous. Choisissez une autre heure.' : 'Ce créneau est en dehors des disponibilités du moniteur.');
      else setReview(body);
    } catch (error) { if (mounted.current) setProblem(error instanceof RequestFailure ? error.status === 401 || error.status === 0 ? readError(error) : commandMessage(error.code) : error instanceof Error ? error.message : 'Vérification impossible. Réessayez.'); }
    finally { if (mounted.current) setChecking(false); }
  };
  const submit = async () => {
    if (!review) return;
    const result = await runner.run(createCommand({ schoolId, kind: original ? 'moveLesson' : 'createLesson', path: original ? `lessons/${original.id}/move` : 'lessons',
      body: review, resourceVersion: original?.version ?? 0, ...(original ? { ifMatch: original.version, resourceId: original.id } : {}) }), original ? 'La leçon est déplacée.' : 'La leçon est planifiée.');
    if (result.status === 'rejected' || result.status === 'pending') setReview(null);
    if (result.status === 'pending') window.requestAnimationFrame(() => document.getElementById('pending-title')?.focus());
  };
  const rereadVersion = async () => {
    if (!original) return;
    setChecking(true);
    try {
      const current = await readSchool(schoolId, `lessons/${original.id}`, planningLessonSchema);
      if (!mounted.current) return;
      if (current.id !== original.id || current.schoolId !== schoolId || current.trainingId !== original.trainingId) throw new RequestFailure('INVALID_RESPONSE');
      setOriginal(current); setReview(null); runner.clearOutcome();
      setForm(previous => ({ ...previous, buffer: String(current.bufferMinutesSnapshot),
        duration: previous.commercialChange ? previous.duration : String((Date.parse(current.plannedEnd) - Date.parse(current.plannedStart)) / 60_000), agreement: false }));
      setProblem(`Version actuelle relue : ${formatDateTime(current.plannedStart, current.timeZone)}, ${formatCents(current.priceCentsSnapshot)}. Votre proposition reste saisie. Relisez-la et confirmez de nouveau l’accord.`);
    } catch (error) { if (mounted.current) setProblem(readError(error)); }
    finally { if (mounted.current) setChecking(false); }
  };
  return <>
    <div className="planning-page-heading"><button type="button" className="button quiet planning-back" disabled={locked} onClick={close}><Symbol kind="back" bare />{original ? 'Retour à la leçon' : 'Retour à l’agenda'}</button>
      <h2 tabIndex={-1} ref={heading}>{original ? 'Modifier la leçon' : 'Planifier une leçon'}</h2></div>
    {catalogue.truncated && <Notice tone="warning" title="Catalogue incomplet"><p>La liste dépasse la limite de lecture. La planification est suspendue pour éviter un choix incomplet.</p></Notice>}
    <form className="section-stack planning-editor" onSubmit={event => { event.preventDefault(); void verify(); }}>
      <fieldset disabled={locked} className="planning-fieldset planning-form-grid">
        <legend>Élève et moniteur</legend>
        <SelectField label="Élève" required search value={form.learnerId} disabled={!!original} onChange={value => { change('learnerId', value); setForm(previous => ({ ...previous, trainingId: '', instructorId: '', productId: '' })); }}
          options={[{ value: '', label: 'Choisir un élève' }, ...learners.map(item => ({ value: item.id, label: distinctLabel(item.displayName, learnerReferences.get(item.id)) }))]} />
        <SelectField label="Formation" required value={form.trainingId} disabled={!!original} onChange={value => {
          const selected = trainings.find(item => item.id === value), offer = catalogue.offerings.find(item => item.id === selected?.offeringId);
          change('trainingId', value); setForm(previous => ({ ...previous, instructorId: '', productId: '', duration: offer ? String(offer.defaultDurationMinutes) : '' }));
        }} options={[{ value: '', label: 'Choisir une formation' }, ...trainingLabels.map(item => ({ value: item.id, label: distinctLabel(item.label, trainingReferences.get(item.id)) }))]} />
        <SelectField label="Moniteur" required search value={form.instructorId} onChange={value => change('instructorId', value)} options={[{ value: '', label: 'Choisir un moniteur affecté' }, ...instructors.map(item => ({ value: item.id, label: distinctLabel(item.displayName, instructorReferences.get(item.id)) }))]} />
      </fieldset>
      <fieldset disabled={locked} className="planning-fieldset planning-form-grid">
        <legend>Rendez-vous</legend>
        <TextField label={`Début (${school.timeZone})`} type="datetime-local" required value={form.localStart} onChange={value => { change('localStart', value); setForm(previous => ({ ...previous, localChoice: '' })); }} />
        {localInstants.length > 1 && <SelectField label="Heure répétée lors du changement d’heure" required value={form.localChoice} onChange={value => change('localChoice', value)} options={[{ value: '', label: 'Choisir le passage' }, ...localInstants.map((instant, index) => ({ value: instant, label: `${index + 1}ᵉ passage · ${new Intl.DateTimeFormat('fr-CH', { timeZone: school.timeZone, hour: '2-digit', minute: '2-digit', timeZoneName: 'shortOffset' }).format(new Date(instant))}` }))]} />}
        <TextField label="Durée en minutes" type="number" required value={form.duration} disabled={!!original && !form.commercialChange} onChange={value => change('duration', value)} />
        <TextField label="Marge après la leçon (minutes)" type="number" required value={form.buffer} disabled={!!original} onChange={value => change('buffer', value)} />
        <TextField label="Lieu de rendez-vous" maxLength={500} value={form.meetingPoint} onChange={value => change('meetingPoint', value)} />
      </fieldset>
      <LoadState loaded={trainingRead} label="Lecture des formations…">{data => data.truncated ? <Notice tone="warning" title="Formations partiellement chargées" /> : null}</LoadState>
      <LoadState loaded={assignmentRead} label="Lecture des affectations…">{data => data.truncated ? <Notice tone="warning" title="Affectations partiellement chargées" /> : null}</LoadState>
      <fieldset disabled={locked} className="planning-fieldset section-stack"><legend>Tarif convenu</legend>
      {original && <CheckField label="Changer explicitement la durée ou le tarif" checked={form.commercialChange} disabled={locked} onChange={value => { change('commercialChange', value); if (!value) setForm(previous => ({ ...previous, duration: String((Date.parse(original.plannedEnd) - Date.parse(original.plannedStart)) / 60_000) })); }} />}
      {usesNewTerms ? <SelectField label="Prestation et tarif" required value={form.productId} disabled={locked} onChange={value => change('productId', value)}
        options={[{ value: '', label: 'Choisir le tarif applicable' }, ...products.map(item => ({ value: item.id, label: `${item.label} · ${formatCents(lessonCommercial(item, Number(form.duration)).agreedPriceCents)}` }))]} />
        : <p>Prix convenu conservé : <strong>{formatCents(original.priceCentsSnapshot)}</strong></p>}
      {usesNewTerms && form.localStart && form.duration && products.length === 0 && <Notice tone="warning" title="Aucun tarif applicable"><p>Vérifiez la formation, la durée et la date. Un tarif en vigueur et ses conditions approuvées sont nécessaires.</p></Notice>}
      {original && <><TextArea label={form.commercialChange ? 'Motif du changement de tarif' : 'Motif du déplacement'} required={form.commercialChange} maxLength={1000} value={form.reason} disabled={locked} onChange={value => change('reason', value)} />
        <CheckField label="L’élève et le moniteur ont accepté ce déplacement" checked={form.agreement} disabled={locked} onChange={value => change('agreement', value)} /></>}
      </fieldset>
      {problem && <Notice tone="error" title="Planification à corriger"><p>{problem}</p></Notice>}
      <OutcomeNotice outcome={runner.outcome} actions={original && runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary" disabled={locked} onClick={() => void rereadVersion()}>Relire la version actuelle</button> : undefined} />
      {runner.blockedReason && <Notice tone="warning" title="Résultat en cours de vérification"><p>{runner.blockedReason}</p></Notice>}
      <div className="planning-form-actions"><button type="submit" className="button primary" disabled={locked} aria-busy={checking}>{checking ? 'Vérification du créneau…' : 'Vérifier la leçon'}</button></div>
    </form>
    <ConfirmDialog open={review !== null} title={original ? 'Vérifier le déplacement' : 'Vérifier la leçon'} confirmLabel={original ? 'Confirmer le déplacement' : 'Planifier la leçon'} busy={locked} disabledReason={runner.blockedReason} onCancel={() => setReview(null)} onConfirm={() => void submit()}>
      <Facts items={[
        ...(original ? [['Ancien rendez-vous', formatDateTime(original.plannedStart, original.timeZone)] as const] : []),
        ['Élève', learners.find(item => item.id === form.learnerId)?.displayName ?? ''], ['Formation', offering?.categoryCode ?? ''],
        ['Moniteur', instructors.find(item => item.id === form.instructorId)?.displayName ?? ''],
        ['Début', interval ? formatDateTime(interval.plannedStart, school.timeZone) : ''], ['Fin', interval ? formatDateTime(interval.plannedEnd, school.timeZone) : ''],
        ['Rendez-vous', form.meetingPoint || 'Non précisé'], ['Prix convenu', price !== null ? formatCents(price) : ''],
        ...(cancellationDeadline ? [['Annulation : prévenir l’école au plus tard', `${formatDateTime(cancellationDeadline, school.timeZone)} (${school.timeZone})`] as const] : []),
      ]} />
      {terms && <details><summary>Conditions · {terms.label}</summary><p className="preserve-lines">{terms.termsText}</p></details>}
      {!original && policy && <details><summary>Procédure et annulation</summary><p className="preserve-lines">{policy.procedureText}</p><p className="preserve-lines">{policy.cancellationPolicyText}</p></details>}
      {original && <p>{form.commercialChange ? 'Le nouveau tarif remplacera les conditions de cette leçon.' : 'Le tarif et les conditions convenus restent inchangés.'}</p>}
      <OutcomeNotice outcome={runner.outcome} />
    </ConfirmDialog>
    <ConfirmDialog open={closing} title="Quitter sans enregistrer ?" confirmLabel="Abandonner les modifications" busy={false} onCancel={() => setClosing(false)} onConfirm={() => { release(); onClose(); }}><p>Les modifications de cette leçon seront perdues.</p></ConfirmDialog>
  </>;
}
