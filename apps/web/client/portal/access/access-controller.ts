import { useEffect, useRef, useState } from 'react';
import { createCommand, filled } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { roleLabel, type Role } from '../../protocol';
import { useCommandRunner, useConsole, usePendingResources, useRouteSelection, useUnsavedChanges } from '../../console/context';
import { useMembers } from './members';

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

/**
 * Existing member commands and draft/version rules, independent from presentation.
 * Editing state is local; only the selected member lives in the URL. Removing an access is a separate intention (team/).
 * `onClose` is called when the person leaves the editor: with a message once the school confirmed the change.
 */
export function useAccessController({ onClose }: { onClose?: (confirmed?: string) => void } = {}) {
  const context = useConsole();
  const { schoolId, school, membership } = context;
  const { confirmed } = useCommandSnapshot();
  const runner = useCommandRunner();
  const pendingResources = usePendingResources(schoolId);
  const { loaded, members, references, nameOf } = useMembers();
  const [selected, select] = useRouteSelection();
  const [mode, setMode] = useState<'read' | 'edit'>('read');
  const [step, setStep] = useState(0);
  const [domain, setDomain] = useState<string>('learners');
  const [draftRoles, setDraftRoles] = useState<Role[]>([]);
  const [draftGrants, setDraftGrants] = useState<string[]>([]);
  const [reason, setReason] = useState('');
  const [showErrors, setShowErrors] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const [conflict, setConflict] = useState(false);
  const draftBase = useRef<{ id: string; version: number; roles: Role[]; grants: string[] } | null>(null);
  const operation = useRef<string | null>(null);
  const successMessage = useRef<string | undefined>(undefined);
  const inFlight = useRef(false);
  const current = members.find(member => member.id === selected) ?? null;
  const changed = !!current && (!sameSet(current.roles, draftRoles) || !sameSet(current.grants, draftGrants));
  const dirty = !!current && (changed || !!reason);
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
    setReason(''); setShowErrors(false); setConfirming(false); setConflict(false); setAcknowledged(false);
  }
  useEffect(() => {
    if (!selected) { draftBase.current = null; operation.current = null; setConflict(false); setMode('read'); return; }
    if (!current) return;
    const base = draftBase.current;
    const ownWrite = operation.current !== null && confirmed?.operationId === operation.current;
    const edited = base && (!sameSet(base.roles, draftRoles) || !sameSet(base.grants, draftGrants) || !!reason);
    // A newer version written elsewhere never replaces a draft silently: the person relies on it.
    if (base?.id === current.id && base.version !== current.version && edited && !ownWrite) {
      setConflict(true); setConfirming(false); return;
    }
    reset();
    if (base?.id !== current.id || ownWrite) { setMode('read'); setStep(0); }
    // The school confirmed this very change, possibly learned from its receipt after a lost reply.
    if (ownWrite && onClose) onClose(successMessage.current);
  }, [selected, current?.id, current?.version]);

  function startEditing() { if (canWrite) { reset(); setStep(0); setMode('edit'); runner.clearOutcome(); } }
  function cancelEditing() { if (!runner.busy && !runner.pending) { reset(); setMode('read'); onClose?.(); } }
  /** Back to the school's current accesses without leaving the editor. */
  function restart() { if (!runner.busy && !runner.pending) { reset(); setStep(0); } }
  function next() { setShowErrors(true); if (rolesProblem) return; setShowErrors(false); setStep(Math.min(step + 1, 2)); }
  function review() {
    setShowErrors(true);
    if (canWrite && changed && !rolesProblem && !reasonProblem) { setAcknowledged(false); runner.clearOutcome(); setConfirming(true); }
  }
  function closeConfirmation() { if (!runner.busy && !runner.pending) setConfirming(false); }
  async function confirm() {
    if (!current || !canWrite || inFlight.current || !confirming) return;
    if (!changed || rolesProblem || reasonProblem || (loseAdmin && !acknowledged)) return;
    const success = `Les accès de ${nameOf(current)} sont modifiés.`;
    const command = createCommand({ schoolId, kind: 'updateMember', path: `members/${current.id}`, ifMatch: current.version, resourceId: current.id, resourceVersion: current.version,
      body: { roles: accessRoles.map(role => role.value).filter(value => draftRoles.includes(value)), grants: draftGrants, reason: reason.trim() } });
    operation.current = command.operationId; successMessage.current = success; inFlight.current = true;
    try {
      const result = await runner.run(command, success);
      if (result.status !== 'rejected') setConfirming(false);
      if (result.status === 'confirmed') { setMode('read'); setReason(''); onClose?.(success); }
      // A refusal on the version means the school changed: read it again, the draft stays.
      if (result.status === 'rejected' && result.code === 'VERSION_CONFLICT') loaded.refresh?.();
    } finally { inFlight.current = false; }
  }
  const changes = current ? {
    rolesAdded: draftRoles.filter(role => !current.roles.includes(role)), rolesRemoved: current.roles.filter(role => !draftRoles.includes(role)),
    grantsAdded: draftGrants.filter(grant => !current.grants.includes(grant)), grantsRemoved: current.grants.filter(grant => !draftGrants.includes(grant)),
  } : { rolesAdded: [], rolesRemoved: [], grantsAdded: [], grantsRemoved: [] };
  return { context, loaded, members, nameOf, selected, select, current, mode, step, setStep, domain, setDomain,
    draftRoles, setDraftRoles, draftGrants, setDraftGrants, reason, setReason, showErrors, confirming, acknowledged, setAcknowledged,
    conflict, canWrite, self, loseAdmin, rolesProblem, reasonProblem, changed, dirty, changes, pendingResources, references, runner,
    reset, restart, startEditing, cancelEditing, next, review, closeConfirmation, confirm };
}
