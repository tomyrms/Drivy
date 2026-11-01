import { useCommandSnapshot } from '../../command-store';
import { useConsole, useLoad } from '../../console/context';
import { activeInstructors } from '../../invitation-model';
import { distinctLabel, homonymReferences } from '../../person-reference';
import { learnerSchema, memberSchema, readAll } from '../../school-api';
import type { FilterOption } from './components';

/**
 * Noms nécessaires aux pages de pilotage : les moniteurs pour le filtre, les élèves seulement quand une liste de rendez-vous les nomme.
 * Une lecture qui échoue ne bloque jamais les chiffres : le filtre disparaît ou un nom générique le remplace.
 */
export function useDirectory({ learners: withLearners }: { learners: boolean }) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const members = useLoad(() => readAll(schoolId, 'members', memberSchema), [schoolId, revision]);
  const learners = useLoad(async () => withLearners ? readAll(schoolId, 'learners', learnerSchema, { status: 'ALL' }) : { items: [], truncated: false },
    [schoolId, revision, withLearners]);
  const instructors = activeInstructors(members.data?.items ?? []);
  const references = homonymReferences(instructors.map(item => ({ id: item.id, label: item.displayName })));
  const instructorOptions: FilterOption[] = instructors.map(item => ({ value: item.id, label: distinctLabel(item.displayName, references.get(item.id)) }));
  return {
    instructorOptions,
    memberName: (id: string) => members.data?.items.find(item => item.id === id)?.displayName ?? 'Moniteur',
    learnerName: (id: string) => learners.data?.items.find(item => item.id === id)?.displayName ?? 'Élève',
  };
}
