import { useEffect, useMemo, useState } from 'react';
import { createCommand, matchesSearch } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { readReference, termsListSchema, textProposalsLite, uncategorizedTariffsSchema, type CatalogueReference, type Tariff, type TariffType, type TextProposalsLite } from '../../formation-api';
import { readSchool } from '../../school-api';
import { useConsole, useLoad, useUnsavedChanges } from '../../console/context';
import { useListState } from '../../console/list-state';
import { createTariffBody, newTariffDraft, tariffChanged, tariffDraft, tariffProblems, updateTariffBody, updatedValidFrom, type TariffDraft } from '../../console/formation-model';
import { changedCodes, createdId, unchangedCodes, type CatalogueCommand } from '../formations/catalogue-command';

/** Prestations sans permis : mêmes tarifs, même éditeur, sans catégorie. */
export function useUncategorizedTariffs() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readSchool(schoolId, 'formations/uncategorized-tariffs', uncategorizedTariffsSchema), [schoolId, revision]);
  const proposals = useLoad(() => readSchool(schoolId, 'text-proposals', textProposalsLite), [schoolId]);
  return { loaded, proposals };
}

/** Conditions commerciales : liste versionnée, recherche et filtre d'usage gardés en mémoire pour la session. */
export function useTermsList() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
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
  const { revision } = useCommandSnapshot();
  return useLoad(async () => selection ? readReference(schoolId, selection) : null, [schoolId, selection, revision, ...extra], `${schoolId}/${selection ?? ''}`);
}

export type TariffMode = { kind: 'create' } | { kind: 'edit'; productKey: string; baseId: string };
interface TariffEditing { mode: TariffMode; draft: TariffDraft; snapshot: string; /** Basculer l'offre sans ouvrir le formulaire. */ quick: boolean; rebased: boolean; waitingFor: Tariff | undefined }

export interface TariffEditorOptions {
  tariffs: readonly Tariff[];
  categoryCode: string | null;
  today: string;
  types: readonly TariffType[];
  proposals: TextProposalsLite | undefined;
  command: CatalogueCommand;
  reload: () => void;
  /** Appelé après confirmation, avec l'identifiant de la nouvelle version quand la réponse le donne. */
  onSaved?: (versionId: string | null) => void;
}

/**
 * Un seul éditeur de tarif à la fois (création, révision ou bascule proposé/non proposé), toujours par la commande existante.
 * Le prix saisi n'est jamais complété : un champ vide reste une erreur, jamais 0.
 */
export function useTariffEditor(options: TariffEditorOptions) {
  const { schoolId } = useConsole();
  const { tariffs, categoryCode, today, command } = options;
  const [editing, setEditing] = useState<TariffEditing | null>(null);
  const [attempted, setAttempted] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const dirty = editing !== null && !editing.quick && JSON.stringify(editing.draft) !== editing.snapshot;
  useUnsavedChanges(dirty && !command.busy);
  const current = editing?.mode.kind === 'edit' ? tariffs.find(item => item.productKey === (editing.mode as { productKey: string }).productKey) : undefined;
  useEffect(() => {
    if (editing?.waitingFor && current && current !== editing.waitingFor && editing.mode.kind === 'edit')
      setEditing({ ...editing, mode: { ...editing.mode, baseId: current.head.id }, waitingFor: undefined, rebased: true });
  }, [current, editing]);
  const mode = editing?.mode.kind === 'edit' ? 'UPDATE' as const : 'CREATE' as const;
  const start = current ? updatedValidFrom(current, today) : editing?.draft.validFrom ?? today;
  const problems = editing ? tariffProblems(editing.draft, mode, today, start) : null;
  const changed = !editing ? false : mode === 'CREATE' ? editing.draft.label !== '' || JSON.stringify(editing.draft) !== editing.snapshot
    : !!current && tariffChanged(editing.draft, current, today);
  const reset = () => { setEditing(null); setReviewing(false); setAttempted(false); };
  const sharedTerms = tariffs.find(item => item.terms)?.terms?.termsText ?? options.proposals?.commercialTerms.termsText ?? '';
  return {
    editing: editing !== null, quick: editing?.quick ?? false, mode, current, draft: editing?.draft ?? null, rebased: editing?.rebased ?? false,
    problems, valid: problems?.valid ?? false, changed, dirty, attempted, reviewing, start,
    openCreate: () => {
      const draft = newTariffDraft(options.types[0]!, today, sharedTerms);
      setEditing({ mode: { kind: 'create' }, draft, snapshot: JSON.stringify(draft), quick: false, rebased: false, waitingFor: undefined });
      setAttempted(false); command.runner.clearOutcome();
    },
    openEdit: (tariff: Tariff) => {
      const draft = tariffDraft(tariff);
      setEditing({ mode: { kind: 'edit', productKey: tariff.productKey, baseId: tariff.head.id }, draft, snapshot: JSON.stringify(draft), quick: false, rebased: false, waitingFor: undefined });
      setAttempted(false); command.runner.clearOutcome();
    },
    /** Ne plus proposer / proposer à nouveau : même commande, seul « enabled » change, confirmée avant l'envoi. */
    openToggle: (tariff: Tariff, enabled: boolean) => {
      const draft = { ...tariffDraft(tariff), enabled };
      setEditing({ mode: { kind: 'edit', productKey: tariff.productKey, baseId: tariff.head.id }, draft, snapshot: JSON.stringify(tariffDraft(tariff)), quick: true, rebased: false, waitingFor: undefined });
      setAttempted(false); setReviewing(true); command.runner.clearOutcome();
    },
    update: (draft: TariffDraft) => setEditing(state => state ? { ...state, draft } : state),
    cancel: () => { if (!command.busy) reset(); },
    review: () => {
      setAttempted(true);
      if (editing && problems?.valid && changed) { command.runner.clearOutcome(); setReviewing(true); return true; }
      return false;
    },
    closeReview: () => { if (command.busy) return; setReviewing(false); if (editing?.quick) reset(); },
    confirm: async () => {
      if (!editing || command.busy || !problems?.valid || !changed) return;
      const body = editing.mode.kind === 'create' ? createTariffBody(editing.draft, categoryCode)
        : { ...updateTariffBody(editing.draft, current!, today), expectedProductVersionId: editing.mode.baseId };
      const created = editing.mode.kind === 'create';
      const result = await command.submit(createCommand({ schoolId, kind: 'saveTariff', path: 'formations/tariffs', resourceVersion: 0, body }),
        created ? 'Le tarif est ajouté.' : editing.quick ? (editing.draft.enabled ? 'Le tarif est de nouveau proposé.' : 'Le tarif n’est plus proposé.') : 'Le tarif est enregistré.', reset);
      if (result.status === 'confirmed') options.onSaved?.(createdId(result));
      if (result.status === 'pending') setReviewing(false);
      if (result.status !== 'rejected') return;
      if (changedCodes.has(result.code)) { setEditing(state => state ? { ...state, waitingFor: current, quick: false } : state); setReviewing(false); options.reload(); }
      else if (unchangedCodes.has(result.code)) { reset(); options.reload(); }
    },
  };
}
export type TariffEditor = ReturnType<typeof useTariffEditor>;

