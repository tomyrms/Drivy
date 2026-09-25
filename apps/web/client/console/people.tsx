import { useEffect, useMemo, useState } from 'react';
import { createCommand, filled, isEmail } from '../command-core';
import { useCommandSnapshot } from '../command-store';
import { roleLabel, type Role } from '../protocol';
import { invitationSchema, memberSchema, readAll, type Invitation } from '../school-api';
import { CheckField, ConfirmDialog, EmptyState, Facts, Notice, StatusBadge, Symbol, TextArea, TextField, formatDateTime, type Tone } from '../ui';
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
      <SectionHeading context="Personnes" title="Équipe et accès" description="Rôles et autorisations des membres de l’école. Chaque changement est motivé, relu et confirmé par l’école."
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
                <p className="caption">Le rôle Moniteur ne donne accès qu’aux formations explicitement affectées. Ajouter Élève ouvre un dossier minimal, sans créer de formation.</p>
              </fieldset>
              <fieldset className="fieldset">
                <legend>Autorisations particulières</legend>
                <div className="check-grid">{grants.map(grant => <CheckField key={grant.value} label={grant.label} checked={draftGrants.includes(grant.value)}
                  disabled={!canWrite} onChange={on => setDraftGrants(list => toggle(list, grant.value, on))} />)}</div>
                <p className="caption">Ces autorisations complètent les rôles. Elles ne créent ni affectation ni accès à une autre école.</p>
              </fieldset>
              {changed && <TextArea label="Motif du changement" rows={3} maxLength={1000} value={reason} onChange={setReason} disabled={!canWrite}
                hint="Conservé dans l’historique de l’école." error={showErrors && problem && draftRoles.length ? problem : null} />}
              {changed && draftRoles.length === 0 && <p className="field-error"><Symbol kind="alert" bare />Gardez au moins un rôle.</p>}
              {loseAdmin && <Notice tone="warning" title="Vous retirez votre propre rôle Administration" live={false}><p>Vous ne pourrez plus administrer cette école après la confirmation.</p></Notice>}
              <p className="caption">Un changement d’accès peut demander de vous reconnecter pour le confirmer.</p>
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

