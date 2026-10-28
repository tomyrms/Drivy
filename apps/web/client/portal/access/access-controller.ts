import { useEffect, useMemo, useRef, useState } from 'react';
import { createCommand, filled, matchesSearch } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { roleLabel, type Role } from '../../protocol';
import { memberSchema, readAll } from '../../school-api';
import { distinctLabel, homonymReferences } from '../../person-reference';
import { useCommandRunner, useConsole, useLoad, usePendingResources, useRouteSelection, useUnsavedChanges } from '../../console/context';
import { useListState } from '../../console/list-state';

export const accessRoles: readonly { value: Role; description: string }[] = [
  { value: 'ADMIN', description: 'Administration de l’école et de ses dossiers.' },
  { value: 'INSTRUCTOR', description: 'Enseignement et suivi des élèves affectés.' },
  { value: 'LEARNER', description: 'Accès à son propre parcours de formation.' },
];
export const accessDomains = [
  { id: 'learners', label: 'Dossiers élèves', permissions: [
    { value: 'permit_review', label: 'Vérifier les permis' },
    { value: 'REVIEW_REGULATORY_PROFILE', label: 'Revoir les profils réglementaires' },
    { value: 'MANAGE_LEARNER_ARCHIVES', label: 'Gérer les archives des élèves' },
  ] },
  { id: 'planning', label: 'Planning et cours', permissions: [
    { value: 'MANAGE_COURSES', label: 'Organiser les cours collectifs' },
    { value: 'TAKE_ATTENDANCE', label: 'Consigner les présences' },
    { value: 'VALIDATE_REQUIREMENT', label: 'Valider les exigences' },
  ] },
  { id: 'finance', label: 'Prestations et finances', permissions: [
    { value: 'CONFIGURE_CATALOG', label: 'Configurer les prestations et tarifs' },
    { value: 'SELL_SERVICES', label: 'Vendre les prestations' },
    { value: 'cash_record', label: 'Enregistrer les encaissements' },
    { value: 'VIEW_FINANCIAL_METRICS', label: 'Consulter les indicateurs financiers' },
  ] },
  { id: 'school', label: 'Administration', permissions: [
    { value: 'VIEW_SCHOOL_METRICS', label: 'Consulter les indicateurs de l’école' },
    { value: 'EXPORT_MANAGEMENT', label: 'Exporter les données de gestion' },
    { value: 'MANAGE_OBSERVATION_THEMES', label: 'Gérer les signalements' },
  ] },
] as const;
const grants = accessDomains.flatMap(domain => [...domain.permissions]);
export const grantName = (value: string) => grants.find(grant => grant.value === value)?.label ?? value;
export const roleNames = (values: readonly Role[]) => values.map(roleLabel).join(' · ') || 'Aucun rôle';
const sameSet = (left: readonly string[], right: readonly string[]) => left.length === right.length && left.every(value => right.includes(value));

