import { useState } from 'react';
import { createCommand } from '../command-core';
import { ConfirmDialog } from '../ui';
import { useCommandRunner, useConsole } from './context';
import { OutcomeNotice } from './layout';

/** The school enables the option; each lesson still needs its own allowed recording choice and device checks. */
export function GPSSettings() {
  const { schoolId, school, reloadSchool } = useConsole();
  const [review, setReview] = useState<{ enabled: boolean; version: number } | null>(null);
  const runner = useCommandRunner(() => setReview(null));
  const enabled = school.modules.gpsEnabled;
  const action = enabled ? 'Désactiver les trajets GPS' : 'Activer les trajets GPS';
  const reviewAction = review?.enabled ? 'Activer les trajets GPS' : 'Désactiver les trajets GPS';

  async function confirm() {
    if (!review || runner.busy || runner.pending) return;
    const result = await runner.run(createCommand({ schoolId, kind: 'updateModules', path: 'modules',
      ifMatch: review.version, resourceVersion: review.version, body: { gpsEnabled: review.enabled } }),
    review.enabled ? 'Les trajets GPS sont activés pour l’école.' : 'Les trajets GPS sont désactivés pour l’école.');
    if (result.status !== 'rejected') setReview(null);
  }

  const outcome = <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome}
    actions={runner.outcome?.code === 'VERSION_CONFLICT' ? <button type="button" className="button secondary"
      onClick={() => { setReview(null); runner.clearOutcome(); void reloadSchool(); }}>Recharger le réglage</button> : undefined} />;

  return <section className="settings-section" aria-labelledby="gps-title">
    <div className="settings-section-heading">
      <div className="settings-section-title"><h2 id="gps-title" className="section-title">Trajets GPS</h2>
        <span className="row-meta">{enabled ? 'Activés' : 'Désactivés'}</span></div>
      <button id="school-gps" type="button" className={`button ${enabled ? 'secondary' : 'primary'}`}
        disabled={runner.busy || !!runner.pending} onClick={() => {
          runner.clearOutcome(); setReview({ enabled: !enabled, version: school.version });
        }}>{action}</button>
    </div>
    {!review && outcome}
    {runner.blockedReason && <p className="caption">{runner.blockedReason}</p>}
    <ConfirmDialog open={review !== null} busy={runner.busy} onCancel={() => setReview(null)} onConfirm={() => void confirm()}
      title={reviewAction} confirmLabel={review?.enabled ? 'Activer' : 'Désactiver'} disabledReason={runner.blockedReason}>
      {outcome}
      {review?.enabled
        ? <p>Les moniteurs pourront enregistrer les trajets dans l’app, avec l’accord de l’élève et la localisation autorisée sur leur appareil.</p>
        : <p>Les trajets en cours seront arrêtés, dès la reconnexion pour un appareil hors ligne. Les leçons pourront continuer sans GPS.</p>}
    </ConfirmDialog>
  </section>;
}
