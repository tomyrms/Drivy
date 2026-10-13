import { useMemo, useState } from 'react';
import { characters, createCommand, filled, isEmail, profilePolicyProblem, type ProfileField } from '../command-core';
import { useCommandSnapshot, type SubmitResult } from '../command-store';
import {
  POLICY_TEXT_MINIMUM, catalogPolicySchema, dataPolicySchema, policyImpactSchema, profilePolicySchema, readAll, readSchool, termsSchema, textProposalsSchema,
  type ProfilePolicy, type TextProposals,
} from '../school-api';
import { ConfirmDialog, Facts, Loading, Notice, SelectField, StatusBadge, Symbol, TextArea, TextField, formatDateTime } from '../ui';
import { useCommandRunner, useConsole, useDraft, useLoad } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
import { choiceLabels, choiceOf, editableFields, impactSentences, initialDrafts, rulesOf, type Choice, type FieldDraft } from './privacy-model';
import { ProfileFieldsPreview } from './profile-fields-preview';

/* ------------------------------------------------------------ Textes de confidentialité */

type PolicyText = { noticeText: string; retentionText: string; contactEmail: string };

const policyTextProblem = (value: string) => characters(value.trim()) < POLICY_TEXT_MINIMUM
  ? `Écrivez au moins ${POLICY_TEXT_MINIMUM} caractères.` : filled(value, 20_000) ? null : '20 000 caractères au plus.';

const fieldLabels: Record<ProfileField, string> = {
  firstName: 'Prénom', lastName: 'Nom', birthDate: 'Date de naissance', postalAddress: 'Adresse postale',
  contactEmail: 'E-mail', contactPhone: 'Téléphone', profilePhotoDocumentId: 'Photo de profil',
};

