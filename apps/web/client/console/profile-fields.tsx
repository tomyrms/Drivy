import { useMemo, useState } from 'react';
import {
  createCommand, fieldPurposes, instantToSchoolTime, profileFields, profilePolicyProblem, profileRuleProblem, schoolTimeToInstant,
  type ProfileField, type ProfilePurpose, type ProfileRequirement, type ProfileRule, type ProfileStage,
} from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { dataPolicySchema, profilePolicySchema, readAll, readSchool, type ProfilePolicy } from '../school-api';
import { CheckField, ConfirmDialog, EmptyState, Facts, Loading, Notice, SelectField, StatusBadge, Symbol, TextArea, TextField, formatDateTime } from '../ui';
import { readError, useCommandRunner, useConsole, useLoad } from './context';
import { DetailPanel, LoadState, OutcomeNotice, Placeholder, RowButton, SectionHeading, SplitView } from './layout';

const fieldLabels: Record<ProfileField, string> = {
  firstName: 'Prénom', lastName: 'Nom', birthDate: 'Date de naissance', postalAddress: 'Adresse postale',
  contactEmail: 'E-mail', contactPhone: 'Téléphone', profilePhotoDocumentId: 'Photo de profil',
};
const requirementLabels: Record<ProfileRequirement, string> = { REQUIRED: 'Requis', CONDITIONAL: 'Selon la situation', OPTIONAL: 'Facultatif' };
const stageLabels: Record<ProfileStage, string> = { JOIN: 'À l’entrée', BEFORE_LESSON: 'Avant une leçon', BEFORE_COURSE: 'Avant un cours', OPTIONAL: 'Facultatif' };
const purposeLabels: Record<ProfilePurpose, string> = {
  IDENTIFICATION: 'Identifier la personne', LESSON_CONTACT: 'Contacter pour une leçon', COURSE_ELIGIBILITY: 'Vérifier les prérequis d’un cours',
  CERTIFICATE: 'Établir une attestation', POSTAL_CONTACT: 'Contacter par courrier', PERSONALISATION: 'Personnaliser le profil',
};
const isName = (field: ProfileField) => field === 'firstName' || field === 'lastName';
const defaultRule = (field: ProfileField): ProfileRule => isName(field)
  ? { field, requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: '' }
  : { field, requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: fieldPurposes[field][0]!, explanation: '' };

type PolicyDraft = { effectiveFrom: string; included: ProfileField[]; rules: Record<ProfileField, ProfileRule>; basedOn: ProfilePolicy | null };

function RulesTable({ rules }: { rules: readonly ProfileRule[] }) {
  return (
    <table className="data-table rules">
      <caption className="visually-hidden">Champs demandés</caption>
      <thead><tr><th scope="col">Champ</th><th scope="col">Exigence</th><th scope="col">Moment</th><th scope="col">Utilité</th></tr></thead>
      <tbody>{rules.map(rule => <tr key={rule.field}>
        <th scope="row">{fieldLabels[rule.field]}<span className="caption block">{rule.explanation}</span></th>
        <td>{requirementLabels[rule.requirement]}</td><td>{stageLabels[rule.stage]}</td><td>{purposeLabels[rule.purposeCode]}</td>
      </tr>)}</tbody>
    </table>
  );
}

