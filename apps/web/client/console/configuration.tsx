import { useState } from 'react';
import { createCommand, filled, isEmail, characters } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { dataPolicySchema, readSchool, readinessSchema, setupSchema } from '../school-api';
import { ConfirmDialog, Facts, Notice, StatusBadge, Symbol, TextArea, TextField, formatDateTime } from '../ui';
import { useCommandRunner, useConsole, useDraft, useLoad } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
import { capabilityTitle, schoolStatus } from './overview';

type Identity = { name: string; contactEmail: string; contactPhone: string };
type PolicyText = { noticeText: string; retentionText: string; contactEmail: string };
type Review = 'identity' | 'policy' | 'activation' | null;

/** Same rules as apps/ios/Drivy/SchoolConfigurationUI: relire, confirmer, puis seulement l’école confirme. */
export function ConfigurationSection() {
  const { schoolId, school } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => setEditingPolicy(false));
  const loaded = useLoad(async () => {
    const [setup, policy, readiness] = await Promise.all([
      readSchool(schoolId, 'setup', setupSchema), readSchool(schoolId, 'data-policy', dataPolicySchema), readSchool(schoolId, 'readiness', readinessSchema)]);
    return { setup, policy, readiness };
  }, [schoolId, revision, school.version]);
  const policy = loaded.data?.policy ?? null;
  const identity = useDraft<Identity>({ name: school.name, contactEmail: school.contactEmail, contactPhone: school.contactPhone ?? '' });
  const texts = useDraft<PolicyText>(policy ? { noticeText: policy.noticeText, retentionText: policy.retentionText, contactEmail: policy.contactEmail ?? school.contactEmail } : null);
  const [editingPolicy, setEditingPolicy] = useState(false);
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
  const showTexts = policy?.status !== 'APPROVED' || editingPolicy || texts.edited;
  const readiness = loaded.data?.readiness;
  const canActivate = mayEdit && school.status === 'DRAFT' && readiness?.activationReady === true && policy?.status === 'APPROVED' && !identity.edited && !texts.edited;
  const status = schoolStatus(school.status);

  function open(kind: Review) { runner.clearOutcome(); setAcknowledged(false); setReview(kind); }
  async function confirm() {
    if (review === 'identity' && idValue && identityValid) {
      const command = createCommand({ schoolId, kind: 'updateSchool', path: '', ifMatch: school.version, resourceVersion: school.version,
        body: { name: idValue.name, timeZone: school.timeZone, contactEmail: idValue.contactEmail.trim(), contactPhone: idValue.contactPhone.trim() ? idValue.contactPhone.trim() : null, impactConfirmed: true } });
      await runner.run(command, 'Les coordonnées de l’école sont enregistrées.');
    } else if (review === 'policy' && textValue && textsValid && policy) {
      const command = createCommand({ schoolId, kind: 'saveDataPolicy', path: 'data-policy', ifMatch: policy.version, resourceVersion: policy.version,
        body: { noticeText: textValue.noticeText, retentionText: textValue.retentionText, contactEmail: textValue.contactEmail.trim(), reviewAcknowledged: true } });
      const result = await runner.run(command, 'Les textes sont adoptés. La version précédente reste conservée.');
      if (result.status === 'confirmed') setEditingPolicy(false);
    } else if (review === 'activation' && canActivate && readiness) {
      const command = createCommand({ schoolId, kind: 'activate', path: 'activate', ifMatch: school.version, resourceVersion: school.version,
        body: { expectedConfigurationVersion: readiness.configurationVersion, reviewAcknowledged: true } });
      await runner.run(command, 'Votre école est activée.');
    }
    setReview(null);
  }
  async function saveProgress() {
    const setup = loaded.data?.setup;
    if (!setup || !mayEdit) return;
    const completed = [...setup.completedSteps];
    if (identityValid && !completed.includes('IDENTITY')) completed.push('IDENTITY');
    if (policy?.status === 'APPROVED' && !completed.includes('DATA')) completed.push('DATA');
    runner.clearOutcome();
    await runner.run(createCommand({ schoolId, kind: 'saveSetup', path: 'setup', ifMatch: setup.version, resourceVersion: setup.version,
      body: { currentStep: 'REVIEW', completedSteps: completed } }), 'L’avancement de la préparation est enregistré.');
  }

  return (
    <div className="section-stack">
      <SectionHeading context={school.name} title={school.status === 'DRAFT' ? 'Préparer l’école' : 'Configuration'}
        description={school.status === 'DRAFT' ? 'Trois étapes : coordonnées, textes d’information, puis activation.' : 'Coordonnées, textes d’information et fonctionnement de l’école.'}
        actions={<StatusBadge tone={status.tone} symbol={school.status === 'ACTIVE' ? 'check' : 'clock'}>{status.label}</StatusBadge>} />
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome}
        actions={runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary" onClick={loaded.reload}>Recharger les informations</button> : undefined} />
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}

      <LoadState loaded={loaded} label="Vérification de l’école…">{data => <div className="config-grid">
        <section className="panel form-panel" aria-labelledby="identity-title">
          <div className="panel-head"><h2 id="identity-title" className="section-title">Coordonnées</h2></div>
          {idValue && identityErrors && <form className="form-grid" onSubmit={event => { event.preventDefault(); if (identityValid && identity.edited && mayEdit) open('identity'); }}>
            <TextField label="Nom de l’école" value={idValue.name} onChange={name => identity.setDraft({ ...idValue, name })} disabled={!mayEdit}
              autoComplete="organization" error={identity.edited ? identityErrors.name : null} />
            <TextField label="E-mail de l’école" type="email" value={idValue.contactEmail} onChange={contactEmail => identity.setDraft({ ...idValue, contactEmail })}
              disabled={!mayEdit} autoComplete="email" error={identity.edited ? identityErrors.contactEmail : null} />
            <TextField label="Téléphone" type="tel" required={false} value={idValue.contactPhone} onChange={contactPhone => identity.setDraft({ ...idValue, contactPhone })}
              disabled={!mayEdit} autoComplete="tel" error={identityErrors.contactPhone} />
            <Facts items={[['Fuseau horaire', school.timeZone]]} />
            {school.status === 'ACTIVE' && <p className="caption">Le fuseau d’une école active ne se change pas ici : il demande une analyse d’impact dédiée.</p>}
            <div className="button-row compact">
              <button type="submit" className={identity.edited ? 'button primary' : 'button secondary'} disabled={!mayEdit || !identityValid || !identity.edited}>Relire les modifications</button>
              {identity.edited && <button type="button" className="button quiet" onClick={identity.reset}>Revenir aux valeurs de l’école</button>}
            </div>
            {!identity.edited && <p className="caption">Modifiez un champ pour relire puis confirmer les nouvelles coordonnées.</p>}
          </form>}
        </section>

        <section className="panel form-panel" aria-labelledby="policy-title">
          <div className="panel-head">
            <h2 id="policy-title" className="section-title">Information et conservation</h2>
            <StatusBadge tone={data.policy.status === 'APPROVED' ? 'success' : 'neutral'} symbol={data.policy.status === 'APPROVED' ? 'check' : 'file'}>
              {data.policy.status === 'APPROVED' ? `Version ${data.policy.version} adoptée` : 'Textes à préparer'}</StatusBadge>
          </div>
          {data.policy.approvedAt && <p className="caption">Adoptée le {formatDateTime(data.policy.approvedAt, school.timeZone)}.</p>}
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
            <TextArea label="Information des personnes" rows={8} maxLength={20_000} value={textValue.noticeText} disabled={!mayEdit}
              onChange={noticeText => texts.setDraft({ ...textValue, noticeText })} error={texts.edited ? textErrors.noticeText : null} />
            <TextArea label="Conservation des données" rows={6} maxLength={20_000} value={textValue.retentionText} disabled={!mayEdit}
              onChange={retentionText => texts.setDraft({ ...textValue, retentionText })} error={texts.edited ? textErrors.retentionText : null} />
            <TextField label="Contact pour les données" type="email" value={textValue.contactEmail} disabled={!mayEdit}
              onChange={contactEmail => texts.setDraft({ ...textValue, contactEmail })} error={texts.edited ? textErrors.contactEmail : null} />
            <p className="caption">L’adoption s’effectue après relecture des deux textes. La version précédente reste conservée.</p>
            <div className="button-row compact">
              <button type="submit" className={!identity.edited && (texts.edited || data.policy.status !== 'APPROVED') ? 'button primary' : 'button secondary'} disabled={!mayEdit || !textsValid || (data.policy.status === 'APPROVED' && !texts.edited)}>Relire et adopter les textes</button>
              {(editingPolicy || texts.edited) && data.policy.status === 'APPROVED' &&
                <button type="button" className="button quiet" onClick={() => { texts.reset(); setEditingPolicy(false); }}>Abandonner cette version</button>}
            </div>
          </form>}
        </section>

        <section className="panel form-panel wide" aria-labelledby="activation-title">
          <div className="panel-head">
            <h2 id="activation-title" className="section-title">{school.status === 'ACTIVE' ? 'Fonctionnement' : 'Activation'}</h2>
            <button type="button" className="button quiet" onClick={loaded.reload} disabled={loaded.status === 'loading'}><Symbol kind="refresh" bare />Actualiser la vérification</button>
          </div>
          {school.status === 'DRAFT' && (data.readiness.activationReady
            ? <Notice tone="success" title="Préparation vérifiée" live={false}><p>L’école peut être activée.</p></Notice>
            : <ul className="blocker-list">{data.readiness.activationBlockers.map(item => <li key={item.code}><Symbol kind="dot" bare />{item.message}</li>)}</ul>)}
          {(identity.edited || texts.edited) && <Notice tone="warning" title="Modifications non confirmées" live={false}><p>Des modifications attendent encore votre confirmation.</p></Notice>}
          <ul className="plain-list">{data.readiness.capabilities.map(capability => <li key={capability.capability}>
            <StatusBadge tone={capability.ready ? 'success' : 'neutral'} symbol={capability.ready ? 'check' : 'dot'}>{capability.ready ? 'Disponible' : 'À configurer'}</StatusBadge>
            <span className="row-title">{capabilityTitle(capability.capability)}</span>
          </li>)}</ul>
          <div className="button-row compact">
            {school.status === 'DRAFT' && <button type="button" className={canActivate ? 'button primary' : 'button secondary'} disabled={!canActivate} onClick={() => open('activation')}>Relire et activer l’école</button>}
            {data.setup.status !== 'COMPLETED' && <button type="button" className="button secondary" onClick={() => void saveProgress()}
              disabled={!mayEdit || identity.edited || texts.edited}>Enregistrer l’avancement</button>}
          </div>
          {school.status === 'DRAFT' && !canActivate && <p className="caption">
            {runner.pending ? runner.blockedReason : identity.edited || texts.edited ? 'Confirmez ou abandonnez d’abord les modifications en cours.'
              : 'L’activation devient possible quand les éléments ci-dessus sont complétés.'}</p>}
          {school.status === 'DRAFT' && <p className="caption">L’activation ouvre l’espace de l’école. Les formations et les cours se préparent ensuite.</p>}
        </section>
      </div>}</LoadState>

      <ConfirmDialog open={review !== null} busy={runner.busy} onCancel={() => setReview(null)} onConfirm={() => void confirm()}
        title={review === 'identity' ? 'Vos coordonnées' : review === 'policy' ? 'Relire les textes' : 'Activer l’école'}
        confirmLabel={review === 'identity' ? 'Confirmer les coordonnées' : review === 'policy' ? 'J’adopte ces textes' : 'Activer mon école'}
        {...(review === 'policy' ? { acknowledgement: 'J’ai relu les deux textes et je les adopte exactement pour mon école.', acknowledged, onAcknowledge: setAcknowledged } : {})}>
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
        </>}
        {review === 'activation' && <>
          <p className="dialog-lead">{school.name}</p>
          <p>Les coordonnées et les textes d’information ont été vérifiés. L’activation ouvre l’espace de l’école à ses membres.</p>
          <p className="caption">Les formations, réservations et cours se créent séparément.</p>
        </>}
      </ConfirmDialog>
    </div>
  );
}