function PolicyTexts({ proposals, fieldsPublished, onAdopted }: { proposals: TextProposals | null; fieldsPublished: boolean; onAdopted: () => void }) {
  const { schoolId, school } = useConsole();
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
  const [reviewing, setReviewing] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const replacesTexts = reviewing && adopted;
  const impact = useLoad(async () => replacesTexts ? readSchool(schoolId, 'data-policy/impact', policyImpactSchema) : null,
    [replacesTexts, schoolId], `${schoolId}/${replacesTexts ? 'impact' : ''}`);
  const value = texts.draft;
  const errors = value ? {
    noticeText: policyTextProblem(value.noticeText), retentionText: policyTextProblem(value.retentionText),
    contactEmail: isEmail(value.contactEmail.trim()) ? null : 'Indiquez l’adresse de contact pour les données.',
  } : null;
  const valid = !!errors && Object.values(errors).every(item => item === null);
  const mayEdit = !!policy && !runner.pending && !runner.busy;
  const showForm = !adopted || editing || texts.edited;
  const consequences = replacesTexts && impact.status !== 'loading' ? impactSentences(impact.data ?? null) : [];
  const publishesFields = !fieldsPublished && !!proposals;

  async function confirm() {
    if (!value || !valid || !policy) return;
    const result: SubmitResult = await runner.run(createCommand({ schoolId, kind: 'saveDataPolicy', path: 'data-policy', ifMatch: policy.version, resourceVersion: policy.version,
      body: { noticeText: value.noticeText, retentionText: value.retentionText, contactEmail: value.contactEmail.trim(), reviewAcknowledged: true,
        ...(publishesFields ? { publishProposedFields: true } : {}) } }), 'Les textes sont adoptés.');
    if (result.status !== 'rejected') setReviewing(false);
  }

  return <section className="settings-section" aria-labelledby="policy-title">
    <div className="settings-section-heading">
      <h2 id="policy-title" className="section-title">Textes de confidentialité</h2>
      {policy?.approvedAt ? <span className="row-meta">Adoptés le {formatDateTime(policy.approvedAt, school.timeZone)}</span>
        : <StatusBadge tone="warning" symbol="file">À adopter</StatusBadge>}
    </div>
    <div className="settings-section-body">
      {!reviewing && <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />}
      <LoadState loaded={loaded} label="Lecture des textes…">{data => <>
        {!showForm && <>
          <details className="disclosure">
            <summary>Lire les textes</summary>
            <h3>Information</h3><p className="policy-copy">{data.noticeText}</p>
            <h3>Conservation</h3><p className="policy-copy">{data.retentionText}</p>
            {data.contactEmail && <p className="caption">Contact : {data.contactEmail}</p>}
          </details>
          <button type="button" className="button secondary" disabled={!mayEdit} onClick={() => setEditing(true)}><Symbol kind="edit" bare />Modifier les textes</button>
        </>}
        {showForm && !value && <Loading label="Préparation des textes proposés…" />}
        {showForm && value && errors && <form className="form-grid" onSubmit={event => { event.preventDefault(); if (valid && mayEdit) { runner.clearOutcome(); setAcknowledged(false); setReviewing(true); } }}>
          {!adopted && <p className="caption with-symbol"><Symbol kind="file" bare />Textes proposés par Drivy, à relire et adapter.</p>}
          <TextArea label="Information" rows={8} maxLength={20_000} value={value.noticeText} disabled={!mayEdit}
            onChange={noticeText => texts.setDraft({ ...value, noticeText })} error={texts.edited ? errors.noticeText : null} />
          <TextArea label="Conservation" rows={5} maxLength={20_000} value={value.retentionText} disabled={!mayEdit}
            onChange={retentionText => texts.setDraft({ ...value, retentionText })} error={texts.edited ? errors.retentionText : null} />
          <TextField label="Contact pour les données" type="email" value={value.contactEmail} disabled={!mayEdit}
            onChange={contactEmail => texts.setDraft({ ...value, contactEmail })} error={texts.edited ? errors.contactEmail : null} />
          <div className="button-row compact">
            <button type="submit" className="button primary" disabled={!mayEdit || !valid || (adopted && !texts.edited)}>Relire et adopter</button>
            {adopted && <button type="button" className="button quiet" onClick={() => { texts.reset(); setEditing(false); }}>Annuler</button>}
          </div>
        </form>}
      </>}</LoadState>
    </div>
    <ConfirmDialog open={reviewing} busy={runner.busy} onCancel={() => setReviewing(false)} onConfirm={() => void confirm()}
      title="Relire les textes" confirmLabel="J’adopte ces textes"
      acknowledgement="J’ai relu ces textes et je les adopte pour mon école." acknowledged={acknowledged} onAcknowledge={setAcknowledged}
      disabledReason={replacesTexts && impact.status === 'loading' ? 'Vérification des trajets GPS concernés…' : null}>
      <OutcomeNotice outcome={runner.outcome} />
      {replacesTexts && impact.status === 'loading' && <Loading label="Vérification des trajets GPS concernés…" />}
      {consequences.length > 0 && <Notice tone="warning" title="Effet sur le GPS" live={false}>{consequences.map(sentence => <p key={sentence}>{sentence}</p>)}</Notice>}
      {value && <>
        <h3>Information</h3><p className="policy-copy review-copy">{value.noticeText}</p>
        <h3>Conservation</h3><p className="policy-copy review-copy">{value.retentionText}</p>
        <Facts items={[['Contact pour les données', value.contactEmail.trim()]]} />
      </>}
      {publishesFields && proposals && <p className="caption">Les informations demandées sont publiées en même temps : {
        proposals.profileFields.map(rule => `${fieldLabels[rule.field as ProfileField] ?? rule.field} (${rule.requirement === 'REQUIRED' ? 'requis' : 'facultatif'})`).join(', ')}.</p>}
    </ConfirmDialog>
  </section>;
}

/* ------------------------------------------------------------ Informations demandées */

