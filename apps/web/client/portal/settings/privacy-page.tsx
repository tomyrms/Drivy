import { useEffect, useId, useMemo, useRef, useState, type ReactNode } from 'react';
import { ArrowRight, ChevronRight, CircleCheck, CircleSlash, Pencil } from 'lucide-react';
import { characters, createCommand, filled, isEmail, profilePolicyProblem, type ProfileField } from '../../command-core';
import { useCommandSnapshot, type SubmitResult } from '../../command-store';
import {
  POLICY_TEXT_MINIMUM, catalogPolicySchema, dataPolicySchema, policyImpactSchema, profilePolicySchema, readAll, readSchool, termsSchema, textProposalsSchema,
  type ProfilePolicy, type TextProposals,
} from '../../school-api';
import { request, sessionSchema } from '../../protocol';
import { setupProfileRequirement } from '../../setup-model';
import { readError, useCommandRunner, useConsole, useDraft, useLoad, useUnsavedChanges } from '../../console/context';
import { choiceLabels, choiceOf, editableFields, impactSentences, initialDrafts, rulesOf, sameProfileRules, type Choice, type FieldDraft } from '../../console/privacy-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Label } from '../../components/ui/label';
import { RadioGroup, RadioGroupItem } from '../../components/ui/radio-group';
import { Skeleton } from '../../components/ui/skeleton';
import { Textarea } from '../../components/ui/textarea';
import { CommandFeedback, ReadFeedback } from '../components/feedback';
import './settings.css';

type PolicyText = { noticeText: string; retentionText: string; contactEmail: string };
const policyTextProblem = (value: string) => characters(value.trim()) < POLICY_TEXT_MINIMUM
  ? `Écrivez au moins ${POLICY_TEXT_MINIMUM} caractères.` : filled(value, 20_000) ? null : '20 000 caractères au plus.';
const fieldLabels: Record<ProfileField, string> = {
  firstName: 'Prénom', lastName: 'Nom', birthDate: 'Date de naissance', postalAddress: 'Adresse postale',
  contactEmail: 'E-mail', contactPhone: 'Téléphone', profilePhotoDocumentId: 'Photo de profil',
};
const inputTypes: Record<string, string> = { contactPhone: 'tel', contactEmail: 'email', birthDate: 'date' };
const dateTime = (value: string, timeZone: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'long', timeStyle: 'short', timeZone }).format(new Date(value));

/** Review before an irreversible-looking command: content, consequences, explicit acknowledgement. Stays open on refusal. */
function Review({ open, title, confirmLabel, acknowledgement, busy, blocked, onCancel, onConfirm, children }: {
  open: boolean; title: string; confirmLabel: string; acknowledgement?: string; busy: boolean; blocked?: string | null;
  onCancel: () => void; onConfirm: () => void; children: ReactNode;
}) {
  const id = useId();
  const [acknowledged, setAcknowledged] = useState(false);
  useEffect(() => { if (open) setAcknowledged(false); }, [open]);
  return <Dialog open={open} onOpenChange={(next, details) => { if (busy) details.cancel(); else if (!next) onCancel(); }}>
    <DialogContent showCloseButton={!busy} className="settings-review">
      <DialogHeader><DialogTitle>{title}</DialogTitle></DialogHeader>
      <div className="settings-review-body">{children}</div>
      {acknowledgement && <div className="settings-ack"><Checkbox id={`${id}-ack`} checked={acknowledged} onCheckedChange={value => setAcknowledged(value === true)} disabled={busy} />
        <Label htmlFor={`${id}-ack`}>{acknowledgement}</Label></div>}
      {blocked && <p className="settings-muted" role="status">{blocked}</p>}
      <DialogFooter><Button variant="outline" disabled={busy} onClick={onCancel}>Retour</Button>
        <Button disabled={busy || !!blocked || (!!acknowledgement && !acknowledged)} aria-busy={busy} onClick={onConfirm}>{busy ? 'Confirmation…' : confirmLabel}</Button></DialogFooter>
    </DialogContent>
  </Dialog>;
}

