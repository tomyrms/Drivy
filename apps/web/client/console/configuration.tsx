import { useState } from 'react';
import { createCommand, filled, isEmail, characters } from '../command-core';
import { useCommandSnapshot, type SubmitResult } from '../command-store';
import { readSchool, readinessSchema } from '../school-api';
import { ConfirmDialog, Facts, Notice, StatusBadge, Symbol, TextField } from '../ui';
import { useCommandRunner, useConsole, useDraft, useLoad } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
import { schoolStatus } from './overview';

type Identity = { name: string; contactEmail: string; contactPhone: string };
type Review = 'identity' | null;

/** Maintenance des coordonnées ; la première activation reste dans le guide. */
export function ConfigurationSection() {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => setEditingIdentity(false));
  const loaded = useLoad(async () => ({ readiness: await readSchool(schoolId, 'readiness', readinessSchema) }), [schoolId, revision, school.version]);
  const identity = useDraft<Identity>({ name: school.name, contactEmail: school.contactEmail, contactPhone: school.contactPhone ?? '' });
  const [editingIdentity, setEditingIdentity] = useState(false);
  const [review, setReview] = useState<Review>(null);

  const mayEdit = loaded.data !== undefined && !runner.pending && !runner.busy;
  const idValue = identity.draft;
  const identityErrors = idValue ? {
    name: filled(idValue.name, 150) ? null : 'Indiquez le nom de l’école (150 caractères au plus).',
    contactEmail: isEmail(idValue.contactEmail.trim()) ? null : 'Indiquez une adresse e-mail valide.',
    contactPhone: characters(idValue.contactPhone) <= 32 ? null : '32 caractères au plus.',
  } : null;
  const identityValid = !!identityErrors && Object.values(identityErrors).every(value => value === null);
  const showIdentity = editingIdentity || identity.edited || school.status === 'DRAFT';
  const status = schoolStatus(school.status);

  function open(kind: Review) { runner.clearOutcome(); setReview(kind); }
  async function confirm() {
    let result: SubmitResult | undefined;
    if (review === 'identity' && idValue && identityValid) {
      const command = createCommand({ schoolId, kind: 'updateSchool', path: '', ifMatch: school.version, resourceVersion: school.version,
        body: { name: idValue.name, timeZone: school.timeZone, contactEmail: idValue.contactEmail.trim(), contactPhone: idValue.contactPhone.trim() ? idValue.contactPhone.trim() : null, impactConfirmed: true } });
      result = await runner.run(command, 'Les coordonnées de l’école sont enregistrées.');
      if (result.status === 'confirmed') setEditingIdentity(false);
    }
    // A refusal stays in the dialog, next to the action it concerns, with the typed values.
    if (result?.status !== 'rejected') setReview(null);
  }

  return (
    <div className="section-stack">
      <SectionHeading context="Réglages" title="École"
        actions={school.status !== 'ACTIVE' ? <StatusBadge tone={status.tone} symbol="clock">{status.label}</StatusBadge> : undefined} />
      {review === null && <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome}
        actions={runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary" onClick={loaded.reload}>Recharger les informations</button> : undefined} />}
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}

      <LoadState loaded={loaded} label="Vérification de l’école…">{() => <div className="config-sections">
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

        {school.status === 'DRAFT' && <section className="settings-section" aria-labelledby="activation-title">
          <div className="settings-section-heading">
            <h2 id="activation-title" className="section-title">Préparation</h2>
            <button type="button" className="button quiet" onClick={loaded.reload} disabled={loaded.status === 'loading'}><Symbol kind="refresh" bare />Actualiser</button>
          </div>
          <div className="settings-section-body">
          {identity.edited && <Notice tone="warning" title="Modifications non confirmées" live={false}><p>Des modifications attendent encore votre confirmation.</p></Notice>}
          <div className="button-row compact">
            <button type="button" className="button primary" disabled={!mayEdit || identity.edited} onClick={() => navigate('apercu')}>Continuer la préparation</button>
          </div>
          </div>
        </section>}
      </div>}</LoadState>

      <ConfirmDialog open={review !== null} busy={runner.busy} onCancel={() => setReview(null)} onConfirm={() => void confirm()}
        title="Vos coordonnées" confirmLabel="Confirmer les coordonnées">
        <OutcomeNotice outcome={runner.outcome}
          actions={runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary" onClick={() => { setReview(null); loaded.reload(); }}>Recharger les informations</button> : undefined} />
        {review === 'identity' && idValue && <>
          <p className="dialog-lead">{idValue.name}</p>
          <Facts items={[['E-mail', idValue.contactEmail.trim()], ['Téléphone', idValue.contactPhone.trim() || 'Non renseigné']]} />
          <p className="caption">Ces coordonnées remplaceront celles affichées par votre école.</p>
        </>}
      </ConfirmDialog>
    </div>
  );
}
