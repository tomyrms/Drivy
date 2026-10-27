import { useEffect, useState, useSyncExternalStore } from 'react';
import { meSchema, request, RequestFailure, sessionSchema } from './protocol';
import { load, notificationKeys, saveNotificationPreferences } from './notification-preferences-model';
import { NotificationPreferenceStore } from './notification-preferences-store';
import { CheckField } from './ui';

export function NotificationPreferencesSection() {
  const [store] = useState(() => new NotificationPreferenceStore({
    read: async () => {
      const me = (await request('me', meSchema)).data;
      return { personId: me.personId, value: await load() };
    },
    write: async (personId, choices, version) => {
      const session = await request('session', sessionSchema);
      if (!session.authenticated) throw new RequestFailure('SESSION_EXPIRED', 401);
      const me = (await request('me', meSchema)).data;
      if (me.personId !== personId) return { ok: false, conflict: false, kind: 'contextChanged' };
      return saveNotificationPreferences(choices, version, session.csrfToken);
    },
  }));
  const state = useSyncExternalStore(store.subscribe, store.getSnapshot);
  const [slow, setSlow] = useState(false);
  useEffect(() => {
    void store.refresh();
    const resume = () => { if (document.visibilityState === 'visible') void store.refresh(); };
    const pageShow = () => void store.refresh();
    const pageHide = () => store.clear();
    const beforeUnload = (event: BeforeUnloadEvent) => {
      if (store.getSnapshot().pendingKeys.length) { event.preventDefault(); event.returnValue = ''; }
    };
    document.addEventListener('visibilitychange', resume);
    window.addEventListener('online', pageShow);
    window.addEventListener('pageshow', pageShow);
    window.addEventListener('pagehide', pageHide);
    window.addEventListener('beforeunload', beforeUnload);
    return () => {
      document.removeEventListener('visibilitychange', resume);
      window.removeEventListener('online', pageShow);
      window.removeEventListener('pageshow', pageShow);
      window.removeEventListener('pagehide', pageHide);
      window.removeEventListener('beforeunload', beforeUnload);
      store.clear();
    };
  }, [store]);
  useEffect(() => {
    setSlow(false);
    if (state.phase !== 'saving') return;
    const timer = window.setTimeout(() => setSlow(true), 5_000);
    return () => window.clearTimeout(timer);
  }, [state.phase]);
  return <section className="settings-section"><div className="settings-section-heading"><h2>Notifications</h2></div>
    <div className="settings-section-body">
      {state.value && <fieldset className="fieldset"><legend className="visually-hidden">Notifications</legend>
        {notificationKeys.map(item => <CheckField key={item.key} checked={state.value![item.key]} onChange={value => store.choose(item.key, value)}
          label={<>{item.label}{state.pendingKeys.includes(item.key) && <span className="visually-hidden"> · Choix en attente de confirmation</span>}</>} />)}
      </fieldset>}
      {state.message && <p className="field-error" role="alert">{state.message}</p>}
      {state.phase === 'uncertain' && <div className="button-row compact">
        <button type="button" className="button secondary" onClick={() => void store.refresh()}>Vérifier</button>
        <button type="button" className="button quiet" onClick={() => void store.retry()}>Renvoyer les mêmes choix</button>
      </div>}
      {state.phase === 'conflict' && <div className="button-row compact">
        <button type="button" className="button secondary" onClick={() => void store.retry()}>Appliquer mes choix</button>
        <button type="button" className="button quiet" onClick={() => store.useConfirmed()}>Garder les choix actuels</button>
      </div>}
      {(state.phase === 'unavailable' || state.phase === 'rejected') && <button type="button" className="button quiet" onClick={() => void store.refresh()}>Réessayer</button>}
      {slow && <p role="status">Synchronisation en cours…</p>}
      <p className="visually-hidden" role="status">{state.phase === 'loading' ? 'Chargement des préférences.'
        : state.phase === 'saving' ? 'Choix en cours de synchronisation.' : state.phase === 'ready' ? 'Préférences synchronisées.' : ''}</p>
    </div>
  </section>;
}
