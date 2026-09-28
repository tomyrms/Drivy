import { useEffect, useMemo, useState } from 'react';
import { commandMessage, createCommand, filled, isEmail } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { roleLabel, type Role } from '../protocol';
import {
  activeInstructors, defaultInstructorId, invitationCodeMessage, invitationLabel, invitationSchema, issuedCodeOf, openOfferings, parseInvitationResponse,
  type Invitation,
} from '../invitation-model';
import { memberSchema, offeringSchema, readAll } from '../school-api';
import { CheckField, ConfirmDialog, EmptyState, Facts, Notice, SelectField, StatusBadge, Symbol, TextArea, TextField, formatDateTime, type Tone } from '../ui';
import { useCommandRunner, useConsole, useLoad } from './context';
import { DetailPanel, LoadState, OutcomeNotice, Placeholder, RowButton, SectionHeading, SplitView } from './layout';

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
const memberStatus = (status: string): { label: string; tone: Tone } => status === 'ACTIVE' ? { label: 'Actif', tone: 'success' } : { label: 'Accès inactif', tone: 'neutral' };

/* ---------------------------------------------------------------- Équipe et accès */

export function TeamSection() {
  const { schoolId, membership, navigate, login } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner();
  const loaded = useLoad(() => readAll(schoolId, 'members', memberSchema), [schoolId, revision]);
  const [filter, setFilter] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const [draftRoles, setDraftRoles] = useState<Role[]>([]);
  const [draftGrants, setDraftGrants] = useState<string[]>([]);
  const [reason, setReason] = useState('');
  const [showErrors, setShowErrors] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const members = useMemo(() => [...(loaded.data?.items ?? [])].sort((a, b) => a.displayName.localeCompare(b.displayName, 'fr')), [loaded.data]);
  const visible = members.filter(item => item.displayName.toLocaleLowerCase('fr').includes(filter.trim().toLocaleLowerCase('fr')));
  const current = members.find(item => item.id === selected) ?? null;
  useEffect(() => {
    if (!current) return;
    setDraftRoles([...current.roles]); setDraftGrants([...current.grants]); setReason(''); setShowErrors(false);
  }, [current?.id, current?.version]);
  const self = current?.id === membership.membershipId;
  const changed = !!current && (!sameSet(current.roles, draftRoles) || !sameSet(current.grants, draftGrants));
  const loseAdmin = self && current?.roles.includes('ADMIN') && !draftRoles.includes('ADMIN');
  const problem = !changed ? null : draftRoles.length === 0 ? 'Gardez au moins un rôle.' : !filled(reason, 1000) ? 'Indiquez le motif du changement (1 000 caractères au plus).' : null;
  const canWrite = !runner.pending && !runner.busy;

  async function confirm() {
    if (!current || problem || !changed) return;
    const command = createCommand({ schoolId, kind: 'updateMember', path: `members/${current.id}`, ifMatch: current.version, resourceId: current.id,
      resourceVersion: current.version, body: { roles: roles.map(item => item.value).filter(value => draftRoles.includes(value)), grants: grants.map(item => item.value).filter(value => draftGrants.includes(value)), reason: reason.trim() } });
    await runner.run(command, `Les accès de ${current.displayName} sont modifiés.`);
    setReviewing(false);
  }
  const toggle = <T extends string,>(list: T[], value: T, on: boolean) => on ? [...list, value] : list.filter(item => item !== value);

  return (
    <div className="section-stack">
      <SectionHeading context="Personnes" title="Équipe et accès"
        actions={<button type="button" className="button secondary" onClick={() => navigate('invitations')}><Symbol kind="mail" bare />Inviter une personne</button>} />
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome}
        actions={runner.outcome?.code === 'REAUTH_REQUIRED' ? <button type="button" className="button secondary" onClick={login}>Se reconnecter</button> : undefined} />
      {runner.outcome?.code === 'REAUTH_REQUIRED' && <p className="caption">Après la reconnexion, rouvrez ce membre et saisissez à nouveau le changement : la saisie n’est pas conservée.</p>}
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture de l’équipe…">{data => <SplitView
        list={<>
          <div className="list-toolbar"><TextField label="Rechercher un membre" value={filter} onChange={setFilter} placeholder="Nom" /></div>
          {visible.length === 0 ? <EmptyState symbol="users" title={members.length ? 'Aucun membre trouvé' : 'Aucun membre'} message={members.length ? 'Modifiez la recherche.' : 'Invitez les personnes de votre école.'} />
          : <table className="data-table">
            <caption className="visually-hidden">Membres de l’école{data.truncated ? ' (liste partielle)' : ''}</caption>
            <thead><tr><th scope="col">Nom</th><th scope="col">Rôles</th><th scope="col" className="numeric">Autorisations</th><th scope="col">Accès</th></tr></thead>
            <tbody>{visible.map(item => <tr key={item.id} className={item.id === selected ? 'selected' : undefined}>
              <th scope="row"><RowButton selected={item.id === selected} onSelect={() => setSelected(item.id)}>{item.displayName}</RowButton>
                {item.id === membership.membershipId && <span className="caption"> · vous</span>}</th>
              <td>{rolesText(item.roles)}</td><td className="numeric">{item.grants.length}</td>
              <td><StatusBadge tone={memberStatus(item.status).tone} symbol={item.status === 'ACTIVE' ? 'check' : 'dot'}>{memberStatus(item.status).label}</StatusBadge></td>
            </tr>)}</tbody>
          </table>}
        </>}
        detail={current ? <DetailPanel focusKey={current.id} title={current.displayName} meta={self ? 'Votre propre accès' : rolesText(current.roles)}
            badge={<StatusBadge tone={memberStatus(current.status).tone} symbol={current.status === 'ACTIVE' ? 'check' : 'dot'}>{memberStatus(current.status).label}</StatusBadge>}
            actions={<>
              <button type="button" className="button primary" disabled={!canWrite || !changed} onClick={() => { setShowErrors(true); if (!problem) { setAcknowledged(false); setReviewing(true); } }}>Relire le changement</button>
              {changed && <button type="button" className="button quiet" onClick={() => { setDraftRoles([...current.roles]); setDraftGrants([...current.grants]); setReason(''); }}>Annuler les modifications</button>}
            </>}>
            <form className="form-grid" onSubmit={event => event.preventDefault()}>
              <fieldset className="fieldset">
                <legend>Rôles dans cette école</legend>
                {roles.map(role => <CheckField key={role.value} label={roleLabel(role.value)} description={role.explanation} checked={draftRoles.includes(role.value)}
                  disabled={!canWrite} onChange={on => setDraftRoles(list => toggle(list, role.value, on))} />)}
              </fieldset>
              <fieldset className="fieldset">
                <legend>Autorisations particulières</legend>
                <div className="check-grid">{grants.map(grant => <CheckField key={grant.value} label={grant.label} checked={draftGrants.includes(grant.value)}
                  disabled={!canWrite} onChange={on => setDraftGrants(list => toggle(list, grant.value, on))} />)}</div>
              </fieldset>
              {changed && <TextArea label="Motif du changement" rows={3} maxLength={1000} value={reason} onChange={setReason} disabled={!canWrite}
                hint="Conservé dans l’historique de l’école." error={showErrors && problem && draftRoles.length ? problem : null} />}
              {changed && draftRoles.length === 0 && <p className="field-error"><Symbol kind="alert" bare />Gardez au moins un rôle.</p>}
              {loseAdmin && <Notice tone="warning" title="Vous retirez votre propre rôle Administration" live={false}><p>Vous ne pourrez plus administrer cette école après la confirmation.</p></Notice>}
            </form>
          </DetailPanel>
          : <Placeholder>Choisissez un membre pour consulter ou modifier ses accès.</Placeholder>} />}
      </LoadState>
      {current && <ConfirmDialog open={reviewing} busy={runner.busy} onCancel={() => setReviewing(false)} onConfirm={() => void confirm()}
        title="Modifier les accès" confirmLabel="Confirmer le changement d’accès"
        {...(loseAdmin ? { acknowledgement: 'Je comprends que je ne pourrai plus administrer cette école.', acknowledged, onAcknowledge: setAcknowledged } : {})}>
        <p className="dialog-lead">{current.displayName}</p>
        <Facts items={[
          ['Rôles actuels', rolesText(current.roles)], ['Rôles demandés', rolesText(roles.map(item => item.value).filter(value => draftRoles.includes(value)))],
          ['Autorisations ajoutées', draftGrants.filter(item => !current.grants.includes(item)).map(grantLabel).join(', ') || 'Aucune'],
          ['Autorisations retirées', current.grants.filter(item => !draftGrants.includes(item)).map(grantLabel).join(', ') || 'Aucune'],
          ['Motif', reason.trim()],
        ]} />
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
  async function copy() {
    setState(await copyText(value) ? 'copied' : 'failed');
    window.setTimeout(() => setState('idle'), 2500);
  }
  return <button type="button" className="button secondary" onClick={() => void copy()}>
    {state !== 'idle' && <Symbol kind={state === 'copied' ? 'check' : 'alert'} bare />}
    {state === 'copied' ? 'Copié' : state === 'failed' ? 'Copie impossible' : label}
  </button>;
}

