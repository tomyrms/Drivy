import { useEffect, useMemo, useRef } from 'react';
import { createCommand } from '../../command-core';
import { refusalOutcome } from '../../command-lane';
import { useCommandSnapshot } from '../../command-store';
import { useCommandLane, useConsole, type Outcome } from '../../console/context';
import { useJournal } from '../../console/session-journal';
import type { TariffDraft } from '../../console/formation-model';
import type { CatalogueReference, Tariff } from '../../formation-api';
import { changedCodes, createdId, unchangedCodes } from '../formations/catalogue-command';
import {
  projectTariffs, projectTermsRevision, resolveIntentions, tariffScope, tariffTag, termsScope, termsTag, pendingFor,
  type TariffIntention, type TermsIntention,
} from './pricing-projection';

/**
 * Les deux éditeurs du catalogue passent par la voie de commandes du lot A (#124) : le magasin conserve la demande, le formulaire
 * se libère, et la ligne concernée dit ce qui est en cours. Une intention vit en mémoire dans les brouillons de la console
 * (`drafts`, renouvelés avec le compte, l'école, le rattachement et l'époque) : jamais dans le stockage du navigateur.
 */

/** Source d'une écriture de tarif : une création, ou une révision (simple ou bascule) d'un produit précis. */
export type TariffTarget = { readonly kind: 'create' } | { readonly kind: 'edit'; readonly productKey: string; readonly baseId: string; readonly quick: boolean };

export interface TariffSave {
  readonly target: TariffTarget;
  readonly draft: TariffDraft;
  /** Le tarif partage ses conditions : il ne peut pas nommer deux agrégats, il attend donc tout le catalogue. */
  readonly sharedTerms: boolean;
  readonly body: Record<string, unknown>;
  readonly success: string;
}

export interface TariffRefusal {
  readonly intention: TariffIntention;
  readonly target: TariffTarget;
  readonly outcome: NonNullable<Outcome>;
}

export interface TermsRefusal { readonly intention: TermsIntention; readonly outcome: NonNullable<Outcome> }

const TARIFF_KEY = 'pricing/intentions';
const TERMS_KEY = 'pricing/terms';
const REFUSALS_KEY = 'pricing/refusals';
const TERMS_REFUSALS_KEY = 'pricing/terms-refusals';

/** Demandes de cette école encore envoyées ou suivies par le magasin, par opération. */
function useStorePhases(schoolId: string) {
  const { entries } = useCommandSnapshot();
  return useMemo(() => {
    const sending = new Set<string>(), followed = new Set<string>();
    for (const entry of entries.values()) {
      if (entry.meta.schoolId !== schoolId) continue;
      if (entry.phase === 'sending' || entry.phase === 'verifying') sending.add(entry.meta.operationId);
      else followed.add(entry.meta.operationId);
    }
    return { sending, followed };
  }, [entries, schoolId]);
}

/**
 * Éditeur de tarifs : une intention par produit, libérée dès que le magasin la conserve. Un tarif à conditions partagées, une
 * création (pas encore d'identifiant d'école) partent dans la famille `catalogue` et attendent la révision des conditions.
 * `reload` relit la fiche après un conflit de version ou une demande sans changement ; rien n'est publié localement.
 */
