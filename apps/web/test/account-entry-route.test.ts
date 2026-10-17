import { describe, expect, test } from 'vitest';
import { accountEntryDestination } from '../client/account-entry-route.js';

describe('Reprise du parcours après connexion depuis la gestion', () => {
  test('une invitation et une ouverture quittent la gestion pour continuer le code reconnu', () => {
    expect(accountEntryDestination('LEARNER_INVITATION')).toBe('/app/invitation');
    expect(accountEntryDestination('EMAIL_INVITATION')).toBe('/app/invitation');
    expect(accountEntryDestination('SCHOOL_OPENING')).toBe('/app/ouvrir');
  });

  test('une connexion sans code laisse la console relire la page scolaire demandée', () => {
    expect(accountEntryDestination(null)).toBeNull();
  });
});
