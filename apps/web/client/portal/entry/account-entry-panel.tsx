import { useId, type ComponentProps, type FormEvent, type ReactNode } from 'react';
import { Building2, CircleAlert, Loader2 } from 'lucide-react';
import { Alert, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel, FieldSeparator } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { passwordMinimum, type AccessKind, type EntryRoutes } from './entry-model';
import { useAccountEntry, type AccountEntryState } from './use-account-entry';

const titles = { login: 'Se connecter', code: 'J’ai un code', register: 'Créer votre compte' } as const;

/** After a refused submission, the first field to correct takes the focus. */
function focusFirstProblem(form: HTMLFormElement) {
  requestAnimationFrame(() => form.querySelector<HTMLInputElement>('[aria-invalid="true"]')?.focus());
}

function submitWith(action: () => boolean) {
  return (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!action()) focusFirstProblem(event.currentTarget);
  };
}

function TextField({ id, label, error, description, aside, ...input }: {
  id: string; label: string; error?: string | undefined; description?: string; aside?: ReactNode;
} & Omit<ComponentProps<typeof Input>, 'id'>) {
  const describedBy = [error ? `${id}-error` : '', description ? `${id}-hint` : ''].filter(Boolean).join(' ');
  return <Field data-invalid={!!error}>
    {aside ? <div className="entry-label-row"><FieldLabel htmlFor={id}>{label}</FieldLabel>{aside}</div> : <FieldLabel htmlFor={id}>{label}</FieldLabel>}
    <Input id={id} aria-invalid={error ? true : undefined} aria-describedby={describedBy || undefined} {...input} />
    {description && !error && <FieldDescription id={`${id}-hint`}>{description}</FieldDescription>}
    {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
  </Field>;
}

function Submit({ busy, label, busyLabel }: { busy: boolean; label: string; busyLabel: string }) {
  return <Button type="submit" size="lg" className="entry-submit" disabled={busy} focusableWhenDisabled>
    {busy && <Loader2 className="entry-spin" aria-hidden="true" />}{busy ? busyLabel : label}
  </Button>;
}

function EntryError({ message }: { message: string | null }) {
  if (!message) return null;
  return <Alert variant="destructive"><CircleAlert aria-hidden="true" /><AlertTitle>{message}</AlertTitle></Alert>;
}

/**
 * Sign-in, code and account creation of a signed-out person (#319). Each action is distinct: sign in, type a code,
 * recover the password in another tab. Only a valid code or link creates an account.
 */
export function AccountEntryPanel({ routes, invitation = false, initialCode, onSignedIn }: {
  routes: EntryRoutes; invitation?: boolean; initialCode?: string; onSignedIn: (kind: AccessKind | null) => void;
}) {
  const state = useAccountEntry({ invitation, onSignedIn, ...(initialCode ? { initialCode } : {}) });
  const uid = useId();
  const titleId = `${uid}-title`;
  const context = state.step === 'register' && (state.schoolName || state.canChangeCode);
  return <section className="entry-auth" aria-labelledby={titleId}>
    <header className="entry-auth-header">
      {context && <p className="entry-context">
        {state.schoolName && <><Building2 aria-hidden="true" /><span>{state.schoolName}</span></>}
        {state.canChangeCode && <Button variant="link" size="sm" className="entry-context-action" disabled={state.busy} onClick={() => state.go('code')}>Changer de code</Button>}
      </p>}
      <h1 id={titleId} ref={state.heading} tabIndex={-1}>{titles[state.step]}</h1>
    </header>
    <div className="entry-card">
      <EntryError message={state.error} />
      {state.step === 'login' && <SignInForm uid={uid} state={state} routes={routes} />}
      {state.step === 'code' && <CodeForm uid={uid} state={state} />}
      {state.step === 'register' && <RegisterForm uid={uid} state={state} />}
    </div>
    <div className="entry-alternatives">
      <FieldSeparator>ou</FieldSeparator>
      {state.step === 'login' && state.kind === null && <Button variant="outline" size="lg" disabled={state.busy} onClick={() => state.go('code')}>J’ai un code</Button>}
      {state.step === 'login' && state.kind !== null && <Button variant="outline" size="lg" disabled={state.busy} onClick={() => state.go('register')}>Créer un compte</Button>}
      {state.step === 'code' && <Button variant="outline" size="lg" disabled={state.busy} onClick={state.existingAccount}>J’ai déjà un compte</Button>}
      {state.step === 'register' && <Button variant="outline" size="lg" disabled={state.busy} onClick={() => state.go('login')}>J’ai déjà un compte</Button>}
    </div>
  </section>;
}

function SignInForm({ uid, state, routes }: { uid: string; state: AccountEntryState; routes: EntryRoutes }) {
  return <form className="entry-form" method="post" noValidate onSubmit={submitWith(state.signIn)}>
    <FieldGroup>
      <TextField id={`${uid}-email`} name="email" label="E-mail" type="email" autoComplete="username" inputMode="email" autoCapitalize="off" spellCheck={false}
        maxLength={254} value={state.email} onChange={event => state.setEmail(event.target.value)} readOnly={state.busy} error={state.problems.email} />
      <TextField id={`${uid}-password`} name="password" label="Mot de passe" type="password" autoComplete="current-password" maxLength={128}
        value={state.password} onChange={event => state.setPassword(event.target.value)} readOnly={state.busy} error={state.problems.password}
        aside={<a className="entry-inline-link" href={routes.recover} target="_blank" rel="noopener noreferrer" onClick={state.forgetPassword}>
          Mot de passe oublié<span className="sr-only"> (nouvel onglet)</span></a>} />
    </FieldGroup>
    <Submit busy={state.busy} label="Se connecter" busyLabel="Connexion…" />
  </form>;
}

function CodeField({ uid, state, autoFocus = false }: { uid: string; state: AccountEntryState; autoFocus?: boolean }) {
  return <TextField id={`${uid}-code`} autoFocus={autoFocus} name="code" label="Code ou lien reçu" placeholder="XXXX-XXXX" autoComplete="one-time-code" autoCapitalize="off" autoCorrect="off"
    spellCheck={false} maxLength={300} value={state.code} onChange={event => state.setCode(event.target.value)} readOnly={state.busy} error={state.codeProblem ?? undefined} />;
}

function CodeForm({ uid, state }: { uid: string; state: AccountEntryState }) {
  return <form className="entry-form" method="post" noValidate onSubmit={submitWith(state.submitCode)}>
    <CodeField uid={uid} state={state} />
    <Submit busy={state.busy} label="Continuer" busyLabel="Vérification…" />
  </form>;
}

function RegisterForm({ uid, state }: { uid: string; state: AccountEntryState }) {
  return <form className="entry-form" method="post" noValidate onSubmit={submitWith(state.register)}>
    <FieldGroup>
      <div className="entry-name-row">
        <TextField id={`${uid}-first`} name="firstName" label="Prénom" autoComplete="given-name" maxLength={100}
          value={state.firstName} onChange={event => state.setFirstName(event.target.value)} readOnly={state.busy} error={state.problems.firstName} />
        <TextField id={`${uid}-last`} name="lastName" label="Nom" autoComplete="family-name" maxLength={100}
          value={state.lastName} onChange={event => state.setLastName(event.target.value)} readOnly={state.busy} error={state.problems.lastName} />
      </div>
      <TextField id={`${uid}-email`} name="email" label="E-mail" type="email" autoComplete="username" inputMode="email" autoCapitalize="off" spellCheck={false}
        maxLength={254} value={state.email} onChange={event => state.setEmail(event.target.value)} readOnly={state.busy} error={state.problems.email} />
      <TextField id={`${uid}-password`} name="password" label="Mot de passe" type="password" autoComplete="new-password" maxLength={128}
        description={`${passwordMinimum} caractères au moins`} value={state.password} onChange={event => state.setPassword(event.target.value)}
        readOnly={state.busy} error={state.problems.password} />
    </FieldGroup>
    <Submit busy={state.busy} label="Créer mon compte" busyLabel="Création…" />
  </form>;
}

/** « J’ai un code » of a signed-in person, inside the list of schools. */
export function SignedInCodePanel({ onSignedIn, onCancel }: { onSignedIn: (kind: AccessKind | null) => void; onCancel: () => void }) {
  const state = useAccountEntry({ signedIn: true, onSignedIn });
  const uid = useId();
  return <section className="entry-inline-code" aria-labelledby={`${uid}-title`}>
    <h2 id={`${uid}-title`} ref={state.heading} tabIndex={-1}>J’ai un code</h2>
    <EntryError message={state.error} />
    <form className="entry-form" method="post" noValidate onSubmit={submitWith(state.submitCode)}>
      <CodeField uid={uid} state={state} autoFocus />
      <div className="entry-actions">
        <Submit busy={state.busy} label="Continuer" busyLabel="Vérification…" />
        <Button variant="ghost" size="lg" disabled={state.busy} onClick={onCancel}>Annuler</Button>
      </div>
    </form>
  </section>;
}