function RequestedFields({ proposals, policies, noticeVersionId }: { proposals: TextProposals | null; policies: readonly ProfilePolicy[]; noticeVersionId: string | null }) {
  const { schoolId, school } = useConsole();
  const current = useMemo(() => policies.filter(item => item.status === 'PUBLISHED' && Date.parse(item.effectiveFrom) <= Date.now())
    .sort((a, b) => Date.parse(b.effectiveFrom) - Date.parse(a.effectiveFrom))[0] ?? null, [policies]);
  const [drafts, setDrafts] = useState<Record<ProfileField, FieldDraft> | null>(null);
  const runner = useCommandRunner(() => setDrafts(null));
  const [reviewing, setReviewing] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const shown = drafts ?? initialDrafts(current, proposals);
  const rules = rulesOf(shown);
  const problem = profilePolicyProblem(rules);
  const changed = !current || JSON.stringify(rules) !== JSON.stringify(current.fields);
  const mayEdit = !!noticeVersionId && !runner.pending && !runner.busy;
  const update = (field: ProfileField, change: Partial<FieldDraft>) => setDrafts({ ...shown, [field]: { ...shown[field], ...change } });
  const blocksPlanning = rules.some(rule => rule.stage === 'BEFORE_LESSON' && !current?.fields.some(item => item.field === rule.field && item.stage === 'BEFORE_LESSON'));

  async function confirm() {
    if (problem || !noticeVersionId) return;
    const result = await runner.run(createCommand({ schoolId, kind: 'createProfilePolicy', path: 'profile-field-policies', ifMatch: school.version, resourceVersion: 0,
      body: { fields: rules, noticeVersionId, publishNow: true, impactAcknowledged: true } }), 'Les informations demandées sont enregistrées.');
    if (result.status !== 'rejected') setReviewing(false);
  }

  return <section className="settings-section" aria-labelledby="fields-title">
    <div className="settings-section-heading">
      <h2 id="fields-title" className="section-title">Informations demandées</h2>
      {current ? <span className="row-meta">Depuis le {formatDateTime(current.effectiveFrom, school.timeZone)}</span>
        : <StatusBadge tone="warning" symbol="file">À publier</StatusBadge>}
    </div>
    <div className="settings-section-body">
      {!reviewing && <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />}
      {!noticeVersionId && <p className="caption">Adoptez d’abord les textes de confidentialité.</p>}
      <form className="form-grid" onSubmit={event => { event.preventDefault(); if (!problem && changed && mayEdit) { runner.clearOutcome(); setAcknowledged(false); setReviewing(true); } }}>
        <table className="data-table rules">
          <caption className="visually-hidden">Informations demandées aux élèves</caption>
          <thead><tr><th scope="col">Information</th><th scope="col">Demande</th></tr></thead>
          <tbody>
            {(['firstName', 'lastName'] as const).map(field => <tr key={field}><th scope="row">{fieldLabels[field]}</th><td>Requis à l’entrée</td></tr>)}
            {[...editableFields, ...(shown.profilePhotoDocumentId.original ? ['profilePhotoDocumentId' as const] : [])].map(field => {
              const draft = shown[field];
              const options: Choice[] = field === 'profilePhotoDocumentId' ? ['none', 'optional'] : ['none', 'optional', 'lesson', ...(draft.original && choiceOf(draft.original) === 'keep' ? ['keep' as const] : [])];
              return <tr key={field}>
                <th scope="row">{fieldLabels[field]}</th>
                <td>
                  <SelectField label={`Demande · ${fieldLabels[field]}`} value={draft.choice} disabled={!mayEdit}
                    options={options.map(value => ({ value, label: choiceLabels[value] }))} onChange={choice => update(field, { choice: choice as Choice })} />
                  {draft.choice !== 'none' && <TextArea label="Pourquoi" rows={2} maxLength={1000} value={draft.explanation} disabled={!mayEdit}
                    onChange={explanation => update(field, { explanation })} error={filled(draft.explanation, 1000) ? null : 'Expliquez pourquoi.'} />}
                </td>
              </tr>;
            })}
          </tbody>
        </table>
        <details className="disclosure"><summary>Aperçu pour l’élève</summary><ProfileFieldsPreview fields={rules} /></details>
        {problem && <p className="field-error"><Symbol kind="alert" bare />{problem}</p>}
        <div className="button-row compact">
          <button type="submit" className="button primary" disabled={!mayEdit || !!problem || !changed}>{current ? 'Enregistrer' : 'Publier'}</button>
          {drafts && <button type="button" className="button quiet" onClick={() => setDrafts(null)}>Annuler</button>}
        </div>
      </form>
    </div>
    <ConfirmDialog open={reviewing} busy={runner.busy} onCancel={() => setReviewing(false)} onConfirm={() => void confirm()}
      title="Informations demandées" confirmLabel="Enregistrer" acknowledgement="J’ai relu ces informations et leur raison." acknowledged={acknowledged} onAcknowledge={setAcknowledged}>
      <OutcomeNotice outcome={runner.outcome} />
      <Facts items={rules.map(rule => [fieldLabels[rule.field], rule.stage === 'JOIN' ? 'Requis à l’entrée' : rule.stage === 'BEFORE_LESSON' ? 'Requis avant une leçon'
        : rule.stage === 'BEFORE_COURSE' ? 'Avant un cours' : 'Facultatif'] as [string, string])} />
      <details className="disclosure"><summary>Relire le formulaire et les explications</summary><ProfileFieldsPreview fields={rules} /></details>
      {blocksPlanning && <Notice tone="warning" title="Planification" live={false}><p>Une leçon ne pourra plus être planifiée pour un élève à qui il manque une information requise.</p></Notice>}
    </ConfirmDialog>
  </section>;
}

