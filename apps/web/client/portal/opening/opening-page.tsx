import { useEffect, useRef } from 'react';
import { Copy, Link, Plus } from 'lucide-react';
import type { OpeningLink, OpeningReceipt } from '../../school-opening-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldError, FieldGroup, FieldLabel, FieldSet } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Skeleton } from '../../components/ui/skeleton';
import { AccountEntryPanel } from '../entry/account-entry-panel';
import { EntryFrame } from '../entry/entry-frame';
import { entryRoutes, type EntryRoutes } from '../entry/entry-model';
import { useSchoolOpening, type SchoolOpeningState } from './use-school-opening';
import './opening.css';

const dateTime = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
const statuses = { AVAILABLE: 'Disponible', USED: 'Utilisé', EXPIRED: 'Expiré', REVOKED: 'Révoqué' } as const;

/** Full standalone surface for school opening and operator links, using the same account entry as #319. */
export function SchoolOpeningPage({ link, operator = false, routes = entryRoutes, destination }: {
  link: OpeningLink; operator?: boolean; routes?: EntryRoutes; destination?: (receipt: OpeningReceipt) => string;
}) {
  const state = useSchoolOpening(link, operator, destination);
  useEffect(() => { document.title = operator ? 'Liens d’ouverture · Drivy' : 'Créer votre école · Drivy'; }, [operator]);
  const busy = !state.loaded || state.busy;
  return <EntryFrame home={routes.account} width={operator && state.session?.authenticated ? 'wide' : 'narrow'} busy={busy}>
    <div className="opening-page">
      {(state.session?.authenticated || !state.loaded || link.error) && <header className="opening-heading"><h1>{operator ? 'Liens d’ouverture' : 'Créer votre école'}</h1></header>}
      {state.error && <Alert variant="destructive"><AlertTitle>{operator ? 'Action impossible' : 'Ouverture à vérifier'}</AlertTitle>
        <AlertDescription>{state.error}</AlertDescription><Button variant="outline" className="mt-3" disabled={busy} onClick={() => void state.boot()}>Actualiser</Button></Alert>}
      {!state.loaded && <div className="grid gap-4" role="status" aria-label="Chargement de l’ouverture"><Skeleton className="h-12 w-full" /><Skeleton className="h-48 w-full" /></div>}
      {state.loaded && !state.session?.authenticated && !link.error && <AccountEntryPanel routes={routes}
        {...(!operator && link.token ? { initialCode: link.token } : {})} onSignedIn={() => void state.boot()} />}
      {state.loaded && state.session?.authenticated && <>
        <div className="opening-identity"><div><strong>{state.session.user?.displayName}</strong><span>{state.session.user?.email}</span></div>
          <Button variant="ghost" disabled={busy || state.uncertain} onClick={() => void state.changeAccount()}>Changer de compte</Button></div>
        {state.result ? <p role="status">Ouverture de votre école…</p>
          : state.ready && (operator ? <OperatorLinks state={state} /> : <SchoolFields state={state} />)}
      </>}
    </div>
    <Dialog open={state.revoking !== null} onOpenChange={(open, details) => { if (state.busy) details.cancel(); else if (!open) state.setRevoking(null); }}>
      <DialogContent showCloseButton={!state.busy}><DialogHeader><DialogTitle>Révoquer ce lien d’ouverture ?</DialogTitle>
        <DialogDescription>Le lien créé le {state.revoking ? dateTime(state.revoking.createdAt) : ''} ne permettra plus de créer une école.</DialogDescription></DialogHeader>
        {state.error && <Alert variant="destructive"><AlertTitle>Révocation non confirmée</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert>}
        <DialogFooter><Button variant="outline" disabled={state.busy} onClick={() => state.setRevoking(null)}>Garder le lien</Button>
          <Button variant="destructive" disabled={state.busy} onClick={() => void state.revoke()}>Révoquer le lien</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </EntryFrame>;
}

