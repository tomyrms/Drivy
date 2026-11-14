import { useEffect, useState } from 'react';
import { Copy, Mail, ScrollText, Users } from 'lucide-react';
import { logoutNoticeText } from '../../logout-notice';
import {
  actionLabel, invitationStatusLabel, isInviteeEmail, journalDetail, reasonLabel,
  type PlatformInvitation, type PlatformJournalEntry, type PlatformOperator, type PlatformRoutes, platformRoutes,
} from '../../platform-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button, buttonVariants } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Skeleton } from '../../components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '../../components/ui/tabs';
import { AccountEntryPanel } from '../entry/account-entry-panel';
import { EntryFrame } from '../entry/entry-frame';
import { entryRoutes, type EntryRoutes } from '../entry/entry-model';
import { PortalSelect } from '../components/portal-select';
import { AttachDialog, ClientsSection, CodeDialog } from './clients-section';
import { OfferDialog, OffersSection } from './offers-section';
import { RightsDialog } from './rights-section';
import { usePlatformConsole, type PlatformConsoleState } from './use-platform-console';
import './platform.css';

const dateTime = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
const day = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium' }).format(new Date(value));
const validities = [{ value: '1', label: '1 jour' }, { value: '3', label: '3 jours' }, { value: '7', label: '7 jours' }, { value: '14', label: '14 jours' }] as const;

/** Console privée des opérateurs de la plateforme : écoles clientes, équipe, invitations, journal. Hors de toute école. */
export function PlatformConsolePage({ routes = entryRoutes, platform = platformRoutes }: { routes?: EntryRoutes; platform?: PlatformRoutes }) {
  const state = usePlatformConsole();
  const [tab, setTab] = useState<'clients' | 'offers' | 'team' | 'invitations' | 'journal'>('clients');
  useEffect(() => { document.title = 'Plateforme · Drivy'; }, []);
  const busy = !state.loaded || state.busy;
  const signedIn = state.session?.authenticated === true;
  return <EntryFrame home={routes.account} width={signedIn ? 'console' : 'narrow'} busy={busy}>
    <div className="platform-page">
      {(signedIn || !state.loaded) && <header className="platform-heading"><h1>Plateforme</h1></header>}
      <p className="entry-notice" role="status">{state.loaded && !signedIn && state.logoutUnconfirmed ? logoutNoticeText : ''}</p>
      {!state.loaded && <div className="grid gap-4" role="status" aria-label="Chargement de la console"><Skeleton className="h-10 w-72" /><Skeleton className="h-48 w-full" /></div>}
      {state.loaded && !signedIn && !state.error && <AccountEntryPanel routes={routes} onSignedIn={() => void state.boot()} />}
      {state.loaded && signedIn && <div className="platform-identity"><div><strong>{state.session?.user?.displayName}</strong><span>{state.session?.user?.email}</span></div>
        <Button variant="ghost" disabled={busy} onClick={() => void state.changeAccount()}>Changer de compte</Button></div>}
      {state.conflict ? <Alert><AlertTitle>Données mises à jour</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert>
        : state.error && !state.dialogOpen && !state.uncertain && <Alert variant="destructive"><AlertTitle>Action impossible</AlertTitle><AlertDescription>{state.error}</AlertDescription>
          <Button variant="outline" className="mt-3" disabled={busy} onClick={() => void (signedIn ? state.refresh() : state.boot())}>Actualiser</Button></Alert>}
      {state.loaded && signedIn && state.access === 'denied' && <Empty className="platform-denied" role="alert">
        <EmptyHeader><EmptyMedia variant="icon"><Users aria-hidden="true" /></EmptyMedia><EmptyTitle>Accès refusé</EmptyTitle></EmptyHeader>
        <a className={buttonVariants({ variant: 'outline' })} href={platform.join}>Saisir un code d’accès</a></Empty>}
      {state.access === 'allowed' && <Tabs value={tab} onValueChange={value => setTab(value as typeof tab)}>
        <TabsList variant="line" aria-label="Sections de la console">
          <TabsTrigger value="clients">Écoles</TabsTrigger><TabsTrigger value="offers">Offres</TabsTrigger><TabsTrigger value="team">Équipe</TabsTrigger><TabsTrigger value="invitations">Invitations</TabsTrigger><TabsTrigger value="journal">Journal</TabsTrigger>
        </TabsList>
        <TabsContent value="clients"><ClientsSection state={state} /></TabsContent>
        <TabsContent value="offers"><OffersSection state={state} /></TabsContent>
        <TabsContent value="team"><TeamSection state={state} /></TabsContent>
        <TabsContent value="invitations"><InvitationsSection state={state} /></TabsContent>
        <TabsContent value="journal"><JournalSection state={state} /></TabsContent>
      </Tabs>}
    </div>
    <RemovalDialog state={state} />
    <CodeDialog state={state} />
    <AttachDialog state={state} />
    <OfferDialog state={state} />
    <RightsDialog state={state} />
  </EntryFrame>;
}