/** The school enables GPS trips; each lesson still needs the learner's agreement and device permission. Identity is confirmed first. */
function GpsCard() {
  const { schoolId, school, reloadSchool, confirmIdentity, login } = useConsole();
  const [review, setReview] = useState<{ enabled: boolean; version: number } | null>(null);
  const runner = useCommandRunner(() => setReview(null));
  const [checking, setChecking] = useState(false), [identityError, setIdentityError] = useState<string | null>(null);
  const working = useRef(false), mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const enabled = school.modules.gpsEnabled;
  async function confirm() {
    if (!review || runner.busy || runner.pending || working.current) return;
    working.current = true; setChecking(true); setIdentityError(null);
    try {
      const session = await request('session', sessionSchema);
      if (!mounted.current) return;
      if (!session.authenticated) { login(); return; }
      if (session.reauthenticationRequired) {
        if (confirmIdentity) { if (await confirmIdentity() && mounted.current) runner.clearOutcome(); } else login({ reauthenticate: true });
        return; // Authentication alone never changes the reviewed setting.
      }
      const result = await runner.run(createCommand({ schoolId, kind: 'updateModules', path: 'modules', ifMatch: review.version, resourceVersion: review.version,
        body: { gpsEnabled: review.enabled } }), review.enabled ? 'Les trajets GPS sont activés pour l’école.' : 'Les trajets GPS sont désactivés pour l’école.');
      if (!mounted.current) return;
      if (result.status !== 'rejected') setReview(null);
      else if (result.code === 'REAUTH_REQUIRED' && confirmIdentity && await confirmIdentity() && mounted.current) runner.clearOutcome();
    } catch (error) { if (mounted.current) setIdentityError(readError(error)); }
    finally { working.current = false; if (mounted.current) setChecking(false); }
  }
  const feedback = <>
    {runner.outcome?.code === 'REAUTH_REQUIRED' ? <Alert><AlertTitle>Confirmez votre identité pour continuer.</AlertTitle></Alert> : <CommandFeedback runner={runner} />}
    {runner.outcome?.code === 'VERSION_CONFLICT' && <Button variant="outline" onClick={() => { setReview(null); runner.clearOutcome(); void reloadSchool(); }}>Recharger le réglage</Button>}
  </>;
  return <section className="settings-card" aria-labelledby="gps-title">
    <header className="settings-card-heading"><h2 id="gps-title">Trajets GPS</h2>
      <Button id="school-gps" variant="outline" disabled={runner.busy || checking || !!runner.pending}
        onClick={() => { runner.clearOutcome(); setIdentityError(null); setReview({ enabled: !enabled, version: school.version }); }}>{enabled ? 'Désactiver' : 'Activer'}</Button></header>
    <p className="settings-state">{enabled ? <CircleCheck aria-hidden="true" /> : <CircleSlash aria-hidden="true" />}{enabled ? 'Enregistrement autorisé par l’école' : 'Enregistrement désactivé par l’école'}</p>
    {!review && feedback}
    <Review open={review !== null} busy={runner.busy || checking} blocked={runner.blockedReason} onCancel={() => setReview(null)} onConfirm={() => void confirm()}
      title={review?.enabled ? 'Activer les trajets GPS' : 'Désactiver les trajets GPS'} confirmLabel={review?.enabled ? 'Activer' : 'Désactiver'}>
      {feedback}
      {identityError && <Alert variant="destructive"><AlertTitle>Vérification impossible</AlertTitle><AlertDescription>{identityError}</AlertDescription></Alert>}
      <p>{review?.enabled ? 'Les moniteurs pourront enregistrer les trajets dans l’app, avec l’accord de l’élève et la localisation autorisée sur leur appareil.'
        : 'Les trajets en cours seront arrêtés, dès la reconnexion pour un appareil hors ligne. Les leçons pourront continuer sans GPS.'}</p>
    </Review>
  </section>;
}

