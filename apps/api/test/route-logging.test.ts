import { describe, expect, it } from 'vitest';
import type { Pool, PoolClient } from 'pg';
import { buildApp } from '../src/app.js';

/**
 * Journal des réponses de la messagerie et de la crypto : méthode, modèle de route, statut, code métier, durée.
 * Jamais d'identifiant réel, de jeton, d'en-tête, de requête ni de corps. Faux Pool : aucune donnée de personne.
 */
const identity = { issuer: 'https://harness-identity.example.invalid', subject: 'synthetic-subject' };
const schoolId = '5c0f1e2a-3b4c-4d5e-8f60-718293a4b5c6';
const personId = '9a8b7c6d-5e4f-4a3b-9c2d-1e0f2a3b4c5d';
const deviceId = 'DEVICESYNTHETIC42';
const token = 'eyJsecret-bearer-token-synthetic-0123456789';
const ciphertext = 'AwgAEhAciphertextSYNTHETICpayloadXYZ987';

function fakePool(): Pool {
  const client = { query: async () => ({ rows: [], rowCount: 0 }), release: () => undefined } as unknown as PoolClient;
  return { connect: async () => client } as unknown as Pool;
}

function harness() {
  const lines: string[] = [];
  const app = buildApp({ pool: fakePool(), cursorSecret: 'harness-test-secret-32-characters!!', verifyToken: async () => identity,
    messaging: { mode: 'qualification', schoolIds: [schoolId] },
    logger: { level: 'info', stream: { write: (line: string) => { lines.push(line); } } } });
  const entries = () => lines.map(line => JSON.parse(line) as Record<string, unknown>).filter(entry => entry.msg === 'Réponse API');
  return { app, lines, entries };
}
const headers = { authorization: `Bearer ${token}`, 'content-type': 'application/json', 'x-drivy-device-id': deviceId };

describe('journal des réponses messagerie et crypto', () => {
  it('journalise un 4xx crypto avec le modèle de route, sans identifiant ni contenu', async () => {
    const { app, lines, entries } = harness();
    try {
      const response = await app.inject({ method: 'POST', url: `/v1/schools/${schoolId}/messaging/crypto/keys/upload?user=${personId}`, headers,
        payload: JSON.stringify({ device_keys: { user_id: personId, device_id: deviceId, ciphertext } }) });
      expect(response.statusCode).toBeGreaterThanOrEqual(400);
      expect(response.statusCode).toBeLessThan(500);
      const [entry] = entries();
      expect(entry).toMatchObject({ method: 'POST', route: '/v1/schools/:schoolId/messaging/crypto/keys/upload', statusCode: response.statusCode });
      expect(typeof entry?.errorCode).toBe('string');
      expect(typeof entry?.durationMs).toBe('number');
      const output = lines.join('\n');
      for (const secret of [schoolId, personId, deviceId, token, ciphertext]) expect(output).not.toContain(secret);
      expect(Object.keys(entry ?? {}).filter(key => !['level', 'time', 'pid', 'hostname', 'msg'].includes(key)).sort())
        .toEqual(['durationMs', 'errorCode', 'method', 'reason', 'route', 'statusCode'].sort());
      expect(entry?.reason).toBe('Paramètres invalides.');
    } finally { await app.close(); }
  });

  it('ajoute le motif générique d’une validation refusée, jamais la valeur reçue', async () => {
    const { app, lines, entries } = harness();
    try {
      const response = await app.inject({ method: 'POST', url: `/v1/schools/${schoolId}/messaging/conversations/${personId}/messages`, headers,
        payload: `{"ciphertext":"${ciphertext}",` });
      expect(response.statusCode).toBe(400);
      expect(entries()[0]).toMatchObject({ route: '/v1/schools/:schoolId/messaging/conversations/:conversationId/messages',
        statusCode: 400, errorCode: 'INVALID_REQUEST', reason: 'Requête invalide.' });
      const output = lines.join('\n');
      for (const secret of [schoolId, personId, deviceId, token, ciphertext]) expect(output).not.toContain(secret);
    } finally { await app.close(); }
  });

  it('ne journalise pas les autres routes', async () => {
    const { app, entries } = harness();
    try {
      await app.inject({ method: 'GET', url: `/v1/schools/${schoolId}/learners`, headers });
      await app.inject({ method: 'GET', url: '/v1/inconnue' });
      expect(entries()).toEqual([]);
    } finally { await app.close(); }
  });
});
