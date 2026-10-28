import { useEffect, useRef, useState } from 'react';
import { civilDateIn } from '../agenda-model';
import { commonLessonTexts, type CommonLessonRules } from '../common-lesson-rules';
import { createCommand, formatCents } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { confirmedData, readSchool, offeringSchema, readAll, type Offering } from '../school-api';
import { RequestFailure } from '../protocol';
import { setupStepState } from '../setup-progress';
import { CheckField, ConfirmDialog, Facts, Notice, SegmentField, SelectField, Symbol, TextArea, TextField, formatCivilDate } from '../ui';
import { catalogueSetupContent, issueStep, selectSetupSection, setupContentSchema, setupDraftSchema, setupFormation, setupPreviewSchema, setupPrice, templateAlreadyAdded,
  setupStepLabels, initialSetupStep, setupNavigationSteps, setupTemplatesSchema, setupExampleText, refreshSetupExamples, resolvedSetupFormation, type SetupContent, type SetupDraft, type SetupFormation, type SetupPreview, type SetupStep, type SetupTemplates } from '../setup-model';
import { readError, useCommandRunner, useConsole, useLoad } from './context';
import { priceAmountProblem } from './formation-model';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
import { ProfileFieldsPreview } from './profile-fields-preview';
import './school-setup.css';

type StoredDraft = { version: number; content: SetupContent; step: SetupStep; dirty: boolean };
const fieldLabels: Record<string, string> = { firstName: 'Prénom', lastName: 'Nom', contactPhone: 'Téléphone', contactEmail: 'E-mail',
  birthDate: 'Date de naissance', postalAddress: 'Adresse postale', profilePhotoDocumentId: 'Photo de profil' };
const fieldDefaults: SetupContent['profile']['fields'] = [
  { field: 'firstName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Identifier votre dossier dans l’école.' },
  { field: 'lastName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Identifier votre dossier dans l’école.' },
  { field: 'contactPhone', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'LESSON_CONTACT', explanation: 'Vous joindre au sujet de vos leçons.' },
  { field: 'contactEmail', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'LESSON_CONTACT', explanation: 'Vous contacter au sujet de vos leçons.' },
  { field: 'birthDate', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'COURSE_ELIGIBILITY', explanation: 'Examiner les prérequis de votre formation.' },
  { field: 'postalAddress', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'POSTAL_CONTACT', explanation: 'Vous adresser les courriers nécessaires à votre dossier.' },
];
const clone = <T,>(value: T): T => structuredClone(value);
const focusPendingRequest = () => window.requestAnimationFrame(() => window.document.getElementById('pending-title')?.focus());
const atPath = (value: unknown, path: string): unknown => path.split('.').reduce<unknown>((current, key) =>
  current !== null && typeof current === 'object' ? (current as Record<string, unknown>)[key] : undefined, value);
function matchesReviewedField(current: unknown, reviewed: SetupContent, path: string): boolean {
  if (!Object.is(atPath(current, path), atPath(reviewed, path))) return false;
  const owners = [[/^formations\.\d+/, 'id'], [/^formations\.\d+\.competencies\.\d+/, 'key'], [/^profile\.fields\.\d+/, 'field']] as const;
  return owners.every(([pattern, key]) => {
    const prefix = path.match(pattern)?.[0];
    return !prefix || atPath(current, `${prefix}.${key}`) === atPath(reviewed, `${prefix}.${key}`);
  });
}

