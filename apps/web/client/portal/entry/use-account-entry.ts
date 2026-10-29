import { useEffect, useRef, useState } from 'react';
import { okSchema, request, sessionSchema } from '../../protocol';
import {
  accessCodeSchema, accountCreationFailure, accountProblems, codeFromInput, codeProblem, createdAccountSchema, entryFailureMessage,
  hasProblems, initialAccessKind, initialEntryStep, signInProblems, type AccessKind, type EntryStep,
} from './entry-model';

export interface AccountEntryOptions {
  /** An opening link already names its code. */
  initialCode?: string;
  /** Opened from an invitation link: the account is named by that link, no code is typed. */
  invitation?: boolean;
  /** The person is signed in and only types a code. */
  signedIn?: boolean;
  onSignedIn: (kind: AccessKind | null) => void;
}

/**
 * Sign-in and account creation, the same as in the app: « Se connecter », or « J’ai un code ».
 * Only a valid code (or link) can create an account. The password goes to the identity service and is never kept:
 * it is cleared after each attempt that leaves the form and at every change of step.
 */
export function useAccountEntry({ initialCode, invitation = false, signedIn = false, onSignedIn }: AccountEntryOptions) {
  const [step, setStep] = useState<EntryStep>(() => initialEntryStep({ signedIn, invitation, ...(initialCode ? { initialCode } : {}) }));
  const [code, setCode] = useState(initialCode ?? '');
  const [kind, setKind] = useState<AccessKind | null>(() => initialAccessKind({ invitation, ...(initialCode ? { initialCode } : {}) }));
  const [schoolName, setSchoolName] = useState<string | null>(null);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showProblems, setShowProblems] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null);
  const started = useRef(false);
  const inFlight = useRef(false);
  const mounted = useRef(true);

  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
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
    catch (cause) { if (mounted.current) setError(entryFailureMessage(cause)); }
    finally { inFlight.current = false; if (mounted.current) setBusy(false); }
  }
  async function inspect(value: string, csrf: string) {
    const result = await request('access-code', accessCodeSchema, { csrf, body: { code: codeFromInput(value) } });
    setKind(result.kind); setSchoolName(result.schoolName ?? null);
    if (signedIn) { onSignedIn(result.kind); return; }
    setStep('register');
  }
  function go(next: EntryStep) { setError(null); setShowProblems(false); setPassword(''); setStep(next); }
  function existingAccount() {
    if (!code.trim()) { go('login'); return; }
    // A typed code is read first, so that the journey it opens continues after sign-in.
    void run(async csrf => { await inspect(code, csrf); go('login'); });
  }

  const signInDraft = { email, password };
  const accountDraft = { firstName, lastName, email, password };
  const problems = step === 'login' ? signInProblems(signInDraft) : step === 'register' ? accountProblems(accountDraft) : {};
  const typedCodeProblem = step === 'code' ? codeProblem(code) : null;

  function signIn() {
    setShowProblems(true);
    if (hasProblems(signInProblems(signInDraft))) return false;
    void run(async csrf => {
      await request('password-login', okSchema, { csrf, body: { email, password } });
      setPassword('');
      onSignedIn(kind);
    });
    return true;
  }
  function submitCode() {
    setShowProblems(true);
    if (codeProblem(code)) return false;
    void run(csrf => inspect(code, csrf));
    return true;
  }
  function register() {
    setShowProblems(true);
    if (hasProblems(accountProblems(accountDraft))) return false;
    void run(async csrf => {
      // An e-mail invitation is named by the link already opened in this browser: no code is sent.
      const named = kind === 'EMAIL_INVITATION' ? {} : { code: codeFromInput(code) };
      let result;
      try { result = await request('accounts', createdAccountSchema, { csrf, body: { ...named, firstName, lastName, email, password } }); }
      catch (cause) { throw accountCreationFailure(kind, cause); }
      setPassword('');
      onSignedIn(result.kind);
    });
    return true;
  }

  return {
    step, kind, schoolName, busy, error, heading, showProblems,
    code, setCode, email, setEmail, password, setPassword, firstName, setFirstName, lastName, setLastName,
    problems: showProblems ? problems : {}, codeProblem: showProblems ? typedCodeProblem : null,
    go, existingAccount, signIn, submitCode, register,
    /** Leaving for the recovery page in another tab never leaves the password typed here. */
    forgetPassword: () => setPassword(''),
    /** The typed code can be replaced while its journey is kept until another code is read. */
    canChangeCode: step === 'register' && kind !== 'EMAIL_INVITATION' && !initialCode,
  };
}
export type AccountEntryState = ReturnType<typeof useAccountEntry>;
