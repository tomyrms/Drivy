import { useEffect, useMemo, useState } from 'react';
import { createCommand, matchesSearch } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { formationListSchema, proposalsSchema, readFormationSheet, readReference, textProposalsLite, type Programme } from '../../formation-api';
import { programmeUpdate } from '../../formation-programme-update';
import { readSchool } from '../../school-api';
import { useConsole, useLoad, useUnsavedChanges } from '../../console/context';
import { useListState } from '../../console/list-state';
import { changedCodes, unchangedCodes, type CatalogueCommand } from './catalogue-command';
import { referenceDestination } from './sheet-routing';
import type { SectionKey } from '../../console/sections';

/** Liste des permis préparés, avec recherche gardée en mémoire pour la session. */
export function useCatalogueList() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readSchool(schoolId, 'formations', formationListSchema), [schoolId, revision]);
  const [search, setSearch] = useListState('catalogue/search', '');
  const categories = useMemo(() => (loaded.data?.categories ?? []).filter(item => matchesSearch([`Permis ${item.categoryCode}`, item.categoryCode], search)), [loaded.data, search]);
  return { loaded, search, setSearch, categories };
}

/** Fiche d'un permis ; une fiche d'un autre permis n'est jamais affichée (contrôle dans readFormationSheet). */
export function useFormationSheet(category: string) {
  const { schoolId, routeQuery = {} } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readFormationSheet(schoolId, category), [schoolId, category, revision], `${schoolId}/${category}`);
  const proposals = useLoad(() => readSchool(schoolId, 'text-proposals', textProposalsLite), [schoolId]);
  const programmes = loaded.data?.programmes ?? [];
  // Le serveur ordonne les parcours par date de dernière version : enregistrer un parcours le ferait changer de place.
  // Le parcours ouvert reste donc celui qui a été affiché en premier, tant que l'adresse n'en désigne pas un autre.
  const [first, setFirst] = useState<string | null>(null);
  useEffect(() => { if (!first && programmes[0]) setFirst(programmes[0].offeringKey); }, [first, programmes]);
  const wanted = routeQuery.programme ?? first;
  const selected = programmes.find(item => item.offeringKey === wanted) ?? programmes[0];
  return { loaded, proposals, programmes, selected };
}

export interface ProgrammeEditorOptions<D> {
  programme: Programme;
  command: CatalogueCommand;
  /** Brouillon initial, construit depuis la version enregistrée. */
  initial: () => D;
  valid: (draft: D) => boolean;
  changed: (draft: D) => boolean;
  /** Seule la rubrique concernée est envoyée. */
  body: (draft: D) => Record<string, unknown>;
  success: string;
  reload: () => void;
}
/** `waitingFor` : la fiche affichée au moment du conflit ; une nouvelle lecture la remplace, l'édition repart alors de la version relue. */
interface Editing<D> { draft: D; snapshot: string; baseId: string; rebased: boolean; waitingFor: Programme | null }

/**
 * Édition d'une seule rubrique d'un parcours. La version attendue (`expectedOfferingVersionId`) est celle lue à l'ouverture ;
 * si le serveur répond que la fiche a changé, la fiche est relue, la saisie est gardée et signalée comme à relire.
 */
