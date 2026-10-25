import { useEffect, useState } from 'react';
import { request, sessionSchema } from './protocol';
import { load, notificationKeys, saveNotificationPreferences, type Choices, type NotificationPreferences } from './notification-preferences-model';

export function NotificationPreferencesSection() {
  const [current, setCurrent] = useState<NotificationPreferences | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'unavailable' | 'saving' | 'saved' | 'conflict' | 'failed'>('loading');
  const reload = () => { setState('loading'); load().then(value => { setCurrent(value); setState('ready'); }).catch(() => setState('unavailable')); };
  useEffect(reload, []);
  const toggle = async (key: keyof Choices, value: boolean) => {
    if (!current) return;
    const { version, ...choices } = current;
    setState('saving');
    let csrf: string;
    try { csrf = (await request('session', sessionSchema)).csrfToken; } catch { setState('failed'); return; }
    const outcome = await saveNotificationPreferences({ ...choices, [key]: value }, version, csrf);
    if (outcome.ok) { setCurrent(outcome.value); setState('saved'); }
    else setState(outcome.conflict ? 'conflict' : 'failed');
  };
  return <section className="settings-section"><div className="settings-section-heading"><h2>Notifications</h2></div>
    <div className="settings-section-body">
      {state === 'unavailable' && <p className="field-error" role="alert">Préférences indisponibles. <button type="button" className="button quiet" onClick={reload}>Réessayer</button></p>}
      {current && <fieldset disabled={state === 'saving' || state === 'loading'}><legend className="visually-hidden">Notifications</legend>
        {notificationKeys.map(item => <label className="switch-row" key={item.key}>
          <input type="checkbox" role="switch" checked={current[item.key]} onChange={event => void toggle(item.key, event.target.checked)} />
          <span>{item.label}</span>
        </label>)}
      </fieldset>}
      {state === 'conflict' && <p className="field-error" role="alert">Modifiées ailleurs. <button type="button" className="button quiet" onClick={reload}>Recharger</button></p>}
      {state === 'failed' && <p className="field-error" role="alert">Non enregistré. Réessayez.</p>}
      <p className="visually-hidden" role="status">{state === 'saved' ? 'Enregistré.' : ''}</p>
    </div>
  </section>;
}
