import { ArrowRight } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Field, FieldContent, FieldDescription, FieldError, FieldGroup, FieldLabel, FieldLegend, FieldSet } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { offeringLabel } from '../../invitation-model';
import { roleLabel } from '../../protocol';
import { accessRoles } from '../access/access-controller';
import { PortalSelect } from '../components/portal-select';
import { portalSections } from '../pages';
import type { InvitationsState } from './use-invitations';

/** Creating a learner code: which licences, which instructor. The recap comes next, before anything is issued. */
export function CodeForm({ state }: { state: InvitationsState }) {
  const { navigate } = state.context;
  const locked = !state.canWrite;
  return <form className="invitation-form" onSubmit={event => { event.preventDefault(); state.review(); }} noValidate>
    <FieldGroup>
      <FieldSet><FieldLegend>Permis</FieldLegend>
        <div className="invitation-choices">{state.offerings.map(offering => <Field key={offering.id} orientation="horizontal" className="invitation-choice" data-selected={state.offeringIds.includes(offering.id)}>
          <Checkbox id={`offering-${offering.id}`} checked={state.offeringIds.includes(offering.id)} disabled={locked}
            onCheckedChange={checked => state.setOfferingIds(ids => checked ? [...ids, offering.id] : ids.filter(id => id !== offering.id))} />
          <FieldLabel htmlFor={`offering-${offering.id}`}>{offeringLabel(offering, state.offerings)}</FieldLabel></Field>)}</div>
      </FieldSet>
      <PortalSelect id="invitation-instructor" label="Moniteur" searchable placeholder="Choisir un moniteur" disabled={locked} value={state.instructorId || null}
        onValueChange={value => state.setInstructorId(value ?? '')} options={state.instructors.map(item => ({ value: item.id, label: state.instructorName(item) }))}
        emptyText="Aucun moniteur actif" />
      {state.showErrors && state.trainingError && <FieldError>{state.trainingError}</FieldError>}
    </FieldGroup>
    {state.offerings.length === 0 && state.loaded.status === 'ready' && <Alert><AlertTitle>Aucune offre ouverte</AlertTitle><AlertDescription>Activez une offre pour créer un code élève.</AlertDescription>
      {portalSections.includes('offres') && <div className="invitation-alert-actions"><Button variant="outline" onClick={() => navigate('offres')}>Ouvrir les offres</Button></div>}</Alert>}
    {state.offerings.length > 0 && state.instructors.length === 0 && state.loaded.status === 'ready' && <Alert><AlertTitle>Aucun moniteur actif</AlertTitle><AlertDescription>Donnez le rôle Moniteur à un membre actif.</AlertDescription>
      <div className="invitation-alert-actions"><Button variant="outline" onClick={() => navigate('equipe')}>Ouvrir l’équipe</Button></div></Alert>}
    <FormActions state={state} />
  </form>;
}

/** Inviting by e-mail: an address and the roles proposed, within what the viewer may propose. */
export function EmailForm({ state }: { state: InvitationsState }) {
  const locked = !state.canWrite;
  return <form className="invitation-form" onSubmit={event => { event.preventDefault(); state.review(); }} noValidate>
    <FieldGroup>
      <Field data-invalid={state.showErrors && !!state.emailError}><FieldLabel htmlFor="invitation-email">Adresse e-mail</FieldLabel>
        <Input id="invitation-email" type="email" inputMode="email" autoComplete="off" maxLength={254} value={state.email} onChange={event => state.setEmail(event.target.value)} disabled={locked}
          aria-invalid={state.showErrors && !!state.emailError} />
        {state.showErrors && state.emailError && <FieldError>{state.emailError}</FieldError>}</Field>
      <FieldSet><FieldLegend>Rôles proposés</FieldLegend>
        <div className="invitation-choices">{accessRoles.filter(role => state.proposable.includes(role.value)).map(role => <Field key={role.value} orientation="horizontal" className="invitation-choice" data-selected={state.invitedRoles.includes(role.value)}>
          <Checkbox id={`invited-${role.value}`} checked={state.invitedRoles.includes(role.value)} disabled={locked}
            onCheckedChange={checked => state.setInvitedRoles(values => checked ? [...values, role.value] : values.filter(value => value !== role.value))} />
          <FieldContent><FieldLabel htmlFor={`invited-${role.value}`}>{roleLabel(role.value)}</FieldLabel><FieldDescription>{role.description}</FieldDescription></FieldContent></Field>)}</div>
        {state.showErrors && state.roleError && <FieldError>{state.roleError}</FieldError>}
      </FieldSet>
    </FieldGroup>
    <FormActions state={state} />
  </form>;
}

function FormActions({ state }: { state: InvitationsState }) {
  return <footer className="invitation-form-actions">
    <Button type="button" variant="ghost" disabled={state.busy} onClick={state.cancelCreation}>Annuler</Button>
    <Button type="submit" disabled={!state.canWrite}>Relire<ArrowRight data-icon="inline-end" aria-hidden="true" /></Button>
  </footer>;
}
