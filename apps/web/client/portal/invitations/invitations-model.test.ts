import { describe, expect, it } from 'vitest';
import { audienceInvitations, emailProblem, filterInvitations, isActionable, proposableRoles, rolesProblem, trainingProblem } from './invitations-model';

const invitation = (id: string, roles: ('ADMIN' | 'INSTRUCTOR' | 'LEARNER')[], status: 'PENDING' | 'ACCEPTED' | 'EXPIRED' | 'REVOKED' = 'PENDING') => ({ id, roles, status });

describe('invitation audiences', () => {
  it('separates staff from learners and lists the most recent first', () => {
    const items = [invitation('a', ['LEARNER']), invitation('b', ['INSTRUCTOR']), invitation('c', ['ADMIN', 'INSTRUCTOR']), invitation('d', ['LEARNER'])];
    expect(audienceInvitations(items, true).map(item => item.id)).toEqual(['c', 'b']);
    expect(audienceInvitations(items, false).map(item => item.id)).toEqual(['d', 'a']);
  });
  it('only lets a waiting or expired invitation be renewed or revoked', () => {
    expect(['PENDING', 'EXPIRED', 'ACCEPTED', 'REVOKED'].map(status => isActionable({ status: status as 'PENDING' }))).toEqual([true, true, false, false]);
  });
  it('filters by state and by accent-insensitive search', () => {
    const items = [invitation('a', ['LEARNER'], 'PENDING'), invitation('b', ['LEARNER'], 'REVOKED')];
    const label = (item: { id: string }) => item.id === 'a' ? 'Code élève · Permis B · Marie' : 'Code élève · Permis A1 · Simon';
    expect(filterInvitations(items, label, { status: 'REVOKED', search: '' }).map(item => item.id)).toEqual(['b']);
    expect(filterInvitations(items, label, { status: 'all', search: 'ELEVE marie' }).length).toBe(0);
    expect(filterInvitations(items, label, { status: 'all', search: 'marie' }).map(item => item.id)).toEqual(['a']);
  });
});

describe('invitation forms', () => {
  it('proposes team roles to administrators only', () => {
    expect(proposableRoles(true, true)).toEqual(['ADMIN', 'INSTRUCTOR']);
    expect(proposableRoles(true, false)).toEqual([]);
    expect(proposableRoles(false, false)).toEqual(['LEARNER']);
  });
  it('refuses a role that is not proposable and an empty choice', () => {
    expect(rolesProblem(['INSTRUCTOR'], ['ADMIN', 'INSTRUCTOR'])).toBeNull();
    expect(rolesProblem(['LEARNER'], ['ADMIN', 'INSTRUCTOR'])).not.toBeNull();
    expect(rolesProblem([], ['LEARNER'])).not.toBeNull();
  });
  it('requires a valid address', () => {
    expect(emailProblem(' marie@example.test ')).toBeNull();
    expect(emailProblem('marie')).not.toBeNull();
  });
  it('requires open offers and an active instructor', () => {
    const offers = [{ id: 'o1' }, { id: 'o2' }], instructors = [{ id: 'm1' }];
    expect(trainingProblem(['o1'], 'm1', offers, instructors)).toBeNull();
    expect(trainingProblem([], 'm1', offers, instructors)).not.toBeNull();
    expect(trainingProblem(['o1'], '', offers, instructors)).not.toBeNull();
    expect(trainingProblem(['unknown'], 'm1', offers, instructors)).not.toBeNull();
  });
});
