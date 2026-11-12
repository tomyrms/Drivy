import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { commandStore } from '../../command-store';
import { ScopedReadCache } from '../../console/load-model';
import { readError, type ConsoleContextValue } from '../../console/context';
import { canPersonalizeSignals } from '../../console/observation-preferences-model';
import { meSchema, request, RequestFailure, sessionSchema } from '../../protocol';
import type { Me, Member } from '../../protocol';
import { readSchool, schoolSchema, type School } from '../../school-api';

/**
 * Cadre d'une page PERSONNELLE liée à une école (R08) : le compte lit et écrit ses propres préférences dans le contexte d'une école
 * où il est moniteur ou administrateur, sans ouvrir la gestion de l'école (réservée à l'administration). Même magasin de commandes,
 * mêmes reçus et mêmes gardes que la gestion : seul le cadre est plus léger. Le serveur relit les droits à chaque requête.
 */
export type PersonalScope =
  | { status: 'loading' }
  | { status: 'signin' }
  | { status: 'error'; message: string }
  /** Compte sans rôle de terrain ou d'administration (élève seul) : rien à régler ici. */
  | { status: 'none'; me: Me }
  | { status: 'ready'; me: Me; membership: Member; school: School; eligible: Member[] };

const sameAccess = (left: Member | undefined, right: Member | undefined) =>
  left !== undefined && right !== undefined && left.membershipId === right.membershipId && left.accessEpoch === right.accessEpoch
  && left.roles.join() === right.roles.join();

export function usePersonalScope(initialSchoolId?: string) {
  const [state, setState] = useState<PersonalScope>({ status: 'loading' });
  const stateRef = useRef(state); stateRef.current = state;
  const generation = useRef(0);
  const csrf = useRef('');
  const unsaved = useRef(new Set<string>());
  const [departure, setDeparture] = useState<{ proceed: () => void } | null>(null);

  const load = useCallback(async (schoolId?: string) => {
    const current = ++generation.current;
    setState({ status: 'loading' });
    try {
      const session = await request('session', sessionSchema);
      if (current !== generation.current) return;
      csrf.current = session.csrfToken;
      if (!session.authenticated) { setState({ status: 'signin' }); return; }
      const me = (await request('me', meSchema)).data;
      if (current !== generation.current) return;
      // Another person on the same browser never inherits followed requests.
      if (commandStore.scopeToPerson(me.personId)) unsaved.current.clear();
      const eligible = me.memberships.filter(member => canPersonalizeSignals(member.roles));
      if (eligible.length === 0) { setState({ status: 'none', me }); return; }
      const membership = eligible.find(member => member.schoolId.toLowerCase() === schoolId?.toLowerCase()) ?? eligible[0]!;
      commandStore.scopeToAccess(membership.schoolId, membership.membershipId, membership.accessEpoch);
      const school = await readSchool(membership.schoolId, '', schoolSchema);
      if (current !== generation.current) return;
      if (school.id !== membership.schoolId) throw new RequestFailure('INVALID_RESPONSE');
      setState({ status: 'ready', me, membership, school, eligible });
    } catch (error) {
      if (current !== generation.current) return;
      if (error instanceof RequestFailure && error.status === 401) { setState({ status: 'signin' }); return; }
      setState({ status: 'error', message: readError(error) });
    }
  }, []);

  useEffect(() => { void load(initialSchoolId); return () => { generation.current++; }; }, [load]);

  /** Account or access changed behind the page (another tab, restored page): start again, drafts included. */
  const revalidate = useCallback(async () => {
    const previous = stateRef.current;
    if (previous.status !== 'ready') return;
    const scope = generation.current;
    try {
      const session = await request('session', sessionSchema);
      if (scope !== generation.current) return;
      csrf.current = session.csrfToken;
      const me = session.authenticated ? (await request('me', meSchema)).data : null;
      if (scope !== generation.current) return;
      const membership = me?.memberships.find(member => member.schoolId === previous.membership.schoolId);
      if (!me || me.personId !== previous.me.personId || !sameAccess(membership, previous.membership)) {
        unsaved.current.clear(); setDeparture(null);
        await load(previous.membership.schoolId);
      }
    } catch { /* A failed check keeps the page: the next request or the server will say. */ }
  }, [load]);

  useEffect(() => {
    const resume = () => { if (document.visibilityState === 'visible') void revalidate(); };
    const pageShow = (event: PageTransitionEvent) => { if (event.persisted) void revalidate(); };
    const beforeUnload = (event: BeforeUnloadEvent) => { if (unsaved.current.size) { event.preventDefault(); event.returnValue = ''; } };
    document.addEventListener('visibilitychange', resume);
    window.addEventListener('pageshow', pageShow);
    window.addEventListener('beforeunload', beforeUnload);
    return () => {
      document.removeEventListener('visibilitychange', resume);
      window.removeEventListener('pageshow', pageShow);
      window.removeEventListener('beforeunload', beforeUnload);
    };
  }, [revalidate]);

  const proceed = useCallback((next: () => void) => {
    if (unsaved.current.size) setDeparture({ proceed: next }); else next();
  }, []);

  const scopeKey = state.status === 'ready' ? `${state.me.personId}/${state.membership.schoolId}/${state.membership.membershipId}/${state.membership.accessEpoch}` : null;
  // Drafts and reads belong to one account, school and access: any change of the four starts them again.
  const drafts = useMemo(() => new Map<string, unknown>(), [scopeKey]);
  const readCache = useMemo(() => new ScopedReadCache(), [scopeKey]);
  useEffect(() => () => readCache.invalidate(), [readCache]);

  const registerUnsavedChanges = useCallback((id: string) => { unsaved.current.add(id); return () => { unsaved.current.delete(id); }; }, []);

  const context = useMemo<ConsoleContextValue | null>(() => {
    if (state.status !== 'ready') return null;
    return {
      schoolId: state.membership.schoolId, me: state.me, membership: state.membership, school: state.school,
      canConfigureCatalog: false, drafts, readCache, registerUnsavedChanges, confirmNavigation: proceed,
      reloadSchool: revalidate,
      csrf: () => csrf.current,
      refreshCsrf: async () => { const next = await request('session', sessionSchema); csrf.current = next.csrfToken; return next.csrfToken; },
      // Cette page n'a pas de sections : un lien de la gestion n'y mène nulle part.
      navigate: () => undefined,
      login: () => window.location.assign('/app/'),
    };
  }, [state, drafts, readCache, registerUnsavedChanges, proceed, revalidate]);

  const select = useCallback((schoolId: string) => proceed(() => { unsaved.current.clear(); void load(schoolId); }), [proceed, load]);

  return { state, context, load, select, proceed, departure, setDeparture, unsaved };
}
