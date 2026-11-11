import { useEffect, useMemo, useState } from 'react';
import { matchesSearch } from '../../command-core';
import { catalogueReads } from '../../command-families';
import { useCommandRevision } from '../../command-store';
import { formationListSchema, proposalsSchema, readFormationSheet, readReference, textProposalsLite, type Programme } from '../../formation-api';
import { programmeUpdate } from '../../formation-programme-update';
import { readSchool } from '../../school-api';
import { useConsole, useLoad, useUnsavedChanges, type Outcome } from '../../console/context';
import { useListState } from '../../console/list-state';
import { changedCodes } from './catalogue-command';
import { formationTag, projectProgramme, type ProgrammeSection } from './formation-projection';
import type { ProgrammeLane, ProgrammeRefusal } from './formation-commands';
import { referenceDestination } from './sheet-routing';
import type { SectionKey } from '../../console/sections';

/** Liste des permis préparés, avec recherche gardée en mémoire pour la session. */
export function useCatalogueList() {
  const { schoolId } = useConsole();
  const revision = useCommandRevision(catalogueReads);
  const loaded = useLoad(() => readSchool(schoolId, 'formations', formationListSchema), [schoolId, revision]);
  const [search, setSearch] = useListState('catalogue/search', '');
  const categories = useMemo(() => (loaded.data?.categories ?? []).filter(item => matchesSearch([`Permis ${item.categoryCode}`, item.categoryCode], search)), [loaded.data, search]);
  return { loaded, search, setSearch, categories };
}

/** Fiche d'un permis ; une fiche d'un autre permis n'est jamais affichée (contrôle dans readFormationSheet). */
export function useFormationSheet(category: string) {
  const { schoolId, routeQuery = {} } = useConsole();
  const revision = useCommandRevision(catalogueReads);
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
  /** Rubrique éditée : la marque, le refus et la saisie rendue ne concernent que la demande de cette rubrique. */
  section: ProgrammeSection;
  commands: ProgrammeLane;
  /** Brouillon initial, construit depuis la version enregistrée. */
  initial: () => D;
  valid: (draft: D) => boolean;
  changed: (draft: D) => boolean;
  /** Seule la rubrique concernée est envoyée. */
  body: (draft: D) => Record<string, unknown>;
  /** Une version plus récente de l'école devient la base de la saisie gardée : le brouillon est rapproché de celle-ci. */
  rebase?: (draft: D, programme: Programme) => D;
  success: string;
}
/** `waitingFor` : la fiche affichée au moment du conflit ; une nouvelle lecture la remplace, l'édition repart alors de la version relue. */
interface Editing<D> { draft: D; snapshot: string; baseId: string; rebased: boolean; waitingFor: Programme | null }

/**
 * Édition d'une seule rubrique d'un parcours sur la voie de commandes (#124). La version attendue (`expectedOfferingVersionId`) est
 * celle lue à l'ouverture ; dès que le magasin conserve la demande, l'éditeur se libère et la rubrique dit « Enregistrement en cours ».
 * Si le serveur répond que la fiche a changé, la fiche est relue, la saisie est gardée et rendue dans l'éditeur avec sa raison.
 */
