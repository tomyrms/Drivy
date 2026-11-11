import { useEffect, useMemo, useState } from 'react';
import { matchesSearch } from '../../command-core';
import { catalogueReads } from '../../command-families';
import { useCommandRevision } from '../../command-store';
import { readReference, termsListSchema, textProposalsLite, uncategorizedTariffsSchema, type CatalogueReference, type Tariff, type TariffType, type TextProposalsLite } from '../../formation-api';
import { readSchool } from '../../school-api';
import { useConsole, useLoad, useUnsavedChanges, type Outcome } from '../../console/context';
import { useListState } from '../../console/list-state';
import { createTariffBody, newTariffDraft, tariffChanged, tariffDraft, tariffProblems, updateTariffBody, updatedValidFrom, type TariffDraft } from '../../console/formation-model';
import { changedCodes } from '../formations/catalogue-command';
import { termsTag, tariffTag } from './pricing-projection';
import type { TariffLane, TariffTarget, TermsLane } from './pricing-commands';

/**
 * La fiche principale ouvre la version actuelle ; une version ancienne se lit dans son propre bloc de référence.
 * `consulting` couvre aussi un identifiant absent de la liste : le panneau ne doit jamais ouvrir un autre tarif.
 */
export function consultedTariff(tariffs: readonly Tariff[] | undefined, selection: string | undefined) {
  const owner = selection && tariffs ? tariffs.find(item => item.history.some(version => version.id === selection)) : undefined;
  return { owner, consulting: !!selection && !!tariffs && owner?.head.id !== selection };
}

/** Prestations sans permis : mêmes tarifs, même éditeur, sans catégorie. */
export function useUncategorizedTariffs() {
  const { schoolId } = useConsole();
  const revision = useCommandRevision(catalogueReads);
  const loaded = useLoad(() => readSchool(schoolId, 'formations/uncategorized-tariffs', uncategorizedTariffsSchema), [schoolId, revision]);
  const proposals = useLoad(() => readSchool(schoolId, 'text-proposals', textProposalsLite), [schoolId]);
  return { loaded, proposals };
}

/** Conditions commerciales : liste versionnée, recherche et filtre d'usage gardés en mémoire pour la session. */
export function useTermsList() {
  const { schoolId } = useConsole();
  const revision = useCommandRevision(catalogueReads);
  const list = useLoad(() => readSchool(schoolId, 'formations/terms', termsListSchema), [schoolId, revision]);
  const [search, setSearch] = useListState('conditions/search', '');
  const [usage, setUsage] = useListState<'all' | 'used' | 'unused'>('conditions/usage', 'all');
  const items = useMemo(() => (list.data?.items ?? []).filter(item => matchesSearch([item.label], search)
    && (usage === 'all' || (usage === 'used' ? item.currentTariffs > 0 : item.currentTariffs === 0))), [list.data, search, usage]);
  return { list, search, setSearch, usage, setUsage, items };
}

/** Lecture d'une version exacte (tarif, conditions, programme) par son identifiant. */
export function useReference(selection: string | undefined, extra: readonly unknown[] = []) {
  const { schoolId } = useConsole();
  const revision = useCommandRevision(catalogueReads);
  return useLoad(async () => selection ? readReference(schoolId, selection) : null, [schoolId, selection, revision, ...extra], `${schoolId}/${selection ?? ''}`);
}

interface TariffEditing { target: TariffTarget; draft: TariffDraft; snapshot: string }

export interface TariffEditorOptions {
  tariffs: readonly Tariff[];
  categoryCode: string | null;
  today: string;
  types: readonly TariffType[];
  proposals: TextProposalsLite | undefined;
  commands: TariffLane;
}

/**
 * Éditeur de tarif (création, révision ou bascule proposé/non proposé) sur la voie de commandes (#124) : le formulaire se libère dès
 * que le magasin conserve la demande, la ligne concernée dit « Enregistrement en cours » puis « À confirmer », et un refus revient
 * dans le formulaire avec la saisie et la raison. Le prix saisi n'est jamais complété : un champ vide reste une erreur, jamais 0.
 */