/* ------------------------------------------------------------ Conditions */

function Conditions() {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    const [terms, procedures] = await Promise.all([readAll(schoolId, 'commercial-terms', termsSchema), readAll(schoolId, 'policy-versions', catalogPolicySchema)]);
    return { terms: terms.items, procedures: procedures.items };
  }, [schoolId, revision]);
  return <section className="settings-section" aria-labelledby="conditions-title">
    <div className="settings-section-heading"><h2 id="conditions-title" className="section-title">Conditions</h2></div>
    <div className="settings-section-body">
      <LoadState loaded={loaded} label="Lecture des conditions…">{data => {
        const terms = data.terms.filter(item => item.approved).sort((a, b) => b.version - a.version)[0] ?? null;
        const categories = [...new Set(data.procedures.filter(item => item.approved).map(item => item.categoryCode))].sort((a, b) => a.localeCompare(b, 'fr'));
        return <ul className="plain-list">
          <li>
            <span className="row-title">Conditions commerciales</span>
            <span className="row-meta">{terms ? `${terms.label} · ${terms.approvedAt ? `adoptées le ${formatDateTime(terms.approvedAt, school.timeZone)}` : ''}` : 'À écrire'}</span>
            <button type="button" className="button secondary compact" onClick={() => navigate('conditions')}><Symbol kind="edit" bare />{terms ? 'Modifier' : 'Écrire'}</button>
          </li>
          <li>
            <span className="row-title">Déroulement et annulation</span>
            <span className="row-meta">{categories.length ? `Permis ${categories.join(', ')}` : 'À écrire'}</span>
            <button type="button" className="button secondary compact" onClick={() => navigate('procedures')}><Symbol kind="edit" bare />{categories.length ? 'Modifier' : 'Écrire'}</button>
          </li>
        </ul>;
      }}</LoadState>
    </div>
  </section>;
}

/** Un seul endroit pour ce que l'école dit à ses élèves : confidentialité, informations demandées et conditions. */
export function PrivacySection({ section = 'privacy' }: { section?: 'privacy' | 'fields' } = {}) {
  const { schoolId, school } = useConsole();
  const { revision } = useCommandSnapshot();
  const proposals = useLoad(() => readSchool(schoolId, 'text-proposals', textProposalsSchema), [schoolId, school.version]);
  const context = useLoad(async () => {
    const [policy, fields] = await Promise.all([readSchool(schoolId, 'data-policy', dataPolicySchema), readAll(schoolId, 'profile-field-policies', profilePolicySchema)]);
    return { policy, fields: fields.items };
  }, [schoolId, revision, school.version]);
  const notice = context.data?.policy.status === 'APPROVED' ? context.data.policy.noticeVersionId ?? null : null;
  return <div className="section-stack">
    <SectionHeading context="Réglages" title={section === 'fields' ? 'Informations des élèves' : 'Confidentialité'} />
    <div className="config-sections">
      {section === 'privacy' && <PolicyTexts proposals={proposals.data ?? null} fieldsPublished={!!context.data?.fields.some(item => item.status === 'PUBLISHED')} onAdopted={context.reload} />}
      {section === 'fields' && <LoadState loaded={context} label="Lecture des informations demandées…">{data => <RequestedFields proposals={proposals.data ?? null} policies={data.fields} noticeVersionId={notice} />}</LoadState>}
      {section === 'privacy' && <details className="disclosure"><summary>Conditions de l’école</summary><Conditions /></details>}
    </div>
  </div>;
}
