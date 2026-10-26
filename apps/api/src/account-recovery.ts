import { z } from 'zod';
import type { FastifyInstance } from 'fastify';

export type AccountRecoveryOptions = { available: false; recoveryUrl: null } | { available: true; recoveryUrl: string };

/** Activation follows SMTP qualification; no address, identity lookup or delivery is performed by this endpoint. */
export function readAccountRecoveryConfig(env: NodeJS.ProcessEnv = process.env): AccountRecoveryOptions {
  const enabled = z.enum(['true', 'false']).default('false').parse(env.ACCOUNT_RECOVERY_ENABLED);
  if (enabled === 'false') return { available: false, recoveryUrl: null };
  const origin = new URL(z.url().parse(env.PUBLIC_ORIGIN));
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(origin.hostname);
  if ((origin.protocol !== 'https:' && !(env.NODE_ENV !== 'production' && loopback && origin.protocol === 'http:')) ||
      origin.pathname !== '/' || origin.search || origin.hash || origin.username || origin.password) {
    throw new Error('PUBLIC_ORIGIN doit être une origine HTTPS contrôlée.');
  }
  return { available: true, recoveryUrl: `${origin.origin}/app/recover` };
}

export function registerAccountRecovery(app: FastifyInstance, options: { accountRecovery?: AccountRecoveryOptions }) {
  const configuration = options.accountRecovery ?? { available: false, recoveryUrl: null };
  app.get('/v1/account-recovery/options', async request => {
    z.object({}).strict().parse(request.query);
    return { data: configuration, serverTime: new Date().toISOString(), requestId: request.id };
  });
}
