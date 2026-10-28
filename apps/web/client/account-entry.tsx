import { useEffect, useRef, useState, type FormEvent } from 'react';
import { z } from 'zod';
import { errorMessage, okSchema, request, RequestFailure, sessionSchema } from './protocol';
import { Notice, Symbol, TextField } from './ui';
import type { AccessKind } from './account-entry-route';

/** What a code opens, as the server read it. */
export type { AccessKind } from './account-entry-route';
const codeSchema = z.object({ kind: z.enum(['LEARNER_INVITATION', 'SCHOOL_OPENING']), schoolName: z.string().max(200).optional(), expiresAt: z.string() });
const accountSchema = z.object({ kind: z.enum(['LEARNER_INVITATION', 'SCHOOL_OPENING', 'EMAIL_INVITATION']) });
type Step = 'login' | 'code' | 'register';

/**
 * A pasted link keeps only its code: `…/ouvrir#token=…` (opening) or the typed `XXXX-XXXX`.
 * Anything else is sent as typed and the server answers whether it is a code.
 */
export function codeFromInput(value: string): string {
  const trimmed = value.trim();
  const fragment = /#token=([A-Za-z0-9_-]+)$/.exec(trimmed);
  return fragment?.[1] ?? trimmed;
}

const messages: Record<string, string> = {
  INVALID_CREDENTIALS: 'E-mail ou mot de passe incorrect.',
  ACCESS_CODE_INVALID: 'Ce code n’est pas valide ou n’est plus utilisable.',
  ACCESS_CODE_ATTEMPTS: 'Trop de tentatives. Réessayez dans quelques minutes.',
  ACCOUNT_EXISTS: 'Un compte existe déjà avec cette adresse. Connectez-vous : votre code sera repris.',
  EMAIL_INVITATION_MISMATCH: 'Utilisez l’adresse à laquelle l’école a envoyé l’invitation.',
  ACCOUNT_PASSWORD_REJECTED: 'Ce mot de passe n’est pas accepté. Choisissez-en un plus long ou moins courant.',
  ACCOUNT_CREATION_UNAVAILABLE: 'La création de compte est momentanément indisponible. Réessayez plus tard.',
  INVALID_REQUEST: 'Vérifiez les champs puis réessayez.',
  RATE_LIMITED: 'Trop de tentatives. Réessayez dans quelques minutes.',
};
const failure = (cause: unknown) => cause instanceof RequestFailure && messages[cause.code] ? messages[cause.code]! : errorMessage(cause);

/**
 * Sign-in and account creation of the web, the same as in the app: « Se connecter », or « J'ai un code ».
 * Only a valid code (or opening link) can create an account; the password goes to the identity service and is never kept here.
 */
