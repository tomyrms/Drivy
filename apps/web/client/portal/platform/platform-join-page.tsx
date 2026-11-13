import { useEffect } from 'react';
import { Check, X } from 'lucide-react';
import { logoutNoticeText } from '../../logout-notice';
import { levelLabel, notGrantedLabel, platformRoutes, rightLabel, type PlatformPreview, type PlatformRoutes } from '../../platform-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Skeleton } from '../../components/ui/skeleton';
import { AccountEntryPanel } from '../entry/account-entry-panel';
import { EntryFrame } from '../entry/entry-frame';
import { entryRoutes, type EntryRoutes } from '../entry/entry-model';
import { usePlatformJoin, type PlatformAccepted, type PlatformJoinState } from './use-platform-join';
import './platform.css';

const dateTime = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));

/** Acceptation d'un code d'accès à la plateforme : les droits sont lus, puis confirmés, puis le serveur confirme à son tour. */
export function PlatformJoinPage({ routes = entryRoutes, platform = platformRoutes }: { routes?: EntryRoutes; platform?: PlatformRoutes }) {
  const state = usePlatformJoin();
  useEffect(() => { document.title = 'Rejoindre la plateforme · Drivy'; }, []);
  const busy = !state.loaded || state.busy;
  const signedIn = state.session?.authenticated === true;
  return <EntryFrame home={routes.account} width="narrow" busy={busy}>
    <div className="platform-join">
      {(signedIn || !state.loaded) && <header className="platform-heading"><h1>Rejoindre la plateforme</h1></header>}
      <p className="entry-notice" role="status">{state.loaded && !signedIn && state.logoutUnconfirmed ? logoutNoticeText : ''}</p>
      {!state.loaded && <div className="grid gap-4" role="status" aria-label="Chargement"><Skeleton className="h-12 w-full" /><Skeleton className="h-40 w-full" /></div>}
      {state.error && <Alert variant="destructive"><AlertTitle>Action impossible</AlertTitle><AlertDescription>{state.error}</AlertDescription>
        {!signedIn && <Button variant="outline" className="mt-3" disabled={busy} onClick={() => void state.boot()}>Actualiser</Button>}</Alert>}
      {state.loaded && !signedIn && !state.error && <AccountEntryPanel routes={routes} onSignedIn={() => void state.boot()} />}
      {state.loaded && signedIn && <>
        <div className="platform-identity"><div><strong>{state.session?.user?.displayName}</strong><span>{state.session?.user?.email}</span></div>
          <Button variant="ghost" disabled={busy || state.uncertain} onClick={() => void state.changeAccount()}>Changer de compte</Button></div>
        {state.accepted ? <Accepted result={state.accepted} platform={platform} />
          : state.uncertain ? <Uncertain state={state} />
          : state.preview ? <Review state={state} preview={state.preview} platform={platform} />
          : <CodeForm state={state} />}
      </>}
    </div>
  </EntryFrame>;
}

function CodeForm({ state }: { state: PlatformJoinState }) {
  return <form className="platform-form" noValidate onSubmit={event => { event.preventDefault(); void state.review(); }}>
    <FieldGroup><Field data-invalid={!!state.codeError}>
      <FieldLabel htmlFor="platform-join-code">Code d’accès</FieldLabel>
      <Input id="platform-join-code" className="platform-code" name="code" inputMode="text" autoComplete="off" autoCapitalize="characters" spellCheck={false} maxLength={11} placeholder="XXXXX-XXXXX"
        required value={state.code} disabled={state.busy} aria-invalid={!!state.codeError} aria-describedby={state.codeError ? 'platform-join-code-error' : undefined}
        onChange={event => state.setCode(event.target.value)} />
      {state.codeError && <FieldError id="platform-join-code-error">{state.codeError}</FieldError>}
    </Field></FieldGroup>
    <Button type="submit" className="platform-primary" disabled={state.busy} aria-busy={state.busy}>{state.busy ? 'Vérification…' : 'Voir les droits'}</Button>
  </form>;
}

function RightsList({ granted, denied }: { granted: readonly string[]; denied: readonly string[] }) {
  return <>
    <div className="platform-group"><h3>Droits accordés</h3>
      <ul className="platform-rights">{granted.map(right => <li key={right}><Check aria-hidden="true" />{rightLabel(right)}</li>)}</ul></div>
    <div className="platform-group"><h3>Jamais accordé</h3>
      <ul className="platform-rights platform-rights-denied">{denied.map(access => <li key={access}><X aria-hidden="true" />{notGrantedLabel(access)}</li>)}</ul></div>
  </>;
}

function Review({ state, preview, platform }: { state: PlatformJoinState; preview: PlatformPreview; platform: PlatformRoutes }) {
  const { data } = preview;
  const blocked = !data.matchesAccount || data.alreadyMember;
  return <div className="platform-review">
    <section className="platform-review-card" aria-labelledby="platform-review-title">
      <h2 id="platform-review-title">Niveau {levelLabel(data.level).toLowerCase()}</h2>
      <p className="platform-recipient">Invitation pour {data.maskedEmail} · expire le {dateTime(data.expiresAt)}</p>
      <RightsList granted={data.rights} denied={data.notGranted} />
    </section>
    {!data.matchesAccount && <Alert variant="destructive"><AlertTitle>Autre adresse</AlertTitle>
      <AlertDescription>Cette invitation est destinée à une autre adresse. Connectez-vous avec le compte invité.</AlertDescription></Alert>}
    {data.alreadyMember && <Alert><AlertTitle>Déjà dans l’équipe</AlertTitle><AlertDescription>Ce compte a déjà accès à la console.</AlertDescription>
      <Button variant="outline" className="mt-3" nativeButton={false} render={<a href={platform.console} />}>Ouvrir la console</Button></Alert>}
    <Button className="platform-primary" disabled={state.busy || blocked} aria-busy={state.busy} onClick={() => void state.accept()}>{state.busy ? 'Confirmation…' : 'Accepter et rejoindre'}</Button>
    <Button variant="ghost" disabled={state.busy} onClick={state.changeCode}>Changer de code</Button>
  </div>;
}

function Uncertain({ state }: { state: PlatformJoinState }) {
  return <div className="platform-review">
    <Alert><AlertTitle>Acceptation non confirmée</AlertTitle>
      <AlertDescription>La même demande sera renvoyée : elle ne peut être acceptée qu’une fois.</AlertDescription></Alert>
    <Button className="platform-primary" disabled={state.busy} aria-busy={state.busy} onClick={() => void state.accept()}>{state.busy ? 'Envoi…' : 'Renvoyer la même demande'}</Button>
  </div>;
}

function Accepted({ result, platform }: { result: PlatformAccepted; platform: PlatformRoutes }) {
  return <div className="platform-accepted" role="status">
    <section className="platform-review-card" aria-labelledby="platform-accepted-title">
      <h2 id="platform-accepted-title">Vous faites partie de l’équipe</h2>
      <RightsList granted={result.rights} denied={result.notGranted} />
    </section>
    <Button className="platform-primary" nativeButton={false} render={<a href={platform.console} />}>Ouvrir la console</Button>
  </div>;
}
