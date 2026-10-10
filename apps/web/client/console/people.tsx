import { useEffect, useMemo, useRef, useState } from 'react';
import { commandMessage, createCommand, filled, isEmail, matchesSearch } from '../command-core';
import { useCommandSnapshot, type SubmitResult } from '../command-store';
import { roleLabel, type Role } from '../protocol';
import {
  activeInstructors, defaultInstructorId, invitationCodeMessage, invitationLabel, invitationSchema, issuedCodeOf, offeringLabel, openOfferings, parseInvitationResponse,
  type Invitation,
} from '../invitation-model';
import { memberSchema, offeringSchema, readAll } from '../school-api';
import { CheckField, ConfirmDialog, EmptyState, Facts, Notice, SelectField, StatusBadge, Symbol, TextArea, TextField, formatDateTime, type Tone } from '../ui';
import { useCommandRunner, useConsole, useLoad, useRouteSelection } from './context';
import { DirectoryRow } from './directory';
import { DetailPanel, LoadState, OutcomeNotice, Placeholder, SectionHeading, SplitView } from './layout';

const roles: readonly { value: Role; explanation: string }[] = [
  { value: 'ADMIN', explanation: 'Gérer l’école, ses membres et les dossiers administratifs.' },
  { value: 'INSTRUCTOR', explanation: 'Accompagner les élèves affectés à ses formations.' },
  { value: 'LEARNER', explanation: 'Accéder à son propre dossier et à ses leçons.' },
];
/** Same labels as SchoolMemberGrant on iPhone. */
const grants: readonly { value: string; label: string }[] = [
  { value: 'permit_review', label: 'Vérifier les permis' }, { value: 'cash_record', label: 'Enregistrer les encaissements' },
  { value: 'CONFIGURE_CATALOG', label: 'Configurer les prestations et tarifs' }, { value: 'SELL_SERVICES', label: 'Vendre les prestations' },
  { value: 'MANAGE_COURSES', label: 'Organiser les cours collectifs' }, { value: 'TAKE_ATTENDANCE', label: 'Consigner les présences' },
  { value: 'VALIDATE_REQUIREMENT', label: 'Valider les exigences' }, { value: 'REVIEW_REGULATORY_PROFILE', label: 'Revoir les profils réglementaires' },
  { value: 'MANAGE_LEARNER_ARCHIVES', label: 'Gérer les archives des élèves' }, { value: 'VIEW_SCHOOL_METRICS', label: 'Consulter les indicateurs de l’école' },
  { value: 'VIEW_FINANCIAL_METRICS', label: 'Consulter les indicateurs financiers' }, { value: 'EXPORT_MANAGEMENT', label: 'Exporter les données de gestion' },
];
const grantLabel = (value: string) => grants.find(item => item.value === value)?.label ?? 'Autorisation inconnue';
const rolesText = (values: readonly Role[]) => values.length ? values.map(roleLabel).join(' · ') : 'Aucun rôle';
const sameSet = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every(item => b.includes(item));
const isStaff = (member: { roles: readonly Role[] }) => member.roles.includes('ADMIN') || member.roles.includes('INSTRUCTOR');

/* ---------------------------------------------------------------- Équipe et accès */

