import { useState } from 'react';
import { createCommand, filled, isEmail, characters } from '../command-core';
import { useCommandSnapshot, type SubmitResult } from '../command-store';
import { POLICY_TEXT_MINIMUM, dataPolicySchema, policyImpactSchema, readSchool, readinessSchema, type PolicyImpact } from '../school-api';
import { ConfirmDialog, Facts, Loading, Notice, StatusBadge, Symbol, TextArea, TextField, formatDateTime } from '../ui';
import { useCommandRunner, useConsole, useDraft, useLoad } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
import { schoolStatus } from './overview';

type Identity = { name: string; contactEmail: string; contactPhone: string };
type PolicyText = { noticeText: string; retentionText: string; contactEmail: string };
type Review = 'identity' | 'policy' | 'activation' | null;

const policyTextProblem = (value: string) => characters(value.trim()) < POLICY_TEXT_MINIMUM
  ? `Écrivez au moins ${POLICY_TEXT_MINIMUM} caractères.` : filled(value, 20_000) ? null : '20 000 caractères au plus.';

/** Ce qu'une nouvelle version arrête : les accords GPS donnés sur les textes actuels et les trajets en cours. */
function impactSentences(impact: PolicyImpact | null): string[] {
  if (!impact) return ['Les élèves devront redonner leur accord GPS et les trajets en cours s’arrêteront.'];
  const sentences: string[] = [];
  if (impact.gpsAgreements > 0) sentences.push(impact.gpsAgreements === 1
    ? '1 élève avait accepté le GPS avec les textes actuels : la question lui sera reposée.'
    : `${impact.gpsAgreements} élèves avaient accepté le GPS avec les textes actuels : la question leur sera reposée.`);
  if (impact.activeCaptures > 0) sentences.push(impact.activeCaptures === 1
    ? '1 trajet en cours s’arrêtera.' : `${impact.activeCaptures} trajets en cours s’arrêteront.`);
  return sentences;
}