export function InvitationsSection() {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const runner = useCommandRunner(() => { setCreating(false); setEmail(''); setInvitedRoles(['LEARNER']); setRevokeReason(''); });
  const loaded = useLoad(() => readAll(schoolId, 'invitations', invitationSchema), [schoolId, revision]);
  const [selected, setSelected] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [email, setEmail] = useState('');
  const [invitedRoles, setInvitedRoles] = useState<Role[]>(['LEARNER']);
  const [revokeReason, setRevokeReason] = useState('');
  const [showErrors, setShowErrors] = useState(false);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [acknowledged, setAcknowledged] = useState(false);
  const items = useMemo(() => [...(loaded.data?.items ?? [])].reverse(), [loaded.data]);
  const current = items.find(item => item.id === selected) ?? null;
  const active = school.status === 'ACTIVE';
  const canWrite = active && !runner.pending && !runner.busy;
  const emailProblem = isEmail(email.trim()) ? null : 'Indiquez l’adresse e-mail de la personne invitée.';
  const rolesProblem = invitedRoles.length ? null : 'Choisissez au moins un rôle.';
  const actionable = current && (current.status === 'PENDING' || current.status === 'EXPIRED');

  async function confirm() {
    if (dialog === 'create' && !emailProblem && !rolesProblem) {
      const command = createCommand({ schoolId, kind: 'createInvitation', path: 'invitations', resourceVersion: 0,
        body: { email: email.trim(), roles: [...invitedRoles].sort() } });
      const result = await runner.run(command, 'L’invitation est créée. Le message part vers l’adresse indiquée ; le lien est valable 7 jours.');
      if (result.status === 'confirmed') { setCreating(false); setEmail(''); setInvitedRoles(['LEARNER']); }
    } else if (dialog === 'resend' && current && actionable) {
      await runner.run(createCommand({ schoolId, kind: 'resendInvitation', path: `invitations/${current.id}/resend`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: {} }), 'Un nouveau lien est envoyé ; l’ancien n’est plus utilisable.');
    } else if (dialog === 'revoke' && current && actionable && filled(revokeReason, 1000)) {
      const result = await runner.run(createCommand({ schoolId, kind: 'revokeInvitation', path: `invitations/${current.id}/revoke`, ifMatch: current.version,
        resourceId: current.id, resourceVersion: current.version, body: { reason: revokeReason.trim() } }), 'L’invitation est révoquée : son lien ne permet plus de rejoindre l’école.');
      if (result.status === 'confirmed') setRevokeReason('');
    }
    setDialog(null);
  }

  return (
    <div className="section-stack">
      <SectionHeading context="Personnes" title="Invitations" description="La personne invitée accepte avec son propre compte. Son dossier est ensuite créé, sans formation automatique."
        actions={active ? <button type="button" className={current || creating ? 'button secondary' : 'button primary'} disabled={!canWrite} onClick={() => { runner.clearOutcome(); setSelected(null); setShowErrors(false); setCreating(true); }}>
          <Symbol kind="plus" bare />Inviter une personne</button> : undefined} />
      {!active && <Notice tone="info" title="Invitations disponibles après l’activation" live={false}
        actions={<button type="button" className="button secondary" onClick={() => navigate('configuration')}>Ouvrir la configuration</button>}>
        <p>L’école doit être active, avec ses textes d’information adoptés, avant d’inviter des personnes.</p></Notice>}
      <OutcomeNotice outcome={runner.outcome} onDismiss={runner.clearOutcome} />
      {runner.blockedReason && <p className="caption with-symbol"><Symbol kind="lock" bare />{runner.blockedReason}</p>}
      <LoadState loaded={loaded} label="Lecture des invitations…">{() => <SplitView
        list={items.length === 0 ? <EmptyState symbol="mail" title="Aucune invitation" message="Invitez les moniteurs et les élèves de votre école." />
          : <table className="data-table">
            <caption className="visually-hidden">Invitations de l’école, les plus récentes d’abord</caption>
            <thead><tr><th scope="col">Adresse</th><th scope="col">Rôles</th><th scope="col">Statut</th><th scope="col">Expire le</th></tr></thead>
            <tbody>{items.map(item => <tr key={item.id} className={item.id === selected && !creating ? 'selected' : undefined}>
              <th scope="row"><RowButton selected={item.id === selected && !creating} onSelect={() => { setCreating(false); setSelected(item.id); }}>{item.maskedEmail}</RowButton></th>
              <td>{rolesText(item.roles)}</td>
              <td><StatusBadge tone={invitationStatus(item.status).tone} symbol={item.status === 'ACCEPTED' ? 'check' : item.status === 'PENDING' ? 'mail' : item.status === 'EXPIRED' ? 'clock' : 'ban'}>{invitationStatus(item.status).label}</StatusBadge></td>
              <td>{formatDateTime(item.expiresAt, school.timeZone)}</td>
            </tr>)}</tbody>
          </table>}
        detail={creating ? <DetailPanel focusKey="create" title="Inviter une personne" meta="Un e-mail avec un lien personnel, valable 7 jours, est envoyé à cette adresse."
            actions={<>
              <button type="button" className="button primary" disabled={!canWrite} onClick={() => { setShowErrors(true); if (!emailProblem && !rolesProblem) { setAcknowledged(false); setDialog('create'); } }}>Relire l’invitation</button>
              <button type="button" className="button quiet" onClick={() => setCreating(false)} disabled={runner.busy}>Annuler</button>
            </>}>
            <form className="form-grid" onSubmit={event => { event.preventDefault(); setShowErrors(true); if (!emailProblem && !rolesProblem && canWrite) { setAcknowledged(false); setDialog('create'); } }}>
              <TextField label="Adresse e-mail" type="email" value={email} onChange={setEmail} disabled={!canWrite} maxLength={254} error={showErrors ? emailProblem : null} />
              <fieldset className="fieldset">
                <legend>Rôles proposés</legend>
                {roles.map(role => <CheckField key={role.value} label={roleLabel(role.value)} description={role.explanation} checked={invitedRoles.includes(role.value)}
                  disabled={!canWrite} onChange={on => setInvitedRoles(list => on ? [...list, role.value] : list.filter(item => item !== role.value))} />)}
                {showErrors && rolesProblem && <p className="field-error"><Symbol kind="alert" bare />{rolesProblem}</p>}
              </fieldset>
              <p className="caption">L’invitation ne réserve aucune leçon et n’autorise aucun enregistrement GPS.</p>
            </form>
          </DetailPanel>
          : current ? <DetailPanel focusKey={current.id} title={current.maskedEmail} meta={rolesText(current.roles)}
            badge={<StatusBadge tone={invitationStatus(current.status).tone} symbol="mail">{invitationStatus(current.status).label}</StatusBadge>}
            actions={actionable && active ? <>
              <button type="button" className="button secondary" disabled={!canWrite} onClick={() => { runner.clearOutcome(); setAcknowledged(false); setDialog('resend'); }}><Symbol kind="send" bare />Renvoyer l’invitation</button>
              <button type="button" className="button quiet danger" disabled={!canWrite} onClick={() => { runner.clearOutcome(); setShowErrors(false); setDialog('revoke'); }}><Symbol kind="ban" bare />Révoquer…</button>
            </> : undefined}>
            <Facts items={[['Expiration', formatDateTime(current.expiresAt, school.timeZone)], ['Rôles', rolesText(current.roles)], ['Version', String(current.version)]]} />
            {!actionable && <p className="caption">{current.status === 'ACCEPTED' ? 'La personne a rejoint l’école : gérez ses accès dans Équipe et accès.' : 'Cette invitation ne peut plus être utilisée. Créez-en une nouvelle si nécessaire.'}</p>}
          </DetailPanel>
          : <Placeholder>Choisissez une invitation pour la renvoyer ou la révoquer.</Placeholder>} />}
      </LoadState>
      <ConfirmDialog open={dialog !== null} busy={runner.busy} onCancel={() => setDialog(null)} onConfirm={() => void confirm()}
        title={dialog === 'create' ? 'Envoyer l’invitation' : dialog === 'resend' ? 'Renvoyer l’invitation' : 'Révoquer l’invitation'}
        confirmLabel={dialog === 'create' ? 'Envoyer l’invitation' : dialog === 'resend' ? 'Envoyer un nouveau lien' : 'Révoquer l’invitation'}
        disabledReason={dialog === 'revoke' && !filled(revokeReason, 1000) ? 'Indiquez le motif de la révocation.' : null}
        {...(dialog === 'create' ? { acknowledgement: 'J’ai vérifié l’adresse et les rôles proposés.', acknowledged, onAcknowledge: setAcknowledged } : {})}>
        {dialog === 'create' && <>
          <p className="dialog-lead">{email.trim()}</p>
          <Facts items={[['Rôles', rolesText(roles.map(item => item.value).filter(value => invitedRoles.includes(value)))], ['École', school.name], ['Validité du lien', '7 jours']]} />
          <p className="caption">La personne relira la notice de données de l’école avant d’accepter.</p>
        </>}
        {dialog === 'resend' && current && <>
          <p className="dialog-lead">{current.maskedEmail}</p>
          <p>Un nouveau lien valable 7 jours est envoyé. Le lien précédent ne fonctionnera plus.</p>
        </>}
        {dialog === 'revoke' && current && <>
          <p className="dialog-lead">{current.maskedEmail}</p>
          <p>Le lien ne permettra plus de rejoindre l’école. Cette action ne supprime aucun dossier existant.</p>
          <TextArea label="Motif de la révocation" rows={3} maxLength={1000} value={revokeReason} onChange={setRevokeReason} disabled={runner.busy} />
        </>}
      </ConfirmDialog>
    </div>
  );
}