export function TeamSection() {
  const { schoolId, school, membership, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner();
  const loaded = useLoad(() => readAll(schoolId, 'members', memberSchema), [schoolId, revision]);
  const [filter, setFilter] = useState('');
  const [showLearners, setShowLearners] = useState(false);
  const [selected, setSelected] = useRouteSelection();
  const [draftRoles, setDraftRoles] = useState<Role[]>([]);
  const [draftGrants, setDraftGrants] = useState<string[]>([]);
  const [reason, setReason] = useState('');
  const [showErrors, setShowErrors] = useState(false);
  const [dialog, setDialog] = useState<'access' | 'deactivate' | null>(null);
  const [deactivateReason, setDeactivateReason] = useState('');
  const [acknowledged, setAcknowledged] = useState(false);
  const members = useMemo(() => [...(loaded.data?.items ?? [])].sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr')), [loaded.data]);
  const visible = members.filter(item => (showLearners || isStaff(item)) && matchesSearch([item.displayName], filter));
  const current = members.find(item => item.id === selected) ?? null;
  useEffect(() => {
    if (!current) return;
    setDraftRoles([...current.roles]); setDraftGrants([...current.grants]); setReason(''); setDeactivateReason(''); setShowErrors(false); setDialog(null);
  }, [current?.id, current?.version]);
  const self = current?.id === membership.membershipId;
  const changed = !!current && (!sameSet(current.roles, draftRoles) || !sameSet(current.grants, draftGrants));
  const loseAdmin = self && current?.roles.includes('ADMIN') && !draftRoles.includes('ADMIN');
  const problem = !changed ? null : draftRoles.length === 0 ? 'Gardez au moins un rôle.' : !filled(reason, 1000) ? 'Indiquez le motif du changement (1 000 caractères au plus).' : null;
  const canWrite = school.status === 'ACTIVE' && current?.status === 'ACTIVE' && loaded.status === 'ready' && !runner.pending && !runner.busy;
  const deactivateProblem = filled(deactivateReason, 1000) ? null : 'Indiquez le motif du retrait (1 000 caractères au plus).';

  async function confirm() {
    if (!current || !canWrite) return;
    let result: SubmitResult | undefined;
    if (dialog === 'access' && !problem && changed) {
      const command = createCommand({ schoolId, kind: 'updateMember', path: `members/${current.id}`, ifMatch: current.version, resourceId: current.id,
        resourceVersion: current.version, body: { roles: roles.map(item => item.value).filter(value => draftRoles.includes(value)), grants: grants.map(item => item.value).filter(value => draftGrants.includes(value)), reason: reason.trim() } });
      result = await runner.run(command, `Les accès de ${current.displayName} sont modifiés.`);
    } else if (dialog === 'deactivate' && !deactivateProblem && !self) {
      const command = createCommand({ schoolId, kind: 'deactivateMember', path: `members/${current.id}/deactivate`, ifMatch: current.version, resourceId: current.id,
        resourceVersion: current.version, body: { reason: deactivateReason.trim() } });
      result = await runner.run(command, `${current.displayName} n’a plus accès à l’école.`);
    }
    if (result && result.status !== 'rejected') setDialog(null);
  }
  const toggle = <T extends string,>(list: T[], value: T, on: boolean) => on ? [...list, value] : list.filter(item => item !== value);

  return (
    <div className="section-stack">
      <SectionHeading title="Équipe et accès" />
      {!dialog && <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />}
      {runner.outcome?.code === 'REAUTH_REQUIRED' && <p className="caption">Après la reconnexion, rouvrez ce membre et saisissez à nouveau le changement : la saisie n’est pas conservée.</p>}
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture de l’équipe…">{data => <SplitView mobileDetail={!!selected} onBack={() => setSelected(null)} backLabel="Tous les membres"
        list={<>
          <div className="list-toolbar directory-toolbar">
            <TextField label="Rechercher un membre" value={filter} onChange={setFilter} placeholder="Nom" />
            <CheckField label="Afficher les élèves" checked={showLearners} onChange={setShowLearners} />
            {filter && <button type="button" className="button quiet" onClick={() => setFilter('')}>Effacer la recherche</button>}
          </div>
          {visible.length === 0 ? <EmptyState symbol="users" title={members.length ? 'Aucun membre trouvé' : 'Aucun membre'} message="" />
          : <ul className="directory-list" aria-label={`Membres de l’école${data.truncated ? ' (liste partielle)' : ''}`}>
            {visible.map(item => <DirectoryRow key={item.id} title={item.displayName} selected={item.id === selected} onSelect={() => setSelected(item.id)}
              meta={item.id === membership.membershipId ? 'Vous' : undefined} detail={rolesText(item.roles)}
              badge={item.status !== 'ACTIVE' ? <StatusBadge tone="neutral" symbol="ban">Accès inactif</StatusBadge> : undefined} />)}
          </ul>}
        </>}
        detail={current ? <DetailPanel focusKey={current.id} title={current.displayName} meta={self ? 'Votre propre accès' : rolesText(current.roles)}
            badge={current.status !== 'ACTIVE' ? <StatusBadge tone="neutral" symbol="ban">Accès inactif</StatusBadge> : undefined}>
            {current.roles.includes('INSTRUCTOR') && <div className="detail-links">
              <button type="button" className="button quiet" onClick={() => navigate('agenda', { instructor: current.id })}><Symbol kind="calendar" bare />Voir le planning</button>
              <button type="button" className="button quiet" onClick={() => navigate('disponibilites', { instructor: current.id, from: 'equipe' })}>Disponibilités et absences</button>
            </div>}
            <form className="form-grid" onSubmit={event => event.preventDefault()}>
              <fieldset className="fieldset">
                <legend>Rôles dans cette école</legend>
                {roles.map(role => <CheckField key={role.value} label={roleLabel(role.value)} description={role.explanation} checked={draftRoles.includes(role.value)}
                  disabled={!canWrite} onChange={on => setDraftRoles(list => toggle(list, role.value, on))} />)}
              </fieldset>
              <details className="disclosure"><summary>Autorisations particulières</summary><fieldset className="fieldset">
                <legend className="visually-hidden">Autorisations particulières</legend>
                <div className="check-grid">{grants.map(grant => <CheckField key={grant.value} label={grant.label} checked={draftGrants.includes(grant.value)}
                  disabled={!canWrite} onChange={on => setDraftGrants(list => toggle(list, grant.value, on))} />)}</div>
              </fieldset></details>
              {changed && <TextArea label="Motif du changement" rows={3} maxLength={1000} value={reason} onChange={setReason} disabled={!canWrite}
                hint="Conservé dans l’historique de l’école." error={showErrors && problem && draftRoles.length ? problem : null} />}
              {changed && draftRoles.length === 0 && <p className="field-error"><Symbol kind="alert" bare />Gardez au moins un rôle.</p>}
              {loseAdmin && <Notice tone="warning" title="Vous retirez votre propre rôle Administration" live={false}><p>Vous ne pourrez plus administrer cette école après la confirmation.</p></Notice>}
              {changed && <div className="form-actions">
                <button type="button" className="button primary" disabled={!canWrite} onClick={() => { setShowErrors(true); if (!problem) { setAcknowledged(false); setDialog('access'); } }}>Relire le changement</button>
                <button type="button" className="button quiet" disabled={runner.busy} onClick={() => { setDraftRoles([...current.roles]); setDraftGrants([...current.grants]); setReason(''); setShowErrors(false); }}>Annuler les modifications</button>
              </div>}
            </form>
            {current.status === 'ACTIVE' && !self && <div className="form-actions"><button type="button" className="button quiet danger" disabled={!canWrite}
              onClick={() => { runner.clearOutcome(); setAcknowledged(false); setDialog('deactivate'); }}>Retirer l’accès…</button></div>}
          </DetailPanel>
          : <Placeholder>Choisissez un membre pour consulter ou modifier ses accès.</Placeholder>} />}
      </LoadState>
      {current && <ConfirmDialog open={dialog !== null} busy={runner.busy} onCancel={() => setDialog(null)} onConfirm={() => void confirm()}
        title={dialog === 'deactivate' ? 'Retirer l’accès' : 'Modifier les accès'}
        confirmLabel={dialog === 'deactivate' ? 'Retirer l’accès' : 'Confirmer le changement d’accès'}
        disabledReason={runner.busy ? null : !canWrite ? 'Actualisez les accès avant de confirmer.' : dialog === 'deactivate' ? deactivateProblem : problem}
        {...(dialog === 'deactivate' ? { acknowledgement: 'Je comprends que cette personne ne pourra plus accéder à l’école.', acknowledged, onAcknowledge: setAcknowledged }
          : loseAdmin ? { acknowledgement: 'Je comprends que je ne pourrai plus administrer cette école.', acknowledged, onAcknowledge: setAcknowledged } : {})}>
        <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
        <p className="dialog-lead">{current.displayName}</p>
        {dialog === 'deactivate' ? <TextArea label="Motif du retrait" required rows={3} maxLength={1000} value={deactivateReason} onChange={setDeactivateReason} disabled={runner.busy} />
          : <Facts items={[
          ['Rôles actuels', rolesText(current.roles)], ['Rôles demandés', rolesText(roles.map(item => item.value).filter(value => draftRoles.includes(value)))],
          ['Autorisations ajoutées', draftGrants.filter(item => !current.grants.includes(item)).map(grantLabel).join(', ') || 'Aucune'],
          ['Autorisations retirées', current.grants.filter(item => !draftGrants.includes(item)).map(grantLabel).join(', ') || 'Aucune'],
          ['Motif', reason.trim()],
        ]} />}
        <p className="caption">Les accès de cette personne changent dès la confirmation par l’école.</p>
      </ConfirmDialog>}
    </div>
  );
}

/* ---------------------------------------------------------------- Invitations */

const invitationStatus = (status: Invitation['status']): { label: string; tone: Tone } => ({
  PENDING: { label: 'En attente', tone: 'accent' as Tone }, ACCEPTED: { label: 'Acceptée', tone: 'success' as Tone },
  REVOKED: { label: 'Révoquée', tone: 'neutral' as Tone }, EXPIRED: { label: 'Expirée', tone: 'warning' as Tone },
})[status];
function InvitationState({ status }: { status: Invitation['status'] }) {
  return status === 'EXPIRED' || status === 'REVOKED'
    ? <StatusBadge tone={invitationStatus(status).tone} symbol={status === 'EXPIRED' ? 'clock' : 'ban'}>{invitationStatus(status).label}</StatusBadge>
    : <span className="row-meta">{invitationStatus(status).label}</span>;
}
/**
 * The school has no e-mail relay: invitations by e-mail are not offered (a 5xx from a mail that never left used to
 * block every other change). Existing ones stay listed; set to true to offer them again.
 */
const emailInvitations = false;
type Dialog = 'create' | 'resend' | 'revoke' | null;
type CreateMode = 'code' | 'email';
/** The single-use code lives in this component's memory only, for as long as it is on screen. */
type IssuedCode = NonNullable<ReturnType<typeof issuedCodeOf>>;

/** Clipboard API first; a temporary selection when the browser refuses it (insecure page, missing permission). */
async function copyText(value: string): Promise<boolean> {
  try { await navigator.clipboard.writeText(value); return true; } catch { /* try the selection below */ }
  const opener = document.activeElement;
  const area = document.createElement('textarea');
  area.value = value; area.readOnly = true; area.style.position = 'fixed'; area.style.opacity = '0';
  document.body.append(area); area.select();
  try { return document.execCommand('copy'); } catch { return false; }
  finally { area.remove(); if (opener instanceof HTMLElement) opener.focus(); }
}

function CopyButton({ value, label }: { value: string; label: string }) {
  const [state, setState] = useState<'idle' | 'copied' | 'failed'>('idle');
  const timer = useRef<number | undefined>(undefined);
  // The confirmation fades after a moment; a new copy restarts it and leaving the page cancels it.
  useEffect(() => () => window.clearTimeout(timer.current), []);
  async function copy() {
    setState(await copyText(value) ? 'copied' : 'failed');
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setState('idle'), 2500);
  }
  return <>
    <button type="button" className="button secondary" onClick={() => void copy()}>
      {state !== 'idle' && <Symbol kind={state === 'copied' ? 'check' : 'alert'} bare />}
      {state === 'copied' ? 'Copié' : state === 'failed' ? 'Copie impossible' : label}
    </button>
    <span className="visually-hidden" role="status">{state === 'copied' ? 'Copié' : state === 'failed' ? 'Copie impossible' : ''}</span>
  </>;
}

