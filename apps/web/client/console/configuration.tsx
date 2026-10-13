import { useRef, useState } from 'react';
import { createCommand, filled, isEmail, characters } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { readSchool, readinessSchema } from '../school-api';
import { Facts, StatusBadge, Symbol, TextField } from '../ui';
import { useCommandRunner, useConsole, useDraft, useLoad } from './context';
import { LoadState, OutcomeNotice, SectionHeading } from './layout';
import { schoolStatus } from './overview';

type Identity = { name: string; contactEmail: string; contactPhone: string };

/** Everyday coordinates save directly; adoption, access and destructive commands retain their review. */
export function ConfigurationSection() {
  const { schoolId, school, navigate, reloadSchool } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner();
  const loaded = useLoad(async () => ({ readiness: await readSchool(schoolId, 'readiness', readinessSchema) }), [schoolId, revision, school.version]);
  const identity = useDraft<Identity>({ name: school.name, contactEmail: school.contactEmail, contactPhone: school.contactPhone ?? '' });
  const [attempted, setAttempted] = useState(false);
  const form = useRef<HTMLFormElement>(null);
  const mayEdit = loaded.data !== undefined && !runner.pending && !runner.busy;
  const value = identity.draft;
  const errors = value ? {
    name: filled(value.name, 150) ? null : 'Indiquez le nom de l’école (150 caractères au plus).',
    contactEmail: isEmail(value.contactEmail.trim()) ? null : 'Indiquez une adresse e-mail valide.',
    contactPhone: characters(value.contactPhone) <= 32 ? null : '32 caractères au plus.',
  } : null;
  const valid = !!errors && Object.values(errors).every(error => error === null);
  const status = schoolStatus(school.status);
  async function save() {
    setAttempted(true);
    if (!valid || !value) { requestAnimationFrame(() => form.current?.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus()); return; }
    if (!mayEdit || !identity.edited) return;
    const normalized = { name: value.name.trim(), contactEmail: value.contactEmail.trim(), contactPhone: value.contactPhone.trim() };
    const result = await runner.run(createCommand({ schoolId, kind: 'updateSchool', path: '', ifMatch: school.version, resourceVersion: school.version,
      body: { ...normalized, contactPhone: normalized.contactPhone || null, timeZone: school.timeZone, impactConfirmed: true } }), 'Les coordonnées de l’école sont enregistrées.');
    if (result.status === 'confirmed') { identity.markSaved(normalized); setAttempted(false); }
  }
  return <div className="section-stack">
    <SectionHeading title="École"
      actions={school.status !== 'ACTIVE' ? <StatusBadge tone={status.tone} symbol="clock">{status.label}</StatusBadge> : undefined} />
    <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome}
      actions={runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary" onClick={() => { loaded.reload(); void reloadSchool(); }}>Recharger les informations</button> : undefined} />
    {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
    <LoadState loaded={loaded} label="Vérification de l’école…">{() => <div className="config-sections">
      <section className="settings-section" aria-labelledby="identity-title">
        <div className="settings-section-heading"><h2 id="identity-title" className="section-title">Coordonnées</h2></div>
        <div className="settings-section-body">
          {value && errors && <form ref={form} className="form-grid" noValidate onSubmit={event => { event.preventDefault(); void save(); }}>
            <TextField id="school-name" label="Nom de l’école" value={value.name} onChange={name => identity.setDraft({ ...value, name })}
              disabled={!mayEdit} autoComplete="organization" maxLength={150} error={attempted ? errors.name : null} />
            <TextField id="school-email" label="E-mail de l’école" type="email" value={value.contactEmail} onChange={contactEmail => identity.setDraft({ ...value, contactEmail })}
              disabled={!mayEdit} autoComplete="email" error={attempted ? errors.contactEmail : null} />
            <TextField id="school-phone" label="Téléphone" type="tel" required={false} value={value.contactPhone} onChange={contactPhone => identity.setDraft({ ...value, contactPhone })}
              disabled={!mayEdit} autoComplete="tel" maxLength={32} error={attempted ? errors.contactPhone : null} />
            <div className="form-save-bar">
              <p className="save-state" role="status">{runner.busy ? 'Enregistrement…' : identity.edited ? 'Modifications non enregistrées' : 'À jour'}</p>
              <div className="button-row compact"><button type="submit" className="button primary" disabled={!mayEdit || !identity.edited} aria-busy={runner.busy}>
                {runner.busy ? 'Enregistrement…' : 'Enregistrer'}</button>
                {identity.edited && <button type="button" className="button quiet" disabled={runner.busy} onClick={() => { identity.reset(); setAttempted(false); }}>Annuler</button>}
              </div>
            </div>
          </form>}
        </div>
      </section>
      <section className="settings-section" aria-labelledby="timezone-title"><div className="settings-section-heading"><h2 id="timezone-title" className="section-title">Horaires de référence</h2></div>
        <div className="settings-section-body"><Facts items={[["Fuseau horaire", school.timeZone]]} /></div>
      </section>
      {school.status === 'DRAFT' && <section className="settings-section" aria-labelledby="activation-title">
        <div className="settings-section-heading"><h2 id="activation-title" className="section-title">Préparation</h2></div>
        <div className="settings-section-body"><button type="button" className="button secondary" onClick={() => navigate('apercu')}>Continuer la préparation</button></div>
      </section>}
    </div>}</LoadState>
  </div>;
}
