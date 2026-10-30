import { Check, GraduationCap, ShieldCheck, UsersRound } from 'lucide-react';
import { roleLabel, type Role } from '../../protocol';
import { accessDomains, accessRoles } from './access-controller';

export const roleIcons = { ADMIN: ShieldCheck, INSTRUCTOR: UsersRound, LEARNER: GraduationCap };

/** Effective accesses of a member, read only: roles first, then the particular permissions grouped by domain. */
export function AccessSummary({ roles, grants }: { roles: readonly Role[]; grants: readonly string[] }) {
  return <>
    <section className="access-read-section"><h2>Rôles dans l’école</h2><div className="access-role-read">{roles.map(role => {
      const Icon = roleIcons[role];
      return <div key={role}><span className="access-role-icon"><Icon aria-hidden="true" /></span><span><strong>{roleLabel(role)}</strong><span>{accessRoles.find(item => item.value === role)?.description}</span></span></div>;
    })}</div></section>
    <section className="access-read-section"><h2>Autorisations particulières</h2>
      {grants.length ? accessDomains.filter(domain => domain.permissions.some(permission => grants.includes(permission.value))).map(domain =>
        <div className="access-domain-read" key={domain.id}><h3>{domain.label}</h3><ul>{domain.permissions.filter(permission => grants.includes(permission.value)).map(permission => <li key={permission.value}><Check aria-hidden="true" />{permission.label}</li>)}</ul></div>) : <p className="access-muted">Aucune autorisation particulière.</p>}
    </section>
  </>;
}
