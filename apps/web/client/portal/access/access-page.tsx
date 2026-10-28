import { useEffect, useRef } from 'react';
import { ArrowLeft, ArrowRight, Check, ChevronRight, GraduationCap, LockKeyhole, ShieldCheck, UsersRound } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Avatar, AvatarFallback } from '../../components/ui/avatar';
import { Alert, AlertTitle, AlertDescription } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Field, FieldContent, FieldDescription, FieldError, FieldGroup, FieldLabel, FieldLegend, FieldSet } from '../../components/ui/field';
import { Textarea } from '../../components/ui/textarea';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Skeleton } from '../../components/ui/skeleton';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '../../components/ui/tabs';
import { roleLabel } from '../../protocol';
import { filled } from '../../command-core';
import { accessDomains, accessRoles, grantName, useAccessController } from './access-controller';
import './access.css';

const steps = ['Rôles', 'Autorisations', 'Relire'] as const;
const roleIcons = { ADMIN: ShieldCheck, INSTRUCTOR: UsersRound, LEARNER: GraduationCap };
const initials = (name: string) => name.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join('');

export function AccessPilot({ initialEdit = false }: { initialEdit?: boolean }) {
  const state = useAccessController();
  const entered = useRef(false);
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    if (initialEdit && state.canWrite && !entered.current) { entered.current = true; state.startEditing(); }
  }, [initialEdit, state.canWrite]);
  useEffect(() => { heading.current?.focus({ preventScroll: true }); }, [state.mode, state.step]);
  const current = state.current;
  if (!current) return <section className="access-page">
    <h1>Équipe et accès</h1>
    {state.loaded.status === 'loading' ? <div className="access-loading"><Skeleton className="h-12 w-64" /><Skeleton className="h-40 w-full" /></div>
      : state.loaded.status === 'error' ? <Alert variant="destructive"><AlertTitle>Lecture impossible</AlertTitle><AlertDescription>{state.loaded.error}</AlertDescription><Button variant="outline" onClick={state.loaded.reload}>Réessayer</Button></Alert>
      : <div className="access-members">{state.members.map(member => <Button key={member.id} variant="outline" onClick={() => state.select(member.id)}>{state.nameOf(member)}</Button>)}</div>}
  </section>;
  const busy = state.runner.busy || !!state.runner.pending;
  const changedCount = state.changes.rolesAdded.length + state.changes.rolesRemoved.length + state.changes.grantsAdded.length + state.changes.grantsRemoved.length;
  const renderChanges = () => <dl className="access-changes">
    <div><dt>Rôles ajoutés</dt><dd>{state.changes.rolesAdded.length ? state.changes.rolesAdded.map(roleLabel).join(', ') : 'Aucun'}</dd></div>
    <div><dt>Rôles retirés</dt><dd>{state.changes.rolesRemoved.length ? state.changes.rolesRemoved.map(roleLabel).join(', ') : 'Aucun'}</dd></div>
    <div><dt>Autorisations ajoutées</dt><dd>{state.changes.grantsAdded.length ? state.changes.grantsAdded.map(grantName).join(', ') : 'Aucune'}</dd></div>
    <div><dt>Autorisations retirées</dt><dd>{state.changes.grantsRemoved.length ? state.changes.grantsRemoved.map(grantName).join(', ') : 'Aucune'}</dd></div>
  </dl>;

  return <section className="access-page">
    <nav className="access-breadcrumb" aria-label="Fil d’Ariane"><span>Équipe</span><ChevronRight aria-hidden="true" /><span>{state.nameOf(current)}</span></nav>
    <header className="access-heading">
      <div><h1 ref={heading} tabIndex={-1}>{state.mode === 'edit' ? 'Modifier les accès' : 'Accès du membre'}</h1>
        <div className="access-person-line"><Avatar><AvatarFallback>{initials(current.displayName)}</AvatarFallback></Avatar><span>{state.nameOf(current)}</span>{state.self && <Badge variant="secondary">Vous</Badge>}</div>
      </div>
      {state.mode === 'read' && <Button disabled={!state.canWrite} onClick={state.startEditing}>Modifier les accès<ArrowRight data-icon="inline-end" /></Button>}
    </header>

    {state.runner.outcome && <Alert variant={state.runner.outcome.tone === 'error' ? 'destructive' : 'default'}>
      <AlertTitle>{state.runner.outcome.title}</AlertTitle><AlertDescription>{state.runner.outcome.message}</AlertDescription>
      {state.runner.outcome.needsLogin && <Button variant="outline" onClick={() => state.context.login({ reauthenticate: state.runner.outcome?.code === 'REAUTH_REQUIRED' })}>Se reconnecter</Button>}
    </Alert>}
    {state.conflict && <Alert variant="destructive"><AlertTitle>Les accès ont changé</AlertTitle><AlertDescription>Votre saisie est conservée. Relisez la version actuelle avant de refaire le changement.</AlertDescription><Button variant="outline" disabled={busy} onClick={state.cancelEditing}>Repartir des accès actuels</Button></Alert>}
    {state.runner.blockedReason && <Alert><AlertTitle>Confirmation en attente</AlertTitle><AlertDescription>{state.runner.blockedReason}</AlertDescription></Alert>}
    {state.loaded.status === 'error' && <Alert variant="destructive"><AlertTitle>Actualisation impossible</AlertTitle><AlertDescription>{state.loaded.error}</AlertDescription><Button variant="outline" onClick={state.loaded.reload}>Réessayer</Button></Alert>}

    {state.mode === 'read' ? <div className="access-read-layout">
      <div className="access-read-main"><section className="access-read-section"><h2>Rôles dans l’école</h2><div className="access-role-read">{current.roles.map(role => {
        const Icon = roleIcons[role];
        return <div key={role}><span className="access-role-icon"><Icon aria-hidden="true" /></span><span><strong>{roleLabel(role)}</strong><span>{accessRoles.find(item => item.value === role)?.description}</span></span></div>;
      })}</div></section>
        <section className="access-read-section"><h2>Autorisations particulières</h2>
          {current.grants.length ? accessDomains.filter(domain => domain.permissions.some(permission => current.grants.includes(permission.value))).map(domain =>
            <div className="access-domain-read" key={domain.id}><h3>{domain.label}</h3><ul>{domain.permissions.filter(permission => current.grants.includes(permission.value)).map(permission => <li key={permission.value}><Check aria-hidden="true" />{permission.label}</li>)}</ul></div>) : <p className="access-muted">Aucune autorisation particulière.</p>}
        </section>
      </div>
      <aside className="access-context"><LockKeyhole aria-hidden="true" /><h2>{state.context.school.name}</h2><dl><div><dt>État</dt><dd>{current.status === 'ACTIVE' ? 'Accès actif' : 'Accès inactif'}</dd></div></dl>
        {current.status === 'ACTIVE' && !state.self && <Button variant="outline" disabled={!state.canWrite} onClick={state.removeAccess}>Retirer l’accès</Button>}
      </aside>
    </div> : <div className="access-editor-layout">
      <aside className="access-stepper" aria-label="Étapes de modification">
        <ol>{steps.map((step, index) => <li key={step} data-current={state.step === index} data-complete={state.step > index}>
          <Button variant="ghost" disabled={busy || (index > 0 && !!state.rolesProblem)} onClick={() => state.setStep(index)} aria-current={state.step === index ? 'step' : undefined}>
            <span className="access-step-number">{state.step > index ? <Check aria-hidden="true" /> : index + 1}</span><span>{step}</span>
          </Button></li>)}</ol>
        <div className="access-step-context"><LockKeyhole aria-hidden="true" /><span>{state.context.school.name}</span><p>Les accès actuels restent actifs jusqu’à la confirmation.</p></div>
      </aside>
      <form className="access-editor-body" onSubmit={event => { event.preventDefault(); if (state.step < 2) state.next(); else state.review(); }}>
        <div className="access-step-content">
          {state.step === 0 && <FieldSet><FieldLegend>Quel est son rôle dans l’école ?</FieldLegend><FieldDescription>Plusieurs rôles peuvent être associés au même membre.</FieldDescription>
            <FieldGroup className="access-role-options">{accessRoles.map(role => { const Icon = roleIcons[role.value]; return <Field key={role.value} orientation="horizontal" className="access-role-option" data-selected={state.draftRoles.includes(role.value)} data-disabled={!state.canWrite}>
              <span className="access-role-icon"><Icon aria-hidden="true" /></span>
              <FieldContent><FieldLabel htmlFor={`role-${role.value}`}>{roleLabel(role.value)}</FieldLabel><FieldDescription>{role.description}</FieldDescription></FieldContent>
              <Checkbox id={`role-${role.value}`} checked={state.draftRoles.includes(role.value)} disabled={!state.canWrite} onCheckedChange={checked => state.setDraftRoles(values => checked ? [...values, role.value] : values.filter(value => value !== role.value))} />
            </Field>; })}</FieldGroup>
            {state.showErrors && state.rolesProblem && <FieldError>{state.rolesProblem}</FieldError>}
            {state.loseAdmin && <Alert variant="destructive"><AlertTitle>Votre propre accès change</AlertTitle><AlertDescription>Vous ne pourrez plus administrer cette école après confirmation.</AlertDescription></Alert>}
          </FieldSet>}
          {state.step === 1 && <section className="access-permissions"><header><h2>Autorisations particulières</h2><p>Choisissez les actions supplémentaires confiées à ce membre.</p></header>
            <Tabs value={state.domain} onValueChange={value => state.setDomain(String(value))} className="access-domains">
              <TabsList>{accessDomains.map(domain => <TabsTrigger key={domain.id} value={domain.id}>{domain.label}</TabsTrigger>)}</TabsList>
              {accessDomains.map(domain => <TabsContent key={domain.id} value={domain.id}><FieldSet><FieldLegend className="sr-only">{domain.label}</FieldLegend><FieldGroup>
                {domain.permissions.map(permission => <Field key={permission.value} orientation="horizontal" className="access-permission-row" data-disabled={!state.canWrite}>
                  <FieldLabel htmlFor={`permission-${permission.value}`}>{permission.label}</FieldLabel>
                  <Checkbox id={`permission-${permission.value}`} checked={state.draftGrants.includes(permission.value)} disabled={!state.canWrite}
                    onCheckedChange={checked => state.setDraftGrants(values => checked ? [...values, permission.value] : values.filter(value => value !== permission.value))} />
                </Field>)}
              </FieldGroup></FieldSet></TabsContent>)}
            </Tabs>
          </section>}
          {state.step === 2 && <section className="access-review"><header><h2>Relire les changements</h2><p>{state.nameOf(current)} · {state.context.school.name}</p></header>
            {changedCount ? <><p className="access-review-count"><Check aria-hidden="true" />{changedCount} changement{changedCount > 1 ? 's' : ''} à confirmer</p>{renderChanges()}</> : <p className="access-no-changes">Les accès sont identiques à ceux déjà enregistrés.</p>}
            <FieldGroup><Field data-invalid={state.showErrors && !!state.reasonProblem}><FieldLabel htmlFor="access-reason">Motif du changement</FieldLabel>
              <Textarea id="access-reason" value={state.reason} onChange={event => state.setReason(event.target.value)} maxLength={1000} rows={3} disabled={!state.canWrite} aria-invalid={state.showErrors && !!state.reasonProblem} aria-describedby="access-reason-help" />
              <FieldDescription id="access-reason-help">Conservé dans l’historique de l’école.</FieldDescription>{state.showErrors && state.reasonProblem && <FieldError>{state.reasonProblem}</FieldError>}
            </Field></FieldGroup>
          </section>}
        </div>
        <footer className="access-editor-footer"><Button type="button" variant="ghost" onClick={state.cancelEditing} disabled={busy}>Annuler</Button>
          <div>{state.step > 0 && <Button type="button" variant="outline" disabled={busy} onClick={() => state.setStep(state.step - 1)}><ArrowLeft data-icon="inline-start" />Retour</Button>}
            <Button type="submit" disabled={!state.canWrite || (state.step === 2 && !state.changed)}>{state.step < 2 ? 'Continuer' : 'Confirmer les changements'}<ArrowRight data-icon="inline-end" /></Button></div>
        </footer>
      </form>
    </div>}

    <Dialog open={state.confirmation !== null} onOpenChange={(open, details) => { if (busy) { details.cancel(); return; } if (!open) state.closeConfirmation(); }}>
      <DialogContent showCloseButton={!busy}>
        <DialogHeader><DialogTitle>{state.confirmation === 'deactivate' ? 'Retirer l’accès à l’école ?' : 'Confirmer ces accès ?'}</DialogTitle><DialogDescription>{state.nameOf(current)} · {state.context.school.name}</DialogDescription></DialogHeader>
        {state.confirmation === 'deactivate' ? <FieldGroup><Field><FieldLabel htmlFor="deactivate-reason">Motif du retrait</FieldLabel><Textarea id="deactivate-reason" value={state.deactivateReason} onChange={event => state.setDeactivateReason(event.target.value)} maxLength={1000} rows={3} disabled={busy} /></Field></FieldGroup> : <>{renderChanges()}<p className="access-confirm-reason">{state.reason.trim()}</p></>}
        {(state.confirmation === 'deactivate' || state.loseAdmin) && <Field orientation="horizontal"><Checkbox id="access-acknowledge" checked={state.acknowledged} onCheckedChange={value => state.setAcknowledged(value === true)} disabled={busy} /><FieldLabel htmlFor="access-acknowledge">{state.confirmation === 'deactivate' ? 'Cette personne ne pourra plus accéder à l’école.' : 'Je ne pourrai plus administrer cette école.'}</FieldLabel></Field>}
        {state.runner.outcome?.tone === 'error' && <Alert variant="destructive"><AlertTitle>{state.runner.outcome.title}</AlertTitle><AlertDescription>{state.runner.outcome.message}</AlertDescription></Alert>}
        <DialogFooter><Button variant="outline" disabled={busy} onClick={state.closeConfirmation}>Retour</Button><Button disabled={busy || !state.canWrite || ((state.confirmation === 'deactivate' || state.loseAdmin) && !state.acknowledged) || (state.confirmation === 'deactivate' && !filled(state.deactivateReason, 1000))} onClick={() => void state.confirm()}>{busy ? 'Confirmation…' : state.confirmation === 'deactivate' ? 'Retirer l’accès' : 'Confirmer'}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </section>;
}