export function InvitationsSection() {
  const { schoolId, school, membership, navigate, routeQuery } = useConsole();
  const team = routeQuery?.audience === 'team';
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => { setCreating(null); setEmail(''); setInvitedRoles(['LEARNER']); setRevokeReason(''); });
  const loaded = useLoad(async () => {
    const [invitations, offerings, members] = await Promise.all([
      readAll(schoolId, 'invitations', invitationSchema), readAll(schoolId, 'offerings', offeringSchema), readAll(schoolId, 'members', memberSchema)]);
    return { invitations: invitations.items, offerings: offerings.items, members: members.items };
  }, [schoolId, revision]);
  const [selected, setSelected] = useRouteSelection();
  const [creating, setCreating] = useState<CreateMode | null>(null);
  useEffect(() => { if (selected) setCreating(null); }, [selected]);
  const [email, setEmail] = useState('');
  const [invitedRoles, setInvitedRoles] = useState<Role[]>(['LEARNER']);
  const [offeringIds, setOfferingIds] = useState<string[]>([]);
  const [instructorId, setInstructorId] = useState('');
  const [revokeReason, setRevokeReason] = useState('');
  const [showErrors, setShowErrors] = useState(false);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [acknowledged, setAcknowledged] = useState(false);
  const [issuedCode, setIssuedCode] = useState<IssuedCode | null>(null);
  /** The school confirmed a code but its response carried none that could be verified. */
  const [codeMissing, setCodeMissing] = useState(false);
  const data = loaded.data;
  const items = useMemo(() => [...(data?.invitations ?? [])].filter(item => team ? isStaff(item) : !isStaff(item)).reverse(), [data, team]);
  const offerings = useMemo(() => openOfferings(data?.offerings ?? []), [data]);
  const instructors = useMemo(() => activeInstructors(data?.members ?? []), [data]);
  const current = items.find(item => item.id === selected) ?? null;
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | Invitation['status']>('all');
  const active = school.status === 'ACTIVE';
  const canWrite = active && !runner.pending && !runner.busy;
  const emailProblem = isEmail(email.trim()) ? null : 'Indiquez l’adresse e-mail de la personne invitée.';
  const rolesProblem = invitedRoles.length ? null : 'Choisissez au moins un rôle.';
  const trainingProblem = offeringIds.length > 0 && offeringIds.length <= 16
    && offeringIds.every(id => offerings.some(item => item.id === id))
    && instructors.some(item => item.id === instructorId) ? null : commandMessage('INVITATION_TRAINING_INVALID');
  const actionable = current && (current.status === 'PENDING' || current.status === 'EXPIRED');
  const chosenInstructor = instructors.find(item => item.id === instructorId);

  const label = (item: Invitation) => invitationLabel(item, data?.offerings ?? [], data?.members ?? []);
  const expiryOf = (value: string) => formatDateTime(value, school.timeZone);
  const visible = items.filter(item => (statusFilter === 'all' || item.status === statusFilter) && matchesSearch([label(item)], search));
  function openCode() {
    runner.clearOutcome(); setSelected(null); setShowErrors(false); setCodeMissing(false);
    setOfferingIds(offerings.length === 1 ? [offerings[0]!.id] : []);
    setInstructorId(defaultInstructorId(membership.membershipId, instructors) || (instructors.length === 1 ? instructors[0]!.id : ''));
    setCreating('code');
  }
  function openEmail() {
    runner.clearOutcome(); setSelected(null); setShowErrors(false); setCodeMissing(false); setEmail(''); setInvitedRoles(['LEARNER']); setCreating('email');
  }
  /** Keep the code of a create or renew response on screen; nothing else ever holds it. */
  function showIssued(body: unknown, invitationId?: string) {
    const invitation = parseInvitationResponse(body, invitationId ? { schoolId, invitationId } : { schoolId });
    const issued = issuedCodeOf(invitation);
    setIssuedCode(issued); setCodeMissing(issued === null);
    return invitation?.id ?? null;
  }

  async function confirm(action: Dialog = dialog) {
    if (!canWrite) return;
    let result: SubmitResult | undefined;
    if (action === 'create' && creating === 'code' && !trainingProblem) {
      const command = createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
        body: { delivery: 'CODE', roles: ['LEARNER'], trainings: offeringIds.map(offeringId => ({ offeringId, instructorMembershipId: instructorId })) } });
      result = await runner.run(command, 'Code créé.');
      if (result.status === 'confirmed') {
        const created = result.via === 'response' ? showIssued(result.body) : null;
        if (created) setSelected(created);
        else setCodeMissing(true);
        setCreating(null);
      }
    } else if (action === 'create' && creating === 'email' && !emailProblem && !rolesProblem) {
      const command = createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
        body: { email: email.trim(), roles: [...invitedRoles].sort() } });
      result = await runner.run(command, 'L’invitation est créée. Le message part vers l’adresse indiquée ; le lien est valable 7 jours.');
      if (result.status === 'confirmed') { setCreating(null); setEmail(''); setInvitedRoles(['LEARNER']); }
    } else if (action === 'resend' && current && actionable) {
      const code = current.delivery === 'CODE';
      result = await runner.run(createCommand({ schoolId, kind: 'resendInvitation', path: `invitations/${current.id}/resend`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: {} }),
        code ? 'Un nouveau code est créé ; l’ancien n’est plus utilisable.' : 'Un nouveau lien est envoyé ; l’ancien n’est plus utilisable.');
      if (result.status === 'confirmed' && code) {
        if (result.via === 'response') showIssued(result.body, current.id); else { setIssuedCode(null); setCodeMissing(true); }
      }
    } else if (action === 'revoke' && current && actionable && filled(revokeReason, 1000)) {
      result = await runner.run(createCommand({ schoolId, kind: 'revokeInvitation', path: `invitations/${current.id}/revoke`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: { reason: revokeReason.trim() } }), 'L’invitation est révoquée : elle ne permet plus de rejoindre l’école.');
      if (result.status === 'confirmed') { setRevokeReason(''); setIssuedCode(null); setCodeMissing(false); }
    }
    // A refusal stays in the dialog, next to the action it concerns, with the typed reason.
    if (result?.status !== 'rejected') setDialog(null);
  }

  return (
    <div className="section-stack">
      <SectionHeading context={team ? 'Équipe' : 'Élèves'} title={team ? 'Invitations de l’équipe' : 'Invitations élèves'}
        actions={active && !team && !creating ? <>
          <button type="button" className="button primary" disabled={!canWrite} onClick={openCode}><Symbol kind="plus" bare />Code élève</button>
          {emailInvitations && <button type="button" className="button quiet" disabled={!canWrite} onClick={openEmail}><Symbol kind="mail" bare />Inviter par e-mail</button>}
        </> : undefined} />
      {!active && <Notice tone="info" title="Invitations disponibles après l’activation" live={false}
        actions={<button type="button" className="button secondary" onClick={() => navigate('configuration')}>Ouvrir la configuration</button>}>
        <p>L’école doit être active, avec ses textes d’information adoptés, avant d’inviter des personnes.</p></Notice>}
      {!dialog && <OutcomeNotice outcome={issuedCode && runner.outcome?.tone === 'success' ? null : runner.outcome} onDismiss={runner.clearOutcome} />}
      {codeMissing && <Notice tone="warning" title="Code non affiché"><p>La réponse de l’école ne permet pas d’afficher le code. « Nouveau code » en crée un autre.</p></Notice>}
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des invitations…">{() => <SplitView mobileDetail={!!selected || !!creating} onBack={() => { setSelected(null); setCreating(null); }} backLabel="Toutes les invitations"
        list={items.length === 0 ? <EmptyState symbol="mail" title="Aucune invitation" message="" />
          : <>
          <div className="list-toolbar directory-toolbar">
            <TextField label="Rechercher une invitation" value={search} onChange={setSearch} placeholder={team ? 'Adresse' : 'Permis ou moniteur'} />
            <SelectField label="État" value={statusFilter} onChange={setStatusFilter}
              options={[{ value: 'all', label: 'Toutes' }, ...(['PENDING', 'ACCEPTED', 'EXPIRED', 'REVOKED'] as const).map(status => ({ value: status, label: invitationStatus(status).label }))]} />
            {search && <button type="button" className="button quiet" onClick={() => setSearch('')}>Effacer la recherche</button>}
          </div>
          {visible.length === 0 ? <EmptyState symbol="mail" title="Aucune invitation trouvée" message="" />
          : <ul className="directory-list" aria-label="Invitations de l’école, les plus récentes d’abord">
            {visible.map(item => <DirectoryRow key={item.id} title={label(item)} selected={item.id === selected && !creating}
              onSelect={() => { setCreating(null); setCodeMissing(false); setSelected(item.id); }}
              meta={<>{team && <>{rolesText(item.roles)} · </>}Expire le <time dateTime={item.expiresAt}>{formatDateTime(item.expiresAt, school.timeZone)}</time></>}
              detail={<InvitationState status={item.status} />} />)}
          </ul>}
          </>}
        detail={creating === 'code' ? <DetailPanel focusKey="create-code" title="Code élève">
            <form className="form-grid" onSubmit={event => { event.preventDefault(); setShowErrors(true); if (!trainingProblem) void confirm('create'); }}>
              <fieldset className="fieldset"><legend>Permis</legend>
                {offerings.map(item => <CheckField key={item.id} label={offeringLabel(item, offerings)} checked={offeringIds.includes(item.id)}
                  disabled={!canWrite} onChange={on => setOfferingIds(ids => on ? [...ids, item.id] : ids.filter(id => id !== item.id))} />)}
              </fieldset>
              <SelectField label="Moniteur" value={instructorId} placeholder="Choisir un moniteur" disabled={!canWrite} onChange={setInstructorId}
                options={instructors.map(item => ({ value: item.id, label: item.displayName }))} />
              {showErrors && trainingProblem && <p className="field-error"><Symbol kind="alert" bare />{trainingProblem}</p>}
              {offerings.length === 0 && <Notice tone="info" title="Aucune offre ouverte" live={false}
                actions={<button type="button" className="button quiet" onClick={() => navigate('offres')}>Ouvrir les offres</button>}>
                <p>Activez une offre pour créer un code élève.</p></Notice>}
              {offerings.length > 0 && instructors.length === 0 && <Notice tone="info" title="Aucun moniteur actif" live={false}
                actions={<button type="button" className="button quiet" onClick={() => navigate('equipe')}>Ouvrir l’équipe</button>}>
                <p>Donnez le rôle Moniteur à un membre actif.</p></Notice>}
              <div className="form-actions">
                <button type="submit" className="button primary" disabled={!canWrite} aria-busy={runner.busy}>Créer le code</button>
                <button type="button" className="button quiet" onClick={() => setCreating(null)} disabled={runner.busy}>Annuler</button>
              </div>
            </form>
          </DetailPanel>
          : creating === 'email' ? <DetailPanel focusKey="create-email" title="Inviter par e-mail"
            actions={<>
              <button type="button" className="button primary" disabled={!canWrite} onClick={() => { setShowErrors(true); if (!emailProblem && !rolesProblem) { setAcknowledged(false); setDialog('create'); } }}>Relire l’invitation</button>
              <button type="button" className="button quiet" onClick={() => setCreating(null)} disabled={runner.busy}>Annuler</button>
            </>}>
            <form className="form-grid" onSubmit={event => { event.preventDefault(); setShowErrors(true); if (!emailProblem && !rolesProblem && canWrite) { setAcknowledged(false); setDialog('create'); } }}>
              <TextField label="Adresse e-mail" type="email" value={email} onChange={setEmail} disabled={!canWrite} maxLength={254} error={showErrors ? emailProblem : null} />
              <fieldset className="fieldset">
                <legend>Rôles proposés</legend>
                {roles.map(role => <CheckField key={role.value} label={roleLabel(role.value)} description={role.explanation} checked={invitedRoles.includes(role.value)}
                  disabled={!canWrite} onChange={on => setInvitedRoles(list => on ? [...list, role.value] : list.filter(item => item !== role.value))} />)}
                {showErrors && rolesProblem && <p className="field-error"><Symbol kind="alert" bare />{rolesProblem}</p>}
              </fieldset>
            </form>
          </DetailPanel>
          : current ? <DetailPanel focusKey={current.id} title={label(current)} meta={rolesText(current.roles)}
            badge={<InvitationState status={current.status} />}
            actions={actionable && active ? <>
              <button type="button" className="button secondary" disabled={!canWrite} onClick={() => { runner.clearOutcome(); setAcknowledged(false); setDialog('resend'); }}>
                <Symbol kind={current.delivery === 'CODE' ? 'refresh' : 'send'} bare />{current.delivery === 'CODE' ? 'Nouveau code' : 'Renvoyer l’invitation'}</button>
              <button type="button" className="button quiet danger" disabled={!canWrite} onClick={() => { runner.clearOutcome(); setShowErrors(false); setDialog('revoke'); }}><Symbol kind="ban" bare />Révoquer…</button>
            </> : undefined}>
            {current.delivery === 'CODE' && issuedCode?.invitationId === current.id && <div className="code-panel">
              <p className="code-display">{issuedCode.code}</p>
              <p className="caption">Valable jusqu’au {expiryOf(issuedCode.expiresAt)}.</p>
              <div className="button-row compact">
                <CopyButton value={issuedCode.code} label="Copier le code" />
                <CopyButton value={invitationCodeMessage(issuedCode.code, expiryOf(issuedCode.expiresAt), school.name)} label="Copier le message" />
              </div>
            </div>}
            {issuedCode?.invitationId !== current.id && <Facts items={[["Expiration", formatDateTime(current.expiresAt, school.timeZone)]]} />}
            {!actionable && (current.status === 'ACCEPTED' ? <button type="button" className="button secondary" onClick={() => navigate(team ? 'equipe' : 'eleves')}>{team ? 'Ouvrir l’équipe' : 'Ouvrir les dossiers élèves'}</button> : <p className="caption">Cette invitation ne peut plus être utilisée.</p>)}
          </DetailPanel>
          : <Placeholder>Choisissez une invitation pour la renvoyer ou la révoquer.</Placeholder>} />}
      </LoadState>
      <ConfirmDialog open={dialog !== null} busy={runner.busy} onCancel={() => setDialog(null)} onConfirm={() => void confirm()}
        title={dialog === 'create' ? (creating === 'code' ? 'Créer le code' : 'Envoyer l’invitation') : dialog === 'resend' ? (current?.delivery === 'CODE' ? 'Nouveau code' : 'Renvoyer l’invitation') : 'Révoquer l’invitation'}
        confirmLabel={dialog === 'create' ? (creating === 'code' ? 'Créer le code' : 'Envoyer l’invitation') : dialog === 'resend' ? (current?.delivery === 'CODE' ? 'Créer un nouveau code' : 'Envoyer un nouveau lien') : 'Révoquer l’invitation'}
        disabledReason={dialog === 'revoke' && !filled(revokeReason, 1000) ? 'Indiquez le motif de la révocation.' : null}
        {...(dialog === 'create' ? { acknowledgement: creating === 'code' ? 'J’ai vérifié l’offre et le moniteur choisis.' : 'J’ai vérifié l’adresse et les rôles proposés.', acknowledged, onAcknowledge: setAcknowledged } : {})}>
        <OutcomeNotice outcome={runner.outcome} />
        {dialog === 'create' && creating === 'code' && <>
          <p className="dialog-lead">Code élève · {offerings.filter(item => offeringIds.includes(item.id)).map(item => offeringLabel(item, offerings)).join(', ')}</p>
          <Facts items={[['Moniteur', chosenInstructor?.displayName ?? '—'], ['École', school.name], ['Validité du code', '7 jours, à usage unique']]} />
        </>}
        {dialog === 'create' && creating === 'email' && <>
          <p className="dialog-lead">{email.trim()}</p>
          <Facts items={[['Rôles', rolesText(roles.map(item => item.value).filter(value => invitedRoles.includes(value)))], ['École', school.name], ['Validité du lien', '7 jours']]} />
          <p className="caption">La personne relira la notice de données de l’école avant d’accepter.</p>
        </>}
        {dialog === 'resend' && current && <>
          <p className="dialog-lead">{label(current)}</p>
          <p>{current.delivery === 'CODE' ? 'Un nouveau code valable 7 jours est créé. Le code précédent ne fonctionnera plus.' : 'Un nouveau lien valable 7 jours est envoyé. Le lien précédent ne fonctionnera plus.'}</p>
        </>}
        {dialog === 'revoke' && current && <>
          <p className="dialog-lead">{label(current)}</p>
          <p>{current.delivery === 'CODE' ? 'Le code' : 'Le lien'} ne permettra plus de rejoindre l’école. Cette action ne supprime aucun dossier existant.</p>
          <TextArea label="Motif de la révocation" rows={3} maxLength={1000} value={revokeReason} onChange={setRevokeReason} disabled={runner.busy} />
        </>}
      </ConfirmDialog>
    </div>
  );
}