export function useProgrammeEditor<D>(options: ProgrammeEditorOptions<D>) {
  const { schoolId } = useConsole();
  const { programme, command } = options;
  const [editing, setEditing] = useState<Editing<D> | null>(null);
  const [attempted, setAttempted] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const dirty = editing !== null && JSON.stringify(editing.draft) !== editing.snapshot;
  useUnsavedChanges(dirty && !command.busy);
  // Après relecture, l'édition repart de la version actuelle et le dit.
  useEffect(() => {
    if (editing?.waitingFor && programme !== editing.waitingFor) setEditing({ ...editing, baseId: programme.head.id, waitingFor: null, rebased: true });
  }, [programme, editing]);
  const valid = editing ? options.valid(editing.draft) : false;
  const changed = editing ? options.changed(editing.draft) : false;
  const close = () => { setEditing(null); setReviewing(false); setAttempted(false); };
  return {
    editing: editing !== null, draft: editing?.draft ?? null, rebased: editing?.rebased ?? false, dirty, valid, changed, attempted, reviewing,
    open: () => { const draft = options.initial(); setEditing({ draft, snapshot: JSON.stringify(draft), baseId: programme.head.id, rebased: false, waitingFor: null }); setAttempted(false); command.runner.clearOutcome(); },
    update: (draft: D) => setEditing(current => current ? { ...current, draft } : current),
    cancel: () => { if (!command.busy) close(); },
    /** Relire : valide, puis présente les différences avant l'envoi. */
    review: () => {
      setAttempted(true);
      if (editing && options.valid(editing.draft) && options.changed(editing.draft)) { command.runner.clearOutcome(); setReviewing(true); return true; }
      return false;
    },
    closeReview: () => { if (!command.busy) setReviewing(false); },
    confirm: async () => {
      if (!editing || command.busy || !options.valid(editing.draft) || !options.changed(editing.draft)) return;
      const result = await command.submit(createCommand({ schoolId, kind: 'saveFormationProgramme', path: 'formations/programmes', resourceVersion: 0,
        body: { offeringKey: programme.offeringKey, expectedOfferingVersionId: editing.baseId, ...options.body(editing.draft) } }), options.success, close);
      // Résultat incertain : la relecture (modale) se ferme pour laisser accessible la vérification de la demande en attente.
      if (result.status === 'pending') { setReviewing(false); return; }
      if (result.status !== 'rejected') return;
      if (changedCodes.has(result.code)) { setEditing(current => current ? { ...current, waitingFor: programme } : current); setReviewing(false); options.reload(); }
      else if (unchangedCodes.has(result.code)) { setReviewing(false); options.reload(); }
    },
  };
}
export type ProgrammeEditor<D> = ReturnType<typeof useProgrammeEditor<D>>;

/** Mise à jour proposée à la demande : seules les clés absentes sont ajoutées, jamais une personnalisation écrasée. */
export function useReferenceUpdate(programme: Programme, categoryCode: string, command: CatalogueCommand) {
  const { schoolId } = useConsole();
  const [open, setOpen] = useState(false);
  const loaded = useLoad(async () => open ? readSchool(schoolId, 'setup-draft/templates', proposalsSchema) : null, [schoolId, open]);
  const template = loaded.data?.formations.find(item => item.categoryCode === categoryCode);
  const diff = useMemo(() => template ? programmeUpdate(programme.curriculum?.competencies ?? [], template) : null, [template, programme.curriculum]);
  return {
    open, setOpen, loaded, template, diff,
    apply: async (reload: () => void) => {
      if (!diff || !diff.canApply || command.busy) return;
      const result = await command.submit(createCommand({ schoolId, kind: 'saveFormationProgramme', path: 'formations/programmes', resourceVersion: 0,
        body: { offeringKey: programme.offeringKey, expectedOfferingVersionId: programme.head.id, competencies: diff.competencies, source: diff.source } }),
        'Le programme est mis à jour pour les nouvelles inscriptions.', () => setOpen(false));
      if (result.status === 'pending') setOpen(false);
      if (result.status === 'rejected' && (changedCodes.has(result.code) || unchangedCodes.has(result.code))) reload();
    },
  };
}

/**
 * Anciennes adresses (offres, référentiels, procédures) : la version exacte désignée est retrouvée puis la destination
 * remplace l'entrée d'historique. Sans référence, la fiche du permis demandé ou la liste.
 */
export function useLegacyReference(section: SectionKey) {
  const { schoolId, routeQuery = {}, navigate } = useConsole();
  const selection = routeQuery.selection;
  const loaded = useLoad(async () => selection ? readReference(schoolId, selection) : null, [schoolId, selection], `${schoolId}/${selection ?? ''}`);
  useEffect(() => {
    if (selection) return;
    navigate('formations', routeQuery.category ? { category: routeQuery.category } : {}, { replace: true });
  }, [selection]);
  useEffect(() => {
    if (!loaded.data) return;
    const target = referenceDestination(loaded.data);
    if (target.section === section && target.query.selection === selection) return;
    navigate(target.section, target.query, { replace: true });
  }, [loaded.data]);
  return loaded;
}
