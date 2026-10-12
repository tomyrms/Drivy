import { useEffect, useState } from 'react';
import { createCommand } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { administrativeProfileSchema, learnerReadinessSchema, readSchool, type Learner } from '../school-api';
import { SelectField, TextField } from '../ui';
import { useCommandRunner, useLoad } from './context';
import { OutcomeNotice } from './layout';
import { countries, labels, missingCount, profileBody, type Draft, type MissingField } from './profile-completion-model';

/**
 * Le dossier d’un élève incomplet dit ce qui manque et le fait renseigner sur place : chaque information requise
 * avant une leçon a son champ. L’école relit le dossier après l’enregistrement ; le badge et ce bloc partent seuls.
 */
export function ProfileCompletion({ schoolId, learner, canEdit }: { schoolId: string; learner: Learner; canEdit: boolean }) {
  const { revision } = useCommandSnapshot();
  const [draft, setDraft] = useState<Draft>({});
  const runner = useCommandRunner(() => setDraft({}));
  // Un autre élève : rien de la saisie précédente ne le suit.
  useEffect(() => { setDraft({}); }, [learner.id]);
  const loaded = useLoad(async () => {
    const [readiness, profile] = await Promise.all([
      readSchool(schoolId, `learners/${learner.id}/action-readiness`, learnerReadinessSchema, { action: 'PLAN_LESSON' }),
      readSchool(schoolId, `learners/${learner.id}/administrative-profile`, administrativeProfileSchema)]);
    if (readiness.learnerId !== learner.id || profile.learnerId !== learner.id) throw new Error('Réponse inattendue.');
    const fields = readiness.blockers.filter(item => item.code === 'PROFILE_ACTION_REQUIRED' && item.field && item.field in labels)
      .map(item => item.field as MissingField);
    return { fields: [...new Set(fields)], profile };
  }, [schoolId, learner.id, learner.version, revision], `${schoolId}/${learner.id}`);

  // Une lecture en cours ou en panne n’affirme rien : le badge de l’élève suffit.
  const data = loaded.data;
  if (!data || data.fields.length === 0) return null;
  const body = profileBody(data.fields, draft);
  const disabled = !canEdit || runner.busy || !!runner.pending;
  const address = draft.postalAddress ?? { line1: '', postalCode: '', locality: '', countryCode: 'CH' };

  async function save() {
    if (!data || !body || disabled) return;
    await runner.run(createCommand({ schoolId, kind: 'updateAdministrativeProfile', path: `learners/${learner.id}/administrative-profile`,
      ifMatch: data.profile.version, resourceId: data.profile.id, resourceVersion: data.profile.version,
      body: { policyVersionId: data.profile.policyVersionId, ...body } }), 'Le profil de l’élève est à jour.');
  }

  return (
    <section className="profile-completion" aria-labelledby="profile-completion-title">
      <div className="profile-completion-heading">
        <h3 id="profile-completion-title" className="row-title"><span className="action-dot" aria-hidden="true" />Profil à compléter</h3>
        <span className="row-meta">{missingCount(data.fields.length)}</span>
      </div>
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      <form className="form-grid" onSubmit={event => { event.preventDefault(); void save(); }}>
        {data.fields.map(field => field === 'postalAddress'
          ? <fieldset key={field} className="form-grid"><legend className="field-label">{labels[field]}</legend>
              <TextField label="Rue et numéro" value={address.line1} disabled={disabled} autoComplete="address-line1" maxLength={200}
                onChange={line1 => setDraft({ ...draft, postalAddress: { ...address, line1 } })} />
              <div className="form-row">
                <TextField label="Code postal" value={address.postalCode} disabled={disabled} autoComplete="postal-code" maxLength={20}
                  onChange={postalCode => setDraft({ ...draft, postalAddress: { ...address, postalCode } })} />
                <TextField label="Localité" value={address.locality} disabled={disabled} autoComplete="address-level2" maxLength={150}
                  onChange={locality => setDraft({ ...draft, postalAddress: { ...address, locality } })} />
              </div>
              <SelectField label="Pays" value={address.countryCode} disabled={disabled} options={countries}
                onChange={countryCode => setDraft({ ...draft, postalAddress: { ...address, countryCode } })} />
            </fieldset>
          : <TextField key={field} label={labels[field]} value={draft[field] ?? ''} disabled={disabled}
              type={field === 'birthDate' ? 'date' : field === 'contactEmail' ? 'email' : field === 'contactPhone' ? 'tel' : 'text'}
              maxLength={field === 'contactPhone' ? 32 : field === 'contactEmail' ? 254 : 150}
              onChange={value => setDraft({ ...draft, [field]: value })} />)}
        {canEdit
          ? <button type="submit" className="button primary" disabled={disabled || !body}>Enregistrer</button>
          : <p className="caption">À compléter par l’administration.</p>}
      </form>
    </section>
  );
}
