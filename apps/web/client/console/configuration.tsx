import { useState } from 'react';
import { createCommand, filled, isEmail, characters } from '../command-core';
import { useCommandSnapshot, type SubmitResult } from '../command-store';
import { dataPolicySchema, readSchool, readinessSchema } from '../school-api';
import { ConfirmDialog, Facts, Notice, StatusBadge, Symbol, TextArea, TextField, formatDateTime } from '../ui';
import { useCommandRunner, useConsole, useDraft, useLoad } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
import { capabilityTitle, schoolStatus } from './overview';

type Identity = { name: string; contactEmail: string; contactPhone: string };
type PolicyText = { noticeText: string; retentionText: string; contactEmail: string };
type Review = 'identity' | 'policy' | null;

/** Same rules as apps/ios/Drivy/SchoolConfigurationUI: relire, confirmer, puis seulement l’école confirme. */
export function ConfigurationSection({ section = 'school' }: { section?: 'school' | 'privacy' } = {}) {
  const { schoolId, school, navigate } = useConsole();
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
    noticeText: filled(textValue.noticeText, 20_000) ? null : 'Rédigez l’information des personnes (20 000 caractères au plus).',
    retentionText: filled(textValue.retentionText, 20_000) ? null : 'Rédigez la politique de conservation (20 000 caractères au plus).',
    contactEmail: isEmail(textValue.contactEmail.trim()) ? null : 'Indiquez l’adresse de contact pour les données.',
  } : null;
  const textsValid = !!textErrors && Object.values(textErrors).every(value => value === null);
  const showIdentity = editingIdentity || identity.edited || school.status === 'DRAFT';
  const showTexts = policy?.status !== 'APPROVED' || editingPolicy || texts.edited;
  const status = schoolStatus(school.status);

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
      result = await runner.run(command, 'Les textes sont adoptés. La version précédente reste conservée.');
      if (result.status === 'confirmed') setEditingPolicy(false);
    }
    // A refusal stays in the dialog, next to the action it concerns, with the typed texts.
    if (result?.status !== 'rejected') setReview(null);
  }

  return (
    <div className="section-stack">
      <SectionHeading context="Réglages" title={section === 'privacy' ? 'Confidentialité' : 'École'}
        actions={section === 'school' && school.status !== 'ACTIVE' ? <StatusBadge tone={status.tone} symbol="clock">{status.label}</StatusBadge> : undefined} />
      {review === null && <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome}
        actions={runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary" onClick={loaded.reload}>Recharger les informations</button> : undefined} />}
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}

      <LoadState loaded={loaded} label="Vérification de l’école…">{data => <div className="config-sections">
        {section === 'school' && <section className="settings-section" aria-labelledby="identity-title">
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
        </section>}

        {section === 'privacy' && <section className="settings-section" aria-labelledby="policy-title">
          <div className="settings-section-heading">
            <h2 id="policy-title" className="section-title">Information et conservation</h2>
            {data.policy.status === 'APPROVED' ? <span className="row-meta">Version {data.policy.version}</span>
              : <StatusBadge tone="warning" symbol="file">Textes à préparer</StatusBadge>}
            {data.policy.approvedAt && <span className="row-meta">Adoptée le {formatDateTime(data.policy.approvedAt, school.timeZone)}</span>}
          </div>
          <div className="settings-section-body">
          {!showTexts && <>
            <details className="disclosure">
              <summary>Consulter les textes adoptés</summary>
              <h3>Information des personnes</h3><p className="policy-copy">{data.policy.noticeText}</p>
              <h3>Conservation des données</h3><p className="policy-copy">{data.policy.retentionText}</p>
              {data.policy.contactEmail && <p className="caption">Contact : {data.policy.contactEmail}</p>}
            </details>
            <button type="button" className="button secondary" disabled={!mayEdit} onClick={() => setEditingPolicy(true)}><Symbol kind="edit" bare />Préparer une nouvelle version</button>
          </>}
          {showTexts && textValue && textErrors && <form className="form-grid" onSubmit={event => { event.preventDefault(); if (textsValid && mayEdit) open('policy'); }}>
            <TextArea label="Information des personnes" rows={5} maxLength={20_000} value={textValue.noticeText} disabled={!mayEdit}
              onChange={noticeText => texts.setDraft({ ...textValue, noticeText })} error={texts.edited ? textErrors.noticeText : null} />
            <TextArea label="Conservation des données" rows={5} maxLength={20_000} value={textValue.retentionText} disabled={!mayEdit}
              onChange={retentionText => texts.setDraft({ ...textValue, retentionText })} error={texts.edited ? textErrors.retentionText : null} />
            <TextField label="Contact pour les données" type="email" value={textValue.contactEmail} disabled={!mayEdit}
              onChange={contactEmail => texts.setDraft({ ...textValue, contactEmail })} error={texts.edited ? textErrors.contactEmail : null} />
            <div className="button-row compact">
              <button type="submit" className={!identity.edited && (texts.edited || data.policy.status !== 'APPROVED') ? 'button primary' : 'button secondary'} disabled={!mayEdit || !textsValid || (data.policy.status === 'APPROVED' && !texts.edited)}>Relire et adopter les textes</button>
              {(editingPolicy || texts.edited) && data.policy.status === 'APPROVED' &&
                <button type="button" className="button quiet" onClick={() => { texts.reset(); setEditingPolicy(false); }}>Abandonner cette version</button>}
            </div>
          </form>}
          </div>
        </section>}

        {section === 'school' && <section className="settings-section" aria-labelledby="activation-title">
          <div className="settings-section-heading">
            <h2 id="activation-title" className="section-title">{school.status === 'DRAFT' ? 'Préparation' : 'Fonctionnement'}</h2>
            <button type="button" className="button quiet" onClick={loaded.reload} disabled={loaded.status === 'loading'}><Symbol kind="refresh" bare />Actualiser</button>
          </div>
          <div className="settings-section-body">
          {(identity.edited || texts.edited) && <Notice tone="warning" title="Modifications non confirmées" live={false}><p>Des modifications attendent encore votre confirmation.</p></Notice>}
          <details className="disclosure">
            <summary>Services de l’école</summary>
            <ul className="plain-list">{data.readiness.capabilities.map(capability => <li key={capability.capability}>
              <Symbol kind={capability.ready ? 'check' : 'alert'} bare />
              <span className="row-title">{capabilityTitle(capability.capability)}</span>
              <span className="row-meta">{capability.ready ? 'Disponible' : 'À configurer'}</span>
            </li>)}</ul>
          </details>
          {school.status === 'DRAFT' && <button type="button" className="button primary" disabled={!!runner.pending || runner.busy || identity.edited || texts.edited}
            onClick={() => navigate('apercu')}>Continuer la préparation</button>}
          </div>
        </section>}
      </div>}</LoadState>

      <ConfirmDialog open={review !== null} busy={runner.busy} onCancel={() => setReview(null)} onConfirm={() => void confirm()}
        title={review === 'identity' ? 'Vos coordonnées' : 'Relire les textes'}
        confirmLabel={review === 'identity' ? 'Confirmer les coordonnées' : 'J’adopte ces textes'}
        {...(review === 'policy' ? { acknowledgement: 'J’ai relu les deux textes et je les adopte exactement pour mon école.', acknowledged, onAcknowledge: setAcknowledged } : {})}>
        <OutcomeNotice outcome={runner.outcome}
          actions={runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary" onClick={() => { setReview(null); loaded.reload(); }}>Recharger les informations</button> : undefined} />
        {review === 'identity' && idValue && <>
          <p className="dialog-lead">{idValue.name}</p>
          <Facts items={[['E-mail', idValue.contactEmail.trim()], ['Téléphone', idValue.contactPhone.trim() || 'Non renseigné']]} />
          <p className="caption">Ces coordonnées remplaceront celles affichées par votre école.</p>
        </>}
        {review === 'policy' && textValue && <>
          <h3>Information des personnes</h3><p className="policy-copy review-copy">{textValue.noticeText}</p>
          <h3>Conservation des données</h3><p className="policy-copy review-copy">{textValue.retentionText}</p>
          <Facts items={[['Contact pour les données', textValue.contactEmail.trim()]]} />
          <p className="caption">En confirmant, vous adoptez exactement ces textes. Leur version sera conservée.</p>
          {policy?.status === 'APPROVED' && <Notice tone="warning" title="Accords GPS à renouveler" live={false}>
            <p>Cette version met fin aux autorisations GPS en cours. Les élèves devront renouveler leur accord avant un nouvel enregistrement.</p>
          </Notice>}
        </>}
      </ConfirmDialog>
    </div>
  );
}