export function useTariffEditor(options: TariffEditorOptions) {
  const { tariffs, categoryCode, today, commands } = options;
  const [editing, setEditing] = useState<TariffEditing | null>(null);
  const [attempted, setAttempted] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [restored, setRestored] = useState<NonNullable<Outcome> | null>(null);
  const [rebased, setRebased] = useState(false);
  const [waitingFor, setWaitingFor] = useState<Tariff | undefined>(undefined);
  const target = editing?.target ?? null;
  const current = target?.kind === 'edit' ? tariffs.find(item => item.productKey === target.productKey) : undefined;
  // Une bascule ne passe pas par le formulaire : ce n'est pas une saisie en cours de navigation.
  const dirty = editing !== null && (editing.target.kind === 'create' || !editing.target.quick) && JSON.stringify(editing.draft) !== editing.snapshot;
  useUnsavedChanges(dirty);
  // Une relecture a apporté une nouvelle version : la base de la révision suit, la saisie reste intacte.
  useEffect(() => {
    if (!waitingFor || !current || current === waitingFor) return;
    setEditing(state => state && state.target.kind === 'edit' ? { ...state, target: { ...state.target, baseId: current.head.id } } : state);
    setWaitingFor(undefined);
    setRebased(true);
  }, [current, waitingFor]);
  const mode = target?.kind === 'create' ? 'CREATE' as const : 'UPDATE' as const;
  const start = current ? updatedValidFrom(current, today) : editing?.draft.validFrom ?? today;
  const problems = editing ? tariffProblems(editing.draft, mode, today, start) : null;
  const changed = !editing ? false : mode === 'CREATE' ? editing.draft.label !== '' || JSON.stringify(editing.draft) !== editing.snapshot
    : !!current && tariffChanged(editing.draft, current, today);
  const sharedTerms = current ? current.termsSharedWith > 0 : false;
  const productKey = target?.kind === 'edit' ? target.productKey : null;
  const blocked = commands.blocked(productKey, sharedTerms);
  const reset = () => { setEditing(null); setReviewing(false); setAttempted(false); setRestored(null); setRebased(false); setWaitingFor(undefined); };
  const sharedTermsText = tariffs.find(item => item.terms)?.terms?.termsText ?? options.proposals?.commercialTerms.termsText ?? '';
  /** Rouvre le formulaire d'un tarif refusé, avec la saisie exacte et la raison ; rien n'est renvoyé sans nouvelle relecture. */
  const reopen = (next: { target: TariffTarget; draft: TariffDraft; outcome: NonNullable<Outcome> }) => {
    const { target: refused } = next;
    const baseline = refused.kind === 'edit' ? tariffs.find(item => item.productKey === refused.productKey) : undefined;
    // La fiche s'est peut-être déjà actualisée avant la reprise (le refus la relit) : la base suit alors la version actuelle, que la
    // relecture montre, sinon un second envoi repartirait avec l'ancienne version et serait refusé de nouveau, à l'infini.
    const moved = refused.kind === 'edit' && !!baseline && baseline.head.id !== refused.baseId;
    const resumed: TariffTarget = refused.kind === 'edit' && baseline && moved ? { ...refused, baseId: baseline.head.id } : refused;
    setEditing({ target: resumed, draft: next.draft, snapshot: JSON.stringify(baseline ? tariffDraft(baseline) : next.draft) });
    setAttempted(false);
    setReviewing(refused.kind === 'edit' && refused.quick);
    setRestored(next.outcome);
    setRebased(moved || changedCodes.has(next.outcome.code ?? ''));
    setWaitingFor(baseline);
    commands.clearOutcome();
  };
  return {
    editing: editing !== null, quick: target?.kind === 'edit' && target.quick, mode, current, draft: editing?.draft ?? null, rebased, restored,
    problems, valid: problems?.valid ?? false, changed, dirty, attempted, reviewing, start, blocked, sharedTerms,
    /** Refus rendu sur place (magasin ou école) pour cette intention : le dialogue reste ouvert, saisie conservée. */
    outcome: commands.outcomeFor(tariffTag(productKey)),
    blockedReason: blocked ? 'Une demande sur ce tarif attend sa confirmation (voir en haut de la page).' : null,
    openCreate: () => {
      const draft = newTariffDraft(options.types[0]!, today, sharedTermsText);
      setEditing({ target: { kind: 'create' }, draft, snapshot: JSON.stringify(draft) });
      setAttempted(false); setRestored(null); setRebased(false); commands.clearOutcome();
    },
    openEdit: (tariff: Tariff) => {
      const draft = tariffDraft(tariff);
      setEditing({ target: { kind: 'edit', productKey: tariff.productKey, baseId: tariff.head.id, quick: false }, draft, snapshot: JSON.stringify(draft) });
      setAttempted(false); setRestored(null); setRebased(false); commands.clearOutcome();
    },
    /** Ne plus proposer / proposer à nouveau : même commande, seul « enabled » change, confirmée avant l'envoi. */
    openToggle: (tariff: Tariff, enabled: boolean) => {
      const draft = { ...tariffDraft(tariff), enabled };
      setEditing({ target: { kind: 'edit', productKey: tariff.productKey, baseId: tariff.head.id, quick: true }, draft, snapshot: JSON.stringify(tariffDraft(tariff)) });
      setAttempted(false); setRestored(null); setRebased(false); setReviewing(true); commands.clearOutcome();
    },
    update: (draft: TariffDraft) => setEditing(state => state ? { ...state, draft } : state),
    cancel: reset,
    review: () => {
      setAttempted(true);
      if (editing && problems?.valid && changed) { commands.clearOutcome(); setReviewing(true); return true; }
      return false;
    },
    closeReview: () => { setReviewing(false); if (target?.kind === 'edit' && target.quick) reset(); },
    reopen,
    /**
     * Le magasin conserve la demande : le formulaire se ferme tout de suite, rien n'est annoncé publié avant la réponse vérifiée ou
     * le reçu. Refusé sur place (une demande du même agrégat attend), le formulaire reste tel quel avec sa saisie.
     */
    confirm: () => {
      if (!editing || !problems?.valid || !changed) return;
      const { target: savedTarget } = editing;
      const create = savedTarget.kind === 'create';
      if (!create && !current) return;
      const body = create ? createTariffBody(editing.draft, categoryCode)
        : { ...updateTariffBody(editing.draft, current!, today), expectedProductVersionId: savedTarget.baseId };
      const saved = commands.save({ target: savedTarget, draft: editing.draft, sharedTerms,
        body, success: create ? 'Le tarif est ajouté.' : !create && savedTarget.quick
          ? (editing.draft.enabled ? 'Le tarif est de nouveau proposé.' : 'Le tarif n’est plus proposé.') : 'Le tarif est enregistré.' });
      if (!saved.admitted) { setAttempted(true); return; }
      reset();
    },
  };
}
export type TariffEditor = ReturnType<typeof useTariffEditor>;

