import { useRef } from 'react';
import type { SchoolCommand } from '../../command-core';
import type { SubmitResult } from '../../command-store';
import { useCommandRunner } from '../../console/context';

/**
 * Une commande de catalogue à la fois, par le moteur existant : aucun succès avant le reçu durable,
 * un refus garde la saisie, un résultat incertain reste suivi par le panneau des demandes en attente.
 * `onConfirmed` ne s'exécute qu'une fois l'école ayant confirmé (réponse ou reçu).
 */
export function useCatalogueCommand() {
  const after = useRef<(() => void) | null>(null);
  const runner = useCommandRunner(() => { const next = after.current; after.current = null; next?.(); });
  async function submit(command: SchoolCommand, success: string, onConfirmed: () => void): Promise<SubmitResult> {
    after.current = onConfirmed;
    const result = await runner.run(command, success);
    if (result.status === 'rejected') after.current = null;
    return result;
  }
  return { runner, submit, busy: runner.busy || !!runner.pending };
}
export type CatalogueCommand = ReturnType<typeof useCatalogueCommand>;

/** Codes du serveur qui signifient « la version affichée n'est plus la version enregistrée » : relecture, brouillon gardé. */
export const changedCodes: ReadonlySet<string> = new Set(['FORMATION_CHANGED', 'TARIFF_CHANGED', 'VERSION_CONFLICT', 'TERMS_USAGE_CHANGED']);
export const unchangedCodes: ReadonlySet<string> = new Set(['FORMATION_UNCHANGED', 'TARIFF_UNCHANGED', 'TERMS_UNCHANGED']);

/** Identifiant de la ressource créée, quand la réponse (et non un reçu) a confirmé la commande. */
export function createdId(result: SubmitResult): string | null {
  if (result.status !== 'confirmed') return null;
  const id = (result.body as { data?: { id?: unknown } } | null)?.data?.id;
  return typeof id === 'string' ? id : null;
}
