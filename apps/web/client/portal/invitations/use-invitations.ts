import { useEffect, useMemo, useRef, useState } from 'react';
import { createCommand, filled, newOperationId, type SchoolCommand } from '../../command-core';
import { kindsOf } from '../../command-families';
import { useCommandRevision, useCommandSnapshot, type SubmitResult } from '../../command-store';
import { activeInstructors, defaultInstructorId, invitationLabel, invitationSchema, issuedCodeOf, openOfferings, parseInvitationResponse, type Invitation } from '../../invitation-model';
import { distinctLabel, homonymReferences } from '../../person-reference';
import type { Role } from '../../protocol';
import { invitationOptionsSchema, memberSchema, offeringSchema, readAll, readSchool } from '../../school-api';
import { pendingResourceLabel, useCommandLane, useConsole, useLoad, usePendingCreations, usePendingResources, useRouteSelection, useUnsavedChanges } from '../../console/context';
import { useListState } from '../../console/list-state';
import { audienceInvitations, emailProblem, filterInvitations, invitationPageSize, isActionable, proposableRoles, rolesProblem, trainingProblem, type InvitationStatusFilter } from './invitations-model';

export type CreateMode = 'code' | 'email';
export type InvitationDialog = 'create' | 'renew' | 'revoke' | null;
/** The single-use code of a create or renew response. It lives in this hook's memory only, as long as it is on screen. */
export type IssuedCode = NonNullable<ReturnType<typeof issuedCodeOf>>;

/** What the person typed, kept in memory while a request is followed so that a refusal gives it back untouched. */
type Typed =
  | { kind: 'create'; mode: CreateMode; formKey: string; email: string; roles: Role[]; offeringIds: string[]; instructorId: string; baseline: string }
  | { kind: 'renew' | 'revoke'; invitationId: string; reason: string };
type Refusal = Typed & { tag: string };

/** Reads that change when an invitation, a member or an offer is confirmed; lessons, hours and dossiers are not read again for them. */
const invitationReads = kindsOf('invitations', 'members', 'catalogue');
/** Refusals that say the list on screen is no longer the school's: it is read again, nothing is changed locally. */
const staleListCodes = new Set(['VERSION_CONFLICT', 'INVITATION_USED', 'INVITATION_REVOKED']);

/**
 * Invitations of the school for one audience (learners or team): reads, local drafts and the existing commands.
 * Creating, handing over (the issued receipt) and following (list and detail) are separate intentions, and each invitation is
 * followed on its own: renewing one never waits for another. The form is released once the request is followed; a refusal gives
 * it back with what was typed. Nothing here invents a member, a link or a code before the school answers.
 */