function PolicyTextsCard({ proposals, fieldsPublished, onAdopted }: { proposals: TextProposals | null; fieldsPublished: boolean; onAdopted: () => void }) {
  const { schoolId, school, routeQuery } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => { setEditing(false); onAdopted(); });
  const loaded = useLoad(() => readSchool(schoolId, 'data-policy', dataPolicySchema), [schoolId, revision, school.version]);
  const policy = loaded.data ?? null;
  const adopted = policy?.status === 'APPROVED';
  // Never adopted: the form starts from the texts Drivy proposes, to read and adapt before adoption.
  const baseline = policy ? adopted ? { noticeText: policy.noticeText, retentionText: policy.retentionText, contactEmail: policy.contactEmail ?? school.contactEmail }
    : proposals ? { ...proposals.dataPolicy } : null : null;
  const texts = useDraft<PolicyText>(baseline);
  const [editing, setEditing] = useState(false);
  useEffect(() => { if (routeQuery?.focus?.startsWith('privacy-')) setEditing(true); }, [routeQuery?.focus]);
  const [reviewing, setReviewing] = useState(false);
  const replacesTexts = reviewing && adopted;
  const impact = useLoad(async () => replacesTexts ? readSchool(schoolId, 'data-policy/impact', policyImpactSchema) : null, [replacesTexts, schoolId], `${schoolId}/${replacesTexts ? 'impact' : ''}`);
  const value = texts.draft;
  const errors = value ? { noticeText: policyTextProblem(value.noticeText), retentionText: policyTextProblem(value.retentionText),
    contactEmail: isEmail(value.contactEmail.trim()) ? null : 'Indiquez l’adresse de contact pour les données.' } : null;
  const valid = !!errors && Object.values(errors).every(item => item === null);
  const mayEdit = !!policy && !runner.pending && !runner.busy;
  const showForm = !adopted || editing || texts.edited;
  const consequences = replacesTexts && impact.status !== 'loading' ? impactSentences(impact.data ?? null) : [];
  const publishesFields = !fieldsPublished && !!proposals;
  const shownError = (key: keyof PolicyText) => texts.edited ? errors?.[key] ?? null : null;

  async function confirm() {
    if (!value || !valid || !policy) return;
    const result: SubmitResult = await runner.run(createCommand({ schoolId, kind: 'saveDataPolicy', path: 'data-policy', ifMatch: policy.version, resourceVersion: policy.version,
      body: { noticeText: value.noticeText, retentionText: value.retentionText, contactEmail: value.contactEmail.trim(), reviewAcknowledged: true,
        ...(publishesFields ? { publishProposedFields: true } : {}) } }), 'Les textes sont adoptés.');
    if (result.status === 'confirmed') texts.markSaved({ ...value, contactEmail: value.contactEmail.trim() });
    if (result.status !== 'rejected') setReviewing(false);
  }

  return <section className="settings-card" aria-labelledby="policy-title">
    <header className="settings-card-heading"><div className="settings-card-title"><h2 id="policy-title">Textes de confidentialité</h2>
      {policy?.approvedAt ? <span className="settings-muted">Adoptés le {dateTime(policy.approvedAt, school.timeZone)}</span> : policy && <Badge variant="outline">À adopter</Badge>}</div>
      {!showForm && <Button variant="outline" disabled={!mayEdit} onClick={() => setEditing(true)}><Pencil aria-hidden="true" />Modifier</Button>}</header>
    {!reviewing && <CommandFeedback runner={runner} />}
    <ReadFeedback loaded={loaded} label="Lecture des textes" />
    {policy && !showForm && <>
      <Disclosure title="Utilisation des données"><p className="settings-copy">{policy.noticeText}</p></Disclosure>
      <Disclosure title="Conservation des données"><p className="settings-copy">{policy.retentionText}</p></Disclosure>
      {policy.contactEmail && <dl className="settings-values"><div><dt>Contact pour les données</dt><dd>{policy.contactEmail}</dd></div></dl>}
    </>}
    {policy && showForm && !value && <Skeleton className="h-40 w-full" />}
    {policy && showForm && value && <form className="settings-form" noValidate onSubmit={event => { event.preventDefault(); if (valid && mayEdit) { runner.clearOutcome(); setReviewing(true); } }}>
      {!adopted && <Badge variant="secondary" className="justify-self-start">Textes proposés par Drivy</Badge>}
      <FieldGroup>
        <Field data-invalid={!!shownError('noticeText') || undefined}><FieldLabel htmlFor="privacy-information">Information</FieldLabel>
          <Textarea id="privacy-information" rows={8} maxLength={20_000} value={value.noticeText} disabled={!mayEdit} aria-invalid={!!shownError('noticeText')} onChange={event => texts.setDraft({ ...value, noticeText: event.target.value })} />
          {shownError('noticeText') && <FieldError>{shownError('noticeText')}</FieldError>}</Field>
        <Field data-invalid={!!shownError('retentionText') || undefined}><FieldLabel htmlFor="privacy-retention">Conservation</FieldLabel>
          <Textarea id="privacy-retention" rows={5} maxLength={20_000} value={value.retentionText} disabled={!mayEdit} aria-invalid={!!shownError('retentionText')} onChange={event => texts.setDraft({ ...value, retentionText: event.target.value })} />
          {shownError('retentionText') && <FieldError>{shownError('retentionText')}</FieldError>}</Field>
        <Field data-invalid={!!shownError('contactEmail') || undefined}><FieldLabel htmlFor="privacy-contact">Contact pour les données</FieldLabel>
          <Input id="privacy-contact" type="email" value={value.contactEmail} disabled={!mayEdit} aria-invalid={!!shownError('contactEmail')} onChange={event => texts.setDraft({ ...value, contactEmail: event.target.value })} />
          {shownError('contactEmail') && <FieldError>{shownError('contactEmail')}</FieldError>}</Field>
      </FieldGroup>
      <div className="settings-form-actions">
        {adopted && <Button type="button" variant="outline" onClick={() => { texts.reset(); setEditing(false); }}>Annuler</Button>}
        <Button type="submit" disabled={!mayEdit || !valid || (adopted && !texts.edited)}>Relire et adopter</Button>
      </div>
    </form>}
    <Review open={reviewing} busy={runner.busy} onCancel={() => setReviewing(false)} onConfirm={() => void confirm()} title="Relire les textes" confirmLabel="J’adopte ces textes"
      acknowledgement="J’ai relu ces textes et je les adopte pour mon école." blocked={replacesTexts && impact.status === 'loading' ? 'Vérification des trajets GPS concernés…' : null}>
      <CommandFeedback runner={runner} />
      {consequences.length > 0 && <Alert><AlertTitle>Effet sur le GPS</AlertTitle><AlertDescription>{consequences.map(sentence => <p key={sentence}>{sentence}</p>)}</AlertDescription></Alert>}
      {value && <><h3>Information</h3><p className="settings-copy">{value.noticeText}</p><h3>Conservation</h3><p className="settings-copy">{value.retentionText}</p>
        <dl className="settings-values"><div><dt>Contact pour les données</dt><dd>{value.contactEmail.trim()}</dd></div></dl></>}
      {publishesFields && proposals && <p className="settings-muted">Publiées en même temps : {proposals.profileFields.map(rule => `${fieldLabels[rule.field as ProfileField] ?? rule.field} (${rule.requirement === 'REQUIRED' ? 'requis' : 'facultatif'})`).join(', ')}.</p>}
    </Review>
  </section>;
}

