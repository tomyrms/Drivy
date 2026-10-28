import { useEffect, useMemo, useRef, useState } from 'react';
import { createCommand, filled } from '../../command-core';
import { useCommandSnapshot, type SubmitResult } from '../../command-store';
import { activeInstructors, defaultInstructorId, invitationLabel, invitationSchema, issuedCodeOf, openOfferings, parseInvitationResponse, type Invitation } from '../../invitation-model';
import { distinctLabel, homonymReferences } from '../../person-reference';
import type { Role } from '../../protocol';
import { invitationOptionsSchema, memberSchema, offeringSchema, readAll, readSchool } from '../../school-api';
import { pendingResourceLabel, useCommandRunner, useConsole, useLoad, usePendingCreations, usePendingResources, useRouteSelection, useUnsavedChanges } from '../../console/context';
import { useListState } from '../../console/list-state';
import { audienceInvitations, emailProblem, filterInvitations, invitationPageSize, isActionable, proposableRoles, rolesProblem, trainingProblem, type InvitationStatusFilter } from './invitations-model';

export type CreateMode = 'code' | 'email';
export type InvitationDialog = 'create' | 'renew' | 'revoke' | null;
/** The single-use code of a create or renew response. It lives in this hook's memory only, as long as it is on screen. */
export type IssuedCode = NonNullable<ReturnType<typeof issuedCodeOf>>;

/**
 * Invitations of the school for one audience (learners or team): reads, local drafts and the existing commands.
 * Creating, handing over (the issued receipt) and following (list and detail) are separate intentions.
 */