function TeamSection({ state }: { state: PlatformConsoleState }) {
  const active = state.operators.filter(operator => operator.status === 'ACTIVE'), former = state.operators.filter(operator => operator.status !== 'ACTIVE');
  return <section className="platform-section" aria-labelledby="platform-team-title">
    <h2 id="platform-team-title">Équipe</h2>
    <ul className="platform-list">{active.map(operator => <li key={operator.id}>
      <div className="platform-summary"><strong>{operator.displayName}{operator.self && <Badge variant="secondary">Vous</Badge>}</strong>
        <span>{[operator.maskedEmail, `depuis le ${day(operator.joinedAt)}`].filter(Boolean).join(' · ')}</span></div>
      <Button variant="ghost" disabled={state.busy} aria-label={operator.self ? 'Me retirer de l’équipe' : `Retirer ${operator.displayName}`} onClick={() => state.chooseRemoval(operator)}>
        {operator.self ? 'Me retirer' : 'Retirer'}</Button>
    </li>)}</ul>
    {former.length > 0 && <>
      <h3 className="platform-subtitle">Anciens opérateurs</h3>
      <ul className="platform-list">{former.map(operator => <li key={operator.id}>
        <div className="platform-summary"><strong>{operator.displayName}</strong>
          <span>{operator.revokedAt ? `Retiré le ${day(operator.revokedAt)}` : 'Retiré'}</span></div>
        <Badge variant="outline">Retiré</Badge>
      </li>)}</ul></>}
  </section>;
}

function InvitationsSection({ state }: { state: PlatformConsoleState }) {
  const [email, setEmail] = useState(''), [validity, setValidity] = useState<string | null>('7'), [invalid, setInvalid] = useState<string | null>(null);
  const locked = state.busy || state.uncertain;
  const submit = () => {
    const value = email.trim().toLowerCase();
    if (!state.uncertain && !isInviteeEmail(value)) { setInvalid('Saisissez une adresse e-mail valide.'); return; }
    setInvalid(null);
    void state.sendInvitation(value, Number(validity ?? '7'));
  };
  // Le code d'une invitation émise est montré une fois ; la liste et le formulaire reviennent à sa fermeture.
  const issued = state.issued;
  return <section className="platform-section" aria-labelledby="platform-invitations-title">
    <h2 id="platform-invitations-title">Invitations</h2>
    {issued ? <div className="platform-issued" role="group" aria-labelledby="platform-issued-title">
      <h3 id="platform-issued-title">Code à transmettre</h3>
      <p className="platform-recipient">{issued.data.maskedEmail} · expire le {dateTime(issued.data.expiresAt)}</p>
      <Field><FieldLabel htmlFor="platform-code">Code d’accès</FieldLabel>
        <div className="platform-copy"><Input id="platform-code" className="platform-code" value={issued.code} readOnly autoComplete="off" spellCheck={false} onFocus={event => event.target.select()} />
          <Button variant="outline" onClick={() => void state.copy()}><Copy aria-hidden="true" data-icon="inline-start" />Copier le code</Button></div>
      </Field>
      {state.copied && <p role="status">Code copié.</p>}
      <Button disabled={state.busy} onClick={() => void state.closeCode()}>J’ai transmis le code</Button>
    </div> : <>
      {state.pending && !state.uncertain && <div className="platform-pending" role="group" aria-labelledby="platform-pending-title">
        <div className="platform-summary"><strong id="platform-pending-title">Code non transmis</strong><span>{state.pending.email}</span></div>
        <div className="platform-actions"><Button variant="outline" disabled={state.busy} onClick={() => void state.resumeInvitation()}>Afficher le code</Button>
          <Button variant="ghost" disabled={state.busy} onClick={() => void state.closeCode()}>Fermer</Button></div>
      </div>}
      <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); submit(); }}>
        <FieldGroup>
          <Field data-invalid={!!invalid}>
            <FieldLabel htmlFor="platform-email">Adresse e-mail de l’invité</FieldLabel>
            <Input id="platform-email" name="email" type="email" autoComplete="off" maxLength={254} required value={email} disabled={locked}
              aria-invalid={!!invalid} aria-describedby={invalid ? 'platform-email-error' : undefined} onChange={event => { setEmail(event.target.value); setInvalid(null); }} />
            {invalid && <FieldError id="platform-email-error">{invalid}</FieldError>}
          </Field>
          <PortalSelect id="platform-validity" label="Validité" options={validities} value={validity} disabled={locked} onValueChange={setValidity} />
        </FieldGroup>
        {state.uncertain && <Alert><AlertTitle>Invitation non confirmée</AlertTitle>
          <AlertDescription>Les informations envoyées sont conservées pour renvoyer cette même demande.</AlertDescription></Alert>}
        <Button type="submit" disabled={state.busy} aria-busy={state.busy}><Mail aria-hidden="true" data-icon="inline-start" />
          {state.busy ? 'Envoi…' : state.uncertain ? 'Renvoyer la même demande' : 'Inviter'}</Button>
      </form>
    </>}
    <InvitationList state={state} />
  </section>;
}

