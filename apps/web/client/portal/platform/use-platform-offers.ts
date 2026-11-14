import { useRef, useState } from 'react';
import { request, type Session } from '../../protocol';
import {
  orderedModules, platformFailureKind, platformModulesResult, platformOfferResult, platformOffersResult, sameModules,
  type PlatformModule, type PlatformOffer,
} from '../../platform-model';

/** Une réponse inconnue garde son opération (la même demande, rejouée, dit si elle a eu lieu) ; toute autre réponse la libère. */
export function useOperationIds() {
  const operations = useRef(new Map<string, string>());
  const operationFor = (key: string) => {
    let operationId = operations.current.get(key);
    if (!operationId) { operationId = crypto.randomUUID(); operations.current.set(key, operationId); }
    return operationId;
  };
  const settle = (key: string, reason?: unknown) => { if (reason === undefined || platformFailureKind(reason) !== 'unconfirmed') operations.current.delete(key); };
  const clear = () => operations.current.clear();
  return { operationFor, settle, clear };
}

type Kernel = { session: Session | null; perform: (action: () => Promise<void>) => Promise<void>; reload: () => Promise<void> };
export type OfferEditor = { offer: PlatformOffer | null };
export type OfferDraft = { name: string; modules: string[] };
export type OffersSnapshot = { offers: PlatformOffer[]; modules: PlatformModule[] };

/**
 * Offres : ensembles nommés de modules du catalogue (R01-T03). Le navigateur ne garde que la lecture ; chaque écriture part sous la version
 * lue et sous un identifiant d'opération, et l'API relit le droit de l'opérateur. Aucun montant ni essai ici : ils appartiennent à #456.
 */
export function usePlatformOffers({ session, perform, reload }: Kernel) {
  const [offers, setOffers] = useState<PlatformOffer[]>([]), [modules, setModules] = useState<PlatformModule[]>([]);
  const [editor, setEditor] = useState<OfferEditor | null>(null);
  const operations = useOperationIds();

  function reset() { setOffers([]); setModules([]); setEditor(null); operations.clear(); }
  async function snapshot(): Promise<OffersSnapshot> {
    const [catalogue, listing] = await Promise.all([request('platform/modules', platformModulesResult), request('platform/offers', platformOffersResult)]);
    return { offers: listing.data.items, modules: [...catalogue.data.items].sort((a, b) => a.sortOrder - b.sortOrder) };
  }
  function apply(next: OffersSnapshot) {
    setOffers(next.offers); setModules(next.modules);
    // Une offre modifiée entre-temps ne laisse pas un éditeur sur son ancienne version.
    setEditor(previous => previous?.offer ? { offer: next.offers.find(item => item.id === previous.offer!.id) ?? null } : previous);
  }

  const startOffer = (offer: PlatformOffer | null) => setEditor({ offer });
  const stopOffer = () => setEditor(null);

  /** Création, ou modification des seules zones changées. Rien ne part quand rien n'a changé. */
  const saveOffer = (draft: OfferDraft) => perform(async () => {
    if (!session || !editor) return;
    const target = editor.offer, name = draft.name.trim(), selected = orderedModules(draft.modules, modules);
    if (!target) {
      const key = `offer:new:${JSON.stringify({ name, selected })}`, operationId = operations.operationFor(key);
      try { await request('platform/offers', platformOfferResult, { csrf: session.csrfToken, body: { operationId, name, modules: selected } }); operations.settle(key); }
      catch (reason) { operations.settle(key, reason); throw reason; }
    } else {
      const changes = { ...(name !== target.name ? { name } : {}), ...(!sameModules(selected, target.modules) ? { modules: selected } : {}) };
      if (Object.keys(changes).length === 0) { setEditor(null); return; }
      const key = `offer:${target.id}:${target.version}:${JSON.stringify(changes)}`, operationId = operations.operationFor(key);
      try { await request(`platform/offers/${target.id}/update`, platformOfferResult, { csrf: session.csrfToken, body: { operationId, version: target.version, ...changes } }); operations.settle(key); }
      catch (reason) { operations.settle(key, reason); throw reason; }
    }
    setEditor(null);
    await reload();
  });

  /** Archiver n'efface rien : les écoles déjà attribuées gardent leur instantané, l'offre n'est plus proposée. */
  const changeStatus = (offer: PlatformOffer, change: 'archive' | 'restore') => perform(async () => {
    if (!session) return;
    const key = `offer-${change}:${offer.id}:${offer.version}`, operationId = operations.operationFor(key);
    try { await request(`platform/offers/${offer.id}/${change}`, platformOfferResult, { csrf: session.csrfToken, body: { operationId, version: offer.version } }); operations.settle(key); }
    catch (reason) { operations.settle(key, reason); throw reason; }
    await reload();
  });

  return { offers, modules, editor, reset, snapshot, apply, startOffer, stopOffer, saveOffer,
    archiveOffer: (offer: PlatformOffer) => changeStatus(offer, 'archive'), restoreOffer: (offer: PlatformOffer) => changeStatus(offer, 'restore') };
}
export type PlatformOffersState = ReturnType<typeof usePlatformOffers>;
