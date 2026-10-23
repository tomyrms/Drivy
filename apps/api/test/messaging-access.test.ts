import { afterEach, describe, expect, it, vi } from 'vitest';
import { messagingSchoolGate } from '../src/messaging-access.js';
const school = '10000000-0000-4000-8000-000000000001';
afterEach(() => vi.unstubAllEnvs());
describe('gate partagé messagerie et clés', () => {
  it('reste fermé par défaut et avec configuration qualification invalide', () => {
    for (const options of [{}, { qualification: { mode: 'disabled' as const, schoolIds: [school] } },
      { qualification: { mode: 'qualification' as const, schoolIds: [] } },
      { qualification: { mode: 'qualification' as const, schoolIds: [school, '*'] } }])
      expect(messagingSchoolGate(options)(school)).toBe(false);
  });
  it('refuse test-synthetic dans tout processus autre que test', () => {
    for (const environment of ['production', 'development']) {
      vi.stubEnv('NODE_ENV', environment);
      expect(messagingSchoolGate({ mode: 'test-synthetic' })(school)).toBe(false);
    }
  });
  it('copie la liste pour ne pas élargir activation après construction', () => {
    const schoolIds = [school];
    const gate = messagingSchoolGate({ qualification: { mode: 'qualification', schoolIds } });
    schoolIds.push('10000000-0000-4000-8000-000000000002');
    expect(gate(school)).toBe(true);
    expect(gate(schoolIds[1]!)).toBe(false);
  });
});
