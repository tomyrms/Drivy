import { useMemo } from 'react';
import { useCommandSnapshot } from '../../command-store';
import { useConsole, useLoad } from '../../console/context';
import { distinctLabel, homonymReferences } from '../../person-reference';
import { memberSchema, readAll, type SchoolMember } from '../../school-api';

export const initials = (name: string) => name.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join('');

/** Members who work for the school: the directory hides learners unless asked. */
export const isStaff = (member: Pick<SchoolMember, 'roles'>) => member.roles.includes('ADMIN') || member.roles.includes('INSTRUCTOR');

/**
 * The school's members, read through the existing scoped reader. A confirmed command bumps the store revision,
 * which re-reads the list. Homonyms get a short non-secret reference derived from their technical identifier.
 */
export function useMembers() {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(() => readAll(schoolId, 'members', memberSchema), [schoolId, revision]);
  const members = useMemo(() => [...(loaded.data?.items ?? [])].sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr') || a.id.localeCompare(b.id)), [loaded.data]);
  const references = useMemo(() => homonymReferences(members.map(item => ({ id: item.id, label: item.displayName }))), [members]);
  const nameOf = (member: { id: string; displayName: string }) => distinctLabel(member.displayName, references.get(member.id));
  return { loaded, members, references, nameOf };
}