export function InvitationsSection() {
  const { schoolId, school, membership, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => { setCreating(null); setEmail(''); setInvitedRoles(['LEARNER']); setRevokeReason(''); });
  const loaded = useLoad(async () => {
    const [invitations, offerings, members] = await Promise.all([
      readAll(schoolId, 'invitations', invitationSchema), readAll(schoolId, 'offerings', offeringSchema), readAll(schoolId, 'members', memberSchema)]);
    return { invitations: invitations.items, offerings: offerings.items, members: members.items };
  }, [schoolId, revision]);
  const [selected, setSelected] = useState<string | null>(null);
  const [creating, setCreating] = useState<CreateMode | null>(null);
  const [email, setEmail] = useState('');
  const [invitedRoles, setInvitedRoles] = useState<Role[]>(['LEARNER']);
  const [offeringId, setOfferingId] = useState('');
  const [instructorId, setInstructorId] = useState('');
  const [revokeReason, setRevokeReason] = useState('');
  const [showErrors, setShowErrors] = useState(false);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [acknowledged, setAcknowledged] = useState(false);
  const [issuedCode, setIssuedCode] = useState<IssuedCode | null>(null);
  /** The school confirmed a code but its response carried none that could be verified. */
  const [codeMissing, setCodeMissing] = useState(false);
  const data = loaded.data;
  const items = useMemo(() => [...(data?.invitations ?? [])].reverse(), [data]);
  const offerings = useMemo(() => openOfferings(data?.offerings ?? []), [data]);
  const instructors = useMemo(() => activeInstructors(data?.members ?? []), [data]);
  const current = items.find(item => item.id === selected) ?? null;
  const active = school.status === 'ACTIVE';
  const canWrite = active && !runner.pending && !runner.busy;
  const emailProblem = isEmail(email.trim()) ? null : 'Indiquez l’adresse e-mail de la personne invitée.';
  const rolesProblem = invitedRoles.length ? null : 'Choisissez au moins un rôle.';
  const trainingProblem = offeringId && instructorId ? null : commandMessage('INVITATION_TRAINING_INVALID');
  const actionable = current && (current.status === 'PENDING' || current.status === 'EXPIRED');
  const chosenOffering = offerings.find(item => item.id === offeringId);
  const chosenInstructor = instructors.find(item => item.id === instructorId);

  const label = (item: Invitation) => invitationLabel(item, data?.offerings ?? [], data?.members ?? []);
  const expiryOf = (value: string) => formatDateTime(value, school.timeZone);
  function openCode() {
    runner.clearOutcome(); setSelected(null); setShowErrors(false); setCodeMissing(false);
    setOfferingId(offerings.length === 1 ? offerings[0]!.id : '');
    setInstructorId(defaultInstructorId(membership.membershipId, instructors));
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

  async function confirm() {
    if (dialog === 'create' && creating === 'code' && !trainingProblem) {
      const command = createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
        body: { delivery: 'CODE', roles: ['LEARNER'], training: { offeringId, instructorMembershipId: instructorId } } });
      const result = await runner.run(command, 'Le code est créé ; il est valable 7 jours.');
      if (result.status === 'confirmed') {
        const created = result.via === 'response' ? showIssued(result.body) : null;
        if (created) setSelected(created);
        else setCodeMissing(true);
        setCreating(null);
      }
    } else if (dialog === 'create' && creating === 'email' && !emailProblem && !rolesProblem) {
      const command = createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
        body: { email: email.trim(), roles: [...invitedRoles].sort() } });
      const result = await runner.run(command, 'L’invitation est créée. Le message part vers l’adresse indiquée ; le lien est valable 7 jours.');
      if (result.status === 'confirmed') { setCreating(null); setEmail(''); setInvitedRoles(['LEARNER']); }
    } else if (dialog === 'resend' && current && actionable) {
      const code = current.delivery === 'CODE';
      const result = await runner.run(createCommand({ schoolId, kind: 'resendInvitation', path: `invitations/${current.id}/resend`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: {} }),
        code ? 'Un nouveau code est créé ; l’ancien n’est plus utilisable.' : 'Un nouveau lien est envoyé ; l’ancien n’est plus utilisable.');
      if (result.status === 'confirmed' && code) {
        if (result.via === 'response') showIssued(result.body, current.id); else { setIssuedCode(null); setCodeMissing(true); }
      }
    } else if (dialog === 'revoke' && current && actionable && filled(revokeReason, 1000)) {
      const result = await runner.run(createCommand({ schoolId, kind: 'revokeInvitation', path: `invitations/${current.id}/revoke`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: { reason: revokeReason.trim() } }), 'L’invitation est révoquée : elle ne permet plus de rejoindre l’école.');
      if (result.status === 'confirmed') { setRevokeReason(''); setIssuedCode(null); setCodeMissing(false); }
    }
    setDialog(null);
  }

  return (
    <div className="section-stack">
      <SectionHeading context="Personnes" title="Invitations"
        actions={active ? <>
          <button type="button" className={creating === 'code' ? 'button secondary' : 'button primary'} disabled={!canWrite} onClick={openCode}><Symbol kind="plus" bare />Code élève</button>
          <button type="button" className="button quiet" disabled={!canWrite} onClick={openEmail}><Symbol kind="mail" bare />Inviter par e-mail</button>
        </> : undefined} />
      {!active && <Notice tone="info" title="Invitations disponibles après l’activation" live={false}
        actions={<button type="button" className="button secondary" onClick={() => navigate('configuration')}>Ouvrir la configuration</button>}>
        <p>L’école doit être active, avec ses textes d’information adoptés, avant d’inviter des personnes.</p></Notice>}
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      {codeMissing && <Notice tone="warning" title="Code non affiché"><p>La réponse de l’école ne permet pas d’afficher le code. « Nouveau code » en crée un autre.</p></Notice>}
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des invitations…">{() => <SplitView
        list={items.length === 0 ? <EmptyState symbol="mail" title="Aucune invitation" message="Invitez les moniteurs et les élèves de votre école." />
          : <table className="data-table">
            <caption className="visually-hidden">Invitations de l’école, les plus récentes d’abord</caption>
            <thead><tr><th scope="col">Invitation</th><th scope="col">Rôles</th><th scope="col">Statut</th><th scope="col">Expire le</th></tr></thead>
            <tbody>{items.map(item => <tr key={item.id} className={item.id === selected && !creating ? 'selected' : undefined}>
              <th scope="row"><RowButton selected={item.id === selected && !creating} onSelect={() => { setCreating(null); setCodeMissing(false); setSelected(item.id); }}>{label(item)}</RowButton></th>
              <td>{rolesText(item.roles)}</td>
              <td><StatusBadge tone={invitationStatus(item.status).tone} symbol={item.status === 'ACCEPTED' ? 'check' : item.status === 'PENDING' ? (item.delivery === 'CODE' ? 'lock' : 'mail') : item.status === 'EXPIRED' ? 'clock' : 'ban'}>{invitationStatus(item.status).label}</StatusBadge></td>
              <td>{formatDateTime(item.expiresAt, school.timeZone)}</td>
            </tr>)}</tbody>
          </table>}
        detail={creating === 'code' ? <DetailPanel focusKey="create-code" title="Code élève"
            actions={<>
              <button type="button" className="button primary" disabled={!canWrite} onClick={() => { setShowErrors(true); if (!trainingProblem) { setAcknowledged(false); setDialog('create'); } }}>Relire avant de créer</button>
              <button type="button" className="button quiet" onClick={() => setCreating(null)} disabled={runner.busy}>Annuler</button>
            </>}>
            <form className="form-grid" onSubmit={event => { event.preventDefault(); setShowErrors(true); if (!trainingProblem && canWrite) { setAcknowledged(false); setDialog('create'); } }}>
              <SelectField label="Offre" value={offeringId} placeholder="Choisir une offre" disabled={!canWrite} onChange={setOfferingId}
                options={offerings.map(item => ({ value: item.id, label: `Permis ${item.categoryCode}` }))} />
              <SelectField label="Moniteur" value={instructorId} placeholder="Choisir un moniteur" disabled={!canWrite} onChange={setInstructorId}
                options={instructors.map(item => ({ value: item.id, label: item.displayName }))} />
              {showErrors && trainingProblem && <p className="field-error"><Symbol kind="alert" bare />{trainingProblem}</p>}
              {offerings.length === 0 && <Notice tone="info" title="Aucune offre ouverte" live={false}
                actions={<button type="button" className="button quiet" onClick={() => navigate('offres')}>Ouvrir les offres</button>}>
                <p>Activez une offre pour créer un code élève.</p></Notice>}
              {offerings.length > 0 && instructors.length === 0 && <Notice tone="info" title="Aucun moniteur actif" live={false}
                actions={<button type="button" className="button quiet" onClick={() => navigate('equipe')}>Ouvrir l’équipe</button>}>
                <p>Ajoutez un moniteur actif pour créer un code élève.</p></Notice>}
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
            badge={<StatusBadge tone={invitationStatus(current.status).tone} symbol={current.delivery === 'CODE' ? 'lock' : 'mail'}>{invitationStatus(current.status).label}</StatusBadge>}
            actions={actionable && active ? <>
              <button type="button" className="button secondary" disabled={!canWrite} onClick={() => { runner.clearOutcome(); setAcknowledged(false); setDialog('resend'); }}>
                <Symbol kind={current.delivery === 'CODE' ? 'refresh' : 'send'} bare />{current.delivery === 'CODE' ? 'Nouveau code' : 'Renvoyer l’invitation'}</button>
              <button type="button" className="button quiet danger" disabled={!canWrite} onClick={() => { runner.clearOutcome(); setShowErrors(false); setDialog('revoke'); }}><Symbol kind="ban" bare />Révoquer…</button>
            </> : undefined}>
            {current.delivery === 'CODE' && issuedCode?.invitationId === current.id && <div className="code-panel">
              <p className="code-display">{issuedCode.code}</p>
              <p className="caption">Valable jusqu’au {expiryOf(issuedCode.expiresAt)}.</p>
              <p className="policy-copy">{invitationCodeMessage(issuedCode.code, expiryOf(issuedCode.expiresAt), school.name)}</p>
              <div className="button-row compact">
                <CopyButton value={issuedCode.code} label="Copier le code" />
                <CopyButton value={invitationCodeMessage(issuedCode.code, expiryOf(issuedCode.expiresAt), school.name)} label="Copier le message" />
              </div>
            </div>}
            <Facts items={[['Expiration', formatDateTime(current.expiresAt, school.timeZone)], ['Rôles', rolesText(current.roles)], ['Version', String(current.version)]]} />
            {!actionable && <p className="caption">{current.status === 'ACCEPTED' ? 'La personne a rejoint l’école : gérez ses accès dans Équipe et accès.' : 'Cette invitation ne peut plus être utilisée. Créez-en une nouvelle si nécessaire.'}</p>}
          </DetailPanel>
          : <Placeholder>Choisissez une invitation pour la renvoyer ou la révoquer.</Placeholder>} />}
      </LoadState>
      <ConfirmDialog open={dialog !== null} busy={runner.busy} onCancel={() => setDialog(null)} onConfirm={() => void confirm()}
        title={dialog === 'create' ? (creating === 'code' ? 'Créer le code' : 'Envoyer l’invitation') : dialog === 'resend' ? (current?.delivery === 'CODE' ? 'Nouveau code' : 'Renvoyer l’invitation') : 'Révoquer l’invitation'}
        confirmLabel={dialog === 'create' ? (creating === 'code' ? 'Créer le code' : 'Envoyer l’invitation') : dialog === 'resend' ? (current?.delivery === 'CODE' ? 'Créer un nouveau code' : 'Envoyer un nouveau lien') : 'Révoquer l’invitation'}
        disabledReason={dialog === 'revoke' && !filled(revokeReason, 1000) ? 'Indiquez le motif de la révocation.' : null}
        {...(dialog === 'create' ? { acknowledgement: creating === 'code' ? 'J’ai vérifié l’offre et le moniteur choisis.' : 'J’ai vérifié l’adresse et les rôles proposés.', acknowledged, onAcknowledge: setAcknowledged } : {})}>
        {dialog === 'create' && creating === 'code' && <>
          <p className="dialog-lead">Code élève{chosenOffering ? ` · Permis ${chosenOffering.categoryCode}` : ''}</p>
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
