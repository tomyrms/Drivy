import { describe, expect, test } from 'vitest';
import { missingCount, profileBody } from '../client/console/profile-completion-model.js';
import { matchSchoolRoute } from '../server/school-routes.js';
import { commandSpecs } from '../client/command-core.js';

const school = '10000000-0000-4000-8000-000000000001';
const learner = '40000000-0000-4000-8000-000000000001';

describe('Profil à compléter sur le web', () => {
  test('le décompte se lit comme dans l’app', () => {
    expect(missingCount(1)).toBe('1 information manquante');
    expect(missingCount(3)).toBe('3 informations manquantes');
  });
  test('seuls les champs manquants renseignés partent, une adresse seulement complète', () => {
    const fields = ['contactPhone', 'postalAddress', 'birthDate'] as const;
    expect(profileBody(fields, {})).toBeNull();
    expect(profileBody(fields, { contactPhone: '  ' })).toBeNull();
    expect(profileBody(fields, { contactPhone: ' +41 21 000 00 00 ', postalAddress: { line1: 'Rue du Lac 1', postalCode: '1000', locality: '', countryCode: 'CH' } }))
      .toEqual({ contactPhone: '+41 21 000 00 00' });
    expect(profileBody(fields, { birthDate: '2008-05-01', postalAddress: { line1: 'Rue du Lac 1', postalCode: '1000', locality: 'Lausanne', countryCode: 'CH' } }))
      .toEqual({ birthDate: '2008-05-01', postalAddress: { line1: 'Rue du Lac 1', line2: null, postalCode: '1000', locality: 'Lausanne', countryCode: 'CH' } });
    // Un champ qui ne manque pas n’est jamais envoyé, même saisi.
    expect(profileBody(['contactPhone'], { contactPhone: '021', contactEmail: 'a@example.test' })).toEqual({ contactPhone: '021' });
  });
  test('le relais ouvre la readiness, la lecture et la saisie du profil, rien de plus', () => {
    expect(matchSchoolRoute('GET', `/schools/${school}/learners/${learner}/action-readiness`, '?action=PLAN_LESSON')?.query).toBe('?action=PLAN_LESSON');
    expect(matchSchoolRoute('GET', `/schools/${school}/learners/${learner}/action-readiness`, '?action=ENROLL_COURSE')).toBeUndefined();
    expect(matchSchoolRoute('GET', `/schools/${school}/learners/${learner}/administrative-profile`, '')).toBeDefined();
    expect(matchSchoolRoute('PATCH', `/schools/${school}/learners/${learner}/administrative-profile`, '')?.route.ifMatch).toBe(true);
    expect(matchSchoolRoute('PUT', `/schools/${school}/learners/${learner}/administrative-profile`, '')).toBeUndefined();
    expect(commandSpecs.updateAdministrativeProfile).toMatchObject({ operationType: 'UPDATE_ADMINISTRATIVE_PROFILE', resourceType: 'AdministrativeProfile', method: 'PATCH' });
  });
});