type TermsReference = Extract<CatalogueReference, { kind: 'TERMS' }>;

/** Révision des conditions communes : tarifs impactés relus, engagements anciens conservés par le serveur. */
export function useSharedTermsRevision(reference: TermsReference, commands: TermsLane, onRevised: (versionId: string | null) => void,
  read: { ready: boolean; reload: () => void }) {
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(reference.terms.termsText);
  const [reviewing, setReviewing] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const [attempted, setAttempted] = useState(false);
  const [restored, setRestored] = useState<NonNullable<Outcome> | null>(null);
  const [waitingFor, setWaitingFor] = useState<TermsReference | null>(null);
  const impacted = reference.usedBy.filter(item => item.current);
  const changed = text.trim() !== reference.terms.termsText.trim();
  const problem = text.trim().length < 20 ? 'Rédigez les conditions (20 caractères au moins).' : null;
  const dirty = editing && changed;
  useUnsavedChanges(dirty);
  useEffect(() => { setEditing(false); setText(reference.terms.termsText); setReviewing(false); setAcknowledged(false); setAttempted(false); setRestored(null); }, [reference.id]);
  // A changed impact list requires another deliberate review, without discarding the drafted text.
  useEffect(() => {
    setAcknowledged(false);
    if (waitingFor && reference !== waitingFor) setWaitingFor(null);
  }, [reference, waitingFor]);
  const readReady = read.ready && waitingFor === null;
  const blocked = commands.blocked();
  // Un conflit de version force une relecture avant toute nouvelle relecture du texte : l'impact peut avoir changé.
  useEffect(() => {
    const refusal = commands.refusal;
    if (!refusal || waitingFor === reference || !changedCodes.has(refusal.outcome.code ?? '')) return;
    setWaitingFor(reference);
    setAcknowledged(false);
  }, [commands.refusal, reference, waitingFor]);
  const reset = () => { setEditing(false); setReviewing(false); setAcknowledged(false); setAttempted(false); setRestored(null); };
  /** Le refus rend la saisie et sa raison ; la révision ne repart qu'après une nouvelle relecture. */
  const resume = () => {
    const refusal = commands.refusal;
    if (!refusal) return;
    setText(refusal.intention.text);
    setEditing(true); setReviewing(false); setAcknowledged(false); setAttempted(false);
    setRestored(refusal.outcome);
    commands.dismiss();
  };
  return {
    editing, text, setText: (value: string) => { setText(value); setAcknowledged(false); }, reviewing, acknowledged, setAcknowledged, attempted, impacted, changed, problem,
    canRevise: impacted.length > 0, readReady, restored, blocked,
    /** Refus rendu sur place pour cette révision : le dialogue reste ouvert, texte conservé. */
    outcome: commands.outcomeFor(termsTag(reference.id)),
    blockedReason: blocked ? 'Une demande sur ces conditions attend sa confirmation (voir en haut de la page).' : null,
    open: () => { setText(reference.terms.termsText); setEditing(true); setRestored(null); commands.clearOutcome(); },
    cancel: () => { setText(reference.terms.termsText); reset(); },
    review: () => { setAttempted(true); if (readReady && !problem && changed) { setAcknowledged(false); commands.clearOutcome(); setReviewing(true); } },
    closeReview: () => setReviewing(false),
    resume,
    confirm: () => {
      if (!readReady || problem || !changed || !acknowledged || !impacted.length) return;
      const kept = commands.revise({ text: text.trim(), success: 'Les nouvelles conditions sont enregistrées.', revised: onRevised,
        body: { termsVersionId: reference.id, expectedProductVersionIds: impacted.map(item => item.id), termsText: text.trim(), reviewAcknowledged: true } });
      if (kept) reset(); else setReviewing(false);
    },
  };
}
export type SharedTermsRevision = ReturnType<typeof useSharedTermsRevision>;