function Disclosure({ title, children, defaultOpen = false }: { title: string; children: ReactNode; defaultOpen?: boolean }) {
  return <Collapsible defaultOpen={defaultOpen} className="settings-disclosure">
    <CollapsibleTrigger render={<Button variant="ghost" className="settings-disclosure-trigger" />}>{title}<ChevronRight aria-hidden="true" /></CollapsibleTrigger>
    <CollapsibleContent>{children}</CollapsibleContent>
  </Collapsible>;
}

/** Empty, read-only controls: the pupil's form with its exact explanations, without collecting anything. */
function FieldsPreview({ fields }: { fields: readonly ProfilePolicy['fields'][number][] }) {
  return <div className="settings-preview" aria-label="Aperçu du formulaire élève">{fields.map(field => <div key={field.field} className="settings-preview-field">
    <p><strong>{fieldLabels[field.field as ProfileField] ?? field.field}</strong><span className="settings-muted">{setupProfileRequirement(field)}</span></p>
    {field.field === 'profilePhotoDocumentId' ? <div className="settings-preview-photo" role="img" aria-label="Emplacement de la photo de profil" />
      : field.field === 'postalAddress' ? <Textarea aria-label={fieldLabels[field.field as ProfileField]} rows={2} readOnly tabIndex={-1} value="" />
      : <Input aria-label={fieldLabels[field.field as ProfileField]} type={inputTypes[field.field] ?? 'text'} readOnly tabIndex={-1} value="" />}
    <p className="settings-muted">{field.explanation}</p>
  </div>)}</div>;
}

