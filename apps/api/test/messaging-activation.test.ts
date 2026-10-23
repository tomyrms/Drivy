import { describe, expect, it } from 'vitest';
import type { Pool } from 'pg';
import { buildApp } from '../src/app.js';

/** This tests the real application composition, not the synthetic messaging harness. */
describe('messaging activation boundary', () => {
  it('keeps messaging disabled in the real composition without touching the lesson database', async () => {
    let connects = 0;
    const pool = { connect: async () => { connects++; throw new Error('database must remain untouched'); } } as unknown as Pool;
    const app = buildApp({ pool, cursorSecret: 'synthetic-cursor-secret-at-least-32-characters',
      verifyToken: async () => ({ issuer: 'https://identity.example.invalid', subject: 'synthetic' }) });
    try {
      const response = await app.inject({ method: 'GET', url: '/v1/schools/11111111-1111-4111-8111-111111111111/messaging/conversations' });
      expect(response.statusCode).toBe(503);
      expect(response.json()).toMatchObject({ code: 'MESSAGING_NOT_ENABLED' });
      expect(response.headers['cache-control']).toBe('no-store');
      expect(connects).toBe(0);
      const unknown = await app.inject({ method: 'GET', url: '/v1/not-a-route' });
      expect(unknown.statusCode).toBe(404);
    } finally { await app.close(); }
  });
});