/** Same rules as the native office screens: relire, confirmer, puis seulement l’école confirme. */
export function ConfigurationSection() {
  const { schoolId, school } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => { setEditingPolicy(false); setEditingIdentity(false); });
  const loaded = useLoad(async () => {
    const [policy, readiness] = await Promise.all([
      readSchool(schoolId, 'data-policy', dataPolicySchema), readSchool(schoolId, 'readiness', readinessSchema)]);
    return { policy, readiness };
  }, [schoolId, revision, school.version]);
  const policy = loaded.data?.policy ?? null;
  const identity = useDraft<Identity>({ name: school.name, contactEmail: school.contactEmail, contactPhone: school.contactPhone ?? '' });
  const texts = useDraft<PolicyText>(policy ? { noticeText: policy.noticeText, retentionText: policy.retentionText, contactEmail: policy.contactEmail ?? school.contactEmail } : null);
  const [editingPolicy, setEditingPolicy] = useState(false);
  const [editingIdentity, setEditingIdentity] = useState(false);
  const [review, setReview] = useState<Review>(null);
  const [acknowledged, setAcknowledged] = useState(false);
  // Read when the review opens, so the numbers are those of the moment the administrator confirms.
  const replacesTexts = review === 'policy' && policy?.status === 'APPROVED';
  const impact = useLoad(async () => replacesTexts ? readSchool(schoolId, 'data-policy/impact', policyImpactSchema) : null,
    [replacesTexts, schoolId], `${schoolId}/${replacesTexts ? 'impact' : ''}`);

  const mayEdit = loaded.data !== undefined && !runner.pending && !runner.busy;
  const idValue = identity.draft;
  const identityErrors = idValue ? {
    name: filled(idValue.name, 150) ? null : 'Indiquez le nom de l’école (150 caractères au plus).',
    contactEmail: isEmail(idValue.contactEmail.trim()) ? null : 'Indiquez une adresse e-mail valide.',
    contactPhone: characters(idValue.contactPhone) <= 32 ? null : '32 caractères au plus.',
  } : null;
  const identityValid = !!identityErrors && Object.values(identityErrors).every(value => value === null);
  const textValue = texts.draft;
  const textErrors = textValue ? {
    noticeText: policyTextProblem(textValue.noticeText),
    retentionText: policyTextProblem(textValue.retentionText),
    contactEmail: isEmail(textValue.contactEmail.trim()) ? null : 'Indiquez l’adresse de contact pour les données.',
  } : null;
  const textsValid = !!textErrors && Object.values(textErrors).every(value => value === null);
  const showIdentity = editingIdentity || identity.edited || school.status === 'DRAFT';
  const showTexts = policy?.status !== 'APPROVED' || editingPolicy || texts.edited;
  const readiness = loaded.data?.readiness;
  const canActivate = mayEdit && school.status === 'DRAFT' && readiness?.activationReady === true && policy?.status === 'APPROVED' && !identity.edited && !texts.edited;
  const status = schoolStatus(school.status);
  const consequences = replacesTexts && impact.status !== 'loading' ? impactSentences(impact.data ?? null) : [];

  function open(kind: Review) { runner.clearOutcome(); setAcknowledged(false); setReview(kind); }
  async function confirm() {
    let result: SubmitResult | undefined;
    if (review === 'identity' && idValue && identityValid) {
      const command = createCommand({ schoolId, kind: 'updateSchool', path: '', ifMatch: school.version, resourceVersion: school.version,
        body: { name: idValue.name, timeZone: school.timeZone, contactEmail: idValue.contactEmail.trim(), contactPhone: idValue.contactPhone.trim() ? idValue.contactPhone.trim() : null, impactConfirmed: true } });
      result = await runner.run(command, 'Les coordonnées de l’école sont enregistrées.');
      if (result.status === 'confirmed') setEditingIdentity(false);
    } else if (review === 'policy' && textValue && textsValid && policy) {
      const command = createCommand({ schoolId, kind: 'saveDataPolicy', path: 'data-policy', ifMatch: policy.version, resourceVersion: policy.version,
        body: { noticeText: textValue.noticeText, retentionText: textValue.retentionText, contactEmail: textValue.contactEmail.trim(), reviewAcknowledged: true } });
      result = await runner.run(command, 'Les textes sont adoptés.');
      if (result.status === 'confirmed') setEditingPolicy(false);
    } else if (review === 'activation' && canActivate && readiness) {
      const command = createCommand({ schoolId, kind: 'activate', path: 'activate', ifMatch: school.version, resourceVersion: school.version,
        body: { expectedConfigurationVersion: readiness.configurationVersion, reviewAcknowledged: true } });
      result = await runner.run(command, 'Votre école est activée.');
    }
    // A refusal stays in the dialog, next to the action it concerns, with the typed texts.
    if (result?.status !== 'rejected') setReview(null);
  }

  return (
    <div className="section-stack">
      <SectionHeading context="Réglages" title={school.status === 'DRAFT' ? 'Préparer l’école' : 'École'}
        actions={school.status !== 'ACTIVE' ? <StatusBadge tone={status.tone} symbol="clock">{status.label}</StatusBadge> : undefined} />
      {review === null && <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome}
        actions={runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary" onClick={loaded.reload}>Recharger les informations</button> : undefined} />}
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}

      <LoadState loaded={loaded} label="Vérification de l’école…">{data => <div className="config-sections">
        <section className="settings-section" aria-labelledby="identity-title">
          <div className="settings-section-heading"><h2 id="identity-title" className="section-title">Coordonnées</h2>
            {!showIdentity && <button className="button secondary compact" type="button" disabled={!mayEdit} onClick={() => setEditingIdentity(true)}><Symbol kind="edit" bare />Modifier</button>}
          </div>
          <div className="settings-section-body">
          {!showIdentity && <>
            <h3 className="identity-name">{school.name}</h3>
            <Facts items={[["E-mail", school.contactEmail], ['Téléphone', school.contactPhone ?? 'Non renseigné'], ['Fuseau horaire', school.timeZone]]} />
          </>}
          {showIdentity && idValue && identityErrors && <form className="form-grid" onSubmit={event => { event.preventDefault(); if (identityValid && identity.edited && mayEdit) open('identity'); }}>
            <TextField label="Nom de l’école" value={idValue.name} onChange={name => identity.setDraft({ ...idValue, name })} disabled={!mayEdit}
              autoComplete="organization" error={identity.edited ? identityErrors.name : null} />
            <TextField label="E-mail de l’école" type="email" value={idValue.contactEmail} onChange={contactEmail => identity.setDraft({ ...idValue, contactEmail })}
              disabled={!mayEdit} autoComplete="email" error={identity.edited ? identityErrors.contactEmail : null} />
            <TextField label="Téléphone" type="tel" required={false} value={idValue.contactPhone} onChange={contactPhone => identity.setDraft({ ...idValue, contactPhone })}
              disabled={!mayEdit} autoComplete="tel" error={identityErrors.contactPhone} />
            <Facts items={[['Fuseau horaire', school.timeZone]]} />
            <div className="button-row compact">
              <button type="submit" className={identity.edited ? 'button primary' : 'button secondary'} disabled={!mayEdit || !identityValid || !identity.edited}>Relire les modifications</button>
              {(identity.edited || editingIdentity) && <button type="button" className="button quiet" onClick={() => { identity.reset(); setEditingIdentity(false); }}>Annuler</button>}
            </div>
          </form>}
          </div>
        </section>

        <section className="settings-section" aria-labelledby="policy-title">
          <div className="settings-section-heading">
            <h2 id="policy-title" className="section-title">Confidentialité</h2>
            {data.policy.approvedAt ? <span className="row-meta">Adoptés le {formatDateTime(data.policy.approvedAt, school.timeZone)}</span>
              : <StatusBadge tone="warning" symbol="file">Textes à écrire</StatusBadge>}
          </div>
          <div className="settings-section-body">
          {!showTexts && <>
            <details className="disclosure">
              <summary>Lire les textes</summary>
              <h3>Information</h3><p className="policy-copy">{data.policy.noticeText}</p>
              <h3>Conservation</h3><p className="policy-copy">{data.policy.retentionText}</p>
              {data.policy.contactEmail && <p className="caption">Contact : {data.policy.contactEmail}</p>}
            </details>
            <button type="button" className="button secondary" disabled={!mayEdit} onClick={() => setEditingPolicy(true)}><Symbol kind="edit" bare />Modifier les textes</button>
          </>}
          {showTexts && textValue && textErrors && <form className="form-grid" onSubmit={event => { event.preventDefault(); if (textsValid && mayEdit) open('policy'); }}>
            <TextArea label="Information" rows={5} maxLength={20_000} value={textValue.noticeText} disabled={!mayEdit}
              onChange={noticeText => texts.setDraft({ ...textValue, noticeText })} error={texts.edited ? textErrors.noticeText : null} />
            <TextArea label="Conservation" rows={5} maxLength={20_000} value={textValue.retentionText} disabled={!mayEdit}
              onChange={retentionText => texts.setDraft({ ...textValue, retentionText })} error={texts.edited ? textErrors.retentionText : null} />
            <TextField label="Contact pour les données" type="email" value={textValue.contactEmail} disabled={!mayEdit}
              onChange={contactEmail => texts.setDraft({ ...textValue, contactEmail })} error={texts.edited ? textErrors.contactEmail : null} />
            <div className="button-row compact">
              <button type="submit" className={!identity.edited && (texts.edited || data.policy.status !== 'APPROVED') ? 'button primary' : 'button secondary'} disabled={!mayEdit || !textsValid || (data.policy.status === 'APPROVED' && !texts.edited)}>Relire et adopter les textes</button>
              {(editingPolicy || texts.edited) && data.policy.status === 'APPROVED' &&
                <button type="button" className="button quiet" onClick={() => { texts.reset(); setEditingPolicy(false); }}>Annuler</button>}
            </div>
          </form>}
          </div>
        </section>

        {school.status === 'DRAFT' && <section className="settings-section" aria-labelledby="activation-title">
          <div className="settings-section-heading">
            <h2 id="activation-title" className="section-title">Activation</h2>
            <button type="button" className="button quiet" onClick={loaded.reload} disabled={loaded.status === 'loading'}><Symbol kind="refresh" bare />Actualiser</button>
          </div>
          <div className="settings-section-body">
          {data.readiness.activationReady
            ? <Notice tone="success" title="Préparation vérifiée" live={false}><p>L’école peut être activée.</p></Notice>
            : <ul className="blocker-list">{data.readiness.activationBlockers.map(item => <li key={item.code}><Symbol kind="dot" bare />{item.message}</li>)}</ul>}
          {(identity.edited || texts.edited) && <Notice tone="warning" title="Modifications non confirmées" live={false}><p>Des modifications attendent encore votre confirmation.</p></Notice>}
          <div className="button-row compact">
            <button type="button" className={canActivate ? 'button primary' : 'button secondary'} disabled={!canActivate} onClick={() => open('activation')}>Relire et activer l’école</button>
          </div>
          {!canActivate && runner.pending && <p className="caption">{runner.blockedReason}</p>}
          {!canActivate && !runner.pending && (identity.edited || texts.edited) && <p className="caption">Confirmez ou abandonnez d’abord les modifications en cours.</p>}
          </div>
        </section>}
      </div>}</LoadState>

      <ConfirmDialog open={review !== null} busy={runner.busy} onCancel={() => setReview(null)} onConfirm={() => void confirm()}
        title={review === 'identity' ? 'Vos coordonnées' : review === 'policy' ? 'Relire les textes' : 'Activer l’école'}
        confirmLabel={review === 'identity' ? 'Confirmer les coordonnées' : review === 'policy' ? 'J’adopte ces textes' : 'Activer mon école'}
        {...(review === 'policy' ? { acknowledgement: 'J’ai relu les deux textes et je les adopte pour mon école.', acknowledged, onAcknowledge: setAcknowledged,
          disabledReason: replacesTexts && impact.status === 'loading' ? 'Vérification des trajets GPS concernés…' : null } : {})}>
        <OutcomeNotice outcome={runner.outcome}
          actions={runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary" onClick={() => { setReview(null); loaded.reload(); }}>Recharger les informations</button> : undefined} />
        {review === 'identity' && idValue && <>
          <p className="dialog-lead">{idValue.name}</p>
          <Facts items={[['E-mail', idValue.contactEmail.trim()], ['Téléphone', idValue.contactPhone.trim() || 'Non renseigné']]} />
          <p className="caption">Ces coordonnées remplaceront celles affichées par votre école.</p>
        </>}
        {review === 'policy' && textValue && <>
          {replacesTexts && impact.status === 'loading' && <Loading label="Vérification des trajets GPS concernés…" />}
          {consequences.length > 0 && <Notice tone="warning" title="Effet sur le GPS" live={false}>
            {consequences.map(sentence => <p key={sentence}>{sentence}</p>)}</Notice>}
          <h3>Information</h3><p className="policy-copy review-copy">{textValue.noticeText}</p>
          <h3>Conservation</h3><p className="policy-copy review-copy">{textValue.retentionText}</p>
          <Facts items={[['Contact pour les données', textValue.contactEmail.trim()]]} />
        </>}
        {review === 'activation' && <>
          <p className="dialog-lead">{school.name}</p>
          <p>Les coordonnées et les textes de confidentialité ont été vérifiés. L’activation ouvre l’espace de l’école à ses membres.</p>
          <p className="caption">Les formations, réservations et cours se créent séparément.</p>
        </>}
      </ConfirmDialog>
    </div>
  );
}