function RequestedFields({ proposals, policies, noticeVersionId }: { proposals: TextProposals | null; policies: readonly ProfilePolicy[]; noticeVersionId: string | null }) {
  const { schoolId, school } = useConsole();
  const current = useMemo(() => policies.filter(item => item.status === 'PUBLISHED' && Date.parse(item.effectiveFrom) <= Date.now())
    .sort((a, b) => Date.parse(b.effectiveFrom) - Date.parse(a.effectiveFrom))[0] ?? null, [policies]);
  const [drafts, setDrafts] = useState<Record<ProfileField, FieldDraft> | null>(null);
  const [editing, setEditing] = useState(false);
  const editButton = useRef<HTMLButtonElement>(null);
  const runner = useCommandRunner(() => { setDrafts(null); setEditing(false); });
  const [reviewing, setReviewing] = useState(false);
  const shown = drafts ?? initialDrafts(current, proposals);
  const rules = rulesOf(shown);
  const problem = profilePolicyProblem(rules);
  const changed = !current || !sameProfileRules(rules, current.fields);
  useUnsavedChanges(drafts !== null && changed);
  const mayEdit = !!noticeVersionId && !runner.pending && !runner.busy;
  const update = (field: ProfileField, change: Partial<FieldDraft>) => setDrafts({ ...shown, [field]: { ...shown[field], ...change } });
  const showForm = !current || editing || drafts !== null;
  const stageLabel = (field: ProfileField) => {
    const rule = rules.find(item => item.field === field);
    return !rule ? 'Non demandé' : rule.stage === 'JOIN' ? 'Requis à l’entrée' : rule.stage === 'BEFORE_LESSON' ? 'Requis avant une leçon' : rule.stage === 'BEFORE_COURSE' ? 'Requis avant un cours' : 'Facultatif';
  };
  const blocksPlanning = rules.some(rule => rule.stage === 'BEFORE_LESSON' && !current?.fields.some(item => item.field === rule.field && item.stage === 'BEFORE_LESSON'));
  const fields = [...editableFields, ...(shown.profilePhotoDocumentId.original ? ['profilePhotoDocumentId' as const] : [])];

  async function confirm() {
    if (problem || !noticeVersionId) return;
    const result = await runner.run(createCommand({ schoolId, kind: 'createProfilePolicy', path: 'profile-field-policies', ifMatch: school.version, resourceVersion: 0,
      body: { fields: rules, noticeVersionId, publishNow: true, impactAcknowledged: true } }), 'Les informations demandées sont enregistrées.');
    if (result.status !== 'rejected') setReviewing(false);
  }

  return <section className="settings-card" aria-labelledby="fields-title">
    <header className="settings-card-heading"><div className="settings-card-title"><h2 id="fields-title">Informations demandées</h2>
      {current ? <span className="settings-muted">Depuis le {dateTime(current.effectiveFrom, school.timeZone)}</span> : <Badge variant="outline">À publier</Badge>}</div>
      {!showForm && <Button ref={editButton} variant="outline" disabled={!mayEdit} onClick={() => setEditing(true)}><Pencil aria-hidden="true" />Personnaliser</Button>}</header>
    {!reviewing && <CommandFeedback runner={runner} />}
    {!noticeVersionId && <Alert><AlertTitle>Textes de confidentialité à adopter</AlertTitle></Alert>}
    {!showForm && <>
      <dl className="settings-values">{(['firstName', 'lastName', ...fields] as ProfileField[]).map(field => <div key={field}><dt>{fieldLabels[field]}</dt><dd>{stageLabel(field)}</dd></div>)}</dl>
      <Disclosure title="Aperçu pour l’élève"><FieldsPreview fields={rules} /></Disclosure>
    </>}
    {showForm && <form className="settings-form" onSubmit={event => { event.preventDefault(); if (!problem && changed && mayEdit) { runner.clearOutcome(); setReviewing(true); } }}>
      <dl className="settings-values">{(['firstName', 'lastName'] as const).map(field => <div key={field}><dt>{fieldLabels[field]}</dt><dd>Requis à l’entrée</dd></div>)}</dl>
      <div className="settings-fields">{fields.map(field => {
        const draft = shown[field];
        const options: Choice[] = field === 'profilePhotoDocumentId' ? ['none', 'optional'] : ['none', 'optional', 'lesson', ...(draft.original && choiceOf(draft.original) === 'keep' ? ['keep' as const] : [])];
        return <fieldset key={field} className="settings-field-row" disabled={!mayEdit}>
          <legend>{fieldLabels[field]}</legend>
          <RadioGroup value={draft.choice} onValueChange={choice => update(field, { choice: choice as Choice })} className="settings-choices" aria-label={`Demande · ${fieldLabels[field]}`}>
            {options.map(choice => <Label key={choice} htmlFor={`${field}-${choice}`} className="settings-choice"><RadioGroupItem id={`${field}-${choice}`} value={choice} />{choiceLabels[choice]}</Label>)}
          </RadioGroup>
          {draft.choice !== 'none' && <Field data-invalid={!filled(draft.explanation, 1000) || undefined}><FieldLabel htmlFor={`${field}-why`}>Pourquoi</FieldLabel>
            <Textarea id={`${field}-why`} rows={2} maxLength={1000} value={draft.explanation} aria-invalid={!filled(draft.explanation, 1000)} onChange={event => update(field, { explanation: event.target.value })} />
            {!filled(draft.explanation, 1000) && <FieldError>Expliquez pourquoi.</FieldError>}</Field>}
        </fieldset>;
      })}</div>
      <Disclosure title="Aperçu pour l’élève"><FieldsPreview fields={rules} /></Disclosure>
      {problem && <FieldError>{problem}</FieldError>}
      <div className="settings-form-actions">
        {current && <Button type="button" variant="outline" disabled={runner.busy} onClick={() => { setDrafts(null); setEditing(false); requestAnimationFrame(() => editButton.current?.focus()); }}>Annuler</Button>}
        <Button type="submit" disabled={!mayEdit || !!problem || !changed}>{current ? 'Enregistrer' : 'Publier'}</Button>
      </div>
    </form>}
    <Review open={reviewing} busy={runner.busy} onCancel={() => setReviewing(false)} onConfirm={() => void confirm()} title="Informations demandées" confirmLabel="Enregistrer"
      acknowledgement="J’ai relu ces informations et leur raison.">
      <CommandFeedback runner={runner} />
      <dl className="settings-values">{rules.map(rule => <div key={rule.field}><dt>{fieldLabels[rule.field]}</dt><dd>{rule.stage === 'JOIN' ? 'Requis à l’entrée' : rule.stage === 'BEFORE_LESSON' ? 'Requis avant une leçon' : rule.stage === 'BEFORE_COURSE' ? 'Avant un cours' : 'Facultatif'}</dd></div>)}</dl>
      {blocksPlanning && <Alert><AlertTitle>Planification</AlertTitle><AlertDescription>Une leçon ne pourra plus être planifiée pour un élève à qui il manque une information requise.</AlertDescription></Alert>}
    </Review>
  </section>;
}