function InvitationList({ state }: { state: PlatformConsoleState }) {
  if (state.invitations.length === 0) return <Empty><EmptyHeader><EmptyMedia variant="icon"><Mail aria-hidden="true" /></EmptyMedia><EmptyTitle>Aucune invitation</EmptyTitle></EmptyHeader></Empty>;
  const available = (item: PlatformInvitation) => item.status === 'AVAILABLE';
  return <ul className="platform-list">{state.invitations.map(item => <li key={item.id}>
    <div className="platform-summary"><strong>{item.maskedEmail}</strong>
      <span>{available(item) ? `Expire le ${dateTime(item.expiresAt)}` : `Créée le ${day(item.createdAt)}`}{item.createdByName ? ` · par ${item.createdByName}` : ''}</span></div>
    {!available(item) && <Badge variant="outline">{invitationStatusLabel(item.status)}</Badge>}
    {available(item) && <Button variant="ghost" disabled={state.busy} aria-label={`Révoquer l’invitation de ${item.maskedEmail}`} onClick={() => void state.revokeInvitation(item)}>Révoquer</Button>}
  </li>)}</ul>;
}

function JournalSection({ state }: { state: PlatformConsoleState }) {
  return <section className="platform-section" aria-labelledby="platform-journal-title">
    <div className="platform-section-head"><h2 id="platform-journal-title">Journal</h2>
      <div className="platform-filter" role="group" aria-label="Filtrer le journal">
        <Button variant={state.filter === 'ALL' ? 'secondary' : 'ghost'} aria-pressed={state.filter === 'ALL'} disabled={state.busy} onClick={() => void state.chooseFilter('ALL')}>Tout</Button>
        <Button variant={state.filter === 'REFUSED' ? 'secondary' : 'ghost'} aria-pressed={state.filter === 'REFUSED'} disabled={state.busy} onClick={() => void state.chooseFilter('REFUSED')}>Refus</Button>
      </div></div>
    {state.journal.items.length === 0
      ? <Empty><EmptyHeader><EmptyMedia variant="icon"><ScrollText aria-hidden="true" /></EmptyMedia><EmptyTitle>Aucune entrée</EmptyTitle></EmptyHeader></Empty>
      : <ol className="platform-list">{state.journal.items.map(entry => <JournalRow key={entry.id} entry={entry} />)}</ol>}
    {state.journal.nextCursor && <Button variant="outline" disabled={state.busy} onClick={() => void state.moreJournal()}>Afficher plus</Button>}
  </section>;
}

function JournalRow({ entry }: { entry: PlatformJournalEntry }) {
  const detail = journalDetail(entry, dateTime), reason = reasonLabel(entry.reasonCode);
  return <li>
    <div className="platform-summary"><strong>{actionLabel(entry.action)}</strong>
      <span>{dateTime(entry.occurredAt)} · {entry.actorKind === 'SYSTEM' ? 'Système' : entry.actorName}</span>
      {detail && <span>{detail}</span>}
      {entry.schoolId && <span>École <code title={entry.schoolId}>{entry.schoolId.slice(0, 8)}</code></span>}</div>
    {entry.result === 'REFUSED' && <Badge variant="destructive">{reason ? `Refusée · ${reason}` : 'Refusée'}</Badge>}
  </li>;
}

function RemovalDialog({ state }: { state: PlatformConsoleState }) {
  const target: PlatformOperator | null = state.removing;
  return <Dialog open={target !== null} onOpenChange={(open, details) => { if (state.busy) details.cancel(); else if (!open) state.chooseRemoval(null); }}>
    <DialogContent showCloseButton={!state.busy}>
      <DialogHeader><DialogTitle>{target?.self ? 'Vous retirer de l’équipe ?' : `Retirer ${target?.displayName ?? ''} ?`}</DialogTitle>
        <DialogDescription>{target?.self ? 'Vous perdrez l’accès à cette console, et vos invitations en attente s’arrêteront, dès la confirmation.' : 'Son accès à la console et ses invitations en attente s’arrêtent dès la confirmation.'}</DialogDescription></DialogHeader>
      {state.error && <Alert variant="destructive"><AlertTitle>Retrait non confirmé</AlertTitle><AlertDescription>{state.error}</AlertDescription></Alert>}
      <DialogFooter><Button variant="outline" disabled={state.busy} onClick={() => state.chooseRemoval(null)}>Garder l’accès</Button>
        <Button variant="destructive" disabled={state.busy} onClick={() => void state.removeOperator()}>{state.busy ? 'Retrait…' : 'Retirer'}</Button></DialogFooter>
    </DialogContent>
  </Dialog>;
}
