import { useEffect, useRef, useState } from 'react';
import { okSchema, request, sessionSchema, type Session } from '../../protocol';
import {
  accessCodeSchema, accountCreationFailure, accountProblems, codeFromInput, codeProblem, createdAccountSchema, entryFailureMessage,
  hasProblems, initialAccessKind, initialEntryStep, signInProblems, singleFlight, type AccessKind, type AccountDraft, type DraftProblems, type EntryStep,
} from './entry-model';

export interface AccountEntryOptions {
  /** An opening link already names its code. */
  initialCode?: string;
  /** Opened from an invitation link: the account is named by that link, no code is typed. */
  invitation?: boolean;
  /** The person is signed in and only types a code. */
  signedIn?: boolean;
  /** The typed code can live above this form, so that it survives the page learning who is signed in. */
  typedCode?: { value: string; set: (value: string) => void };
  onSignedIn: (kind: AccessKind | null) => void;
}

/**
 * Sign-in and account creation, the same as in the app: « Se connecter », or « J’ai un code ».
 * Only a valid code (or link) can create an account. The password goes to the identity service and is never kept:
 * it is cleared after each attempt that leaves the form and at every change of step.
 */
export function useAccountEntry({ initialCode, invitation = false, signedIn = false, typedCode, onSignedIn }: AccountEntryOptions) {
  const [chosenStep, setStep] = useState<EntryStep>(() => initialEntryStep({ signedIn, invitation, ...(initialCode ? { initialCode } : {}) }));
  // Presentation follows a proven session without recreating the form or its single flight.
  const step = signedIn ? 'code' : chosenStep;
  const previousSignedIn = useRef(signedIn);
  const [ownCode, setOwnCode] = useState(initialCode ?? '');
  const code = typedCode ? typedCode.value : ownCode;
  const setCode = typedCode ? typedCode.set : setOwnCode;
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
  const flight = useRef(singleFlight()).current;
  const codeInput = useRef<HTMLInputElement>(null);
  const mounted = useRef(true);

  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  useEffect(() => {
    if (started.current && previousSignedIn.current === signedIn) (step === 'code' ? codeInput : heading).current?.focus({ preventScroll: true });
    previousSignedIn.current = signedIn;
    started.current = true;
  }, [step, signedIn]);
  useEffect(() => {
    // An opening link already names its code: read what it opens, so that an expired link says so before the form.
    if (initialCode) void run(session => inspect(initialCode, session));
  }, []);

  async function run(action: (session: Session) => Promise<void>) {
    await flight(async () => {
      setBusy(true); setError(null);
      try {
        const session = await request('session', sessionSchema);
        if (mounted.current) await action(session);
      }
      catch (cause) {
        if (!mounted.current) return;
        setError(entryFailureMessage(cause));
        // The typed code stays in the field; the refusal is attached to it and takes the focus.
        if (step === 'code') requestAnimationFrame(() => codeInput.current?.focus({ preventScroll: true }));
      }
      finally { if (mounted.current) setBusy(false); }
    });
  }
  /** Reads what a code opens. Only the server's answer says whether the person is signed in, never the screen that was open. */
  async function inspect(value: string, session: Session) {
    const result = await request('access-code', accessCodeSchema, { csrf: session.csrfToken, body: { code: codeFromInput(value) } });
    if (!mounted.current) return;
    setKind(result.kind); setSchoolName(result.schoolName ?? null);
    if (signedIn || session.authenticated) { onSignedIn(result.kind); return; }
    setStep('register');
  }
  function go(next: EntryStep) { setError(null); setShowProblems(false); setPassword(''); setStep(next); }
  function existingAccount() {
    if (!code.trim()) { go('login'); return; }
    // A typed code is read first, so that the journey it opens continues after sign-in.
    void run(async session => { await inspect(code, session); go('login'); });
  }

  const signInDraft = { email, password };
  const accountDraft = { firstName, lastName, email, password };
  const problems: DraftProblems<AccountDraft> = step === 'login' ? signInProblems(signInDraft) : step === 'register' ? accountProblems(accountDraft) : {};
  const typedCodeProblem = step === 'code' ? codeProblem(code) : null;

  function signIn() {
    setShowProblems(true);
    if (hasProblems(signInProblems(signInDraft))) return false;
    void run(async ({ csrfToken: csrf }) => {
      await request('password-login', okSchema, { csrf, body: { email, password } });
      if (!mounted.current) return;
      setPassword('');
      onSignedIn(kind);
    });
    return true;
  }
  function submitCode() {
    setShowProblems(true);
    if (codeProblem(code)) return false;
    void run(session => inspect(code, session));
    return true;
  }
  function register() {
    setShowProblems(true);
    if (hasProblems(accountProblems(accountDraft))) return false;
    void run(async ({ csrfToken: csrf }) => {
      // An e-mail invitation is named by the link already opened in this browser: no code is sent.
      const named = kind === 'EMAIL_INVITATION' ? {} : { code: codeFromInput(code) };
      let result;
      try { result = await request('accounts', createdAccountSchema, { csrf, body: { ...named, firstName, lastName, email, password } }); }
      catch (cause) { throw accountCreationFailure(kind, cause); }
      // A refusal keeps the typed password so the person can correct the other fields;
      // it is cleared only when this form is left.
      if (!mounted.current) return;
      setPassword('');
      onSignedIn(result.kind);
    });
    return true;
  }

  return {
    step, kind, schoolName, busy, error, heading, codeInput, showProblems,
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