function SchoolFields({ state }: { state: SchoolOpeningState }) {
  const form = useRef<HTMLFormElement>(null);
  useEffect(() => {
    // Validation may finish while perform() still disables the fieldset. Keep the target
    // until the controls are enabled, rather than consuming a focus request that did nothing.
    if (!state.invalidField || state.busy || state.uncertain) return;
    const input = form.current?.elements.namedItem(state.invalidField);
    if (!(input instanceof HTMLInputElement) || input.matches(':disabled')) return;
    input.focus();
    if (document.activeElement === input) state.setInvalidField(null);
  }, [state.invalidField, state.busy, state.uncertain, state.setInvalidField]);
  const field = (name: 'schoolName' | 'contactEmail' | 'contactPhone' | 'displayName' | 'timeZone', label: string, type: 'text' | 'email' | 'tel', autoComplete: string, maxLength: number) =>
    <Field data-invalid={!!state.fieldErrors[name]}>
      <FieldLabel htmlFor={`opening-${name}`}>{label}</FieldLabel>
      <Input id={`opening-${name}`} name={name} type={type} autoComplete={autoComplete} maxLength={maxLength} required={name !== 'contactPhone'}
        value={state.fields[name] ?? ''} onChange={event => state.update(name, name === 'contactPhone' ? event.target.value || null : event.target.value)} aria-invalid={!!state.fieldErrors[name]}
        aria-describedby={state.fieldErrors[name] ? `opening-${name}-error` : undefined} />
      {state.fieldErrors[name] && <FieldError id={`opening-${name}-error`}>{state.fieldErrors[name]}</FieldError>}
    </Field>;
  return <form ref={form} className="opening-form" noValidate onSubmit={event => { event.preventDefault(); void state.createSchool(); }}>
    <FieldSet disabled={state.busy || state.uncertain}><FieldGroup>
      {field('schoolName', 'Nom de l’auto-école', 'text', 'organization', 150)}
      {field('contactEmail', 'E-mail de l’école', 'email', 'email', 254)}
      {field('contactPhone', 'Téléphone (facultatif)', 'tel', 'tel', 32)}
      {field('displayName', 'Nom du responsable', 'text', 'name', 200)}
      {field('timeZone', 'Fuseau horaire', 'text', 'off', 100)}
      <Field orientation="horizontal" className="opening-checkbox"><Checkbox id="opening-instructs" disabled={state.busy || state.uncertain} checked={state.fields.instructs} onCheckedChange={checked => state.update('instructs', checked === true)} />
        <FieldLabel htmlFor="opening-instructs">Je donne aussi des leçons</FieldLabel></Field>
    </FieldGroup></FieldSet>
    {state.uncertain && <Alert><AlertTitle>Création non confirmée</AlertTitle><AlertDescription>Les informations envoyées sont conservées pour vérifier ou renvoyer cette même demande.</AlertDescription>
      <Button variant="outline" type="button" className="mt-3" disabled={state.busy} onClick={() => void state.verify()}>Vérifier le résultat</Button></Alert>}
    <Button type="submit" className="opening-primary" disabled={state.busy} aria-busy={state.busy}>{state.busy ? 'Création…' : state.uncertain ? 'Renvoyer la même demande' : 'Créer mon école'}</Button>
  </form>;
}

function OperatorLinks({ state }: { state: SchoolOpeningState }) {
  return <div className="opening-operator">
    <div><Button disabled={state.busy} onClick={() => void state.createLink()}><Plus aria-hidden="true" data-icon="inline-start" />
      {state.busy ? 'Création…' : state.recoverLink ? 'Retrouver le lien' : 'Créer un lien d’ouverture'}</Button></div>
    {state.generated?.data.status === 'AVAILABLE' && <section className="opening-issued" aria-labelledby="opening-issued-title">
      <h2 id="opening-issued-title">Lien à transmettre</h2>
      <FieldGroup>{(['code', 'link'] as const).map(kind => <Field key={kind}><FieldLabel htmlFor={`opening-${kind}`}>{kind === 'code' ? 'Code d’ouverture' : 'Lien d’ouverture'}</FieldLabel>
        <div className="opening-copy"><Input id={`opening-${kind}`} value={state.generated![kind]} readOnly autoComplete="off" spellCheck={false} onFocus={event => event.target.select()} />
          <Button variant="outline" onClick={() => void state.copy(kind)}><Copy aria-hidden="true" data-icon="inline-start" />{kind === 'code' ? 'Copier le code' : 'Copier le lien'}</Button></div>
      </Field>)}</FieldGroup>
      {state.copied && <p role="status">{state.copied === 'code' ? 'Code copié.' : 'Lien copié.'}</p>}
    </section>}
    <section className="opening-list-section" aria-labelledby="opening-links-title"><h2 id="opening-links-title">Liens créés</h2>
      {state.items.length === 0 ? <Empty><EmptyHeader><EmptyMedia variant="icon"><Link aria-hidden="true" /></EmptyMedia><EmptyTitle>Aucun lien créé</EmptyTitle></EmptyHeader></Empty>
        : <ul className="opening-list">{state.items.map(item => <li key={item.id}>
          <div className="opening-link-summary"><strong>Créé le {dateTime(item.createdAt)}</strong><span>Expire le {dateTime(item.expiresAt)}</span></div>
          {item.status !== 'AVAILABLE' && <Badge variant="outline">{statuses[item.status]}</Badge>}
          {item.status === 'AVAILABLE' && <Button variant="ghost" disabled={state.busy} aria-label={`Révoquer le lien créé le ${dateTime(item.createdAt)}`} onClick={() => state.setRevoking(item)}>Révoquer</Button>}
        </li>)}</ul>}
    </section>
  </div>;
}