function ConditionsCard() {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    const [terms, procedures] = await Promise.all([readAll(schoolId, 'commercial-terms', termsSchema), readAll(schoolId, 'policy-versions', catalogPolicySchema)]);
    return { terms: terms.items, procedures: procedures.items };
  }, [schoolId, revision]);
  const terms = loaded.data?.terms.filter(item => item.approved).sort((a, b) => b.version - a.version)[0] ?? null;
  const categories = loaded.data ? [...new Set(loaded.data.procedures.filter(item => item.approved).map(item => item.categoryCode))].sort((a, b) => a.localeCompare(b, 'fr')) : [];
  return <section className="settings-card" aria-labelledby="conditions-title">
    <header className="settings-card-heading"><h2 id="conditions-title">Conditions de l’école</h2></header>
    <ReadFeedback loaded={loaded} label="Lecture des conditions" />
    {loaded.data && <ul className="settings-links">
      <li><Button variant="ghost" onClick={() => navigate('conditions')}><span><strong>Conditions commerciales</strong><span className="settings-muted">{terms ? terms.approvedAt ? `${terms.label} · adoptées le ${dateTime(terms.approvedAt, school.timeZone)}` : terms.label : 'À écrire'}</span></span><ArrowRight aria-hidden="true" /></Button></li>
      <li><Button variant="ghost" onClick={() => navigate('procedures')}><span><strong>Déroulement et annulation</strong><span className="settings-muted">{categories.length ? `Permis ${categories.join(', ')}` : 'À écrire'}</span></span><ArrowRight aria-hidden="true" /></Button></li>
    </ul>}
  </section>;
}