export function useInvitations() {
  const context = useConsole();
  const { schoolId, school, membership, routeQuery, confirmNavigation } = context;
  const team = routeQuery?.audience === 'team';
  const audience = team ? 'team' : 'learners';
  const revision = useCommandRevision(invitationReads);
  const { entries } = useCommandSnapshot();
  const pendingResources = usePendingResources(schoolId);
  const pendingCreations = usePendingCreations(schoolId, 'createInvitation');
  const [selected, select] = useRouteSelection();
  const [creating, setCreating] = useState<CreateMode | null>(null);
  const [formKey, setFormKey] = useState(newOperationId);
  const [email, setEmail] = useState('');
  const [invitedRoles, setInvitedRoles] = useState<Role[]>([]);
  const [offeringIds, setOfferingIds] = useState<string[]>([]);
  const [instructorId, setInstructorId] = useState('');
  const [baseline, setBaseline] = useState('');
  const [revokeReason, setRevokeReason] = useState('');
  const [showErrors, setShowErrors] = useState(false);
  const [dialog, setDialog] = useState<InvitationDialog>(null);
  /** Codes handed over by a response, by invitation, until the invitation is left or the page is. */
  const [issuedCodes, setIssuedCodes] = useState<Record<string, IssuedCode>>({});
  /** The school confirmed a code but its answer carried none that could be verified. */
  const [codeMissing, setCodeMissing] = useState(false);
  const [refusals, setRefusals] = useState<Refusal[]>([]);
  /** Typed content and codes expected, by tag / by operation: memory only, gone with the page. */
  const typed = useRef(new Map<string, Typed>());
  const awaitingCode = useRef(new Set<string>());
  const latest = useRef({ creating, selected, dialog, audience });
  latest.current = { creating, selected, dialog, audience };
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const lane = useCommandLane((intent, result) => {
    typed.current.delete(intent.tag);
    // A code learnt by receipt (lost reply) was never seen: the school does not repeat it.
    if (result === null && awaitingCode.current.delete(intent.operationId)) setCodeMissing(true);
  });
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
  // Writing waits for a complete read of an active school, never for another invitation's request.
  const canWrite = active && loaded.status === 'ready' && (viewerIsAdmin || (!team && membership.roles.includes('INSTRUCTOR')));
  const emailAvailable = data?.options.emailInvitationsAvailable === true;
  const codeAvailable = data?.options.codeInvitationsAvailable === true;
  const proposable = proposableRoles(team, viewerIsAdmin);
  const emailError = emailProblem(email), roleError = rolesProblem(invitedRoles, proposable), trainingError = trainingProblem(offeringIds, instructorId, offerings, instructors);
  const draftValue = creating === 'email' ? JSON.stringify([email, invitedRoles]) : JSON.stringify([offeringIds, instructorId]);
  const releaseChanges = useUnsavedChanges((!!creating && draftValue !== baseline) || !!revokeReason);

  // Another account, school or access epoch never sees what the previous one was shown (the lane itself is dropped with them).
  useEffect(() => {
    setIssuedCodes({}); setCodeMissing(false); setCreating(null); setDialog(null); setRevokeReason(''); setRefusals([]);
    typed.current.clear(); awaitingCode.current.clear();
  }, [schoolId, membership.membershipId, membership.accessEpoch, audience]);

  const leaveForm = (proceed: () => void) => confirmNavigation ? confirmNavigation(proceed) : proceed();
  const dropSeen = (id: string | null) => { if (id) setIssuedCodes(codes => { if (!(id in codes)) return codes; const { [id]: _seen, ...rest } = codes; return rest; }); };
  function open(mode: CreateMode) {
    if (!canWrite || (mode === 'code' ? !codeAvailable || team : !emailAvailable || (team && !viewerIsAdmin))) return;
    leaveForm(() => {
      lane.clearOutcome(); dropSeen(selected); select(null); setShowErrors(false); setCodeMissing(false); setFormKey(newOperationId());
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
  function openInvitation(id: string) { leaveForm(() => { setCreating(null); setCodeMissing(false); setRevokeReason(''); dropSeen(selected); select(id); }); }
  function backToList() { leaveForm(() => { releaseChanges(); setCreating(null); setRevokeReason(''); dropSeen(selected); setCodeMissing(false); select(null); }); }
  function review() {
    setShowErrors(true);
    const problem = creating === 'code' ? trainingError : emailError ?? roleError;
    if (canWrite && !problem) { lane.clearOutcome(); setDialog('create'); }
  }
  const actionBlocked = (kind: 'resendInvitation' | 'revokeInvitation', id: string) => lane.blocked({ kind, resourceId: id });
  function ask(next: 'renew' | 'revoke') {
    if (canWrite && current && isActionable(current) && !actionBlocked(next === 'renew' ? 'resendInvitation' : 'revokeInvitation', current.id)) { lane.clearOutcome(); setDialog(next); }
  }
  const dialogTag = dialog === 'create' ? `create:${formKey}` : dialog && current ? `invitation:${current.id}` : null;
  const dialogView = dialogTag ? lane.view(dialogTag) : null;
  function closeDialog() { if (!dialogView?.busy) { setDialog(null); setRevokeReason(''); } }
  /** Keep the code of a create or renew response on screen; nothing else ever holds it. */
  function showIssued(body: unknown, invitationId?: string) {
    const invitation = parseInvitationResponse(body, invitationId ? { schoolId, invitationId } : { schoolId });
    const code = issuedCodeOf(invitation);
    if (code) setIssuedCodes(codes => ({ ...codes, [code.invitationId]: code }));
    setCodeMissing(code === null);
    return invitation?.id ?? null;
  }
  /** The person is on this audience's list with nothing open: only then does a new code take the screen. */
  const idle = () => mounted.current && !latest.current.creating && !latest.current.selected && !latest.current.dialog && latest.current.audience === audience;

  /** Gives back the form (or the reason) of a refused request, with the school's refusal in its dialog. */
  function restore(refusal: Refusal) {
    if (refusal.kind === 'create') {
      setEmail(refusal.email); setInvitedRoles(refusal.roles); setOfferingIds(refusal.offeringIds); setInstructorId(refusal.instructorId);
      setBaseline(refusal.baseline); setFormKey(refusal.formKey); setShowErrors(false); setCreating(refusal.mode); setDialog('create');
    } else { select(refusal.invitationId); setRevokeReason(refusal.reason); setDialog(refusal.kind); }
  }
  // A refusal comes back by itself only where the person already is: on the very invitation it concerns, with nothing else open.
  // Elsewhere the list says so and offers to take it up again; no dialog opens by surprise.
  useEffect(() => {
    const next = refusals[0];
    if (!next || creating || dialog || next.kind === 'create' || selected !== next.invitationId) return;
    setRefusals(list => list.slice(1)); restore(next);
  }, [refusals, creating, selected, dialog]);
  const resumeRefusal = () => { const next = refusals[0]; if (next) leaveForm(() => { setRefusals(list => list.slice(1)); restore(next); }); };

  async function confirm() {
    if (!canWrite || !dialog || dialogView?.busy) return;
    let command: SchoolCommand | null = null, success = '', tag = dialogTag ?? '', record: Typed | null = null, expectsCode = false;
    const snapshot = (): Typed => ({ kind: 'create', mode: creating ?? 'code', formKey, email, roles: invitedRoles, offeringIds, instructorId, baseline });
    if (dialog === 'create' && creating === 'code' && codeAvailable && !team && !trainingError) {
      command = createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
        body: { delivery: 'CODE', roles: ['LEARNER'], trainings: offeringIds.map(offeringId => ({ offeringId, instructorMembershipId: instructorId })) } });
      success = 'Le code est créé.'; record = snapshot(); expectsCode = true;
    } else if (dialog === 'create' && creating === 'email' && emailAvailable && !emailError && !roleError) {
      command = createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
        body: { delivery: 'EMAIL', email: email.trim(), roles: [...invitedRoles].sort() } });
      success = 'L’invitation est enregistrée pour envoi par e-mail.'; record = snapshot();
    } else if (dialog === 'renew' && current && isActionable(current) && (current.delivery === 'CODE' ? codeAvailable : emailAvailable)) {
      const code = current.delivery === 'CODE';
      command = createCommand({ schoolId, kind: 'resendInvitation', path: `invitations/${current.id}/resend`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: {} });
      success = code ? 'Un nouveau code est créé ; l’ancien n’est plus utilisable.' : 'Un nouveau lien est enregistré pour envoi par e-mail ; l’ancien n’est plus utilisable.';
      record = { kind: 'renew', invitationId: current.id, reason: '' }; expectsCode = code;
    } else if (dialog === 'revoke' && current && isActionable(current) && filled(revokeReason, 1000)) {
      command = createCommand({ schoolId, kind: 'revokeInvitation', path: `invitations/${current.id}/revoke`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: { reason: revokeReason.trim() } });
      success = 'L’invitation est révoquée : elle ne permet plus de rejoindre l’école.';
      record = { kind: 'revoke', invitationId: current.id, reason: revokeReason };
    }
    if (!command || !record) return;
    const started = lane.run(command, success, tag);
    // Not admitted: an identical request is still followed. The refusal stays in the dialog, with what was typed.
    if (!started.admitted) { await started.result; return; }
    // Admitted: the request is kept and followed; the screen is released, nothing is shown as done.
    typed.current.set(tag, record);
    if (expectsCode) awaitingCode.current.add(command.operationId);
    setDialog(null);
    if (record.kind === 'create') { releaseChanges(); setCreating(null); setEmail(''); setInvitedRoles([]); setOfferingIds([]); setInstructorId(''); }
    else setRevokeReason('');
    const result: SubmitResult = await started.result;
    if (result.status === 'confirmed') {
      awaitingCode.current.delete(command.operationId);
      if (record.kind === 'create' && expectsCode) {
        // A code learnt by receipt (lost reply) is never shown; only the response carries it.
        const created = result.via === 'response' ? showIssued(result.body) : null;
        if (created && idle()) select(created); else if (!created) setCodeMissing(true);
      } else if (record.kind === 'renew' && expectsCode) {
        if (result.via === 'response') showIssued(result.body, record.invitationId); else { dropSeen(record.invitationId); setCodeMissing(true); }
      } else if (record.kind === 'revoke') { dropSeen(record.invitationId); setCodeMissing(false); }
    } else if (result.status === 'rejected') {
      awaitingCode.current.delete(command.operationId);
      setRefusals(list => [...list, { ...record, tag }]);
      if (staleListCodes.has(result.code)) loaded.refresh?.();
    }
  }
  const pendingLabel = (id: string) => { const kind = pendingResources.get(id.toLowerCase()); return kind ? pendingResourceLabel[kind] : undefined; };
  /** A request on this invitation whose result is still unknown: the panel at the top of the page carries the verification. */
  const awaitingVerification = (id: string) => [...entries.values()].some(entry => entry.meta.resourceId?.toLowerCase() === id.toLowerCase()
    && entry.phase !== 'sending' && entry.phase !== 'verifying');
  const laneOutcomes = [...lane.outcomes].map(([tag, outcome]) => ({ tag, outcome }));
  const refusalOutcome = laneOutcomes.find(item => item.tag === refusals[0]?.tag)?.outcome ?? null;
  return { context, team, audience, loaded, data, items, visible, pageRows: visible.slice((currentPage - 1) * invitationPageSize, currentPage * invitationPageSize), currentPage, pages, setPage,
    search, setSearch, status, setStatus, offerings, instructors, instructorName, labelOf, references, current, selected, creating, email, setEmail, invitedRoles, setInvitedRoles,
    offeringIds, setOfferingIds, instructorId, setInstructorId, revokeReason, setRevokeReason, showErrors, dialog, issuedCodes, codeMissing, proposable,
    active, viewerIsAdmin, canWrite, emailAvailable, codeAvailable, emailError, roleError, trainingError, pendingCreations, pendingLabel, awaitingVerification,
    dialogBusy: dialogView?.busy ?? false, dialogOutcome: dialogView?.outcome ?? null,
    /** Outcomes of requests that ended while their form was no longer on screen (confirmations; refusals come back as `refusals`). */
    confirmations: laneOutcomes.filter(item => item.outcome.tone === 'success').slice(-1),
    detailOutcome: (id: string) => lane.view(`invitation:${id}`).outcome,
    refusals, refusalOutcome, resumeRefusal, dismissRefusal: () => setRefusals(list => list.slice(1)), dismissOutcomes: () => lane.clearOutcome(),
    actionBlocked, open, openInvitation, backToList, review, ask, closeDialog, confirm, cancelCreation: () => leaveForm(() => { releaseChanges(); setCreating(null); }) };
}
export type InvitationsState = ReturnType<typeof useInvitations>;