export function useProgrammeEditor<D>(options: ProgrammeEditorOptions<D>) {
  const { programme, section, commands } = options;
  const [editing, setEditing] = useState<Editing<D> | null>(null);
  const [attempted, setAttempted] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [restored, setRestored] = useState<NonNullable<Outcome> | null>(null);
  const dirty = editing !== null && JSON.stringify(editing.draft) !== editing.snapshot;
  useUnsavedChanges(dirty);
  // Après relecture, l'édition repart de la version actuelle et le dit.
  useEffect(() => {
    if (editing?.waitingFor && programme !== editing.waitingFor) setEditing({ ...editing, draft: options.rebase ? options.rebase(editing.draft, programme) : editing.draft, baseId: programme.head.id, waitingFor: null, rebased: true });
  }, [programme, editing]);
  const tag = formationTag(programme.offeringKey);
  const valid = editing ? options.valid(editing.draft) : false;
  const changed = editing ? options.changed(editing.draft) : false;
  const blocked = commands.blocked(programme.offeringKey);
  const close = () => { setEditing(null); setReviewing(false); setAttempted(false); setRestored(null); };
  /** Refus de cette rubrique : la saisie exacte revient, rien ne repart sans une nouvelle relecture. */
  const refusals = commands.refusals.filter(refusal => refusal.intention.offeringKey === programme.offeringKey && refusal.section === section);
  const resume = (refusal: ProgrammeRefusal) => {
    // La saisie vient de la même fabrique de rubrique : elle est rendue telle quelle à cet éditeur.
    const rebased = changedCodes.has(refusal.outcome.code ?? '');
    setEditing({ draft: refusal.draft as D, snapshot: JSON.stringify(options.initial()), baseId: programme.head.id, rebased,
      waitingFor: rebased ? programme : null });
    setAttempted(false); setReviewing(false); setRestored(refusal.outcome); commands.dismiss(refusal);
  };
  return {
    editing: editing !== null, draft: editing?.draft ?? null, rebased: editing?.rebased ?? false, dirty, valid, changed, attempted, reviewing, restored,
    /** Ce que la rubrique montre quand l'éditeur est fermé : la version voulue, marquée, sans remplacer celle de l'école. */
    shown: projectProgramme<D>(programme, section, commands.projected),
    blocked, refusals, resume,
    open: () => { const draft = options.initial(); setEditing({ draft, snapshot: JSON.stringify(draft), baseId: programme.head.id, rebased: false, waitingFor: null }); setAttempted(false); setRestored(null); commands.clearOutcome(tag); },
    update: (draft: D) => setEditing(current => current ? { ...current, draft } : current),
    cancel: close,
    /** Relire : valide, puis présente les différences avant l'envoi. */
    review: () => {
      setAttempted(true);
      if (editing && options.valid(editing.draft) && options.changed(editing.draft)) { commands.clearOutcome(tag); setReviewing(true); return true; }
      return false;
    },
    closeReview: () => setReviewing(false),
    /**
     * Le magasin conserve la demande : l'éditeur se ferme tout de suite, rien n'est annoncé publié avant la réponse vérifiée ou le reçu.
     * Refusée sur place (une demande de la même formation attend), la demande reste suivie : l'éditeur garde sa saisie.
     */
    confirm: () => {
      if (!editing || !options.valid(editing.draft) || !options.changed(editing.draft)) return;
      const saved = commands.save({ section, offeringKey: programme.offeringKey, draft: editing.draft, success: options.success,
        body: { offeringKey: programme.offeringKey, expectedOfferingVersionId: editing.baseId, ...options.body(editing.draft) } });
      if (!saved.admitted) { setAttempted(true); return; }
      close();
    },
  };
}
export type ProgrammeEditor<D> = ReturnType<typeof useProgrammeEditor<D>>;

/**
 * Mise à jour proposée à la demande : seules les clés absentes sont ajoutées, jamais une personnalisation écrasée. Elle passe par la
 * voie de commandes de la fiche : le dialogue se ferme dès que le magasin conserve la demande, et un refus le rouvre avec sa raison.
 */
export function useReferenceUpdate(programme: Programme, categoryCode: string, commands: ProgrammeLane) {
  const { schoolId } = useConsole();
  const [open, setOpen] = useState(false);
  const [notice, setNotice] = useState<NonNullable<Outcome> | null>(null);
  const loaded = useLoad(async () => open ? readSchool(schoolId, 'setup-draft/templates', proposalsSchema) : null, [schoolId, open]);
  const template = loaded.data?.formations.find(item => item.categoryCode === categoryCode);
  const diff = useMemo(() => template ? programmeUpdate(programme.curriculum?.competencies ?? [], template) : null, [template, programme.curriculum]);
  const refusals = commands.refusals.filter(refusal => refusal.intention.offeringKey === programme.offeringKey && refusal.section === 'reference');
  const shown = projectProgramme(programme, 'reference', commands.projected);
  return {
    open, loaded, template, diff, refusals, shown, notice, blocked: commands.blocked(programme.offeringKey),
    setOpen: (next: boolean) => { setOpen(next); setNotice(null); },
    /** Le magasin conserve la demande : le dialogue se ferme, la rubrique dit ce qui est en cours. */
    apply: () => {
      if (loaded.status !== 'ready' || !diff || !diff.canApply) return;
      const saved = commands.save({ section: 'reference', offeringKey: programme.offeringKey, draft: null,
        success: 'Le programme est mis à jour pour les nouvelles inscriptions.',
        body: { offeringKey: programme.offeringKey, expectedOfferingVersionId: programme.head.id, competencies: diff.competencies, source: diff.source } });
      if (!saved.admitted) return;
      setOpen(false);
    },
    /** Un refus rend la raison et rouvre le dialogue : la référence proposée est recalculée depuis la fiche relue. */
    resume: (refusal: ProgrammeRefusal) => { commands.dismiss(refusal); setNotice(refusal.outcome); setOpen(true); },
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