export function ProfileFieldsSection() {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => setDraft(null));
  const loaded = useLoad(async () => {
    const [policies, notice] = await Promise.all([readAll(schoolId, 'profile-field-policies', profilePolicySchema), readSchool(schoolId, 'data-policy', dataPolicySchema)]);
    return { policies: policies.items, notice };
  }, [schoolId, revision]);
  const [selected, setSelected] = useState<string | null>(null);
  const [draft, setDraft] = useState<PolicyDraft | null>(null);
  const [showErrors, setShowErrors] = useState(false);
  const [dialog, setDialog] = useState<'create' | 'publish' | null>(null);
  const [acknowledged, setAcknowledged] = useState(false);
  const linkedNotice = useLoad(async () => {
    const target = loaded.data?.policies.find(item => item.id === selected);
    if (dialog !== 'publish' || !target) return null;
    return readSchool(schoolId, 'data-policy', dataPolicySchema, { noticeVersionId: target.noticeVersionId });
  }, [dialog, selected, schoolId]);
  const data = loaded.data;
  const notice = data?.notice;
  const noticeAdopted = notice?.status === 'APPROVED' && !!notice.noticeVersionId;
  const items = useMemo(() => [...(data?.policies ?? [])].sort((a, b) => Date.parse(b.effectiveFrom) - Date.parse(a.effectiveFrom)), [data]);
  const applicable = useMemo(() => items.filter(item => item.status === 'PUBLISHED' && Date.parse(item.effectiveFrom) <= Date.now())
    .sort((a, b) => Date.parse(b.effectiveFrom) - Date.parse(a.effectiveFrom))[0] ?? null, [items]);
  const current = items.find(item => item.id === selected) ?? null;
  const canWrite = !runner.pending && !runner.busy;
  const selectedRules = draft ? profileFields.filter(field => draft.included.includes(field)).map(field => draft.rules[field]) : [];
  const instant = draft ? schoolTimeToInstant(draft.effectiveFrom, school.timeZone) : null;
  const draftProblem = draft ? (instant === null ? 'Choisissez une date et une heure d’effet valides (heure de l’école).' : profilePolicyProblem(selectedRules)) : null;

  const status = (policy: ProfilePolicy) => policy.id === applicable?.id ? <StatusBadge tone="success" symbol="check">En vigueur</StatusBadge>
    : policy.status === 'DRAFT' ? <StatusBadge tone="warning" symbol="edit">Brouillon</StatusBadge>
      : policy.status === 'PUBLISHED' ? <StatusBadge tone="accent" symbol="clock">Publiée · à venir</StatusBadge>
        : <StatusBadge tone="neutral" symbol="dot">Ancienne version</StatusBadge>;

  function edit(from: ProfilePolicy | null) {
    runner.clearOutcome(); setShowErrors(false); setSelected(from?.id ?? null);
    const rules = Object.fromEntries(profileFields.map(field => [field, from?.fields.find(rule => rule.field === field) ?? defaultRule(field)])) as Record<ProfileField, ProfileRule>;
    const start = new Date(Date.now() + 3_600_000); start.setMinutes(0, 0, 0);
    setDraft({ effectiveFrom: instantToSchoolTime(start.toISOString(), school.timeZone), rules, basedOn: from,
      included: from ? from.fields.map(rule => rule.field) : ['firstName', 'lastName'] });
  }
  const updateRule = (field: ProfileField, change: Partial<ProfileRule>) =>
    setDraft(value => value ? { ...value, rules: { ...value.rules, [field]: { ...value.rules[field], ...change } } } : value);

  async function confirm() {
    if (dialog === 'create' && draft && !draftProblem && instant && notice?.noticeVersionId) {
      const command = createCommand({ schoolId, kind: 'createProfilePolicy', path: 'profile-field-policies', ifMatch: school.version, resourceVersion: 0,
        body: { effectiveFrom: instant, fields: selectedRules.map(rule => ({ ...rule, explanation: rule.explanation.trim() })), noticeVersionId: notice.noticeVersionId, impactAcknowledged: true } });
      const result = await runner.run(command, 'Le brouillon est enregistré. Relisez-le puis publiez-le pour l’appliquer.');
      if (result.status === 'confirmed') setDraft(null);
    } else if (dialog === 'publish' && current?.status === 'DRAFT') {
      await runner.run(createCommand({ schoolId, kind: 'publishProfilePolicy', path: `profile-field-policies/${current.id}/publish`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: {} }), 'Les règles sont publiées. Elles s’appliqueront aux profils concernés à la date prévue.');
    }
    setDialog(null);
  }

  return (
    <div className="section-stack">
      <SectionHeading context={school.name} title="Champs du profil" description="Choisissez les informations demandées aux élèves, leur utilité et le moment où elles deviennent nécessaires."
        actions={<button type="button" className={current || draft ? 'button secondary' : 'button primary'} disabled={!canWrite || !noticeAdopted} onClick={() => edit(applicable)}><Symbol kind="plus" bare />Préparer une nouvelle version</button>} />
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des champs du profil…">{() => <>
        {noticeAdopted
          ? <p className="caption with-symbol"><Symbol kind="check" bare />Notice de données adoptée · version {notice!.version}. Chaque nouvelle version y est liée.</p>
          : <Notice tone="info" title="Notice de données à adopter" live={false} actions={<button type="button" className="button secondary" onClick={() => navigate('configuration')}>Ouvrir la configuration</button>}>
              <p>Adoptez d’abord la notice de données dans Configuration.</p></Notice>}
        <SplitView
          list={items.length === 0 ? <EmptyState symbol="list" title="Aucune version enregistrée" message="Préparez une première version pour indiquer les informations demandées aux élèves." />
            : <table className="data-table">
              <caption className="visually-hidden">Versions des champs du profil</caption>
              <thead><tr><th scope="col">Version</th><th scope="col">Prise d’effet</th><th scope="col" className="numeric">Champs</th><th scope="col">Statut</th></tr></thead>
              <tbody>{items.map(item => <tr key={item.id} className={item.id === selected && !draft ? 'selected' : undefined}>
                <th scope="row"><RowButton selected={item.id === selected && !draft} onSelect={() => { setDraft(null); setSelected(item.id); }}>Version {item.version}</RowButton></th>
                <td>{formatDateTime(item.effectiveFrom, school.timeZone)}</td><td className="numeric">{item.fields.length}</td><td>{status(item)}</td>
              </tr>)}</tbody>
            </table>}
          detail={draft ? <DetailPanel focusKey={`edit-${draft.basedOn?.id ?? 'new'}`} title="Nouvelle version des champs"
              meta={draft.basedOn ? `Préremplie à partir de la version ${draft.basedOn.version}, qui reste inchangée.` : 'Le prénom et le nom sont toujours demandés.'}
              actions={<>
                <button type="button" className="button primary" disabled={!canWrite || !noticeAdopted} onClick={() => { setShowErrors(true); if (!draftProblem) { setAcknowledged(false); setDialog('create'); } }}>Créer le brouillon…</button>
                <button type="button" className="button quiet" onClick={() => setDraft(null)} disabled={runner.busy}>Annuler</button>
              </>}>
              <form className="form-grid" onSubmit={event => event.preventDefault()}>
                <TextField label="Prise d’effet" type="datetime-local" value={draft.effectiveFrom} disabled={!canWrite}
                  onChange={effectiveFrom => setDraft({ ...draft, effectiveFrom })} hint={`Heure de l’école : ${school.timeZone}.`}
                  error={showErrors && instant === null ? 'Date ou heure invalide (une heure sautée au changement d’heure n’existe pas).' : null} />
                {profileFields.map(field => {
                  const rule = draft.rules[field];
                  const included = draft.included.includes(field);
                  const locked = isName(field) || field === 'profilePhotoDocumentId';
                  const problem = included ? profileRuleProblem(rule) : null;
                  return <fieldset className="fieldset rule" key={field}>
                    <legend>{fieldLabels[field]}</legend>
                    <CheckField label={`Demander « ${fieldLabels[field]} »`} checked={included} disabled={!canWrite || isName(field)}
                      onChange={on => setDraft({ ...draft, included: on ? [...draft.included, field] : draft.included.filter(item => item !== field) })}
                      {...(isName(field) ? { description: 'Toujours demandé à l’entrée pour identifier la personne.' } : {})} />
                    {included && <>
                      <div className="form-row three">
                        <SelectField label="Exigence" value={rule.requirement} disabled={!canWrite || locked}
                          options={(['REQUIRED', 'CONDITIONAL', 'OPTIONAL'] as const).map(value => ({ value, label: requirementLabels[value] }))}
                          onChange={requirement => updateRule(field, { requirement, stage: requirement === 'OPTIONAL' ? 'OPTIONAL' : requirement === 'CONDITIONAL' ? 'BEFORE_COURSE' : rule.stage === 'OPTIONAL' || rule.stage === 'JOIN' ? 'BEFORE_LESSON' : rule.stage })} />
                        <SelectField label="Moment" value={rule.stage} disabled={!canWrite || locked || rule.requirement !== 'REQUIRED'}
                          options={(isName(field) ? ['JOIN'] as const : rule.requirement === 'REQUIRED' ? ['BEFORE_LESSON', 'BEFORE_COURSE'] as const : rule.requirement === 'CONDITIONAL' ? ['BEFORE_COURSE'] as const : ['OPTIONAL'] as const)
                            .map(value => ({ value, label: stageLabels[value] }))}
                          onChange={stage => updateRule(field, { stage })} />
                        <SelectField label="Utilité" value={rule.purposeCode} disabled={!canWrite || fieldPurposes[field].length === 1}
                          options={fieldPurposes[field].map(value => ({ value, label: purposeLabels[value] }))} onChange={purposeCode => updateRule(field, { purposeCode })} />
                      </div>
                      <TextArea label="Explication affichée à la personne" rows={2} maxLength={1000} value={rule.explanation} disabled={!canWrite}
                        onChange={explanation => updateRule(field, { explanation })} error={showErrors ? problem : null} />
                    </>}
                  </fieldset>;
                })}
                {showErrors && draftProblem && <p className="field-error"><Symbol kind="alert" bare />{draftProblem}</p>}
              </form>
            </DetailPanel>
            : current ? <DetailPanel focusKey={current.id} title={`Version ${current.version}`} meta={`Prise d’effet : ${formatDateTime(current.effectiveFrom, school.timeZone)}`} badge={status(current)}
              actions={<>
                {current.status === 'DRAFT' && <button type="button" className="button primary" disabled={!canWrite} onClick={() => { runner.clearOutcome(); setAcknowledged(false); setDialog('publish'); }}>Relire avant publication</button>}
                <button type="button" className={current.status === 'DRAFT' ? 'button secondary' : 'button primary'} disabled={!canWrite || !noticeAdopted} onClick={() => edit(current)}><Symbol kind="edit" bare />Nouvelle version à partir de celle-ci</button>
              </>}>
              <RulesTable rules={current.fields} />
              {current.status === 'DRAFT' && <p className="caption">Un brouillon ne s’applique à personne tant qu’il n’est pas publié.</p>}
            </DetailPanel>
            : <Placeholder>Choisissez une version pour consulter ses règles.</Placeholder>} />
      </>}</LoadState>

      <ConfirmDialog open={dialog !== null} busy={runner.busy} onCancel={() => setDialog(null)} onConfirm={() => void confirm()}
        title={dialog === 'create' ? 'Créer un brouillon' : 'Publier ces règles'} confirmLabel={dialog === 'create' ? 'Confirmer la création' : 'Publier ces règles'}
        acknowledgement={dialog === 'create' ? 'J’ai relu l’utilité des champs et leur effet sur les profils.' : 'J’ai relu ces règles et la notice liée.'}
        acknowledged={acknowledged} onAcknowledge={setAcknowledged}
        disabledReason={dialog === 'publish' && linkedNotice.status !== 'ready' ? 'La notice liée doit être relue avant la publication.' : null}>
        {dialog === 'create' && draft && <>
          <Facts items={[['Prise d’effet', instant ? formatDateTime(instant, school.timeZone) : '—'], ['Notice liée', notice ? `Version ${notice.version}` : '—']]} />
          <RulesTable rules={selectedRules} />
          <p className="caption">La politique sera liée à la notice de données adoptée affichée ci-dessus. Le brouillon ne s’applique qu’après publication.</p>
        </>}
        {dialog === 'publish' && current && <>
          <p className="dialog-lead">{school.name} · version {current.version}</p>
          <p>Ces règles s’appliqueront aux profils concernés à la date prévue. Les informations existantes ne seront pas complétées automatiquement.</p>
          <Facts items={[['Prise d’effet', formatDateTime(current.effectiveFrom, school.timeZone)]]} />
          <RulesTable rules={current.fields} />
          {linkedNotice.status === 'loading' && <Loading label="Lecture de la notice liée à ce brouillon…" />}
          {linkedNotice.status === 'error' && <Notice tone="error" title="Notice liée indisponible" actions={<button type="button" className="button retry" onClick={linkedNotice.reload}>Relire la notice liée</button>}>
            <p>{linkedNotice.error ?? readError(null)}</p></Notice>}
          {linkedNotice.data && <details className="disclosure" open>
            <summary>Notice liée à cette politique · version {linkedNotice.data.version}</summary>
            <p className="policy-copy review-copy">{linkedNotice.data.noticeText}</p>
            <p className="policy-copy review-copy">{linkedNotice.data.retentionText}</p>
          </details>}
        </>}
      </ConfirmDialog>
    </div>
  );
}
