import { describe, expect, it, vi } from 'vitest';
import type { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import { readAccountRecoveryConfig } from '../src/account-recovery.js';

describe('disponibilité anonyme de récupération', () => {
  it('reste désactivée sans intégration SMTP activée', () => {
    expect(readAccountRecoveryConfig({})).toEqual({ available: false, recoveryUrl: null });
  });
  it('construit seulement une route du portail contrôlé', () => {
    expect(readAccountRecoveryConfig({ ACCOUNT_RECOVERY_ENABLED:'true', NODE_ENV:'production', PUBLIC_ORIGIN:'https://drivy.example' }))
      .toEqual({ available:true, recoveryUrl:'https://drivy.example/app/recover' });
  });
  it.each(['http://drivy.example','https://user:secret@drivy.example','https://drivy.example/path','https://drivy.example?next=elsewhere','https://drivy.example#fragment'])('refuse une origine inadmissible %s', origin => {
    expect(() => readAccountRecoveryConfig({ ACCOUNT_RECOVERY_ENABLED:'true', NODE_ENV:'production', PUBLIC_ORIGIN:origin })).toThrow();
  });
  it('ne consulte ni compte, ni identité, ni base et refuse un email en query', async () => {
    const connect = vi.fn(), verifyToken = vi.fn();
    const app = buildApp({ pool:{connect} as unknown as Pool, verifyToken, cursorSecret:'synthetic-secret-account-recovery-000' });
    try {
      const response = await app.inject('/v1/account-recovery/options');
      expect(response.statusCode).toBe(200); expect(response.json().data).toEqual({available:false,recoveryUrl:null});
      expect(response.headers['cache-control']).toBe('no-store');
      expect((await app.inject('/v1/account-recovery/options?email=synthetic@example.invalid')).statusCode).toBe(400);
      expect(connect).not.toHaveBeenCalled(); expect(verifyToken).not.toHaveBeenCalled();
    } finally { await app.close(); }
  });
});