/** Existing member commands and draft/version rules, independent from presentation. */
export function useAccessController() {
  const context = useConsole();
  const { schoolId, school, membership } = context;
  const { revision, confirmed } = useCommandSnapshot();
  const runner = useCommandRunner();
  const pendingResources = usePendingResources(schoolId);
  const loaded = useLoad(() => readAll(schoolId, 'members', memberSchema), [schoolId, revision]);
  const [selected, select] = useRouteSelection();
  const [search, setSearch] = useListState('team/search', '');
  const [filter, setFilter] = useListState<'all' | 'active' | 'inactive'>('team/status', 'all');
  const [showLearners, setShowLearners] = useListState('team/learners', false);
  const [page, setPage] = useListState('team/page', 1);
  const [sort, setSort] = useListState<'name-asc' | 'name-desc'>('team/sort', 'name-asc');
  const [mode, setMode] = useState<'read' | 'edit'>('read');
  const [step, setStep] = useState(0);
  const [domain, setDomain] = useState<string>('learners');
  const [draftRoles, setDraftRoles] = useState<Role[]>([]);
  const [draftGrants, setDraftGrants] = useState<string[]>([]);
  const [reason, setReason] = useState('');
  const [showErrors, setShowErrors] = useState(false);
  const [confirmation, setConfirmation] = useState<'access' | 'deactivate' | null>(null);
  const [deactivateReason, setDeactivateReason] = useState('');
  const [acknowledged, setAcknowledged] = useState(false);
  const [conflict, setConflict] = useState(false);
  const draftBase = useRef<{ id: string; version: number; roles: Role[]; grants: string[] } | null>(null);
  const operation = useRef<string | null>(null);
  const inFlight = useRef(false);
  const members = useMemo(() => [...(loaded.data?.items ?? [])].sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr') || a.id.localeCompare(b.id)), [loaded.data]);
  const references = useMemo(() => homonymReferences(members.map(item => ({ id: item.id, label: item.displayName }))), [members]);
  const nameOf = (member: { id: string; displayName: string }) => distinctLabel(member.displayName, references.get(member.id));
  const audience = members.filter(member => showLearners || member.roles.includes('ADMIN') || member.roles.includes('INSTRUCTOR'));
  const visible = audience.filter(member => (filter === 'all' || (filter === 'active') === (member.status === 'ACTIVE')) && matchesSearch([member.displayName, references.get(member.id)], search))
    .sort((a, b) => (sort === 'name-desc' ? -1 : 1) * (a.displayName.localeCompare(b.displayName, 'fr') || a.id.localeCompare(b.id)));
  const pageSize = 25;
  const currentPage = Math.max(1, Math.min(page, Math.ceil(visible.length / pageSize) || 1));
  const current = members.find(member => member.id === selected) ?? null;
  const changed = !!current && (!sameSet(current.roles, draftRoles) || !sameSet(current.grants, draftGrants));
  const dirty = !!current && (changed || !!reason || !!deactivateReason);
  useUnsavedChanges(dirty && !runner.busy && !runner.pending);
  const self = current?.id === membership.membershipId;
  const loseAdmin = !!(self && current?.roles.includes('ADMIN') && !draftRoles.includes('ADMIN'));
  const canWrite = membership.roles.includes('ADMIN') && school.status === 'ACTIVE' && current?.status === 'ACTIVE' && loaded.status === 'ready'
    && !runner.busy && !runner.pending && !conflict && draftBase.current?.id === current.id && draftBase.current?.version === current.version;
  const rolesProblem = !draftRoles.length ? 'Gardez au moins un rôle.' : null;
  const reasonProblem = filled(reason, 1000) ? null : 'Indiquez le motif du changement (1 000 caractères au plus).';

  function reset() {
    if (!current) return;
    draftBase.current = { id: current.id, version: current.version, roles: [...current.roles], grants: [...current.grants] };
    operation.current = null;
    setDraftRoles([...current.roles]); setDraftGrants([...current.grants]);
    setReason(''); setDeactivateReason(''); setShowErrors(false); setConfirmation(null); setConflict(false); setAcknowledged(false);
  }
  useEffect(() => {
    if (loaded.status === 'ready' && page !== currentPage) setPage(currentPage);
  }, [loaded.status, page, currentPage, setPage]);
  useEffect(() => {
    if (!selected) { draftBase.current = null; operation.current = null; setConflict(false); setMode('read'); return; }
    if (!current) return;
    const base = draftBase.current;
    const ownWrite = operation.current !== null && confirmed?.operationId === operation.current;
    const edited = base && (!sameSet(base.roles, draftRoles) || !sameSet(base.grants, draftGrants) || !!reason || !!deactivateReason);
    if (base?.id === current.id && base.version !== current.version && edited && !ownWrite) {
      setConflict(true); setConfirmation(null); return;
    }
    reset();
    if (base?.id !== current.id || ownWrite) { setMode('read'); setStep(0); }
  }, [selected, current?.id, current?.version]);

  function startEditing() { if (canWrite) { reset(); setStep(0); setMode('edit'); runner.clearOutcome(); } }
  function cancelEditing() { if (!runner.busy && !runner.pending) { reset(); setMode('read'); } }
  function next() { setShowErrors(true); if (rolesProblem) return; setShowErrors(false); setStep(Math.min(step + 1, 2)); }
  function review() {
    setShowErrors(true);
    if (canWrite && changed && !rolesProblem && !reasonProblem) { setAcknowledged(false); runner.clearOutcome(); setConfirmation('access'); }
  }
  function removeAccess() { if (canWrite && !self) { setDeactivateReason(''); setAcknowledged(false); runner.clearOutcome(); setConfirmation('deactivate'); } }
  function closeConfirmation() { if (!runner.busy && !runner.pending) { setConfirmation(null); setDeactivateReason(''); } }
  async function confirm() {
    if (!current || !canWrite || inFlight.current) return;
    if (confirmation === 'access' && (!changed || rolesProblem || reasonProblem || (loseAdmin && !acknowledged))) return;
    if (confirmation === 'deactivate' && (!filled(deactivateReason, 1000) || !acknowledged || self)) return;
    if (!confirmation) return;
    const command = confirmation === 'access'
      ? createCommand({ schoolId, kind: 'updateMember', path: `members/${current.id}`, ifMatch: current.version, resourceId: current.id, resourceVersion: current.version,
        body: { roles: accessRoles.map(role => role.value).filter(value => draftRoles.includes(value)), grants: draftGrants, reason: reason.trim() } })
      : createCommand({ schoolId, kind: 'deactivateMember', path: `members/${current.id}/deactivate`, ifMatch: current.version, resourceId: current.id, resourceVersion: current.version,
        body: { reason: deactivateReason.trim() } });
    operation.current = command.operationId; inFlight.current = true;
    try {
      const result = await runner.run(command, confirmation === 'access' ? `Les accès de ${nameOf(current)} sont modifiés.` : `${nameOf(current)} n’a plus accès à l’école.`);
      if (result.status !== 'rejected') setConfirmation(null);
      if (result.status === 'confirmed') { setMode('read'); setReason(''); setDeactivateReason(''); }
    } finally { inFlight.current = false; }
  }
  const changes = current ? {
    rolesAdded: draftRoles.filter(role => !current.roles.includes(role)), rolesRemoved: current.roles.filter(role => !draftRoles.includes(role)),
    grantsAdded: draftGrants.filter(grant => !current.grants.includes(grant)), grantsRemoved: current.grants.filter(grant => !draftGrants.includes(grant)),
  } : { rolesAdded: [], rolesRemoved: [], grantsAdded: [], grantsRemoved: [] };
  return { context, loaded, members, audience, visible, pageRows: visible.slice((currentPage - 1) * pageSize, currentPage * pageSize), pageSize, currentPage, setPage,
    references, nameOf, search, setSearch, filter, setFilter, showLearners, setShowLearners, sort, setSort, selected, select, current, mode, step, setStep, domain, setDomain,
    draftRoles, setDraftRoles, draftGrants, setDraftGrants, reason, setReason, showErrors, confirmation, deactivateReason, setDeactivateReason, acknowledged, setAcknowledged,
    conflict, canWrite, self, loseAdmin, rolesProblem, reasonProblem, changed, dirty, changes, pendingResources, runner,
    reset, startEditing, cancelEditing, next, review, removeAccess, closeConfirmation, confirm };
}
