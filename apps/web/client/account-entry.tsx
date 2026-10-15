import { useEffect, useRef, useState, type FormEvent } from 'react';
import { z } from 'zod';
import { errorMessage, okSchema, request, RequestFailure, sessionSchema } from './protocol';
import { Notice, TextField } from './ui';

/** What a code opens, as the server read it. */
export type AccessKind = 'LEARNER_INVITATION' | 'SCHOOL_OPENING';
const codeSchema = z.object({ kind: z.enum(['LEARNER_INVITATION', 'SCHOOL_OPENING']), schoolName: z.string().max(200).optional(), expiresAt: z.string() });
const accountSchema = z.object({ kind: z.enum(['LEARNER_INVITATION', 'SCHOOL_OPENING']) });
type Step = 'login' | 'code' | 'register' | 'learner-ready';

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
export function AccountEntry({ initialCode, onSignedIn }: { initialCode?: string; onSignedIn: (kind: AccessKind | null) => void }) {
  const [step, setStep] = useState<Step>(initialCode ? 'register' : 'login');
  const [code, setCode] = useState(initialCode ?? '');
  const [kind, setKind] = useState<AccessKind | null>(initialCode ? 'SCHOOL_OPENING' : null);
  const [schoolName, setSchoolName] = useState<string | null>(null);
  const [email, setEmail] = useState(''), [password, setPassword] = useState('');
  const [firstName, setFirstName] = useState(''), [lastName, setLastName] = useState('');
  const [busy, setBusy] = useState(false), [error, setError] = useState<string | null>(null);
  const heading = useRef<HTMLHeadingElement>(null), started = useRef(false);

  useEffect(() => { if (started.current) heading.current?.focus({ preventScroll: true }); started.current = true; }, [step]);
  useEffect(() => {
    // An opening link already names its code: read what it opens, so that an expired link says so before the form.
    if (initialCode) void run(async csrf => { await inspect(initialCode, csrf); });
  }, []);

  async function run(action: (csrf: string) => Promise<void>) {
    setBusy(true); setError(null);
    try { await action((await request('session', sessionSchema)).csrfToken); }
    catch (cause) { setError(failure(cause)); }
    finally { setBusy(false); }
  }
  async function inspect(value: string, csrf: string) {
    const result = await request('access-code', codeSchema, { csrf, body: { code: codeFromInput(value) } });
    setKind(result.kind); setSchoolName(result.schoolName ?? null); setStep('register');
  }
  function go(next: Step) { setError(null); setPassword(''); setStep(next); }

  const signIn = (event: FormEvent) => { event.preventDefault(); void run(async csrf => {
    await request('password-login', okSchema, { csrf, body: { email, password } });
    setPassword(''); onSignedIn(kind);
  }); };
  const submitCode = (event: FormEvent) => { event.preventDefault(); void run(csrf => inspect(code, csrf)); };
  const register = (event: FormEvent) => { event.preventDefault(); void run(async csrf => {
    const result = await request('accounts', accountSchema, { csrf, body: { code: codeFromInput(code), firstName, lastName, email, password } });
    setPassword('');
    if (result.kind === 'LEARNER_INVITATION') { setStep('learner-ready'); return; }
    onSignedIn(result.kind);
  }); };

  const title = step === 'login' ? 'Se connecter à Drivy' : step === 'code' ? 'J’ai un code'
    : step === 'learner-ready' ? 'Votre compte est prêt' : kind === 'SCHOOL_OPENING' ? 'Ouvrir votre école' : schoolName ? `Rejoindre ${schoolName}` : 'Créer votre compte';

  return <section className="sign-in account-entry" aria-labelledby="account-entry-title">
    <h1 id="account-entry-title" ref={heading} tabIndex={-1}>{title}</h1>
    {error && <Notice tone="error" title={error} />}

    {step === 'login' && <form className="form-grid" noValidate onSubmit={signIn}>
      <TextField name="email" label="E-mail" type="email" value={email} onChange={setEmail} autoComplete="username" inputMode="email" maxLength={254} required disabled={busy} />
      <TextField name="password" label="Mot de passe" type="password" value={password} onChange={setPassword} autoComplete="current-password" maxLength={128} required disabled={busy} />
      <button className="button primary" type="submit" disabled={busy || !email.trim() || !password}>{busy ? 'Connexion…' : 'Se connecter'}</button>
      {kind === null && <button className="button secondary" type="button" disabled={busy} onClick={() => go('code')}>J’ai un code</button>}
      {kind !== null && <button className="button quiet" type="button" disabled={busy} onClick={() => go('register')}>Créer un compte</button>}
    </form>}

    {step === 'code' && <form className="form-grid" noValidate onSubmit={submitCode}>
      <TextField name="code" label="Code ou lien reçu" value={code} onChange={setCode} placeholder="XXXX-XXXX" autoComplete="one-time-code" maxLength={300} required disabled={busy} />
      <button className="button primary" type="submit" disabled={busy || !code.trim()}>{busy ? 'Vérification…' : 'Continuer'}</button>
      <button className="button quiet" type="button" disabled={busy} onClick={() => go('login')}>J’ai déjà un compte</button>
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

    {step === 'learner-ready' && <div className="form-grid">
      <p>Ouvrez l’app Drivy, connectez-vous avec {email}, puis saisissez votre code pour rejoindre {schoolName ?? 'votre école'}.</p>
      <button className="button primary" type="button" onClick={() => onSignedIn('LEARNER_INVITATION')}>Continuer</button>
    </div>}
  </section>;
}
