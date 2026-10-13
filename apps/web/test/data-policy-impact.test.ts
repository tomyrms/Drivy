import { describe, expect, it } from 'vitest';
import { matchSchoolRoute } from '../server/school-routes.js';
import { POLICY_TEXT_MINIMUM, policyImpactSchema } from '../client/school-api.js';

const school = '10000000-0000-4000-8000-000000000001';

describe('Impact d’une nouvelle version des textes de confidentialité', () => {
  it('le BFF relaie la lecture de l’impact, et seulement en lecture', () => {
    expect(matchSchoolRoute('GET', `/schools/${school}/data-policy/impact`, '')).toBeDefined();
    expect(matchSchoolRoute('GET', `/schools/${school}/data-policy/impact`, '?noticeVersionId=x')).toBeUndefined();
    expect(matchSchoolRoute('PUT', `/schools/${school}/data-policy/impact`, '')).toBeUndefined();
  });
  it('n’accepte que deux nombres positifs, jamais une liste d’élèves', () => {
    expect(policyImpactSchema.safeParse({ gpsAgreements: 29, activeCaptures: 1 }).success).toBe(true);
    expect(policyImpactSchema.safeParse({ gpsAgreements: -1, activeCaptures: 0 }).success).toBe(false);
    expect(policyImpactSchema.safeParse({ gpsAgreements: [], activeCaptures: 0 }).success).toBe(false);
  });
  it('garde la même longueur minimale que l’API', () => {
    expect(POLICY_TEXT_MINIMUM).toBe(40);
  });
});
