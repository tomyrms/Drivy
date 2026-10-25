import { describe, expect, it } from 'vitest';
import Fastify from 'fastify';
import type { Pool } from 'pg';
import { registerMessaging } from '../src/messaging-routes.js';
import { ApiError } from '../src/errors.js';

const school = '00000000-0000-4000-8000-000000000001';

describe('messaging activation boundary', () => {
  it('rejects every route before auth or storage in default mode', async () => {
    const app = Fastify();
    app.setErrorHandler((error, _request, reply) => reply.status(error instanceof ApiError ? error.status : 500).send({ code: error instanceof ApiError ? error.code : 'UNEXPECTED' }));
    registerMessaging(app, {
      pool: { connect: () => { throw new Error('storage touched'); } } as unknown as Pool,
      verifyToken: async () => { throw new Error('auth touched'); }
    });
    const paths: { method: 'GET' | 'PUT' | 'POST'; url: string; payload?: object }[] = [
      { method: 'GET', url: `/v1/schools/${school}/messaging/contacts` },
      { method: 'PUT', url: `/v1/schools/${school}/messaging/general` },
      { method: 'GET', url: `/v1/schools/${school}/messaging/general/members` },
      { method: 'PUT', url: `/v1/schools/${school}/messaging/private/${school}` },
      { method: 'GET', url: `/v1/schools/${school}/messaging/conversations` },
      { method: 'GET', url: `/v1/schools/${school}/messaging/conversations/${school}/messages` },
      { method: 'GET', url: `/v1/schools/${school}/messaging/conversations/${school}/events` },
      { method: 'POST', url: `/v1/schools/${school}/messaging/conversations/${school}/messages`, payload: { clientMessageId: school, ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AA==' } } }
    ];
    try {
      for (const path of paths) {
        const response = await app.inject(path);
        expect(response.statusCode).toBe(503);
        expect(response.json()).toMatchObject({ code: 'MESSAGING_NOT_ENABLED' });
      }
    } finally { await app.close(); }
  });
});
