import { matchesSearch } from '../../command-core';
import type { Role } from '../../protocol';

export type StatusFilter = 'all' | 'active' | 'inactive';
export type SortOrder = 'name-asc' | 'name-desc';
export const memberPageSize = 25;

export interface DirectoryMember { id: string; displayName: string; status: string; roles: readonly Role[] }
export interface DirectoryOptions {
  search: string;
  status: StatusFilter;
  /** Learners are members too: the directory lists the school's staff unless asked. */
  withLearners: boolean;
  sort: SortOrder;
  /** Short references of homonyms (member id to reference), searched with the name. */
  references: ReadonlyMap<string, string>;
}

const isStaff = (member: Pick<DirectoryMember, 'roles'>) => member.roles.includes('ADMIN') || member.roles.includes('INSTRUCTOR');

/** Staff (or everyone), filtered by access state and by search over name and reference, in the requested order. */
export function visibleMembers<T extends DirectoryMember>(members: readonly T[], options: DirectoryOptions): T[] {
  const direction = options.sort === 'name-desc' ? -1 : 1;
  return members
    .filter(member => options.withLearners || isStaff(member))
    .filter(member => options.status === 'all' || (options.status === 'active') === (member.status === 'ACTIVE'))
    .filter(member => matchesSearch([member.displayName, options.references.get(member.id)], options.search))
    .sort((a, b) => direction * (a.displayName.localeCompare(b.displayName, 'fr') || a.id.localeCompare(b.id)));
}

/** A page number that always points at an existing page, whatever filters changed since it was stored. */
export function clampPage(page: number, total: number, size = memberPageSize): number {
  return Math.max(1, Math.min(page, Math.ceil(total / size) || 1));
}

/** Whether the removal of an access may even be offered: the server stays the only authority on last administrator. */
export function canOfferRemoval(input: { viewerIsAdmin: boolean; schoolActive: boolean; memberActive: boolean; memberIsViewer: boolean }): boolean {
  return input.viewerIsAdmin && input.schoolActive && input.memberActive && !input.memberIsViewer;
}
