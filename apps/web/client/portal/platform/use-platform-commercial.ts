import { useState } from 'react';
import { request, type Session } from '../../protocol';
import { platformCommercialResult, type PlatformCommercialDetail } from '../../platform-model';
import type { ClientCommercial } from './use-platform-clients';
import { useOperationIds } from './use-platform-offers';

type Kernel = {
  session: Session | null; perform: (action: () => Promise<void>) => Promise<void>; reload: () => Promise<void>;
  clientId: string | null; commercial: ClientCommercial | null; setCommercial: (next: ClientCommercial | null) => void;
};
export type CommercialDialog =
  | { kind: 'terms' }
  | { kind: 'trial-start' }
  | { kind: 'trial-extend' }
  | { kind: 'trial-end' }
  | { kind: 'paid-start' }
  | { kind: 'paid-cancel' }
  | { kind: 'request' }
  | { kind: 'decision'; requestId: string }
  | { kind: 'revision'; requestId: string; action: 'CHANGE_DATE' | 'RESUME' };

/** Valeurs d'une version de conditions, au format de la commande : chaque version redonne tout, `null` reste à compléter. */
export type TermsInput = {
  initialAmount: number | null; initialDiscount: number; initialDueOn: string | null; monthlyAmount: number | null; recurringDiscount: number;
  recurringDiscountMonths: number | null; paymentTermDays: number | null; suspensionBilling: 'CONTINUE' | 'PAUSE' | null;
  effectiveFrom?: string; exceptionReason?: string;
};
export type RequestInput = { kind: 'OFFER_CHANGE' | 'TERMINATION'; requestedOn: string; requestedOfferId?: string; desiredOn?: string; details?: string };
export type DecisionInput = { status: 'IN_PROGRESS' | 'ACCEPTED' | 'REFUSED' | 'WITHDRAWN'; response?: string; effectiveOn?: string; offerId?: string };
export type RevisionInput = { action: 'CHANGE_DATE' | 'RESUME'; effectiveOn?: string; response: string };

/**
 * Dossier commercial d'une école cliente (R01-T04) : conditions, essai, début payant, demandes. Chaque commande part sous la version du
 * dossier que l'écran a lue et rend le dossier relu après écriture ; un conflit relit toute la console. Aucun montant n'est calculé ici.
 */
export function usePlatformCommercial({ session, perform, reload, clientId, commercial, setCommercial }: Kernel) {
  const [dialog, setDialog] = useState<CommercialDialog | null>(null);
  const operations = useOperationIds();
  const current: PlatformCommercialDetail | null = commercial && commercial.clientId === clientId ? commercial.data : null;

  const stop = () => setDialog(null);
  const start = (next: CommercialDialog) => setDialog(next);
  const reset = () => { stop(); operations.clear(); };

  async function write(action: string, path: string, body: object) {
    if (!session || !clientId || !current) return;
    const key = `${action}:${clientId}:${current.version}:${JSON.stringify(body)}`;
    const operationId = operations.operationFor(key);
    try {
      const result = await request(`platform/clients/${clientId}/commercial/${path}`, platformCommercialResult,
        { csrf: session.csrfToken, body: { operationId, version: current.version, ...body } });
      operations.settle(key); setCommercial({ clientId, data: result.data });
    } catch (reason) { operations.settle(key, reason); throw reason; }
    stop();
    await reload();
  }

  const saveTerms = (input: TermsInput) => perform(() => write('terms', 'terms', input));
  const startTrial = (endsAt: string, startsAt?: string) => perform(() => write('trial-start', 'trial/start', { endsAt, ...(startsAt ? { startsAt } : {}) }));
  const extendTrial = (endsAt: string, reason: string) => perform(() => write('trial-extend', 'trial/extend', { endsAt, reason: reason.trim() }));
  const endTrial = (reason: string) => perform(() => write('trial-end', 'trial/end', { reason: reason.trim() }));
  const confirmPaidStart = (startsOn: string) => perform(() => write('paid-start', 'paid-start', { startsOn, confirm: true }));
  const cancelPaidStart = (reason: string) => perform(() => write('paid-cancel', 'paid-start/cancel', { reason: reason.trim() }));
  const recordRequest = (input: RequestInput) => perform(() => write('request', 'requests', input));
  const decide = (requestId: string, input: DecisionInput) => perform(() => write(`decision:${requestId}`, `requests/${requestId}/decision`, input));
  const revise = (requestId: string, input: RevisionInput) => perform(() => write(`revision:${requestId}`, `requests/${requestId}/revision`, input));

  return { commercial: current, dialog, start, stop, reset, saveTerms, startTrial, extendTrial, endTrial, confirmPaidStart, cancelPaidStart, recordRequest, decide, revise };
}
export type PlatformCommercialState = ReturnType<typeof usePlatformCommercial>;
