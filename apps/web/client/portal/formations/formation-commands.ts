import { useEffect, useMemo, useRef, useState } from 'react';
import { createCommand } from '../../command-core';
import { refusalOutcome } from '../../command-lane';
import { useCommandSnapshot } from '../../command-store';
import { useCommandLane, useConsole } from '../../console/context';
import type { Programme } from '../../formation-api';
import { changedCodes, unchangedCodes } from './catalogue-command';
import {
  formationTag, programmeRefusal, resolveFormationIntentions, type FormationIntention, type ProgrammeIntention, type ProgrammeRefusal,
  type ProgrammeSection,
} from './formation-projection';

/**
 * L'éditeur de programme et la mise à jour de référence passent par la voie de commandes du lot A (#124) : le magasin conserve la
 * demande, l'éditeur se libère, et la rubrique concernée dit ce qui est en cours. Une intention vit en mémoire dans les brouillons de
 * la console (`drafts`, renouvelés avec le compte, l'école, le rattachement et l'époque) : jamais dans le stockage du navigateur.
 * Une demande à la fois par formation : la formation est l'agrégat.
 */

/** Écriture d'une rubrique d'un parcours : la rubrique seule est envoyée, la version attendue vient de la fiche lue. */
export interface ProgrammeSave<D> {
  readonly section: ProgrammeSection;
  readonly offeringKey: string;
  readonly draft: D;
  readonly body: Record<string, unknown>;
  readonly success: string;
}

export type { ProgrammeRefusal } from './formation-projection';

const INTENTIONS_KEY = 'formations/intentions';

/** Liste d'intentions gardée en mémoire, renouvelée avec la portée de la console. */
function useMemoryList<T>(key: string) {
  const { drafts } = useConsole();
  const stored = useRef<T[]>((drafts?.get(key) as T[] | undefined) ?? []);
  const [list, setList] = useState<T[]>(stored.current);
  const change = (next: (items: readonly T[]) => T[]) => {
    stored.current = next(stored.current);
    drafts?.set(key, stored.current);
    setList(stored.current);
  };
  return [list, change] as const;
}

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
 * Voie de commandes d'une fiche de permis : une intention par formation, libérée dès que le magasin la conserve. `reload` relit la
 * fiche après un conflit de version ou une demande sans changement ; rien n'est publié localement.
 */
export function useProgrammeLane(programmes: readonly Programme[] | undefined, reload?: () => void) {
  const { schoolId } = useConsole();
  const [intentions, change] = useMemoryList<FormationIntention>(INTENTIONS_KEY);
  const [refusals, setRefusals] = useState<ProgrammeRefusal[]>([]);
  const { sending, followed } = useStorePhases(schoolId);
  // Une demande confirmée garde ses valeurs sans marque jusqu'à la lecture suivante : l'école reste la seule source.
  const read = useRef<readonly Programme[] | undefined>(undefined);
  useEffect(() => {
    if (programmes === undefined || read.current === programmes) return;
    read.current = programmes;
    change(list => list.filter(item => item.settledAt === undefined));
  }, [programmes]);
  const settle = (operationId: string) => change(list => list.map(item => item.operationId === operationId && item.settledAt === undefined
    ? { ...item, settledAt: Date.now() } : item));
  const lane = useCommandLane(intent => settle(intent.operationId));
  const projected = useMemo(() => resolveFormationIntentions(intentions, sending, followed), [intentions, sending, followed]);

  /** Le magasin conserve la demande : l'éditeur peut se fermer et la rubrique dit « Enregistrement en cours ». */
  function save<D>(input: ProgrammeSave<D>): { admitted: boolean } {
    const tag = formationTag(input.offeringKey);
    const command = createCommand({ schoolId, kind: 'saveFormationProgramme', path: 'formations/programmes', resourceVersion: 0,
      body: input.body, scope: input.offeringKey });
    const intention: ProgrammeIntention = { kind: 'programme', tag, operationId: command.operationId, offeringKey: input.offeringKey,
      section: input.section, draft: input.draft };
    lane.clearOutcome(tag);
    const started = lane.run(command, input.success, tag);
    if (!started.admitted) { void started.result; return { admitted: false }; }
    change(list => [...list, intention]);
    void started.result.then(result => {
      if (result.status === 'rejected') {
        change(list => list.filter(item => item.operationId !== intention.operationId));
        // Rien à enregistrer ou version déjà relue : la fiche se relit, sans présenter un refus qui n'en est pas un.
        if (unchangedCodes.has(result.code)) { reload?.(); return; }
        setRefusals(list => [...list, programmeRefusal(intention, input.draft, refusalOutcome(result))]);
        if (changedCodes.has(result.code)) reload?.();
      }
    });
    return { admitted: true };
  }

  return {
    projected, refusals,
    /** Une demande sur ce parcours attend sa confirmation : une autre écriture de la même formation est refusée sur place. */
    blocked: (offeringKey: string) => lane.blocked({ kind: 'saveFormationProgramme', scope: offeringKey }),
    save, dismiss: (refusal: ProgrammeRefusal) => setRefusals(list => list.filter(item => item !== refusal)),
    clearOutcome: (tag?: string) => lane.clearOutcome(tag),
    confirmation: [...lane.outcomes.values()].filter(item => item.tone === 'success').at(-1) ?? null,
  };
}
export type ProgrammeLane = ReturnType<typeof useProgrammeLane>;