export function AccountEntry({ initialCode, invitation = false, signedIn = false, onSignedIn, onCancel }: {
  initialCode?: string; invitation?: boolean; signedIn?: boolean; onSignedIn: (kind: AccessKind | null) => void; onCancel?: () => void;
}) {
  const [step, setStep] = useState<Step>(signedIn ? 'code' : initialCode || invitation ? 'register' : 'login');
  const [code, setCode] = useState(initialCode ?? '');
  const [kind, setKind] = useState<AccessKind | null>(initialCode ? 'SCHOOL_OPENING' : invitation ? 'EMAIL_INVITATION' : null);
  const [schoolName, setSchoolName] = useState<string | null>(null);
  const [email, setEmail] = useState(''), [password, setPassword] = useState('');
  const [firstName, setFirstName] = useState(''), [lastName, setLastName] = useState('');
  const [busy, setBusy] = useState(false), [error, setError] = useState<string | null>(null);
  const heading = useRef<HTMLHeadingElement>(null), started = useRef(false);
  const inFlight = useRef(false);

  useEffect(() => { if (started.current) heading.current?.focus({ preventScroll: true }); started.current = true; }, [step]);
  useEffect(() => {
    // An opening link already names its code: read what it opens, so that an expired link says so before the form.
    if (initialCode) void run(async csrf => { await inspect(initialCode, csrf); });
  }, []);

  async function run(action: (csrf: string) => Promise<void>) {
    if (inFlight.current) return;
    inFlight.current = true;
    setBusy(true); setError(null);
    try { await action((await request('session', sessionSchema)).csrfToken); }
    catch (cause) { setError(failure(cause)); }
    finally { inFlight.current = false; setBusy(false); }
  }
  async function inspect(value: string, csrf: string) {
    const result = await request('access-code', codeSchema, { csrf, body: { code: codeFromInput(value) } });
    setKind(result.kind); setSchoolName(result.schoolName ?? null);
    if (signedIn) { onSignedIn(result.kind); return; }
    setStep('register');
  }
  function go(next: Step) { setError(null); setPassword(''); setStep(next); }
  function existingAccount() {
    if (!code.trim()) { go('login'); return; }
    void run(async csrf => { await inspect(code, csrf); go('login'); });
  }

  const signIn = (event: FormEvent) => { event.preventDefault(); void run(async csrf => {
    await request('password-login', okSchema, { csrf, body: { email, password } });
    setPassword('');
    onSignedIn(kind);
  }); };
  const submitCode = (event: FormEvent) => { event.preventDefault(); void run(csrf => inspect(code, csrf)); };
  const register = (event: FormEvent) => { event.preventDefault(); void run(async csrf => {
    // An e-mail invitation is named by the link already opened in this browser: no code is sent.
    const named = kind === 'EMAIL_INVITATION' ? {} : { code: codeFromInput(code) };
    let result: z.infer<typeof accountSchema>;
    try { result = await request('accounts', accountSchema, { csrf, body: { ...named, firstName, lastName, email, password } }); }
    catch (cause) {
      if (kind === 'EMAIL_INVITATION' && cause instanceof RequestFailure && cause.code === 'ACCESS_CODE_INVALID') throw new RequestFailure('EMAIL_INVITATION_MISMATCH', 404);
      throw cause;
    }
    setPassword('');
    onSignedIn(result.kind);
  }); };

  const title = step === 'login' ? 'Se connecter à Drivy' : step === 'code' ? 'J’ai un code'
    : 'Créer votre compte';

  return <section className="sign-in account-entry" aria-labelledby="account-entry-title">
    <div className="entry-icon"><Symbol kind={step === 'code' ? 'mail' : step === 'register' ? 'account' : 'lock'} bare /></div>
    {step === 'register' && schoolName && <p className="context">{schoolName}</p>}
    {signedIn
      ? <h2 id="account-entry-title" className="section-title" ref={heading} tabIndex={-1}>{title}</h2>
      : <h1 id="account-entry-title" ref={heading} tabIndex={-1}>{title}</h1>}
    {error && <Notice tone="error" title={error} />}

    {step === 'login' && <form className="form-grid" noValidate onSubmit={signIn}>
      <TextField name="email" label="E-mail" type="email" value={email} onChange={setEmail} autoComplete="username" inputMode="email" maxLength={254} required disabled={busy} />
      <TextField name="password" label="Mot de passe" type="password" value={password} onChange={setPassword} autoComplete="current-password" maxLength={128} required disabled={busy} />
      <button className="button primary" type="submit" disabled={busy || !email.trim() || !password}>{busy ? 'Connexion…' : 'Se connecter'}</button>
      <a className="entry-recovery" href="/app/recover" target="_blank" rel="noopener noreferrer" onClick={() => setPassword('')}>Mot de passe oublié<span className="visually-hidden"> (nouvel onglet)</span></a>
      {kind === null && <div className="entry-secondary"><button className="button secondary" type="button" disabled={busy} onClick={() => go('code')}>J’ai un code</button></div>}
      {kind !== null && <button className="button quiet" type="button" disabled={busy} onClick={() => go('register')}>Créer un compte</button>}
    </form>}

    {step === 'code' && <form className="form-grid" noValidate onSubmit={submitCode}>
      <TextField name="code" label="Code ou lien reçu" value={code} onChange={setCode} placeholder="XXXX-XXXX" autoComplete="one-time-code" maxLength={300} required disabled={busy} />
      <button className="button primary" type="submit" disabled={busy || !code.trim()}>{busy ? 'Vérification…' : 'Continuer'}</button>
      {!signedIn && <button className="button quiet" type="button" disabled={busy} onClick={existingAccount}>J’ai déjà un compte</button>}
      {signedIn && onCancel && <button className="button quiet" type="button" disabled={busy} onClick={onCancel}>Annuler</button>}
    </form>}

    {step === 'register' && <form className="form-grid" noValidate onSubmit={register}>
      <div className="button-row">
        <TextField name="firstName" label="Prénom" value={firstName} onChange={setFirstName} autoComplete="given-name" maxLength={100} required disabled={busy} />
        <TextField name="lastName" label="Nom" value={lastName} onChange={setLastName} autoComplete="family-name" maxLength={100} required disabled={busy} />
      </div>
      <TextField name="email" label="E-mail" type="email" value={email} onChange={setEmail} autoComplete="username" inputMode="email" maxLength={254} required disabled={busy} />
      <TextField name="password" label="Mot de passe" type="password" value={password} onChange={setPassword} autoComplete="new-password" maxLength={128}
        hint="8 caractères au moins" required disabled={busy} />
      <button className="button primary" type="submit" disabled={busy || !firstName.trim() || !lastName.trim() || !email.trim() || password.length < 8}>{busy ? 'Création…' : 'Créer mon compte'}</button>
      <button className="button quiet" type="button" disabled={busy} onClick={() => go('login')}>J’ai déjà un compte</button>
    </form>}

  </section>;
}
