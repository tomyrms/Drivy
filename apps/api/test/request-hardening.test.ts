import { describe, expect, it } from 'vitest';
import { Pool, type PoolClient } from 'pg';
import { buildApp, containsNul } from '../src/app.js';
import { guardPool } from '../src/database.js';

/**
 * Robustesse du transport et de la base, sans PostgreSQL : un faux Pool rejoue les pannes qui n'arrivent qu'en production.
 * Aucune donnée de personne : les corps ne contiennent que des chaînes synthétiques.
 */
const identity = { issuer: 'https://harness-identity.example.invalid', subject: 'synthetic-subject' };
const secret = 'harness-test-secret-32-characters!!';

interface Fake { pool: Pool; released: unknown[]; queries: string[] }
/** Faux Pool : `failOn` fait échouer la première requête qui contient ce texte avec l'erreur donnée ; ROLLBACK peut échouer aussi. */
function fakePool(failOn: string | undefined, error: unknown, rollbackFails = false): Fake {
  const released: unknown[] = [];
  const queries: string[] = [];
  const client = {
    query: async (sql: string) => {
      queries.push(sql);
      if (sql === 'ROLLBACK' && rollbackFails) throw new Error('connexion coupée');
      if (failOn && sql.includes(failOn)) throw error;
      return { rows: [], rowCount: 0 };
    },
    release: (value?: unknown) => { released.push(value); }
  } as unknown as PoolClient;
  const pool = { connect: async () => client } as unknown as Pool;
  return { pool, released, queries };
}
const sqlError = (code: string) => Object.assign(new Error('détail SQL à ne jamais exposer'), { code });
const appFor = (pool: Pool) => buildApp({ pool, cursorSecret: secret, verifyToken: async () => identity });

describe('caractère NUL', () => {
  it('containsNul regarde chaînes, clés, tableaux et objets imbriqués', () => {
    expect(containsNul('texte')).toBe(false);
    expect(containsNul('a\u0000b')).toBe(true);
    expect(containsNul({ a: ['x', { b: 'y\u0000' }] })).toBe(true);
    expect(containsNul({ ['k\u0000']: 'v' })).toBe(true);
    expect(containsNul({ a: 1, b: null, c: [true, 'ok'] })).toBe(false);
  });

  it('un NUL dans le corps ou les paramètres est un refus définitif 400, sans toucher la base', async () => {
    const { pool, queries } = fakePool(undefined, undefined);
    const app = appFor(pool);
    try {
      const body = await app.inject({ method: 'POST', url: '/v1/invitations/preview', headers: { authorization: 'Bearer x', 'content-type': 'application/json' },
        payload: JSON.stringify({ token: `${'a'.repeat(40)}\u0000` }) });
      expect(body.statusCode).toBe(400);
      expect(body.json()).toMatchObject({ status: 400, code: 'INVALID_REQUEST' });
      const query = await app.inject({ method: 'GET', url: '/v1/schools/11111111-1111-4111-8111-111111111111/learners?q=%00', headers: { authorization: 'Bearer x' } });
      expect(query.statusCode).toBe(400);
      expect(query.json().code).toBe('INVALID_REQUEST');
      expect(queries).toEqual([]);
    } finally { await app.close(); }
  });
});

describe('erreurs de données PostgreSQL', () => {
  it.each(['22001', '22003', '22007', '22008', '22021', '22023', '22P02', '22P05'])('SQLSTATE %s vient de la valeur envoyée : 400, jamais un 503 rejoué sans fin', async code => {
    const { pool } = fakePool('identity_link', sqlError(code));
    const app = appFor(pool);
    try {
      const response = await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: 'Bearer x' } });
      expect(response.statusCode).toBe(400);
      expect(response.json()).toMatchObject({ status: 400, code: 'INVALID_REQUEST' });
      expect(response.body).not.toMatch(/détail SQL|22\d{3}|stack/);
    } finally { await app.close(); }
  });

  it.each(['57014', '55P03', '40001', '40P01', '08006', '53300', 'P0001'])('SQLSTATE %s reste une indisponibilité temporaire 503 sans détail', async code => {
    const { pool } = fakePool('identity_link', sqlError(code));
    const app = appFor(pool);
    try {
      const response = await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: 'Bearer x' } });
      expect(response.statusCode).toBe(503);
      expect(response.json().code).toBe('SERVICE_UNAVAILABLE');
      expect(response.body).not.toMatch(/détail SQL/);
    } finally { await app.close(); }
  });
});

describe('transaction interrompue', () => {
  it('un ROLLBACK qui échoue ne masque pas l’erreur d’origine et détruit la connexion', async () => {
    const { pool, released } = fakePool('identity_link', sqlError('22P02'), true);
    const app = appFor(pool);
    try {
      const response = await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: 'Bearer x' } });
      // L'erreur d'origine (données invalides) reste visible : le ROLLBACK raté ne la remplace pas.
      expect(response.statusCode).toBe(400);
      expect(released).toEqual([true]);
    } finally { await app.close(); }
  });

  it('un ROLLBACK réussi rend la connexion saine au pool', async () => {
    const { pool, released } = fakePool('identity_link', sqlError('57014'));
    const app = appFor(pool);
    try {
      await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: 'Bearer x' } });
      expect(released).toEqual([false]);
    } finally { await app.close(); }
  });
});

describe('connexion inactive perdue', () => {
  it('sans écouteur, l’événement « error » d’un Pool arrête le processus ; guardPool le rend inoffensif et sobre', () => {
    const bare = new Pool({ connectionString: 'postgres://nobody:nothing@127.0.0.1:1/none' });
    expect(() => bare.emit('error', new Error('terminating connection due to administrator command'))).toThrow();
    const reported: string[] = [];
    const guarded = guardPool(new Pool({ connectionString: 'postgres://nobody:nothing@127.0.0.1:1/none' }), name => { reported.push(name); });
    expect(() => guarded.emit('error', new Error('postgres://nobody:nothing@127.0.0.1:1/none'))).not.toThrow();
    // Seul le nom de l'erreur est rapporté : ni message, ni adresse, ni identifiant.
    expect(reported).toEqual(['Error']);
    const noisy = guardPool(new Pool({ connectionString: 'postgres://nobody:nothing@127.0.0.1:1/none' }), () => { throw new Error('journal indisponible'); });
    expect(() => noisy.emit('error', new Error('x'))).not.toThrow();
  });
});
