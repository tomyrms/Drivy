import { useState } from 'react';
import { request, type Session } from '../../protocol';
import {
  platformAssignmentPreviewResult, platformEntitlementsResult,
  type PlatformAssignmentPreview, type PlatformEntitlements,
} from '../../platform-model';
import type { ClientRights } from './use-platform-clients';
import { useOperationIds } from './use-platform-offers';

type Kernel = {
  session: Session | null; perform: (action: () => Promise<void>) => Promise<void>; reload: () => Promise<void>;
  clientId: string | null; rights: ClientRights | null; setRights: (next: ClientRights | null) => void;
};
type Effect = 'GRANT' | 'REVOKE';
export type RightsDialog =
  | { kind: 'assign' }
  | { kind: 'adjust'; moduleCode: string; effect: Effect }
  | { kind: 'lift'; adjustmentId: string }
  | { kind: 'cancel'; assignmentId: string };
/** Un aperçu n'est valable que pour l'offre et la date qui l'ont produit, et pour la version des droits qu'il a lue. */
export type AssignmentChoice = { offerId: string; effectiveAt: string | null };
export type ShownPreview = { choice: AssignmentChoice; data: PlatformAssignmentPreview };

/**
 * Droits d'une école cliente aux modules (R01-T03) : attribuer une offre (immédiatement ou à une date), annuler une attribution programmée,
 * ajuster un module avec un motif, lever un ajustement. Chaque commande part sous la version des droits que l'écran a lue : un conflit relit tout.
 */
export function usePlatformRights({ session, perform, reload, clientId, rights, setRights }: Kernel) {
  const [dialog, setDialog] = useState<RightsDialog | null>(null), [preview, setPreview] = useState<ShownPreview | null>(null);
  const operations = useOperationIds();
  const current: PlatformEntitlements | null = rights && rights.clientId === clientId ? rights.data : null;

  const stop = () => { setDialog(null); setPreview(null); };
  const startAssign = () => { setPreview(null); setDialog({ kind: 'assign' }); };
  const startAdjust = (moduleCode: string, effect: Effect) => { setPreview(null); setDialog({ kind: 'adjust', moduleCode, effect }); };
  const startLift = (adjustmentId: string) => setDialog({ kind: 'lift', adjustmentId });
  const startCancel = (assignmentId: string) => setDialog({ kind: 'cancel', assignmentId });
  const reset = () => { stop(); operations.clear(); };

  /** Les conséquences sont calculées par le serveur avant toute écriture : volumes existants, ajustements qui prennent fin. */
  const showPreview = (choice: AssignmentChoice) => perform(async () => {
    if (!clientId) return;
    const query = new URLSearchParams({ offerId: choice.offerId });
    if (choice.effectiveAt) query.set('effectiveAt', choice.effectiveAt);
    const result = await request(`platform/clients/${clientId}/assignment-preview?${query}`, platformAssignmentPreviewResult);
    setPreview({ choice, data: result.data });
  });

  /** Écrit sous la version lue ; la réponse porte les droits à jour, la fiche est relue ensuite. */
  async function write(key: string, path: string, body: Record<string, unknown>) {
    if (!session || !clientId || !current) return;
    const operationId = operations.operationFor(key);
    try {
      const result = await request(path, platformEntitlementsResult, { csrf: session.csrfToken, body: { operationId, version: current.version, ...body } });
      operations.settle(key); setRights({ clientId, data: result.data });
    } catch (reason) { operations.settle(key, reason); throw reason; }
    stop();
    await reload();
  }

  const assign = (choice: AssignmentChoice) => perform(async () => {
    if (!clientId || !current || !preview || preview.choice.offerId !== choice.offerId || preview.choice.effectiveAt !== choice.effectiveAt || preview.data.version !== current.version) return;
    await write(`assign:${clientId}:${current.version}:${choice.offerId}:${choice.effectiveAt ?? 'now'}`, `platform/clients/${clientId}/assignments`,
      { offerId: choice.offerId, ...(choice.effectiveAt ? { effectiveAt: choice.effectiveAt } : {}) });
  });
  const cancelAssignment = (assignmentId: string) => perform(async () => {
    if (!clientId || !current) return;
    await write(`cancel:${clientId}:${current.version}:${assignmentId}`, `platform/clients/${clientId}/assignments/${assignmentId}/cancel`, {});
  });
  const adjust = (moduleCode: string, effect: Effect, reason: string) => perform(async () => {
    if (!clientId || !current) return;
    const text = reason.trim();
    await write(`adjust:${clientId}:${current.version}:${moduleCode}:${effect}:${text}`, `platform/clients/${clientId}/adjustments`, { moduleCode, effect, reason: text });
  });
  const lift = (adjustmentId: string, reason: string) => perform(async () => {
    if (!clientId || !current) return;
    const text = reason.trim();
    await write(`lift:${clientId}:${current.version}:${adjustmentId}:${text}`, `platform/clients/${clientId}/adjustments/${adjustmentId}/lift`, { reason: text });
  });

  return { rights: current, dialog, preview, reset, stop, startAssign, startAdjust, startLift, startCancel, showPreview, assign, cancelAssignment, adjust, lift };
}
export type PlatformRightsState = ReturnType<typeof usePlatformRights>;
