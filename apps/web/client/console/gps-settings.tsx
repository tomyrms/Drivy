import { useEffect, useRef, useState } from 'react';
import { createCommand } from '../command-core';
import { ConfirmDialog, Notice } from '../ui';
import { request, sessionSchema } from '../protocol';
import { readError, useCommandRunner, useConsole } from './context';
import { OutcomeNotice } from './layout';

/** The school enables the option; each lesson still needs its own allowed recording choice and device checks. */
export function GPSSettings() {
  const { schoolId, school, reloadSchool, confirmIdentity, login } = useConsole();
  const [review, setReview] = useState<{ enabled: boolean; version: number } | null>(null);
  const runner = useCommandRunner(() => setReview(null));
  const [checkingIdentity, setCheckingIdentity] = useState(false), [identityError, setIdentityError] = useState<string | null>(null);
  const checking = useRef(false), mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const enabled = school.modules.gpsEnabled;
  const action = enabled ? 'Désactiver les trajets GPS' : 'Activer les trajets GPS';
  const reviewAction = review?.enabled ? 'Activer les trajets GPS' : 'Désactiver les trajets GPS';

  async function confirm() {
    if (!review || runner.busy || runner.pending || checking.current) return;
    checking.current = true; setCheckingIdentity(true); setIdentityError(null);
    try {
      const session = await request('session', sessionSchema);
      if (!mounted.current) return;
      if (!session.authenticated) { login(); return; }
      if (session.reauthenticationRequired) {
        if (confirmIdentity) { if (await confirmIdentity() && mounted.current) runner.clearOutcome(); }
        else login({ reauthenticate: true });
        // The reviewed GPS setting remains open. Authentication alone never changes it.
        return;
      }
      const result = await runner.run(createCommand({ schoolId, kind: 'updateModules', path: 'modules',
        ifMatch: review.version, resourceVersion: review.version, body: { gpsEnabled: review.enabled } }),
      review.enabled ? 'Les trajets GPS sont activés pour l’école.' : 'Les trajets GPS sont désactivés pour l’école.');
      if (!mounted.current) return;
      if (result.status !== 'rejected') setReview(null);
      else if (result.code === 'REAUTH_REQUIRED' && confirmIdentity && await confirmIdentity() && mounted.current) runner.clearOutcome();
    } catch (error) { if (mounted.current) setIdentityError(readError(error)); }
    finally { checking.current = false; if (mounted.current) setCheckingIdentity(false); }
  }

  const outcome = runner.outcome?.code === 'REAUTH_REQUIRED'
    ? <Notice tone="warning" title="Confirmez votre identité pour continuer." />
    : <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome}
    actions={runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary"
      onClick={() => { setReview(null); runner.clearOutcome(); void reloadSchool(); }}>Recharger le réglage</button> : undefined} />;

  return <section className="settings-section" aria-labelledby="gps-title">
    <div className="settings-section-heading">
      <div className="settings-section-title"><h2 id="gps-title" className="section-title">Trajets GPS</h2>
        <span className="row-meta">{enabled ? 'Activés' : 'Désactivés'}</span></div>
      <button id="school-gps" type="button" className={`button ${enabled ? 'secondary' : 'primary'}`}
        disabled={runner.busy || checkingIdentity || !!runner.pending} onClick={() => {
          runner.clearOutcome(); setIdentityError(null); setReview({ enabled: !enabled, version: school.version });
        }}>{action}</button>
    </div>
    {!review && outcome}
    {runner.blockedReason && <p className="caption">{runner.blockedReason}</p>}
    <ConfirmDialog open={review !== null} busy={runner.busy || checkingIdentity} busyLabel={checkingIdentity && !runner.busy ? 'Vérification…' : 'Confirmation par l’école…'} onCancel={() => setReview(null)} onConfirm={() => void confirm()}
      title={reviewAction} confirmLabel={review?.enabled ? 'Activer' : 'Désactiver'} disabledReason={runner.blockedReason}>
      {outcome}
      {identityError && <Notice tone="error" title="Vérification impossible"><p>{identityError}</p></Notice>}
      {review?.enabled
        ? <p>Les moniteurs pourront enregistrer les trajets dans l’app, avec l’accord de l’élève et la localisation autorisée sur leur appareil.</p>
        : <p>Les trajets en cours seront arrêtés, dès la reconnexion pour un appareil hors ligne. Les leçons pourront continuer sans GPS.</p>}
    </ConfirmDialog>
  </section>;
}