function usePrivacyContext() {
  const { schoolId, school } = useConsole();
  const { revision } = useCommandSnapshot();
  const proposals = useLoad(() => readSchool(schoolId, 'text-proposals', textProposalsSchema), [schoolId, school.version]);
  const context = useLoad(async () => {
    const [policy, fields] = await Promise.all([readSchool(schoolId, 'data-policy', dataPolicySchema), readAll(schoolId, 'profile-field-policies', profilePolicySchema)]);
    return { policy, fields: fields.items };
  }, [schoolId, revision, school.version]);
  return { proposals, context, notice: context.data?.policy.status === 'APPROVED' ? context.data.policy.noticeVersionId ?? null : null };
}

/** What the school tells its pupils and the GPS option (#330): one page, cards read first, every change reviewed. */
export function PrivacyPilot() {
  const { proposals, context } = usePrivacyContext();
  return <section className="settings-page"><header className="settings-heading"><h1>Confidentialité</h1></header>
    <GpsCard />
    <PolicyTextsCard proposals={proposals.data ?? null} fieldsPublished={!!context.data?.fields.some(item => item.status === 'PUBLISHED')} onAdopted={context.reload} />
    <ConditionsCard />
  </section>;
}

export function ProfileFieldsPilot() {
  const { proposals, context, notice } = usePrivacyContext();
  return <section className="settings-page"><header className="settings-heading"><h1>Informations des élèves</h1></header>
    <ReadFeedback loaded={context} label="Lecture des informations demandées" />
    {context.data && <RequestedFields proposals={proposals.data ?? null} policies={context.data.fields} noticeVersionId={notice} />}
  </section>;
}