export function useInvitations() {
  const context = useConsole();
  const { schoolId, school, membership, routeQuery, confirmNavigation } = context;
  const team = routeQuery?.audience === 'team';
  const audience = team ? 'team' : 'learners';
  const { revision } = useCommandSnapshot();
  const pendingResources = usePendingResources(schoolId);
  const pendingCreations = usePendingCreations(schoolId, 'createInvitation');
  const [selected, select] = useRouteSelection();
  const [creating, setCreating] = useState<CreateMode | null>(null);
  const [email, setEmail] = useState('');
  const [invitedRoles, setInvitedRoles] = useState<Role[]>([]);
  const [offeringIds, setOfferingIds] = useState<string[]>([]);
  const [instructorId, setInstructorId] = useState('');
  const [baseline, setBaseline] = useState('');
  const [revokeReason, setRevokeReason] = useState('');
  const [showErrors, setShowErrors] = useState(false);
  const [dialog, setDialog] = useState<InvitationDialog>(null);
  const [issued, setIssued] = useState<IssuedCode | null>(null);
  /** The school confirmed a code but its answer carried none that could be verified. */
  const [codeMissing, setCodeMissing] = useState(false);
  const inFlight = useRef(false);
  const runner = useCommandRunner(() => { releaseChanges(); setCreating(null); setEmail(''); setInvitedRoles([]); setRevokeReason(''); });
  const loaded = useLoad(async () => {
    const [invitations, offerings, members, options] = await Promise.all([
      readAll(schoolId, 'invitations', invitationSchema), readAll(schoolId, 'offerings', offeringSchema), readAll(schoolId, 'members', memberSchema),
      readSchool(schoolId, 'invitation-options', invitationOptionsSchema)]);
    return { invitations: invitations.items, truncated: invitations.truncated, offerings: offerings.items, members: members.items, options };
  }, [schoolId, revision]);
  const data = loaded.data;
  const [search, setSearch] = useListState(`invitations/${audience}/search`, '');
  const [status, setStatus] = useListState<InvitationStatusFilter>(`invitations/${audience}/status`, 'all');
  const [page, setPage] = useListState(`invitations/${audience}/page`, 1);

  const offerings = useMemo(() => openOfferings(data?.offerings ?? []), [data]);
  const instructors = useMemo(() => activeInstructors(data?.members ?? []), [data]);
  const items = useMemo(() => audienceInvitations(data?.invitations ?? [], team), [data, team]);
  const references = useMemo(() => homonymReferences(items.map(item => ({ id: item.id, label: invitationLabel(item, data?.offerings ?? [], data?.members ?? []) }))), [items, data]);
  const instructorReferences = useMemo(() => homonymReferences(instructors.map(item => ({ id: item.id, label: item.displayName }))), [instructors]);
  const instructorName = (item: { id: string; displayName: string }) => distinctLabel(item.displayName, instructorReferences.get(item.id));
  const labelOf = (item: Invitation) => distinctLabel(invitationLabel(item, data?.offerings ?? [], data?.members ?? []), references.get(item.id));
  const visible = filterInvitations(items, labelOf, { status, search });
  const pages = Math.max(1, Math.ceil(visible.length / invitationPageSize));
  const currentPage = Math.min(Math.max(1, page), pages);
  const current = items.find(item => item.id === selected) ?? null;

  const active = school.status === 'ACTIVE';
  const viewerIsAdmin = membership.roles.includes('ADMIN');
  const busy = runner.busy || !!runner.pending;
  const canWrite = active && loaded.status === 'ready' && (viewerIsAdmin || (!team && membership.roles.includes('INSTRUCTOR'))) && !busy;
  const emailAvailable = data?.options.emailInvitationsAvailable === true;
  const codeAvailable = data?.options.codeInvitationsAvailable === true;
  const proposable = proposableRoles(team, viewerIsAdmin);
  const emailError = emailProblem(email), roleError = rolesProblem(invitedRoles, proposable), trainingError = trainingProblem(offeringIds, instructorId, offerings, instructors);
  const draftValue = creating === 'email' ? JSON.stringify([email, invitedRoles]) : JSON.stringify([offeringIds, instructorId]);
  const releaseChanges = useUnsavedChanges(!busy && ((!!creating && draftValue !== baseline) || !!revokeReason));

  // Another account, school or access epoch never sees what the previous one was shown.
  useEffect(() => { setIssued(null); setCodeMissing(false); setCreating(null); setDialog(null); setRevokeReason(''); },
    [schoolId, membership.membershipId, membership.accessEpoch, audience]);

  const leaveForm = (proceed: () => void) => confirmNavigation ? confirmNavigation(proceed) : proceed();
  function open(mode: CreateMode) {
    if (!canWrite || (mode === 'code' ? !codeAvailable || team : !emailAvailable || (team && !viewerIsAdmin))) return;
    leaveForm(() => {
      runner.clearOutcome(); select(null); setShowErrors(false); setCodeMissing(false); setIssued(null);
      if (mode === 'code') {
        const initialOfferings = offerings.length === 1 ? [offerings[0]!.id] : [];
        const initialInstructor = defaultInstructorId(membership.membershipId, instructors) || (instructors.length === 1 ? instructors[0]!.id : '');
        setOfferingIds(initialOfferings); setInstructorId(initialInstructor); setBaseline(JSON.stringify([initialOfferings, initialInstructor]));
      } else {
        const initialRoles: Role[] = team ? ['INSTRUCTOR'] : ['LEARNER'];
        setEmail(''); setInvitedRoles(initialRoles); setBaseline(JSON.stringify(['', initialRoles]));
      }
      setCreating(mode);
    });
  }
  function openInvitation(id: string) { leaveForm(() => { setCreating(null); setCodeMissing(false); setRevokeReason(''); setIssued(null); select(id); }); }
  function backToList() { leaveForm(() => { releaseChanges(); setCreating(null); setRevokeReason(''); setIssued(null); setCodeMissing(false); select(null); }); }
  function review() {
    setShowErrors(true);
    const problem = creating === 'code' ? trainingError : emailError ?? roleError;
    if (canWrite && !problem) { runner.clearOutcome(); setDialog('create'); }
  }
  function ask(next: 'renew' | 'revoke') { if (canWrite && current && isActionable(current)) { runner.clearOutcome(); setDialog(next); } }
  function closeDialog() { if (!busy) { setDialog(null); setRevokeReason(''); } }
  /** Keep the code of a create or renew response on screen; nothing else ever holds it. */
  function showIssued(body: unknown, invitationId?: string) {
    const invitation = parseInvitationResponse(body, invitationId ? { schoolId, invitationId } : { schoolId });
    const code = issuedCodeOf(invitation);
    setIssued(code); setCodeMissing(code === null);
    return invitation?.id ?? null;
  }

  async function confirm() {
    if (!canWrite || inFlight.current) return;
    inFlight.current = true;
    let result: SubmitResult | undefined;
    try {
      if (dialog === 'create' && creating === 'code' && codeAvailable && !team && !trainingError) {
        result = await runner.run(createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
          body: { delivery: 'CODE', roles: ['LEARNER'], trainings: offeringIds.map(offeringId => ({ offeringId, instructorMembershipId: instructorId })) } }), 'Le code est créé.');
        if (result.status === 'confirmed') {
          releaseChanges();
          // A code learnt by receipt (lost reply) was never seen: the school does not repeat it.
          const created = result.via === 'response' ? showIssued(result.body) : null;
          if (created) select(created); else setCodeMissing(true);
          setCreating(null);
        }
      } else if (dialog === 'create' && creating === 'email' && emailAvailable && !emailError && !roleError) {
        result = await runner.run(createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
          body: { delivery: 'EMAIL', email: email.trim(), roles: [...invitedRoles].sort() } }), 'L’invitation est enregistrée pour envoi par e-mail.');
        if (result.status === 'confirmed') { releaseChanges(); setCreating(null); setEmail(''); setInvitedRoles([]); }
      } else if (dialog === 'renew' && current && isActionable(current) && (current.delivery === 'CODE' ? codeAvailable : emailAvailable)) {
        const code = current.delivery === 'CODE';
        result = await runner.run(createCommand({ schoolId, kind: 'resendInvitation', path: `invitations/${current.id}/resend`, ifMatch: current.version,
          resourceId: current.id, resourceVersion: current.version, body: {} }),
          code ? 'Un nouveau code est créé ; l’ancien n’est plus utilisable.' : 'Un nouveau lien est enregistré pour envoi par e-mail ; l’ancien n’est plus utilisable.');
        if (result.status === 'confirmed' && code) {
          if (result.via === 'response') showIssued(result.body, current.id); else { setIssued(null); setCodeMissing(true); }
        }
      } else if (dialog === 'revoke' && current && isActionable(current) && filled(revokeReason, 1000)) {
        result = await runner.run(createCommand({ schoolId, kind: 'revokeInvitation', path: `invitations/${current.id}/revoke`, ifMatch: current.version,
          resourceId: current.id, resourceVersion: current.version, body: { reason: revokeReason.trim() } }), 'L’invitation est révoquée : elle ne permet plus de rejoindre l’école.');
        if (result.status === 'confirmed') { setRevokeReason(''); setIssued(null); setCodeMissing(false); }
      }
      // A refusal stays in the dialog, next to the action it concerns, with the typed reason.
      if (result && result.status !== 'rejected') setDialog(null);
      if (result?.status === 'rejected' && result.code === 'VERSION_CONFLICT') loaded.refresh?.();
    } finally { inFlight.current = false; }
  }
  const pendingLabel = (id: string) => { const kind = pendingResources.get(id.toLowerCase()); return kind ? pendingResourceLabel[kind] : undefined; };
  return { context, team, audience, loaded, data, items, visible, pageRows: visible.slice((currentPage - 1) * invitationPageSize, currentPage * invitationPageSize), currentPage, pages, setPage,
    search, setSearch, status, setStatus, offerings, instructors, instructorName, labelOf, references, current, selected, creating, email, setEmail, invitedRoles, setInvitedRoles,
    offeringIds, setOfferingIds, instructorId, setInstructorId, revokeReason, setRevokeReason, showErrors, dialog, issued, codeMissing, proposable,
    active, viewerIsAdmin, busy, canWrite, emailAvailable, codeAvailable, emailError, roleError, trainingError, pendingCreations, pendingLabel, runner,
    open, openInvitation, backToList, review, ask, closeDialog, confirm, cancelCreation: () => leaveForm(() => { releaseChanges(); setCreating(null); }) };
}
export type InvitationsState = ReturnType<typeof useInvitations>;
