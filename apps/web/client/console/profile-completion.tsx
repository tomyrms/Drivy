import { useEffect, useRef, useState } from 'react';
import { createCommand, isCivilDate, isEmail } from '../command-core';
import { civilDateIn } from '../agenda-model';
import { useCommandSnapshot } from '../command-store';
import { administrativeProfileSchema, learnerReadinessSchema, readSchool, type Learner } from '../school-api';
import { Loading, Notice, SelectField, Symbol, TextField } from '../ui';
import { useCommandRunner, useConsole, useLoad, useUnsavedChanges } from './context';
import { OutcomeNotice, ReadRetry } from './layout';
import { countries, labels, missingCount, profileBody, type Draft, type MissingField } from './profile-completion-model';

/**
 * Le dossier d’un élève incomplet dit ce qui manque et le fait renseigner sur place : chaque information requise
 * avant une leçon a son champ. L’école relit le dossier après l’enregistrement ; le badge et ce bloc partent seuls.
 */
export function ProfileCompletion({ schoolId, learner, canEdit }: { schoolId: string; learner: Learner; canEdit: boolean }) {
  const { school } = useConsole();
  const { revision } = useCommandSnapshot();
  const [draft, setDraft] = useState<Draft>({});
  const [submitted, setSubmitted] = useState(false);
  const form = useRef<HTMLFormElement>(null);
  const runner = useCommandRunner(() => { setDraft({}); setSubmitted(false); });
  useUnsavedChanges(Object.keys(draft).length > 0 && !runner.busy && !runner.pending);
  // Un autre élève : rien de la saisie précédente ne le suit.
  useEffect(() => { setDraft({}); setSubmitted(false); }, [learner.id]);
  const loaded = useLoad(async () => {
    const [readiness, profile] = await Promise.all([
      readSchool(schoolId, `learners/${learner.id}/action-readiness`, learnerReadinessSchema, { action: 'PLAN_LESSON' }),
      readSchool(schoolId, `learners/${learner.id}/administrative-profile`, administrativeProfileSchema)]);
    if (readiness.learnerId !== learner.id || profile.learnerId !== learner.id) throw new Error('Réponse inattendue.');
    const fields = readiness.blockers.filter(item => item.code === 'PROFILE_ACTION_REQUIRED' && item.field && item.field in labels)
      .map(item => item.field as MissingField);
    return { fields: [...new Set(fields)], profile };
  }, [schoolId, learner.id, learner.version, revision], `${schoolId}/${learner.id}`);

  const data = loaded.data;
  if (loaded.status === 'loading' && !data) return <Loading label="Vérification des informations manquantes…" />;
  if (loaded.status === 'error') return <Notice tone="error" title="Informations manquantes indisponibles" actions={<ReadRetry loaded={loaded} />}><p>{loaded.error}</p></Notice>;
  if (!data || data.fields.length === 0) return <Notice tone="info" title="Profil à vérifier" live={false} actions={<button type="button" className="button secondary" onClick={loaded.reload}>Actualiser le profil</button>}>
    <p>Aucune information administrative à compléter n’a été trouvée pour la planification. L’élève peut vérifier les étapes restantes dans son profil Drivy.</p>
  </Notice>;
  const body = profileBody(data.fields, draft);
  const disabled = !canEdit || runner.busy || !!runner.pending || loaded.status !== 'ready';
  const address = draft.postalAddress ?? { line1: '', postalCode: '', locality: '', countryCode: 'CH' };
  const fieldProblem = (field: Exclude<MissingField, 'postalAddress'>) => {
    const value = draft[field]?.trim();
    if (!value) return 'Renseignez cette information.';
    if (field === 'contactEmail' && !isEmail(value)) return 'Indiquez une adresse e-mail valide.';
    if (field === 'birthDate' && (!isCivilDate(value) || value > civilDateIn(school.timeZone))) return 'Indiquez une date de naissance valide, non future.';
    return null;
  };
  const invalid = data.fields.some(field => field === 'postalAddress' ? Object.values(address).some(value => !value.trim()) : fieldProblem(field) !== null);

  async function save() {
    setSubmitted(true);
    if (!data || !body || disabled || invalid) {
      if (!disabled) window.requestAnimationFrame(() => form.current?.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus());
      return;
    }
    await runner.run(createCommand({ schoolId, kind: 'updateAdministrativeProfile', path: `learners/${learner.id}/administrative-profile`,
      ifMatch: data.profile.version, resourceId: data.profile.id, resourceVersion: data.profile.version,
      body: { policyVersionId: data.profile.policyVersionId, ...body } }), 'Le profil de l’élève est à jour.');
  }

  return (
    <section className="profile-completion" aria-labelledby="profile-completion-title">
      <div className="profile-completion-heading">
        <h2 id="profile-completion-title" className="row-title"><span className="action-dot" aria-hidden="true" />Profil à compléter</h2>
        <span className="row-meta">{missingCount(data.fields.length)}</span>
      </div>
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      <form ref={form} className="form-grid profile-completion-fields" noValidate onSubmit={event => { event.preventDefault(); void save(); }}>
        {data.fields.map(field => field === 'postalAddress'
          ? <fieldset key={field} className="form-grid"><legend className="field-label">{labels[field]}</legend>
              <TextField label="Rue et numéro" value={address.line1} disabled={disabled} autoComplete="address-line1" maxLength={200}
                error={submitted && !address.line1.trim() ? 'Indiquez la rue et le numéro.' : null}
                onChange={line1 => setDraft({ ...draft, postalAddress: { ...address, line1 } })} />
              <div className="form-row">
                <TextField label="Code postal" value={address.postalCode} disabled={disabled} autoComplete="postal-code" maxLength={20}
                  error={submitted && !address.postalCode.trim() ? 'Indiquez le code postal.' : null}
                  onChange={postalCode => setDraft({ ...draft, postalAddress: { ...address, postalCode } })} />
                <TextField label="Localité" value={address.locality} disabled={disabled} autoComplete="address-level2" maxLength={150}
                  error={submitted && !address.locality.trim() ? 'Indiquez la localité.' : null}
                  onChange={locality => setDraft({ ...draft, postalAddress: { ...address, locality } })} />
              </div>
              <SelectField label="Pays" value={address.countryCode} disabled={disabled} options={countries}
                onChange={countryCode => setDraft({ ...draft, postalAddress: { ...address, countryCode } })} />
            </fieldset>
          : <TextField key={field} label={labels[field]} value={draft[field] ?? ''} disabled={disabled}
              error={submitted ? fieldProblem(field) : null}
              type={field === 'birthDate' ? 'date' : field === 'contactEmail' ? 'email' : field === 'contactPhone' ? 'tel' : 'text'}
              maxLength={field === 'contactPhone' ? 32 : field === 'contactEmail' ? 254 : 150}
              onChange={value => setDraft({ ...draft, [field]: value })} />)}
        {canEdit
          ? <button type="submit" className="button primary" disabled={disabled} aria-busy={runner.busy}><Symbol kind="check" bare />Enregistrer le profil</button>
          : <p className="caption">À compléter par l’administration.</p>}
      </form>
    </section>
  );
}
