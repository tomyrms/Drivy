import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { ApiError } from './errors.js';
import { platformRead } from './platform-command.js';
import { dashboardSchema } from './platform-dashboard-contract.js';

/**
 * Tableau de bord commercial de l'équipe Drivy (R01-T10, #462). Lecture seule : tous les totaux viennent d'une fonction de la base, qui relit
 * l'opérateur et réutilise les calculs des fiches, factures, règlements et relances. La période est bornée à 367 jours.
 */
const MAX_SPAN_DAYS = 366;
export const dashboardQuery = z.object({ from: z.iso.date(), to: z.iso.date() }).strict();

const spanDays = (from: string, to: string) => (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000;

export function registerPlatformDashboard(app: FastifyInstance, options: { pool: Pool; verifyToken: TokenVerifier }) {
  const envelope = (data: unknown, request: FastifyRequest) => ({ data, requestId: request.id, serverTime: new Date().toISOString() });
  app.get('/v1/platform/dashboard', async request => {
    const identity = await options.verifyToken(request.headers.authorization);
    const { from, to } = dashboardQuery.parse(request.query);
    const span = spanDays(from, to);
    if (span < 0 || span > MAX_SPAN_DAYS) throw new ApiError(400, 'DASHBOARD_PERIOD_INVALID', 'Choisissez une période d’un an au plus, dans l’ordre des dates.');
    const data = await platformRead(options.pool, identity, async db => {
      const row = (await db.query<{ dashboard: unknown }>('SELECT drivy.platform_commercial_dashboard($1::date,$2::date) AS dashboard', [from, to])).rows[0]!;
      return dashboardSchema.parse(row.dashboard);
    });
    return envelope(data, request);
  });
}