export function useTariffLane(tariffs: readonly Tariff[], onCreated?: (versionId: string) => void, reload?: () => void) {
  const { schoolId } = useConsole();
  const [intentions, change] = useJournal<TariffIntention>(TARIFF_KEY);
  // Le refus vit autant que l'intention : dans le journal de session, il survit à la fermeture de la page (#430).
  const [refusals, setRefusals] = useJournal<TariffRefusal>(REFUSALS_KEY);
  const { sending, followed } = useStorePhases(schoolId);
  const created = useRef(onCreated);
  created.current = onCreated;
  // Une demande confirmée garde ses valeurs sans marque jusqu'à la lecture suivante : l'école reste la seule source.
  const read = useRef<readonly Tariff[]>(tariffs);
  useEffect(() => {
    if (read.current === tariffs) return;
    read.current = tariffs;
    change(list => list.filter(item => item.settledAt === undefined));
  }, [tariffs]);
  const settle = (operationId: string) => change(list => list.map(item => item.operationId === operationId && item.settledAt === undefined
    ? { ...item, settledAt: Date.now() } : item));
  const lane = useCommandLane(intent => settle(intent.operationId));
  const projected = useMemo(() => resolveIntentions(intentions, sending, followed), [intentions, sending, followed]);
  const rows = useMemo(() => projectTariffs(tariffs, projected), [tariffs, projected]);
  const subject = (productKey: string | null, sharedTerms: boolean) => {
    const scope = tariffScope(productKey, sharedTerms);
    return { kind: 'saveTariff' as const, ...(scope ? { scope } : {}) };
  };

  /** Le magasin conserve la demande : l'éditeur peut se fermer et la ligne dit « Enregistrement en cours ». */
  function save(input: TariffSave): { admitted: boolean } {
    const productKey = input.target.kind === 'create' ? null : input.target.productKey;
    const scope = tariffScope(productKey, input.sharedTerms);
    const command = createCommand({ schoolId, kind: 'saveTariff', path: 'formations/tariffs', resourceVersion: 0, body: input.body,
      ...(scope ? { scope } : {}) });
    const tag = tariffTag(productKey);
    const intention: TariffIntention = { tag, operationId: command.operationId, draft: input.draft, productKey,
      kind: input.target.kind === 'create' ? 'create' : input.target.quick ? 'toggle' : 'update' };
    lane.clearOutcome();
    const started = lane.run(command, input.success, tag);
    if (!started.admitted) { void started.result; return { admitted: false }; }
    change(list => [...list, intention]);
    void started.result.then(result => {
      if (result.status === 'rejected') {
        change(list => list.filter(item => item.operationId !== intention.operationId));
        // Rien à enregistrer ou version déjà relue : la fiche se relit, sans présenter un refus qui n'en est pas un.
        if (unchangedCodes.has(result.code)) { reload?.(); return; }
        setRefusals(list => [...list, { intention, target: input.target, outcome: refusalOutcome(result) as NonNullable<Outcome> }]);
        if (changedCodes.has(result.code)) reload?.();
      }
      if (result.status === 'confirmed') { const id = createdId(result); if (id) created.current?.(id); }
    });
    return { admitted: true };
  }

  return {
    rows, projected, refusals,
    pending: (productKey: string) => pendingFor(productKey, projected),
    blocked: (productKey: string | null, sharedTerms: boolean) => lane.blocked(subject(productKey, sharedTerms)),
    save, dismiss: (refusal: TariffRefusal) => setRefusals(list => list.filter(item => item !== refusal)),
    outcomeFor: (tag: string) => lane.view(tag).outcome,
    clearOutcome: (tag?: string) => lane.clearOutcome(tag),
    confirmation: [...lane.outcomes.values()].filter(item => item.tone === 'success').at(-1) ?? null,
  };
}
export type TariffLane = ReturnType<typeof useTariffLane>;

/** Révision des conditions communes : une intention par jeu de conditions, « Révision en cours » puis « À confirmer ». */
export function useTermsLane(reference: Extract<CatalogueReference, { kind: 'TERMS' }>, reload?: () => void) {
  const { schoolId } = useConsole();
  const [intentions, change] = useJournal<TermsIntention>(TERMS_KEY);
  const [refusals, setRefusals] = useJournal<TermsRefusal>(`${TERMS_REFUSALS_KEY}/${reference.id}`);
  const refusal = refusals.at(-1) ?? null;
  const { sending, followed } = useStorePhases(schoolId);
  const read = useRef(reference);
  useEffect(() => {
    if (read.current === reference) return;
    read.current = reference;
    change(list => list.filter(item => item.settledAt === undefined));
  }, [reference]);
  const settle = (operationId: string) => change(list => list.map(item => item.operationId === operationId && item.settledAt === undefined
    ? { ...item, settledAt: Date.now() } : item));
  const lane = useCommandLane(intent => settle(intent.operationId));
  const pending = useMemo(() => projectTermsRevision(reference.id, intentions, sending, followed), [reference.id, intentions, sending, followed]);

  function revise(input: { text: string; body: Record<string, unknown>; success: string; revised: (versionId: string | null) => void }): boolean {
    const command = createCommand({ schoolId, kind: 'reviseSharedTerms', path: 'formations/terms/revise', resourceVersion: 0, body: input.body,
      scope: termsScope(reference.id) });
    const tag = termsTag(reference.id);
    const intention: TermsIntention = { tag, operationId: command.operationId, termsVersionId: reference.id, text: input.text };
    lane.clearOutcome();
    const started = lane.run(command, input.success, tag);
    if (!started.admitted) { void started.result; return false; }
    change(list => [...list, intention]);
    void started.result.then(result => {
      if (result.status === 'confirmed') input.revised(createdId(result));
      if (result.status === 'rejected') {
        change(list => list.filter(item => item.operationId !== intention.operationId));
        if (unchangedCodes.has(result.code)) { reload?.(); return; }
        setRefusals(() => [{ intention, outcome: refusalOutcome(result) as NonNullable<Outcome> }]);
        if (changedCodes.has(result.code)) reload?.();
      }
    });
    return true;
  }

  return {
    pending, refusal,
    blocked: () => lane.blocked({ kind: 'reviseSharedTerms', scope: termsScope(reference.id) }),
    revise, dismiss: () => setRefusals(() => []),
    outcomeFor: (tag: string) => lane.view(tag).outcome,
    clearOutcome: (tag?: string) => lane.clearOutcome(tag),
    confirmation: [...lane.outcomes.values()].filter(item => item.tone === 'success').at(-1) ?? null,
  };
}
export type TermsLane = ReturnType<typeof useTermsLane>;
