import { useState } from 'react';
import { request, RequestFailure, type Session } from '../../protocol';
import {
  platformCommercialAlertsResult, platformDunningPolicyResult, platformDunningRunResult, platformDunningViewResult,
  type PlatformCommercialAlert, type PlatformDunningPolicy, type PlatformDunningRun, type PlatformDunningView,
} from '../../platform-model';
import type { ClientDunning } from './use-platform-clients';
import { useOperationIds } from './use-platform-offers';

type Kernel = {
  session: Session | null; perform: (action: () => Promise<void>) => Promise<void>; reload: () => Promise<void>; clearError: () => void;
  clientId: string | null; dunning: ClientDunning | null; setDunning: (next: ClientDunning | null) => void;
};
export type DunningDialog =
  | { kind: 'policy' }
  | { kind: 'run' }
  | { kind: 'exception' }
  | { kind: 'revoke'; exceptionId: string }
  | { kind: 'suspend' }
  | { kind: 'lift'; suspensionId: string }
  | { kind: 'confirm'; stepId: string };
/** La politique au format de la commande : chaque version redonne tout. */
export type DunningPolicyInput = Omit<PlatformDunningPolicy, 'version' | 'updatedAt' | 'updatedByName'>;
export type DunningSnapshot = { policy: PlatformDunningPolicy; alerts: PlatformCommercialAlert[] };

/**
 * Relances et suspension (R01-T09) : politique globale, alertes de la console, passage manuel et dossier de relance de la fiche ouverte.
 * Chaque commande d'un dossier part sous la version que l'écran a lue et rend le dossier relu après écriture ; un conflit relit toute la console.
 * Aucun retard, aucune date de suspension ni aucune dette ne sont calculés ici.
 */
export function usePlatformDunning({ session, perform, reload, clearError, clientId, dunning, setDunning }: Kernel) {
  const [dialog, setDialog] = useState<DunningDialog | null>(null);
  const [policy, setPolicy] = useState<PlatformDunningPolicy | null>(null), [alerts, setAlerts] = useState<PlatformCommercialAlert[]>([]);
  const [run, setRun] = useState<PlatformDunningRun | null>(null);
  const operations = useOperationIds();
  const current: PlatformDunningView | null = dunning && dunning.clientId === clientId ? dunning.data : null;

  const stop = () => { setDialog(null); setRun(null); };
  // Ouvrir une boîte efface le refus de la précédente ; `stop` le garde, car un conflit le dit après avoir fermé.
  const start = (next: DunningDialog) => { clearError(); setRun(null); setDialog(next); };
  function reset() { stop(); operations.clear(); setPolicy(null); setAlerts([]); }

  async function snapshot(): Promise<DunningSnapshot> {
    const [rules, open] = await Promise.all([request('platform/dunning/policy', platformDunningPolicyResult),
      request('platform/commercial-alerts', platformCommercialAlertsResult)]);
    return { policy: rules.data, alerts: open.data.items };
  }
  function apply(next: DunningSnapshot) { setPolicy(next.policy); setAlerts(next.alerts); }

  async function write(action: string, path: string, body: object) {
    if (!session || !clientId || !current) return;
    const key = `${action}:${clientId}:${current.version}:${JSON.stringify(body)}`, operationId = operations.operationFor(key);
    try {
      const result = await request(`platform/clients/${clientId}/dunning/${path}`, platformDunningViewResult,
        { csrf: session.csrfToken, body: { operationId, version: current.version, ...body } });
      operations.settle(key); setDunning({ clientId, data: result.data });
    } catch (reason) { operations.settle(key, reason); throw reason; }
    stop();
    await reload();
  }

  const grantException = (kind: 'DELAY' | 'HOLD', suspensionMonths: number | null, endsOn: string, reason: string) =>
    perform(() => write('exception', 'exceptions', { kind, ...(kind === 'DELAY' && suspensionMonths !== null ? { suspensionMonths } : {}), endsOn, reason: reason.trim() }));
  const revokeException = (exceptionId: string, reason: string) =>
    perform(() => write(`revoke:${exceptionId}`, `exceptions/${exceptionId}/revoke`, { reason: reason.trim() }));
  const suspend = (cause: 'PAYMENT' | 'MANUAL', reason: string) => perform(() => write(`suspend:${cause}`, 'suspensions', { cause, reason: reason.trim() }));
  const lift = (suspensionId: string, reason: string) =>
    perform(() => write(`lift:${suspensionId}`, `suspensions/${suspensionId}/lift`, { reason: reason.trim() }));
  const confirmWarning = (stepId: string, reason: string) =>
    perform(() => write(`confirm:${stepId}`, `steps/${stepId}/confirm`, { reason: reason.trim() }));

  const savePolicy = (input: DunningPolicyInput) => perform(async () => {
    if (!session || !policy) return;
    const key = `policy:${policy.version}:${JSON.stringify(input)}`, operationId = operations.operationFor(key);
    try {
      const result = await request('platform/dunning/policy', platformDunningPolicyResult, { csrf: session.csrfToken, body: { operationId, version: policy.version, ...input } });
      operations.settle(key); setPolicy(result.data);
    } catch (reason) { operations.settle(key, reason); throw reason; }
    stop();
    await reload();
  });
  /** Le même traitement que le service planifié, au jour de Zurich : une étape déjà faite ne se refait jamais. Le bilan reste affiché. */
  const runDunning = () => perform(async () => {
    if (!session) return;
    const key = 'dunning-run', operationId = operations.operationFor(key);
    let result: PlatformDunningRun;
    try {
      result = (await request('platform/dunning/run', platformDunningRunResult, { csrf: session.csrfToken, body: { operationId } })).data;
      operations.settle(key);
    } catch (reason) { operations.settle(key, reason); throw reason; }
    await reload();
    setRun(result);
  });
  /** Prendre une alerte en compte la retire de la liste ; cela ne règle, ne suspend et ne lève rien. */
  const acknowledge = (alertId: string) => perform(async () => {
    if (!session) return;
    const key = `alert:${alertId}`, operationId = operations.operationFor(key);
    try {
      const result = await request(`platform/commercial-alerts/${alertId}/acknowledge`, platformCommercialAlertsResult,
        { csrf: session.csrfToken, body: { operationId } });
      operations.settle(key); setAlerts(result.data.items);
    } catch (reason) {
      operations.settle(key, reason);
      // Déjà traitée ailleurs : la liste relue le montre, et le refus reste affiché.
      if (reason instanceof RequestFailure && reason.code === 'ALERT_CLOSED') await reload();
      throw reason;
    }
    await reload();
  });

  return { dunning: current, dialog, start, stop, reset, snapshot, apply, policy, alerts, run,
    savePolicy, runDunning, acknowledge, grantException, revokeException, suspend, lift, confirmWarning };
}
export type PlatformDunningState = ReturnType<typeof usePlatformDunning>;
