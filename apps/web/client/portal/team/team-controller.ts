import { useEffect, useRef, useState } from 'react';
import { createCommand, filled } from '../../command-core';
import { pendingResourceLabel, useCommandRunner, useConsole, usePendingResources, useUnsavedChanges } from '../../console/context';
import { useListState } from '../../console/list-state';
import type { SchoolMember } from '../../school-api';
import { useMembers } from '../access/members';
import { canOfferRemoval, clampPage, memberPageSize, visibleMembers, type SortOrder, type StatusFilter } from './team-model';

/** Directory of the school's members: filters and page live in the school's memory, never in the URL. */
export function useTeamDirectory() {
  const { schoolId, school, membership } = useConsole();
  const { loaded, members, references, nameOf } = useMembers();
  const pending = usePendingResources(schoolId);
  const [search, setSearch] = useListState('team/search', '');
  const [status, setStatus] = useListState<StatusFilter>('team/status', 'all');
  const [withLearners, setWithLearners] = useListState('team/learners', false);
  const [sort, setSort] = useListState<SortOrder>('team/sort', 'name-asc');
  const [page, setPage] = useListState('team/page', 1);
  const visible = visibleMembers(members, { search, status, withLearners, sort, references });
  const currentPage = clampPage(page, visible.length);
  useEffect(() => { if (loaded.status === 'ready' && page !== currentPage) setPage(currentPage); }, [loaded.status, page, currentPage, setPage]);
  const pendingLabel = (id: string) => {
    const kind = pending.get(id.toLowerCase());
    return kind ? pendingResourceLabel[kind] : undefined;
  };
  const filtered = search !== '' || status !== 'all' || withLearners;
  const reset = () => { setSearch(''); setStatus('all'); setWithLearners(false); setPage(1); };
  return {
    loaded, members, references, nameOf, visible, pageRows: visible.slice((currentPage - 1) * memberPageSize, currentPage * memberPageSize), currentPage, pageSize: memberPageSize,
    search, setSearch, status, setStatus, withLearners, setWithLearners, sort, setSort, setPage, pendingLabel, filtered, reset,
    canInvite: membership.roles.includes('ADMIN') && school.status === 'ACTIVE', membershipId: membership.membershipId,
  };
}

/**
 * Removal of an access: its own intention, reason and confirmation, through the existing deactivateMember command.
 * The last administrator and one's own access are refused by the school; the refusal is shown and the reason stays typed.
 */
export function useMemberRemoval(member: SchoolMember | null, reload: () => void) {
  const { schoolId, school, membership } = useConsole();
  const pending = usePendingResources(schoolId);
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [acknowledged, setAcknowledged] = useState(false);
  const inFlight = useRef(false);
  const runner = useCommandRunner(() => { setOpen(false); setReason(''); setAcknowledged(false); });
  useUnsavedChanges(open && !!reason && !runner.busy && !runner.pending);
  const busy = runner.busy || !!runner.pending;
  const offered = !!member && canOfferRemoval({ viewerIsAdmin: membership.roles.includes('ADMIN'), schoolActive: school.status === 'ACTIVE',
    memberActive: member.status === 'ACTIVE', memberIsViewer: member.id === membership.membershipId });
  const available = offered && !busy && !pending.has(member!.id.toLowerCase());
  const reasonProblem = filled(reason, 1000) ? null : 'Indiquez le motif du retrait (1 000 caractères au plus).';
  function start() { if (!available) return; runner.clearOutcome(); setReason(''); setAcknowledged(false); setOpen(true); }
  function close() { if (!busy) { setOpen(false); setReason(''); setAcknowledged(false); } }
  async function confirm(label: string) {
    if (!member || !available || inFlight.current || reasonProblem || !acknowledged) return;
    const command = createCommand({ schoolId, kind: 'deactivateMember', path: `members/${member.id}/deactivate`, ifMatch: member.version, resourceId: member.id,
      resourceVersion: member.version, body: { reason: reason.trim() } });
    inFlight.current = true;
    try {
      const result = await runner.run(command, `${label} n’a plus accès à l’école.`);
      // Confirmed: the form is cleared. Pending: the pending panel owns the request. Refused: the dialog and the reason stay.
      if (result.status === 'confirmed') close();
      if (result.status === 'pending') setOpen(false);
      if (result.status === 'rejected' && result.code === 'VERSION_CONFLICT') reload();
    } finally { inFlight.current = false; }
  }
  return { runner, open, reason, setReason, acknowledged, setAcknowledged, busy, offered, available, reasonProblem, start, close, confirm };
}
