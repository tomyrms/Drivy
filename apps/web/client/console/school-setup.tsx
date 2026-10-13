import { useEffect, useRef, useState } from 'react';
import { civilDateIn } from '../agenda-model';
import { createCommand, formatCents } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { readSchool, offeringSchema, readAll, type Offering } from '../school-api';
import { RequestFailure } from '../protocol';
import { CheckField, ConfirmDialog, Facts, Notice, SelectField, Symbol, TextArea, TextField } from '../ui';
import { issueStep, selectSetupSection, setupContentSchema, setupDraftSchema, setupFormation, setupPreviewSchema, setupPrice,
  setupStepLabels, setupSteps, setupTemplatesSchema, type SetupContent, type SetupDraft, type SetupFormation, type SetupPreview, type SetupStep, type SetupTemplates } from '../setup-model';
import { readError, useCommandRunner, useConsole, useLoad } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
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

/** Same persisted editor for the first school setup and later formation preparation. */
export function SchoolSetupGuide({ catalogueOnly = false, onClose }: { catalogueOnly?: boolean; onClose?: () => void }) {
  const { schoolId, school, navigate, drafts, canConfigureCatalog, setNavigationGuard, routeQuery } = useConsole();
  const snapshot = useCommandSnapshot();
  const [document, setDocument] = useState<SetupDraft | null>(null);
  const [content, setContent] = useState<SetupContent | null>(null);
  const [step, setStep] = useState<SetupStep>(catalogueOnly ? 'FORMATIONS' : 'IDENTITY');
  const [dirty, setDirty] = useState(false);
  const [preview, setPreview] = useState<SetupPreview | null>(null);
  const [reviewing, setReviewing] = useState(false);
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
  const runner = useCommandRunner(() => { needsAdoption.current = true; loaded.reload(); });
  const loaded = useLoad(async () => {
    const [draft, templates, offerings] = await Promise.all([
      readSchool(schoolId, 'setup-draft', setupDraftSchema),
      readSchool(schoolId, 'setup-draft/templates', setupTemplatesSchema),
      readAll(schoolId, 'offerings', offeringSchema),
    ]);
    if (draft.schoolId !== schoolId || draft.id !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return { draft, templates, offerings: offerings.items.filter(item => item.enabled) };
  }, [schoolId, snapshot.revision]);
  const steps: readonly SetupStep[] = catalogueOnly ? ['FORMATIONS', 'PRICING', 'REVIEW'] : setupSteps;
  const blocked = runner.busy || !!runner.pending || reviewing;
  const key = `setup-draft:${catalogueOnly ? 'catalogue' : 'initial'}`;

  useEffect(() => {
    if (!loaded.data) return;
    if (document && !needsAdoption.current) return;
    const saved = loaded.data.draft;
    const remembered = needsAdoption.current ? undefined : drafts?.get(key) as StoredDraft | undefined;
    let next = clone(saved.content), nextStep = saved.currentStep, nextDirty = false;
    if (remembered && remembered.version === saved.version && setupContentSchema.safeParse(remembered.content).success) {
      next = remembered.content; nextStep = remembered.step; nextDirty = remembered.dirty;
    } else if (catalogueOnly && (saved.status === 'APPLIED' || saved.content.selectedSections.length === 0)) {
      next = { ...next, selectedSections: ['CATALOGUE'], formations: next.formations.filter(item => !item.apply || !saved.content.selectedSections.includes('CATALOGUE')) }; nextStep = 'FORMATIONS'; nextDirty = true;
    } else if (!catalogueOnly && !next.privacy.noticeText && !next.privacy.templateId) {
      next.privacy = templatePrivacy(loaded.data.templates, next); nextDirty = true;
    }
    needsAdoption.current = false;
    setDocument(saved); setContent(next); setStep(steps.includes(nextStep) ? nextStep : steps[0]!); setDirty(nextDirty);
    setPreview(null); setAcknowledged(false);
  }, [loaded.data]);
  useEffect(() => {
    if (content && document) drafts?.set(key, { version: document.version, content, step, dirty } satisfies StoredDraft);
  }, [content, document, step, dirty, drafts, key]);
  useEffect(() => {
    const preventLoss = (event: BeforeUnloadEvent) => { if (dirty) { event.preventDefault(); event.returnValue = ''; } };
    window.addEventListener('beforeunload', preventLoss);
    return () => window.removeEventListener('beforeunload', preventLoss);
  }, [dirty]);
  useEffect(() => {
    setNavigationGuard?.(proceed => { if (dirtyRef.current) setLeave(() => proceed); else proceed(); });
    return () => setNavigationGuard?.(null);
  }, [setNavigationGuard]);
  useEffect(() => { heading.current?.focus({ preventScroll: true }); setStepsOpen(false); }, [step]);
  useEffect(() => {
    if (!focusField || issueStep(focusField) !== step) return;
    const root = heading.current?.parentElement;
    const path = focusField.replace(/^content\./, '');
    const target = [...(root?.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('input[name],textarea[name]') ?? [])]
      .find(input => input.name === path || input.name.startsWith(`${path}.`));
    if (target) {
      for (let parent = target.parentElement; parent && parent !== root; parent = parent.parentElement) if (parent instanceof HTMLDetailsElement) parent.open = true;
      target.focus(); target.scrollIntoView({ block: 'center' });
    }
    setFocusField(null);
  }, [step, focusField]);
  const update = (next: SetupContent) => { setContent(next); setDirty(true); setPreview(null); setAcknowledged(false); runner.clearOutcome(); };

  async function refreshReview(saved: SetupDraft) {
    setReviewing(true); setReadFailure(null); setAcknowledged(false);
    try {
      const result = await readSchool(schoolId, 'setup-draft/preview', setupPreviewSchema, { activate: String(school.status === 'DRAFT') });
      if (result.schoolId !== schoolId || result.draftVersion !== saved.version) throw new RequestFailure('VERSION_CONFLICT', 412);
      setPreview(result);
    } catch (error) { setReadFailure(readError(error)); } finally { setReviewing(false); }
  }
  async function save(nextStep: SetupStep, value = content, exit = false, afterSave?: () => void) {
    if (!value || !document || blocked) return;
    setReadFailure(null); setPreview(null); setAcknowledged(false);
    const result = await runner.run(createCommand({ schoolId, kind: 'saveSetupDraft', path: 'setup-draft',
      ifMatch: document.version, resourceVersion: document.version, body: { currentStep: nextStep, content: value } }), 'La préparation est enregistrée.');
    if (result.status !== 'confirmed') return;
    setDirty(false); dirtyRef.current = false; needsAdoption.current = false;
    try {
      const saved = await readSchool(schoolId, 'setup-draft', setupDraftSchema);
      if (saved.schoolId !== schoolId || saved.version <= document.version) throw new RequestFailure('INVALID_RESPONSE');
      setDocument(saved); setContent(clone(saved.content)); setStep(nextStep);
      drafts?.delete(key);
      if (afterSave) { setLeave(null); afterSave(); }
      else if (exit) { if (onClose) onClose(); else navigate('configuration'); }
      else if (nextStep === 'REVIEW') await refreshReview(saved);
    } catch (error) { needsAdoption.current = true; setReadFailure(readError(error)); loaded.reload(); }
  }
  async function finish() {
    if (!preview?.ready || !acknowledged || !document || blocked || dirty || preview.draftVersion !== document.version) return;
    const result = await runner.run(createCommand({ schoolId, kind: 'applySetupDraft', path: 'setup-draft/complete', ifMatch: document.version,
      resourceVersion: document.version, body: { expectedSchoolVersion: preview.schoolVersion, expectedConfigurationVersion: preview.configurationVersion,
        reviewDigest: preview.reviewDigest, reviewAcknowledged: true, activate: preview.activate } }), preview.activate ? 'Votre école est activée.' : 'La préparation est appliquée.');
    if (result.status === 'confirmed') { setDirty(false); dirtyRef.current = false; drafts?.delete(key); navigate(catalogueOnly ? 'formations' : 'agenda'); }
  }
  function skip() {
    if (!content) return;
    if (step === 'PROFILE') void save('FORMATIONS', selectSetupSection(content, 'PROFILE', false));
    if (step === 'FORMATIONS') void save('REVIEW', selectSetupSection({ ...content, formations: content.formations.map(item => ({ ...item, apply: false })) }, 'CATALOGUE', false));
    if (step === 'PRICING') void save('REVIEW', { ...content, formations: content.formations.map(item => ({ ...item, apply: false })) });
  }
  function jump(target: SetupStep, field?: string) {
    if (blocked || !steps.includes(target)) return;
    setFocusField(field ?? null);
    if (dirty) void save(target); else { setStep(target); if (target === 'REVIEW' && document) void refreshReview(document); }
  }
  const nextStep = steps[Math.min(steps.indexOf(step) + 1, steps.length - 1)]!;
  return <div className="section-stack school-setup">
    <SectionHeading title={catalogueOnly ? 'Préparer une formation' : 'Préparer votre école'} />
    <OutcomeNotice outcome={runner.outcome?.tone === 'success' ? null : runner.outcome} actions={runner.outcome?.code === 'VERSION_CONFLICT'
      ? <button type="button" className="button secondary" onClick={() => setDiscard(true)}>Relire la version enregistrée</button> : undefined} />
    {readFailure && <Notice tone="error" title="Vérification impossible" actions={<button className="button secondary" type="button" onClick={() => document && void refreshReview(document)}>Réessayer</button>}><p>{readFailure}</p></Notice>}
    {runner.blockedReason && <Notice tone="warning" title="Demande à vérifier"><p>{runner.blockedReason}</p></Notice>}
    <LoadState loaded={loaded} label="Lecture de votre préparation…">{data => content && document && <>
      <div className="setup-progress-mobile"><button type="button" className="button quiet" aria-expanded={stepsOpen} aria-controls="setup-progress" onClick={() => setStepsOpen(!stepsOpen)}>Étape {steps.indexOf(step) + 1} sur {steps.length}<Symbol kind="chevron" bare /></button></div>
      <div className="setup-layout">
        <nav id="setup-progress" className={`setup-progress${stepsOpen ? ' is-open' : ''}`} aria-label="Étapes de préparation"><ol>{steps.map((item, index) => <li key={item}>
          <button type="button" aria-current={item === step ? 'step' : undefined} disabled={blocked} onClick={() => jump(item)}><span aria-hidden="true">{index + 1}</span>{setupStepLabels[item]}</button>
        </li>)}</ol></nav>
        <div className="setup-workspace">
          <h2 ref={heading} tabIndex={-1} className="setup-title">{catalogueOnly && step === 'REVIEW' ? 'Vérifier la formation' : setupStepLabels[step]}</h2>
          <form onSubmit={event => { event.preventDefault(); if (step === 'REVIEW') void finish(); else void save(nextStep); }}>
            <fieldset className="setup-fields" disabled={blocked}>
              {step === 'IDENTITY' && <IdentityStep content={content} onChange={update} />}
              {step === 'PRIVACY' && <PrivacyStep content={content} templates={data.templates} onChange={update} />}
              {step === 'PROFILE' && <ProfileStep content={content} onChange={update} />}
              {step === 'FORMATIONS' && <FormationStep content={content} templates={data.templates} offerings={data.offerings} initialOfferingId={routeQuery?.selection} today={civilDateIn(school.timeZone)} onChange={update} canWrite={canConfigureCatalog} />}
              {step === 'PRICING' && <PricingStep content={content} templates={data.templates} onChange={update} canWrite={canConfigureCatalog} />}
              {step === 'REVIEW' && <>
                {!preview && <button type="button" className="button secondary" onClick={() => dirty ? void save('REVIEW') : void refreshReview(document)}>Vérifier la préparation</button>}
                {preview && <SetupReview preview={preview} onEdit={jump} />}
                {preview?.ready && <CheckField label={preview.activate ? 'J’ai relu ces choix et ces textes. Je les adopte pour mon école et confirme son activation.' : 'J’ai relu les formations et tarifs sélectionnés. Je confirme leur mise à disposition.'} checked={acknowledged} onChange={setAcknowledged} />}
              </>}
            </fieldset>
            <div className="setup-actions">
              <span className="setup-saved" role="status">{runner.busy ? 'Enregistrement…' : dirty ? 'Modifications non enregistrées' : 'Enregistré'}</span>
              <div className="button-row">
                {steps.indexOf(step) > 0 && <button type="button" className="button quiet" disabled={blocked} onClick={() => jump(steps[steps.indexOf(step) - 1]!)}>Retour</button>}
                {(['PROFILE', 'FORMATIONS', 'PRICING'] as SetupStep[]).includes(step) && !catalogueOnly && <button type="button" className="button quiet" disabled={blocked} onClick={skip}>Plus tard</button>}
                <button type="button" className="button secondary" disabled={blocked} onClick={() => void save(step, content, true)}>Enregistrer et quitter</button>
                <button type="submit" className="button primary" disabled={blocked || (step === 'REVIEW' && (!preview?.ready || !acknowledged || dirty))}>
                  {step === 'REVIEW' ? preview?.activate ? 'Adopter les textes et activer l’école' : 'Confirmer la préparation' : 'Enregistrer et continuer'}
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </>}</LoadState>
    <ConfirmDialog open={discard} busy={blocked} title="Relire la préparation enregistrée ?" confirmLabel="Abandonner ma saisie et relire" onCancel={() => setDiscard(false)} onConfirm={() => {
      setDiscard(false); setDirty(false); drafts?.delete(key); needsAdoption.current = true; loaded.reload();
    }}><p>Votre saisie non enregistrée sera remplacée par la version actuellement conservée par l’école.</p></ConfirmDialog>
    <ConfirmDialog open={leave !== null} busy={blocked} title="Enregistrer avant de quitter ?" confirmLabel="Enregistrer et quitter" onCancel={() => setLeave(null)} onConfirm={() => { if (leave) void save(step, content, false, leave); }}>
      <p>Les dernières modifications ne sont pas encore enregistrées.</p>
      <OutcomeNotice outcome={runner.outcome} />
      <button type="button" className="button quiet" disabled={blocked} onClick={() => { const proceed = leave; setLeave(null); dirtyRef.current = false; setDirty(false); drafts?.delete(key); proceed?.(); }}>Quitter sans enregistrer</button>
    </ConfirmDialog>
  </div>;
}

function templatePrivacy(templates: SetupTemplates, content: SetupContent): SetupContent['privacy'] {
  return { noticeText: templates.privacy.noticeText.replaceAll('[Nom de l’école]', content.identity.name).replaceAll('[contact données]', content.privacy.contactEmail || content.identity.contactEmail),
    retentionText: templates.privacy.retentionText, contactEmail: content.privacy.contactEmail || content.identity.contactEmail,
    templateId: templates.privacy.id, templateVersion: templates.privacy.version };
}
type StepProps = { content: SetupContent; onChange: (value: SetupContent) => void };
function IdentityStep({ content, onChange }: StepProps) {
  const update = (value: Partial<SetupContent['identity']>) => onChange(selectSetupSection({ ...content, identity: { ...content.identity, ...value } }, 'IDENTITY', true));
  return <div className="form-grid">
    <TextField name="identity.name" label="Nom de l’école" value={content.identity.name} maxLength={150} autoComplete="organization" onChange={name => update({ name })} />
    <TextField name="identity.contactEmail" label="E-mail de l’école" type="email" value={content.identity.contactEmail} autoComplete="email" onChange={contactEmail => update({ contactEmail })} />
    <TextField name="identity.contactPhone" label="Téléphone" type="tel" required={false} value={content.identity.contactPhone ?? ''} autoComplete="tel" onChange={contactPhone => update({ contactPhone: contactPhone || null })} />
    <TextField name="identity.timeZone" label="Fuseau horaire" value={content.identity.timeZone} onChange={timeZone => update({ timeZone })} />
  </div>;
}
function PrivacyStep({ content, templates, onChange }: StepProps & { templates: SetupTemplates }) {
  const update = (value: Partial<SetupContent['privacy']>) => onChange(selectSetupSection({ ...content, privacy: { ...content.privacy, ...value } }, 'PRIVACY', true));
  const [replace, setReplace] = useState(false);
  return <div className="section-stack">
    <TextField name="privacy.contactEmail" label="Contact pour les données" type="email" value={content.privacy.contactEmail} onChange={contactEmail => update({ contactEmail })} />
    <TextArea name="privacy.noticeText" label="Information des personnes" value={content.privacy.noticeText} rows={10} maxLength={20_000} onChange={noticeText => update({ noticeText })} />
    <TextArea name="privacy.retentionText" label="Conservation des données" value={content.privacy.retentionText} rows={6} maxLength={20_000} onChange={retentionText => update({ retentionText })} />
    <button type="button" className="button secondary" onClick={() => setReplace(true)}>Repartir de l’exemple Drivy</button>
    <details className="disclosure"><summary>Aperçu des textes</summary><div className="policy-copy"><h3>Information des personnes</h3><p>{content.privacy.noticeText}</p><h3>Conservation</h3><p>{content.privacy.retentionText}</p><p>{content.privacy.contactEmail}</p></div></details>
    <ConfirmDialog open={replace} busy={false} title="Reprendre l’exemple ?" confirmLabel="Utiliser l’exemple" onCancel={() => setReplace(false)} onConfirm={() => { update(templatePrivacy(templates, content)); setReplace(false); }}><p>Les textes de ce brouillon seront remplacés. Les textes déjà adoptés restent inchangés.</p></ConfirmDialog>
  </div>;
}
function ProfileStep({ content, onChange }: StepProps) {
  const update = (fields: SetupContent['profile']['fields']) => onChange(selectSetupSection({ ...content, profile: { ...content.profile, fields } }, 'PROFILE', true));
  return <div className="section-stack">
    <div className="setup-profile-fields">{fieldDefaults.map(base => {
      const current = content.profile.fields.find(item => item.field === base.field), fixed = base.field === 'firstName' || base.field === 'lastName';
      return <div className="setup-profile-field" key={base.field}>
        <div className="setup-profile-control"><strong>{fieldLabels[base.field]}</strong>{fixed ? <span>À l’inscription</span> : <SelectField label={`Demander ${fieldLabels[base.field]!.toLocaleLowerCase('fr')}`} value={!current ? 'NONE' : current.requirement === 'OPTIONAL' ? 'OPTIONAL' : current.stage} options={[
          { value: 'NONE', label: 'Non demandé' }, { value: 'OPTIONAL', label: 'Facultatif' }, { value: 'JOIN', label: 'À l’inscription' }, { value: 'BEFORE_LESSON', label: 'Avant une leçon' },
        ]} onChange={value => { const rest = content.profile.fields.filter(item => item.field !== base.field); update(value === 'NONE' ? rest : [...rest, { ...(current ?? base), requirement: value === 'OPTIONAL' ? 'OPTIONAL' : 'REQUIRED', stage: value as 'OPTIONAL' | 'JOIN' | 'BEFORE_LESSON' }]); }} />}</div>
        {current && <details className="disclosure"><summary>Pourquoi cette information ?</summary><TextArea name={`profile.fields.${base.field}.explanation`} label={`Explication · ${fieldLabels[base.field]}`} rows={2} value={current.explanation} onChange={explanation => update(content.profile.fields.map(item => item.field === base.field ? { ...item, explanation } : item))} /></details>}
      </div>;
    })}</div>
    <details className="disclosure"><summary>Aperçu pour l’élève</summary><ul className="plain-list">{content.profile.fields.map(field => <li key={field.field}><span>{fieldLabels[field.field]}</span><span className="row-meta">{field.requirement === 'OPTIONAL' ? 'Facultatif' : field.stage === 'JOIN' ? 'À l’inscription' : 'Avant une leçon'}</span></li>)}</ul></details>
  </div>;
}
function FormationStep({ content, templates, offerings, initialOfferingId, today, onChange, canWrite }: StepProps & { templates: SetupTemplates; offerings: Offering[]; initialOfferingId?: string | undefined; today: string; canWrite: boolean }) {
  const add = (value: SetupFormation) => onChange(selectSetupSection({ ...content, formations: [...content.formations, value] }, 'CATALOGUE', true));
  const update = (value: SetupFormation) => onChange({ ...content, formations: content.formations.map(item => item.id === value.id ? value : item) });
  const [chosen, setChosen] = useState(offerings.some(item => item.id === initialOfferingId) ? initialOfferingId! : '');
  if (!canWrite) return <Notice tone="warning" title="Accès aux tarifs requis"><p>Un administrateur doit vous donner l’autorisation de configurer le catalogue.</p></Notice>;
  return <div className="section-stack">
    <div className="setup-permits">{templates.formations.map(template => <button type="button" className="button secondary" key={template.id} disabled={content.formations.length >= 12} onClick={() => add(setupFormation(template, today))}><Symbol kind="plus" bare />{template.label}</button>)}
      <button type="button" className="button quiet" disabled={content.formations.length >= 12} onClick={() => add(setupFormation(null, today))}>Autre formation</button></div>
    {offerings.length > 0 && <details className="disclosure" open={!!initialOfferingId}><summary>Ajouter un tarif à une formation existante</summary><SelectField label="Formation" value={chosen} onChange={setChosen} options={[{ value: '', label: 'Choisir une formation' }, ...offerings.map(offer => ({ value: offer.id, label: `Permis ${offer.categoryCode} · ${offer.defaultDurationMinutes} min` }))]} />
      <button type="button" className="button secondary" disabled={!chosen || content.formations.length >= 12} onClick={() => { const offer = offerings.find(item => item.id === chosen); if (!offer) return; add({ ...setupFormation(null, today), existingOfferingId: offer.id, categoryCode: offer.categoryCode, label: `Leçon ${offer.categoryCode}`, durationMinutes: offer.defaultDurationMinutes, competencies: [] }); setChosen(''); }}>Préparer ce tarif</button></details>}
    {content.formations.map((formation, index) => <section className="setup-formation" key={formation.id}>
      <div className="setup-formation-heading"><h3>{formation.label || `Formation ${index + 1}`}</h3><button type="button" className="button quiet" onClick={() => onChange({ ...content, formations: content.formations.filter(item => item.id !== formation.id) })}>Retirer du brouillon</button></div>
      <div className="form-grid"><TextField name={`formations.${index}.categoryCode`} label="Permis" value={formation.categoryCode} maxLength={30} disabled={!!formation.existingOfferingId} onChange={categoryCode => update({ ...formation, categoryCode, templateId: null, templateVersion: null })} />
        <TextField name={`formations.${index}.label`} label="Nom de la formation ou du tarif" value={formation.label} maxLength={200} onChange={label => update({ ...formation, label })} /></div>
      {!formation.existingOfferingId && <>
        <details className="disclosure"><summary>Programme · {formation.competencies.length} compétences</summary><div className="section-stack">{formation.competencies.map((competence, position) => <div className="setup-competency" key={competence.key}>
          <TextField name={`formations.${index}.competencies.${position}.label`} label={`Compétence ${position + 1}`} value={competence.label} onChange={label => update({ ...formation, competencies: formation.competencies.map((item, i) => i === position ? { ...item, label } : item) })} />
          <TextArea name={`formations.${index}.competencies.${position}.description`} label="Description" value={competence.description} rows={2} onChange={description => update({ ...formation, competencies: formation.competencies.map((item, i) => i === position ? { ...item, description } : item) })} />
          <button type="button" className="button quiet" onClick={() => update({ ...formation, competencies: formation.competencies.filter((_, i) => i !== position).map((item, sortOrder) => ({ ...item, sortOrder })) })}>Retirer cette compétence</button>
        </div>)}<button type="button" className="button secondary" disabled={formation.competencies.length >= 200} onClick={() => update({ ...formation, competencies: [...formation.competencies, { key: crypto.randomUUID(), label: '', description: '', sortOrder: formation.competencies.length }] })}>Ajouter une compétence</button></div></details>
        <details className="disclosure"><summary>Déroulement de la formation</summary><TextArea name={`formations.${index}.procedureText`} label="Déroulement" value={formation.procedureText} rows={5} maxLength={4000} onChange={procedureText => update({ ...formation, procedureText })} /></details>
      </>}
    </section>)}
  </div>;
}
function PricingStep({ content, templates, onChange, canWrite }: StepProps & { canWrite: boolean; templates: SetupTemplates }) {
  const update = (value: SetupFormation) => onChange(selectSetupSection({ ...content, formations: content.formations.map(item => item.id === value.id ? value : item) }, 'CATALOGUE', true));
  const [copyFrom, setCopyFrom] = useState<string | null>(null);
  const [exampleFor, setExampleFor] = useState<string | null>(null);
  if (!content.formations.length) return <p>Aucune formation à tarifer dans ce brouillon.</p>;
  return <div className="section-stack">{content.formations.map((formation, index) => <section className="setup-formation" key={formation.id}>
    <h3>{formation.label || `Permis ${formation.categoryCode}`}</h3>
    <fieldset className="setup-fields" disabled={!canWrite}>
      <div className="form-grid"><TextField name={`formations.${index}.durationMinutes`} label="Durée (minutes)" value={formation.durationMinutes === null ? '' : String(formation.durationMinutes)} inputMode="numeric" onChange={value => update({ ...formation, durationMinutes: /^\d+$/.test(value) ? Number(value) : null })} />
        <PriceField name={`formations.${index}.priceCents`} formation={formation} onChange={update} />
        <TextField name={`formations.${index}.validFrom`} label="Disponible dès le" type="date" value={formation.validFrom ?? ''} onChange={validFrom => update({ ...formation, validFrom: validFrom || null })} /></div>
      <TextArea name={`formations.${index}.cancellationPolicyText`} label="Conditions d’annulation" value={formation.cancellationPolicyText} rows={3} maxLength={4000} onChange={cancellationPolicyText => update({ ...formation, cancellationPolicyText })} />
      <TextArea name={`formations.${index}.termsText`} label="Conditions du tarif" value={formation.termsText} rows={4} maxLength={20000} onChange={termsText => update({ ...formation, termsText })} />
      {templates.commercial && <button type="button" className="button secondary" onClick={() => setExampleFor(formation.id)}>Insérer un exemple de conditions</button>}
      {index === 0 && content.formations.length > 1 && <button type="button" className="button secondary" onClick={() => setCopyFrom(formation.id)}>Utiliser ces conditions pour les autres formations</button>}
      <CheckField label="Proposer cette formation et ce tarif après confirmation" checked={formation.apply} onChange={apply => update({ ...formation, apply })} />
    </fieldset>
  </section>)}
    <ConfirmDialog open={exampleFor !== null} busy={false} title="Utiliser cet exemple ?" confirmLabel="Insérer dans le brouillon" onCancel={() => setExampleFor(null)} onConfirm={() => {
      const formation = content.formations.find(item => item.id === exampleFor); if (formation && templates.commercial) update({ ...formation, termsText: templates.commercial.termsText, cancellationPolicyText: templates.commercial.cancellationPolicyText }); setExampleFor(null);
    }}><p>Ces textes remplaceront les conditions de cette formation dans le brouillon. Complétez les passages entre crochets avant de confirmer.</p><h3>Annulation</h3><p className="policy-copy">{templates.commercial?.cancellationPolicyText}</p><h3>Tarif</h3><p className="policy-copy">{templates.commercial?.termsText}</p></ConfirmDialog>
    <ConfirmDialog open={copyFrom !== null} busy={false} title="Reprendre ces conditions ?" confirmLabel="Appliquer aux autres formations" onCancel={() => setCopyFrom(null)} onConfirm={() => {
      const source = content.formations.find(item => item.id === copyFrom); if (source) onChange({ ...content, formations: content.formations.map(item => ({ ...item, termsText: source.termsText, cancellationPolicyText: source.cancellationPolicyText })) }); setCopyFrom(null);
    }}><p>Les conditions des autres formations de ce brouillon seront remplacées.</p></ConfirmDialog>
  </div>;
}
function PriceField({ formation, onChange, name }: { formation: SetupFormation; onChange: (value: SetupFormation) => void; name: string }) {
  const [raw, setRaw] = useState(formation.priceCents === null ? '' : String(formation.priceCents / 100));
  return <TextField name={name} label="Prix (CHF)" value={raw} inputMode="decimal" error={raw && setupPrice(raw) === null ? 'Indiquez un montant avec deux décimales au maximum.' : null}
    onChange={value => { setRaw(value); onChange({ ...formation, priceCents: setupPrice(value) }); }} />;
}
export function SetupReview({ preview, onEdit }: { preview: SetupPreview; onEdit: (step: SetupStep, field?: string) => void }) {
  const { content } = preview;
  return <div className="section-stack">
    {preview.effects.map(effect => <Notice key={effect} tone="warning" title="Conséquence de la modification"><p>{effect}</p></Notice>)}
    {preview.issues.length > 0 && <Notice tone="warning" title="À compléter"><ul className="setup-issues">{preview.issues.map((issue, index) => <li key={`${issue.field}-${index}`}><button type="button" className="text-link" onClick={() => onEdit(issueStep(issue.field), issue.field)}>{issue.message}</button></li>)}</ul></Notice>}
    {content.selectedSections.includes('IDENTITY') && <section><h3>École</h3><Facts items={[["Nom", content.identity.name], ['E-mail', content.identity.contactEmail], ['Téléphone', content.identity.contactPhone ?? 'Non renseigné'], ['Fuseau', content.identity.timeZone]]} /><button type="button" className="button quiet" onClick={() => onEdit('IDENTITY')}>Modifier</button></section>}
    {content.selectedSections.includes('PRIVACY') && <section><h3>Confidentialité</h3><div className="policy-copy"><h4>Information des personnes</h4><p>{content.privacy.noticeText}</p><h4>Conservation</h4><p>{content.privacy.retentionText}</p><p>{content.privacy.contactEmail}</p></div><button type="button" className="button quiet" onClick={() => onEdit('PRIVACY')}>Modifier</button></section>}
    {content.selectedSections.includes('PROFILE') && <section><h3>Informations des élèves</h3><ul className="plain-list">{content.profile.fields.map(field => <li key={field.field}><span>{fieldLabels[field.field]}</span><span>{field.requirement === 'OPTIONAL' ? 'Facultatif' : field.stage === 'JOIN' ? 'À l’inscription' : 'Avant une leçon'}</span></li>)}</ul><button type="button" className="button quiet" onClick={() => onEdit('PROFILE')}>Modifier</button></section>}
    {content.formations.map(formation => <section key={formation.id}><h3>{formation.label || `Permis ${formation.categoryCode}`}</h3>
      {!formation.apply || !content.selectedSections.includes('CATALOGUE') ? <p>Conservée en brouillon · à terminer plus tard</p> : <>
        <Facts items={[["Permis", formation.categoryCode], ['Durée', `${formation.durationMinutes ?? '—'} min`], ['Prix', formation.priceCents === null ? 'À compléter' : formatCents(formation.priceCents)], ['Disponible dès le', formation.validFrom ?? 'À compléter']]} />
        {!formation.existingOfferingId && <details className="disclosure"><summary>Programme et déroulement</summary><ul>{formation.competencies.map(item => <li key={item.key}><strong>{item.label}</strong><p>{item.description}</p></li>)}</ul><p className="policy-copy">{formation.procedureText}</p></details>}
        <h4>Annulation</h4><p className="policy-copy">{formation.cancellationPolicyText}</p><h4>Conditions du tarif</h4><p className="policy-copy">{formation.termsText}</p>
      </>}<button type="button" className="button quiet" onClick={() => onEdit('PRICING')}>Modifier</button>
    </section>)}
  </div>;
}