type TermsReference = Extract<CatalogueReference, { kind: 'TERMS' }>;

/** Révision des conditions communes : tarifs impactés relus, engagements anciens conservés par le serveur. */
export function useSharedTermsRevision(reference: TermsReference, command: CatalogueCommand, onRevised: (versionId: string | null) => void,
  read: { ready: boolean; reload: () => void }) {
  const { schoolId } = useConsole();
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(reference.terms.termsText);
  const [reviewing, setReviewing] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const [attempted, setAttempted] = useState(false);
  const [waitingFor, setWaitingFor] = useState<TermsReference | null>(null);
  const impacted = reference.usedBy.filter(item => item.current);
  const changed = text.trim() !== reference.terms.termsText.trim();
  const problem = text.trim().length < 20 ? 'Rédigez les conditions (20 caractères au moins).' : null;
  useUnsavedChanges(editing && changed && !command.busy);
  useEffect(() => { setEditing(false); setText(reference.terms.termsText); setReviewing(false); setAcknowledged(false); setAttempted(false); }, [reference.id]);
  // A changed impact list requires another deliberate review, without discarding the drafted text.
  useEffect(() => {
    setAcknowledged(false);
    if (waitingFor && reference !== waitingFor) setWaitingFor(null);
  }, [reference, waitingFor]);
  const readReady = read.ready && waitingFor === null;
  const reset = () => { setEditing(false); setReviewing(false); setAcknowledged(false); setAttempted(false); };
  return {
    editing, text, setText: (value: string) => { setText(value); setAcknowledged(false); }, reviewing, acknowledged, setAcknowledged, attempted, impacted, changed, problem,
    canRevise: impacted.length > 0, readReady,
    open: () => { setText(reference.terms.termsText); setEditing(true); command.runner.clearOutcome(); },
    cancel: () => { if (command.busy) return; setText(reference.terms.termsText); reset(); },
    review: () => { setAttempted(true); if (readReady && !problem && changed) { setAcknowledged(false); command.runner.clearOutcome(); setReviewing(true); } },
    closeReview: () => { if (!command.busy) setReviewing(false); },
    confirm: async () => {
      if (!readReady || command.busy || problem || !changed || !acknowledged || !impacted.length) return;
      const result = await command.submit(createCommand({ schoolId, kind: 'reviseSharedTerms', path: 'formations/terms/revise', resourceVersion: 0,
        body: { termsVersionId: reference.id, expectedProductVersionIds: impacted.map(item => item.id), termsText: text.trim(), reviewAcknowledged: true } }),
        'Les nouvelles conditions sont enregistrées.', reset);
      if (result.status === 'confirmed') onRevised(createdId(result));
      if (result.status === 'pending') setReviewing(false);
      if (result.status === 'rejected' && changedCodes.has(result.code)) {
        setAcknowledged(false); setReviewing(false); setWaitingFor(reference); read.reload();
      }
    },
  };
}
export type SharedTermsRevision = ReturnType<typeof useSharedTermsRevision>;