/** Same persisted editor for the first school setup and later formation preparation. */
export function SchoolSetupGuide({ catalogueOnly = false, initialCategory, onClose }: { catalogueOnly?: boolean; initialCategory?: string | undefined; onClose?: () => void }) {
  const { schoolId, school, navigate, drafts, canConfigureCatalog, setNavigationGuard, routeQuery } = useConsole();
  const snapshot = useCommandSnapshot();
  const [document, setDocument] = useState<SetupDraft | null>(null);
  const [content, setContent] = useState<SetupContent | null>(null);
  const [step, setStep] = useState<SetupStep>(catalogueOnly ? 'FORMATIONS' : 'IDENTITY');
  const [dirty, setDirty] = useState(false);
  const [editorRevision, setEditorRevision] = useState(0);
  const [preview, setPreview] = useState<SetupPreview | null>(null);
  const [reviewIssues, setReviewIssues] = useState<SetupPreview['issues']>([]);
  const [reviewContent, setReviewContent] = useState<SetupContent | null>(null);
  const [reviewing, setReviewing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const [readFailure, setReadFailure] = useState<string | null>(null);
  const [discard, setDiscard] = useState(false);
  const [leave, setLeave] = useState<(() => void) | null>(null);
  const [focusField, setFocusField] = useState<string | null>(null);
  const dirtyRef = useRef(false);
  dirtyRef.current = dirty;
  const [stepsOpen, setStepsOpen] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null);
  const needsAdoption = useRef(false);
  const localOperation = useRef<string | null>(null);
  const followedSetup = useRef<{ operationId: string; kind: 'saveSetupDraft' | 'applySetupDraft' } | null>(null);
  const pending = [...snapshot.entries.values()].find(entry => entry.meta.schoolId === schoolId
    && (entry.meta.kind === 'saveSetupDraft' || entry.meta.kind === 'applySetupDraft'));
  const hasPendingRequest = useRef(false);
  hasPendingRequest.current = !!pending;
  if (pending?.meta.kind === 'saveSetupDraft' || pending?.meta.kind === 'applySetupDraft') followedSetup.current = { operationId: pending.meta.operationId, kind: pending.meta.kind };
  const runner = useCommandRunner();
  const loaded = useLoad(async () => {
    const [draft, templates, offerings] = await Promise.all([
      readSchool(schoolId, 'setup-draft', setupDraftSchema),
      readSchool(schoolId, 'setup-draft/templates', setupTemplatesSchema),
      readAll(schoolId, 'offerings', offeringSchema),
    ]);
    if (draft.schoolId !== schoolId || draft.id !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return { draft, templates, offerings: offerings.items.filter(item => item.enabled) };
  }, [schoolId, snapshot.revision]);
  const steps = setupNavigationSteps(content, catalogueOnly);
  const blocked = saving || runner.busy || !!runner.pending || reviewing || needsAdoption.current;
  const key = `setup-draft:${catalogueOnly ? 'catalogue' : 'initial'}`;

  // A receipt may settle a command restored after a page reload, with no local runner.
  useEffect(() => {
    const confirmed = snapshot.confirmed;
    const followed = followedSetup.current;
    if (!confirmed || confirmed.operationId !== followed?.operationId) return;
    followedSetup.current = null;
    if (confirmed.operationId === localOperation.current) return;
    if (followed.kind === 'applySetupDraft') {
      setDirty(false); dirtyRef.current = false; drafts?.delete(key);
      navigate(catalogueOnly ? 'formations' : 'agenda');
      return;
    }
    needsAdoption.current = true;
    drafts?.delete(key);
    setReadFailure(null);
    loaded.reload();
  }, [snapshot.confirmed]);

  useEffect(() => {
    if (!loaded.data || loaded.status !== 'ready') return;
    if (document && !needsAdoption.current) return;
    const saved = loaded.data.draft;
    const remembered = needsAdoption.current ? undefined : drafts?.get(key) as StoredDraft | undefined;
    let next = clone(saved.content), nextStep = catalogueOnly ? saved.currentStep : initialSetupStep(saved, school.status), nextDirty = false;
    if (remembered && remembered.version === saved.version && setupContentSchema.safeParse(remembered.content).success) {
      next = remembered.content; nextStep = remembered.step; nextDirty = remembered.dirty;
    } else if (catalogueOnly && (saved.status === 'APPLIED' || saved.content.selectedSections.length === 0)) {
      next = catalogueSetupContent(next, saved.status === 'APPLIED'); nextStep = 'FORMATIONS'; nextDirty = true;
    } else if (!catalogueOnly && !next.privacy.noticeText && !next.privacy.templateId) {
      next.privacy = templatePrivacy(loaded.data.templates, next); nextDirty = true;
    }
    if (catalogueOnly) {
      nextDirty ||= next.selectedSections.length !== 1 || next.selectedSections[0] !== 'CATALOGUE';
      next = catalogueSetupContent(next);
      const template = loaded.data.templates.formations.find(item => item.categoryCode === initialCategory);
      if (template && next.formations.length === 0 && !loaded.data.offerings.some(item => item.categoryCode === template.categoryCode)) {
        next = { ...next, formations: [setupFormation(template, civilDateIn(school.timeZone))] }; nextDirty = true;
      }
    }
    const availableSteps = setupNavigationSteps(next, catalogueOnly);
    if (nextStep === 'PRICING' && !availableSteps.includes('PRICING')) nextStep = 'REVIEW';
    needsAdoption.current = false;
    setDocument(saved); setContent(next); setStep(availableSteps.includes(nextStep) || !catalogueOnly && ['IDENTITY', 'PRIVACY', 'PROFILE'].includes(nextStep) ? nextStep : availableSteps[0]!); setDirty(nextDirty);
    setEditorRevision(revision => revision + 1);
    setPreview(null); setReviewIssues([]); setReviewContent(null); setAcknowledged(false); setReadFailure(null);
  }, [loaded.data, loaded.status]);
  useEffect(() => {
    if (content && document) drafts?.set(key, { version: document.version, content, step, dirty } satisfies StoredDraft);
  }, [content, document, step, dirty, drafts, key]);
  useEffect(() => {
    const preventLoss = (event: BeforeUnloadEvent) => { if (dirty) { event.preventDefault(); event.returnValue = ''; } };
    window.addEventListener('beforeunload', preventLoss);
    return () => window.removeEventListener('beforeunload', preventLoss);
  }, [dirty]);
  useEffect(() => {
    setNavigationGuard?.(proceed => {
      if (hasPendingRequest.current) { focusPendingRequest(); return; }
      if (dirtyRef.current) setLeave(() => proceed); else proceed();
    });
    return () => setNavigationGuard?.(null);
  }, [setNavigationGuard]);
  useEffect(() => {
    setStepsOpen(false);
    const frame = window.requestAnimationFrame(() => {
      heading.current?.focus({ preventScroll: true });
      window.scrollTo({ top: 0, behavior: 'instant' });
    });
    return () => window.cancelAnimationFrame(frame);
  }, [step]);
  useEffect(() => {
    if (!focusField || issueStep(focusField) !== step) return;
    const frame = window.requestAnimationFrame(() => {
      const root = heading.current?.parentElement;
      const path = focusField.replace(/^content\./, '');
      const target = [...(root?.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('input[name],textarea[name]') ?? [])]
        .find(input => input.name === path || input.name.startsWith(`${path}.`));
      if (target) {
        for (let parent = target.parentElement; parent && parent !== root; parent = parent.parentElement) if (parent instanceof HTMLDetailsElement) parent.open = true;
        target.focus({ preventScroll: true }); target.scrollIntoView({ block: 'center', behavior: 'instant' });
      }
      setFocusField(null);
    });
    return () => window.cancelAnimationFrame(frame);
  }, [step, focusField]);
  const update = (next: SetupContent) => { setContent(content && loaded.data ? refreshSetupExamples(content, next, loaded.data.templates) : next); setDirty(true); setPreview(null); setAcknowledged(false); runner.clearOutcome(); };
  const errorFor = (path: string): string | null => reviewContent && matchesReviewedField(content, reviewContent, path)
    ? reviewIssues.filter(issue => issue.field.replace(/^content\./, '') === path).map(issue => issue.message).join(' ') || null : null;

  async function refreshReview(saved: SetupDraft) {
    setReviewing(true); setReadFailure(null); setAcknowledged(false);
    try {
      const result = await readSchool(schoolId, 'setup-draft/preview', setupPreviewSchema, { activate: String(school.status === 'DRAFT') });
      if (result.schoolId !== schoolId || result.draftVersion !== saved.version) throw new RequestFailure('VERSION_CONFLICT', 412);
      if (catalogueOnly && result.selectedSections.some(section => section !== 'CATALOGUE')) throw new RequestFailure('SETUP_REVIEW_CHANGED', 409);
      setPreview(result); setReviewIssues(result.issues); setReviewContent(result.content);
    } catch (error) { setReadFailure(readError(error)); } finally { setReviewing(false); }
  }
  async function save(nextStep: SetupStep, value = content, exit = false, afterSave?: () => void) {
    if (!value || !document || blocked) return;
    setSaving(true);
    setReadFailure(null); setPreview(null); setAcknowledged(false);
    try {
      const command = createCommand({ schoolId, kind: 'saveSetupDraft', path: 'setup-draft',
        ifMatch: document.version, resourceVersion: document.version, body: { currentStep: nextStep, content: value } });
      localOperation.current = command.operationId;
      const result = await runner.run(command, 'La préparation est enregistrée.');
      if (result.status !== 'confirmed') {
        localOperation.current = null;
        if (result.status === 'pending') { setLeave(null); focusPendingRequest(); }
        return;
      }
      // Use the exact committed response: a later GET could contain another administrator’s edit.
      const parsed = setupDraftSchema.safeParse(confirmedData(result.body));
      if (!parsed.success || parsed.data.schoolId !== schoolId || parsed.data.id !== schoolId || parsed.data.version !== document.version + 1) throw new RequestFailure('INVALID_RESPONSE');
      const saved = parsed.data;
      setDirty(false); dirtyRef.current = false; needsAdoption.current = false;
      setDocument(saved); setContent(clone(saved.content)); setStep(nextStep);
      drafts?.delete(key);
      if (afterSave) { setLeave(null); afterSave(); }
      else if (exit) { if (onClose) onClose(); else navigate('configuration'); }
      else if (nextStep === 'REVIEW') await refreshReview(saved);
    } catch (error) { needsAdoption.current = true; setReadFailure(readError(error)); loaded.reload(); }
    finally { setSaving(false); }
  }
  async function finish() {
    if (!preview?.ready || !acknowledged || !document || blocked || dirty || preview.draftVersion !== document.version) return;
    const command = createCommand({ schoolId, kind: 'applySetupDraft', path: 'setup-draft/complete', ifMatch: document.version,
      resourceVersion: document.version, body: { expectedSchoolVersion: preview.schoolVersion, expectedConfigurationVersion: preview.configurationVersion,
        reviewDigest: preview.reviewDigest, reviewAcknowledged: true, activate: preview.activate } });
    localOperation.current = command.operationId;
    const result = await runner.run(command, preview.activate ? 'Votre école est activée.' : 'La préparation est appliquée.');
    if (result.status === 'confirmed') { setDirty(false); dirtyRef.current = false; drafts?.delete(key); navigate(catalogueOnly ? 'formations' : 'agenda'); }
    else localOperation.current = null;
  }
  function skip() {
    if (!content) return;
    if (step === 'PROFILE') void save('FORMATIONS', selectSetupSection(content, 'PROFILE', false));
    if (step === 'FORMATIONS') void save('REVIEW', selectSetupSection({ ...content, formations: content.formations.map(item => ({ ...item, apply: false })) }, 'CATALOGUE', false));
    if (step === 'PRICING') void save('REVIEW', { ...content, formations: content.formations.map(item => ({ ...item, apply: false })) });
  }
  function jump(target: SetupStep, field?: string) {
    if (blocked || !steps.includes(target) && (catalogueOnly || !['IDENTITY', 'PRIVACY', 'PROFILE'].includes(target))) return;
    setFocusField(field ?? null);
    if (dirty) void save(target); else { setStep(target); if (target === 'REVIEW' && document) void refreshReview(document); }
  }
  const nextStep = steps.includes(step) ? steps[Math.min(steps.indexOf(step) + 1, steps.length - 1)]! : 'REVIEW';
  return <div className="section-stack school-setup">
    <SectionHeading title={catalogueOnly ? 'Préparer une formation' : 'Préparer votre école'} />
    <OutcomeNotice outcome={runner.outcome?.tone === 'success' ? null : runner.outcome} actions={runner.outcome?.code === 'VERSION_CONFLICT'
      ? <button type="button" className="button secondary" onClick={() => setDiscard(true)}>Relire la version enregistrée</button> : undefined} />
    {readFailure && <Notice tone="error" title="Vérification impossible" actions={<button className="button secondary" type="button" onClick={() => needsAdoption.current ? loaded.reload() : document && void refreshReview(document)}>Réessayer</button>}><p>{readFailure}</p></Notice>}
    {runner.blockedReason && <Notice tone="warning" title="Demande à vérifier"><p>{runner.blockedReason}</p></Notice>}
    <LoadState loaded={loaded} label="Lecture de votre préparation…">{data => content && document && <>
      <div className="setup-progress-mobile"><button type="button" className="button secondary" aria-expanded={stepsOpen} aria-controls="setup-progress" onClick={() => setStepsOpen(!stepsOpen)}>{steps.includes(step) ? `Étape ${steps.indexOf(step) + 1} sur ${steps.length}` : 'Modifier le résumé'}<Symbol kind="chevron" bare /></button>
        <div className="setup-progress-track" aria-hidden="true">{steps.map((item, index) => <span key={item} data-passed={index <= steps.indexOf(step)} />)}</div></div>
      <div className="setup-layout">
        <nav id="setup-progress" className={`setup-progress${stepsOpen ? ' is-open' : ''}`} aria-label="Étapes de préparation"><ol>{steps.map((item, index) => {
          const state = setupStepState(item, content, document.currentStep, reviewIssues);
          return <li key={item}><button type="button" aria-current={item === step ? 'step' : undefined} disabled={blocked} onClick={() => jump(item)}><span aria-hidden="true">{index + 1}</span><span className="setup-step-label">{setupStepLabels[item]}{state && <span className={`setup-step-state${state === 'À revoir' ? ' needs-review' : ''}`}>{state}</span>}</span></button></li>;
        })}</ol></nav>
        <div className="setup-workspace">
          <h2 ref={heading} tabIndex={-1} className="setup-title">{catalogueOnly && step === 'REVIEW' ? 'Vérifier la formation' : setupStepLabels[step]}</h2>
          <form onSubmit={event => { event.preventDefault(); if (step === 'REVIEW') void finish(); else void save(nextStep); }}>
            <fieldset className="setup-fields" disabled={blocked}>
              {step === 'IDENTITY' && <IdentityStep content={content} onChange={update} errorFor={errorFor} />}
              {step === 'PRIVACY' && <PrivacyStep content={content} templates={data.templates} onChange={update} errorFor={errorFor} />}
              {step === 'PROFILE' && <ProfileStep content={content} onChange={update} errorFor={errorFor} />}
              {step === 'FORMATIONS' && <FormationStep content={content} templates={data.templates} offerings={data.offerings} initialOfferingId={routeQuery?.selection} today={civilDateIn(school.timeZone)} onChange={update} canWrite={canConfigureCatalog} errorFor={errorFor} />}
              {step === 'PRICING' && <PricingStep key={`${document.version}:${editorRevision}`} content={content} onChange={update} canWrite={canConfigureCatalog} errorFor={errorFor} />}
              {step === 'REVIEW' && <>
                {!preview && <button type="button" className="button secondary" onClick={() => dirty ? void save('REVIEW') : void refreshReview(document)}>Vérifier la préparation</button>}
                {preview && <SetupReview preview={preview} onEdit={jump} />}
                {preview?.ready && <CheckField label={preview.activate ? 'J’ai relu ces choix et ces textes. Je les adopte pour mon école et confirme son activation.' : 'J’ai relu les formations et tarifs sélectionnés. Je confirme leur mise à disposition.'} checked={acknowledged} onChange={setAcknowledged} />}
              </>}
            </fieldset>
            <div className="setup-actions">
              <span className="setup-saved" role="status">{saving || runner.busy ? 'Enregistrement…' : dirty ? 'Modifications non enregistrées' : 'Enregistré'}</span>
              <div className="button-row">
                {steps.indexOf(step) > 0 && <button type="button" className="button quiet" disabled={blocked} onClick={() => jump(steps[steps.indexOf(step) - 1]!)}>Retour</button>}
                {(['PROFILE', 'FORMATIONS', 'PRICING'] as SetupStep[]).includes(step) && !catalogueOnly && <button type="button" className="button quiet" disabled={blocked} onClick={skip}>Plus tard</button>}
                <button type="button" className="button secondary setup-save-exit" disabled={blocked} onClick={() => void save(step, content, true)}>Enregistrer et quitter</button>
                <button type="submit" className="button primary setup-continue" disabled={blocked || (step === 'REVIEW' && (!preview?.ready || !acknowledged || dirty))}>
                  {step === 'REVIEW' ? preview?.activate ? 'Adopter les textes et activer l’école' : 'Confirmer la préparation' : 'Enregistrer et continuer'}
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </>}</LoadState>
    <ConfirmDialog open={discard} busy={blocked} title="Relire la préparation enregistrée ?" confirmLabel="Abandonner ma saisie et relire" onCancel={() => setDiscard(false)} onConfirm={() => {
      setDiscard(false); setDirty(false); runner.clearOutcome(); drafts?.delete(key); needsAdoption.current = true; loaded.reload();
    }}><p>Votre saisie non enregistrée sera remplacée par la version actuellement conservée par l’école.</p></ConfirmDialog>
    <ConfirmDialog open={leave !== null} busy={blocked} title="Enregistrer avant de quitter ?" confirmLabel="Enregistrer et quitter" onCancel={() => setLeave(null)} onConfirm={() => { if (leave) void save(step, content, false, leave); }}>
      <p>Les dernières modifications ne sont pas encore enregistrées.</p>
      <OutcomeNotice outcome={runner.outcome} />
      <button type="button" className="button quiet" disabled={blocked} onClick={() => { const proceed = leave; setLeave(null); dirtyRef.current = false; setDirty(false); drafts?.delete(key); proceed?.(); }}>Quitter sans enregistrer</button>
    </ConfirmDialog>
  </div>;
}

function templatePrivacy(templates: SetupTemplates, content: SetupContent): SetupContent['privacy'] {
  return { noticeText: setupExampleText(templates.privacy.noticeText, content),
    retentionText: setupExampleText(templates.privacy.retentionText, content), contactEmail: content.privacy.contactEmail || content.identity.contactEmail,
    templateId: templates.privacy.id, templateVersion: templates.privacy.version };
}
type StepProps = { content: SetupContent; onChange: (value: SetupContent) => void; errorFor: (path: string) => string | null };
function IdentityStep({ content, onChange, errorFor }: StepProps) {
  const update = (value: Partial<SetupContent['identity']>) => onChange(selectSetupSection({ ...content, identity: { ...content.identity, ...value } }, 'IDENTITY', true));
  return <div className="form-grid">
    <TextField name="identity.name" label="Nom de l’école" value={content.identity.name} maxLength={150} autoComplete="organization" error={errorFor('identity.name')} onChange={name => update({ name })} />
    <TextField name="identity.contactEmail" label="E-mail de l’école" type="email" value={content.identity.contactEmail} autoComplete="email" error={errorFor('identity.contactEmail')} onChange={contactEmail => update({ contactEmail })} />
    <TextField name="identity.contactPhone" label="Téléphone" type="tel" required={false} value={content.identity.contactPhone ?? ''} autoComplete="tel" error={errorFor('identity.contactPhone')} onChange={contactPhone => update({ contactPhone: contactPhone || null })} />
    <TextField name="identity.timeZone" label="Fuseau horaire" value={content.identity.timeZone} error={errorFor('identity.timeZone')} onChange={timeZone => update({ timeZone })} />
  </div>;
}
function PrivacyStep({ content, templates, onChange, errorFor }: StepProps & { templates: SetupTemplates }) {
  const update = (value: Partial<SetupContent['privacy']>) => onChange(selectSetupSection({ ...content, privacy: { ...content.privacy, ...value } }, 'PRIVACY', true));
  const [replace, setReplace] = useState(false);
  return <div className="section-stack">
    <TextField name="privacy.contactEmail" label="Contact pour les données" type="email" value={content.privacy.contactEmail} error={errorFor('privacy.contactEmail')} onChange={contactEmail => update({ contactEmail })} />
    <TextArea name="privacy.noticeText" label="Information des personnes" value={content.privacy.noticeText} rows={10} maxLength={20_000} error={errorFor('privacy.noticeText')} onChange={noticeText => update({ noticeText })} />
    <TextArea name="privacy.retentionText" label="Conservation des données" value={content.privacy.retentionText} rows={6} maxLength={20_000} error={errorFor('privacy.retentionText')} onChange={retentionText => update({ retentionText })} />
    <button type="button" className="button secondary" onClick={() => setReplace(true)}>Repartir de l’exemple Drivy</button>
    <details className="disclosure"><summary>Aperçu des textes</summary><div className="policy-copy"><h3>Information des personnes</h3><p>{content.privacy.noticeText}</p><h3>Conservation</h3><p>{content.privacy.retentionText}</p><p>{content.privacy.contactEmail}</p></div></details>
    <ConfirmDialog open={replace} busy={false} title="Reprendre l’exemple ?" confirmLabel="Utiliser l’exemple" onCancel={() => setReplace(false)} onConfirm={() => { update(templatePrivacy(templates, content)); setReplace(false); }}><p>Les textes de ce brouillon seront remplacés. Les textes déjà adoptés restent inchangés.</p></ConfirmDialog>
  </div>;
}
function ProfileStep({ content, onChange, errorFor }: StepProps) {
  const update = (fields: SetupContent['profile']['fields']) => onChange(selectSetupSection({ ...content, profile: { ...content.profile, fields, effectiveFrom: null } }, 'PROFILE', true));
  return <div className="section-stack">
    {content.profile.effectiveFrom !== null && <Notice tone="warning" title="Date d’effet à actualiser" actions={<button type="button" className="button secondary" onClick={() => update(content.profile.fields)}>Appliquer dès la confirmation</button>}><p>Les informations demandées prennent désormais effet dès leur confirmation. Ce brouillon conserve encore une ancienne date.</p></Notice>}
    <ProfileFieldsPreview fields={content.profile.fields} />
    <details className="disclosure"><summary>Adapter les informations demandées</summary><div className="setup-profile-fields">{fieldDefaults.map(base => {
      const current = content.profile.fields.find(item => item.field === base.field), fixed = base.field === 'firstName' || base.field === 'lastName';
      return <div className="setup-profile-field" key={base.field}>
        <div className="setup-profile-control"><strong>{fieldLabels[base.field]}</strong>{fixed ? <span>À l’inscription</span> : <SegmentField label={`Demander ${fieldLabels[base.field]!.toLocaleLowerCase('fr')}`} value={!current ? 'NONE' : current.requirement === 'OPTIONAL' ? 'OPTIONAL' : current.stage} options={[
          { value: 'NONE', label: 'Non demandé' }, { value: 'OPTIONAL', label: 'Facultatif' }, { value: 'BEFORE_LESSON', label: 'Avant une leçon' }, { value: 'BEFORE_COURSE', label: 'Avant un cours' },
        ]} onChange={value => { const rest = content.profile.fields.filter(item => item.field !== base.field); update(value === 'NONE' ? rest : [...rest, { ...(current ?? base), requirement: value === 'OPTIONAL' ? 'OPTIONAL' : 'REQUIRED', stage: value as 'OPTIONAL' | 'BEFORE_LESSON' | 'BEFORE_COURSE' }]); }} />}</div>
        {current && <details className="disclosure"><summary>Pourquoi cette information ?</summary><TextArea name={`profile.fields.${content.profile.fields.indexOf(current)}.explanation`} error={errorFor(`profile.fields.${content.profile.fields.indexOf(current)}.explanation`)} label={`Explication · ${fieldLabels[base.field]}`} rows={2} value={current.explanation} onChange={explanation => update(content.profile.fields.map(item => item.field === base.field ? { ...item, explanation } : item))} /></details>}
      </div>;
    })}</div></details>
  </div>;
}
function FormationStep({ content, templates, offerings, initialOfferingId, today, onChange, canWrite, errorFor }: StepProps & { templates: SetupTemplates; offerings: Offering[]; initialOfferingId?: string | undefined; today: string; canWrite: boolean }) {
  const add = (value: SetupFormation) => onChange(selectSetupSection({ ...content, formations: [...content.formations, value] }, 'CATALOGUE', true));
  const update = (value: SetupFormation) => onChange({ ...content, formations: content.formations.map(item => item.id === value.id ? value : item) });
  const [chosen, setChosen] = useState(offerings.some(item => item.id === initialOfferingId) ? initialOfferingId! : '');
  if (!canWrite) return <Notice tone="warning" title="Accès aux tarifs requis"><p>Un administrateur doit vous donner l’autorisation de configurer le catalogue.</p></Notice>;
  return <div className="section-stack">
    <div className="setup-permits">{templates.formations.filter(template => !offerings.some(offer => offer.categoryCode === template.categoryCode)).map(template => <button type="button" className="button secondary" key={template.id} disabled={content.formations.length >= 20 || templateAlreadyAdded(content.formations, template.categoryCode)} onClick={() => add(setupFormation(template, today))}><Symbol kind="plus" bare />{template.label}</button>)}
      <button type="button" className="button quiet" disabled={content.formations.length >= 20} onClick={() => add(setupFormation(null, today))}>Autre formation</button></div>
    {offerings.length > 0 && <details className="disclosure" open={!!initialOfferingId}><summary>Ajouter un tarif à une formation existante</summary><SelectField label="Formation" value={chosen} onChange={setChosen} search options={[{ value: '', label: 'Choisir une formation' }, ...offerings.map(offer => ({ value: offer.id, label: `Permis ${offer.categoryCode} · ${offer.defaultDurationMinutes} min` }))]} />
      <button type="button" className="button secondary" disabled={!chosen || content.formations.length >= 20} onClick={() => { const offer = offerings.find(item => item.id === chosen); if (!offer) return; add({ ...setupFormation(null, today), existingOfferingId: offer.id, useCommonTerms: false, categoryCode: offer.categoryCode, label: `Leçon ${offer.categoryCode}`, durationMinutes: offer.defaultDurationMinutes, competencies: [] }); setChosen(''); }}>Préparer ce tarif</button></details>}
    {content.formations.map((formation, index) => <section className="setup-formation" key={formation.id}>
      <div className="setup-formation-heading"><h3>{formation.label || `Formation ${index + 1}`}</h3><button type="button" className="button quiet" aria-label={`Retirer du brouillon · ${formation.label || `Formation ${index + 1}`}`} onClick={() => onChange({ ...content, formations: content.formations.filter(item => item.id !== formation.id) })}>Retirer du brouillon</button></div>
      <details className="disclosure" open={!formation.templateId && !formation.existingOfferingId}><summary>Nom et catégorie</summary><div className="form-grid"><TextField name={`formations.${index}.categoryCode`} error={errorFor(`formations.${index}.categoryCode`)} label="Permis" value={formation.categoryCode} maxLength={30} disabled={!!formation.existingOfferingId} onChange={categoryCode => update({ ...formation, categoryCode, templateId: null, templateVersion: null })} />
        <TextField name={`formations.${index}.label`} error={errorFor(`formations.${index}.label`)} label="Nom de la formation ou du tarif" value={formation.label} maxLength={200} onChange={label => update({ ...formation, label })} /></div></details>
      {!formation.existingOfferingId && <>
        {formation.templateId && <details className="disclosure"><summary>Référence du programme</summary><p>Proposition Drivy · {formation.templateVersion}</p><p>{templates.formations.find(item => item.id === formation.templateId)?.coverageNote}</p><p>À relire par l’école ; ce programme ne certifie pas les prérequis de l’élève.</p><ul>{formation.sourceUrls.map(url => <li key={url}><a href={url} target="_blank" rel="noreferrer">{new URL(url).hostname}</a></li>)}</ul></details>}
        <details className="disclosure"><summary>Programme · {formation.competencies.length} compétences</summary><div className="section-stack">{formation.competencies.map((competence, position) => <div className="setup-competency" key={competence.key}>
          <TextField name={`formations.${index}.competencies.${position}.label`} error={errorFor(`formations.${index}.competencies.${position}.label`)} label={`Compétence ${position + 1}`} value={competence.label} onChange={label => update({ ...formation, competencies: formation.competencies.map((item, i) => i === position ? { ...item, label } : item) })} />
          <TextArea name={`formations.${index}.competencies.${position}.description`} error={errorFor(`formations.${index}.competencies.${position}.description`)} label="Description" value={competence.description} rows={2} onChange={description => update({ ...formation, competencies: formation.competencies.map((item, i) => i === position ? { ...item, description } : item) })} />
          <button type="button" className="button quiet" aria-label={`Retirer cette compétence · ${competence.label || `Compétence ${position + 1}`}`} onClick={() => update({ ...formation, competencies: formation.competencies.filter((_, i) => i !== position).map((item, sortOrder) => ({ ...item, sortOrder })) })}>Retirer cette compétence</button>
        </div>)}<button type="button" className="button secondary" disabled={formation.competencies.length >= 200} onClick={() => update({ ...formation, competencies: [...formation.competencies, { key: crypto.randomUUID(), label: '', description: '', sortOrder: formation.competencies.length }] })}>Ajouter une compétence</button></div></details>
        <details className="disclosure"><summary>Déroulement de la formation</summary><TextArea name={`formations.${index}.procedureText`} error={errorFor(`formations.${index}.procedureText`)} label="Déroulement" value={formation.procedureText} rows={5} maxLength={4000} onChange={procedureText => update({ ...formation, procedureText })} /></details>
      </>}
    </section>)}
  </div>;
}
function PricingStep({ content, onChange, canWrite, errorFor }: StepProps & { canWrite: boolean }) {
  const update = (value: SetupFormation) => onChange(selectSetupSection({ ...content, formations: content.formations.map(item => item.id === value.id ? value : item) }, 'CATALOGUE', true));
  if (!content.formations.length) return <p>Aucune formation à tarifer dans ce brouillon.</p>;
  return <div className="section-stack">
    {content.formations.map((formation, index) => <section className="setup-formation" key={formation.id}>
      <h3>{formation.label || `Permis ${formation.categoryCode}`}</h3>
      <fieldset className="setup-fields" disabled={!canWrite}>
        <div className="form-grid"><TextField name={`formations.${index}.durationMinutes`} error={errorFor(`formations.${index}.durationMinutes`)} label="Durée (minutes)" value={formation.durationMinutes === null ? '' : String(formation.durationMinutes)} inputMode="numeric" onChange={value => update({ ...formation, durationMinutes: /^\d+$/.test(value) ? Number(value) : null })} />
          <PriceField name={`formations.${index}.priceCents`} error={errorFor(`formations.${index}.priceCents`)} formation={formation} onChange={update} /></div>
        <details className="disclosure"><summary>Date et conditions particulières</summary>
          <TextField name={`formations.${index}.validFrom`} error={errorFor(`formations.${index}.validFrom`)} label="Disponible dès le" type="date" value={formation.validFrom ?? ''} onChange={validFrom => update({ ...formation, validFrom: validFrom || null })} />
          {!formation.existingOfferingId && <CheckField label="Utiliser les règles communes des leçons" checked={formation.useCommonTerms ?? false} onChange={useCommonTerms => update({ ...resolvedSetupFormation(content, formation), useCommonTerms })} />}
          {!formation.useCommonTerms && <>
            {!formation.existingOfferingId && <TextArea name={`formations.${index}.cancellationPolicyText`} error={errorFor(`formations.${index}.cancellationPolicyText`)} label="Conditions d’annulation particulières" value={formation.cancellationPolicyText} rows={3} maxLength={4000} onChange={cancellationPolicyText => update({ ...formation, cancellationPolicyText })} />}
            <TextArea name={`formations.${index}.termsText`} error={errorFor(`formations.${index}.termsText`)} label="Conditions particulières du tarif" value={formation.termsText} rows={4} maxLength={20000} onChange={termsText => update({ ...formation, termsText })} />
          </>}
          {formation.existingOfferingId && formation.cancellationPolicyText.trim() && <Notice tone="warning" title="Annulation déjà définie" actions={<button type="button" className="button secondary" onClick={() => update({ ...formation, cancellationPolicyText: '' })}>Conserver l’annulation de la formation</button>}><p>Le tarif conserve les règles de sa formation.</p></Notice>}
          <CheckField label="Inclure ce tarif dans la confirmation" checked={formation.apply} onChange={apply => update({ ...formation, apply })} />
        </details>
      </fieldset>
    </section>)}
    {content.formations.some(item => item.useCommonTerms) && <CommonLessonRulesStep content={content} onChange={onChange} errorFor={errorFor} />}
  </div>;
}
function CommonLessonRulesStep({ content, onChange, errorFor }: StepProps) {
  const rules: CommonLessonRules = content.commonLessonRules ?? { cancellationHours: null, lateAction: null, paymentText: '', exceptionsText: '' };
  const update = (value: Partial<CommonLessonRules>) => onChange({ ...content, commonLessonRules: { ...rules, ...value } });
  const text = commonLessonTexts(rules, content.identity.contactEmail);
  return <section className="setup-formation section-stack"><h3>Règles communes des leçons</h3>
    <SelectField label="En cas d’annulation" value={rules.lateAction ?? ''} onChange={value => update({ lateAction: value === 'CONTACT' || value === 'NO_FEE' ? value : null })} options={[
      { value: '', label: 'Choisir la règle de l’école' }, { value: 'CONTACT', label: 'Un délai, puis contact avec l’école' }, { value: 'NO_FEE', label: 'Annulation sans frais, sur demande à l’école' },
    ]} />
    {errorFor('commonLessonRules.lateAction') && <p role="alert">{errorFor('commonLessonRules.lateAction')}</p>}
    {rules.lateAction === 'CONTACT' && <TextField name="commonLessonRules.cancellationHours" label="Prévenir combien d’heures avant la leçon ?" inputMode="numeric" value={rules.cancellationHours === null ? '' : String(rules.cancellationHours)} error={errorFor('commonLessonRules.cancellationHours')} onChange={value => update({ cancellationHours: /^\d+$/.test(value) ? Number(value) : null })} />}
    <TextField name="commonLessonRules.paymentText" label="Quand et comment se règle la leçon ?" value={rules.paymentText} maxLength={2000} error={errorFor('commonLessonRules.paymentText')} onChange={paymentText => update({ paymentText })} />
    <details className="disclosure"><summary>Exceptions de l’école</summary><TextArea name="commonLessonRules.exceptionsText" label="Exceptions à ces règles" required={false} value={rules.exceptionsText} maxLength={2000} rows={3} onChange={exceptionsText => update({ exceptionsText })} /></details>
    <details className="disclosure"><summary>Texte préparé pour l’élève</summary><p className="policy-copy">{text.termsText}</p></details>
  </section>;
}
function PriceField({ formation, onChange, name, error }: { formation: SetupFormation; onChange: (value: SetupFormation) => void; name: string; error: string | null }) {
  const [raw, setRaw] = useState(formation.priceCents === null ? '' : String(formation.priceCents / 100));
  return <TextField name={name} label="Prix (CHF)" value={raw} inputMode="decimal" error={raw && setupPrice(raw) === null ? priceAmountProblem : error}
    onChange={value => { setRaw(value); onChange({ ...formation, priceCents: setupPrice(value) }); }} />;
}
export function SetupReview({ preview, onEdit }: { preview: SetupPreview; onEdit: (step: SetupStep, field?: string) => void }) {
  const { content } = preview;
  return <div className="section-stack setup-review">
    {preview.effects.map(effect => <Notice key={effect} tone="warning" title="Conséquence de la modification"><p>{effect}</p></Notice>)}
    {preview.issues.length > 0 && <Notice tone="warning" title="À compléter"><ul className="setup-issues">{preview.issues.map((issue, index) => <li key={`${issue.field}-${index}`}><button type="button" className="text-link" onClick={() => onEdit(issueStep(issue.field), issue.field)}>{issue.message}</button></li>)}</ul></Notice>}
    {content.selectedSections.includes('IDENTITY') && <section><h3>École</h3><Facts items={[["Nom", content.identity.name], ['E-mail', content.identity.contactEmail], ['Téléphone', content.identity.contactPhone ?? 'Non renseigné'], ['Fuseau', content.identity.timeZone]]} /><button type="button" className="button quiet" onClick={() => onEdit('IDENTITY')}>Modifier</button></section>}
    {content.selectedSections.includes('PRIVACY') && <section><h3>Confidentialité</h3><p>{content.privacy.contactEmail}</p><details className="disclosure"><summary>Relire les textes avant confirmation</summary><div className="policy-copy"><h4>Information des personnes</h4><p>{content.privacy.noticeText}</p><h4>Conservation</h4><p>{content.privacy.retentionText}</p></div></details><button type="button" className="button quiet" onClick={() => onEdit('PRIVACY')}>Modifier</button></section>}
    {(preview.activate || content.selectedSections.includes('PROFILE')) && <section><h3>Informations des élèves</h3>{content.selectedSections.includes('PROFILE')
      ? <details className="disclosure"><summary>Relire le formulaire et les explications</summary><ProfileFieldsPreview fields={content.profile.fields} /></details>
      : <p>Préparation reportée à plus tard.</p>}<button type="button" className="button quiet" onClick={() => onEdit('PROFILE')}>Modifier</button></section>}
    {preview.activate && !content.selectedSections.includes('CATALOGUE') && content.formations.length === 0 && <section><h3>Formations et tarifs</h3><p>Préparation reportée à plus tard.</p><button type="button" className="button quiet" onClick={() => onEdit('FORMATIONS')}>Modifier</button></section>}
    {content.formations.map(item => { const formation = resolvedSetupFormation(content, item); return <section key={formation.id}><h3>{formation.label || `Permis ${formation.categoryCode}`}</h3>
      {!formation.apply || !content.selectedSections.includes('CATALOGUE') ? <p>Conservée en brouillon · à terminer plus tard</p> : <>
        <Facts items={[["Permis", formation.categoryCode], ['Durée', `${formation.durationMinutes ?? '—'} min`], ['Prix', formation.priceCents === null ? 'À compléter' : formatCents(formation.priceCents)], ['Disponible dès le', formation.validFrom ? formatCivilDate(formation.validFrom) : 'À compléter']]} />
        {!formation.existingOfferingId && <details className="disclosure"><summary>Programme et déroulement</summary><ul>{formation.competencies.map(item => <li key={item.key}><strong>{item.label}</strong><p>{item.description}</p></li>)}</ul><p className="policy-copy">{formation.procedureText}</p></details>}
        <details className="disclosure"><summary>Annulation et conditions du tarif</summary><h4>Annulation</h4><p className="policy-copy">{formation.existingOfferingId ? 'Le déroulement et les conditions d’annulation de la formation sont conservés.' : formation.cancellationPolicyText}</p><h4>Conditions du tarif</h4><p className="policy-copy">{formation.termsText}</p></details>
      </>}<button type="button" className="button quiet" onClick={() => onEdit('PRICING')}>Modifier</button>
    </section>; })}
  </div>;
}
