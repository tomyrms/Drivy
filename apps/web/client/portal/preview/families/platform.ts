import type { z } from 'zod';
import type { platformInvitationSchema, platformJournalSchema, platformOperatorSchema } from '../../../platform-model';
import { previewId, stamp } from '../fixtures';
import type { PreviewFamily } from '../family';
import { clientsRead, clientsWrite } from './platform-clients';
import { offersRead, offersWrite } from './platform-offers';

type Operator = z.infer<typeof platformOperatorSchema>;
type Invitation = z.infer<typeof platformInvitationSchema>;
type Entry = z.infer<typeof platformJournalSchema>;
const rights = { level: 'COMMERCIAL', rights: ['MANAGE_PLATFORM_TEAM', 'MANAGE_SCHOOL_OPENINGS', 'MANAGE_OFFERS', 'READ_COMMERCIAL_JOURNAL'], notGranted: ['SCHOOL_RECORDS', 'TRIPS', 'MESSAGES', 'SCHOOL_ROLES'] };
const day = 86_400_000;
const ago = (days: number) => new Date(Date.now() - days * day).toISOString();
const operators: Operator[] = [
  { id: previewId(920), displayName: 'Camille Aubry', maskedEmail: 'c***@example.test', level: 'COMMERCIAL', status: 'ACTIVE', addedVia: 'BOOTSTRAP', joinedAt: stamp, revokedAt: null, version: 1, self: true },
  { id: previewId(921), displayName: 'Hugo Lambert', maskedEmail: 'h***@example.test', level: 'COMMERCIAL', status: 'ACTIVE', addedVia: 'INVITATION', joinedAt: ago(6), revokedAt: null, version: 1, self: false },
  { id: previewId(922), displayName: 'Inès Morel', maskedEmail: 'i***@example.test', level: 'COMMERCIAL', status: 'REVOKED', addedVia: 'INVITATION', joinedAt: ago(20), revokedAt: ago(9), version: 2, self: false },
];
const invitations: Invitation[] = [
  { id: previewId(930), status: 'AVAILABLE', level: 'COMMERCIAL', maskedEmail: 'n***@example.test', createdAt: ago(1), expiresAt: new Date(Date.now() + 6 * day).toISOString(), version: 1, usedAt: null, revokedAt: null, createdByName: 'Camille Aubry' },
  { id: previewId(931), status: 'EXPIRED', level: 'COMMERCIAL', maskedEmail: 'a***@example.test', createdAt: ago(21), expiresAt: ago(7), version: 1, usedAt: null, revokedAt: null, createdByName: 'Camille Aubry' },
];
const entry = (n: number, action: string, days: number, extra: Partial<Entry> = {}): Entry => ({
  id: previewId(940 + n), occurredAt: ago(days), actorKind: 'OPERATOR', actorName: 'Camille Aubry', action, result: 'SUCCESS', reasonCode: null, schoolId: null, subject: null, operationId: null, changes: {}, ...extra,
});
const journal: Entry[] = [
  entry(1, 'CREATE_PLATFORM_INVITATION', 1, { changes: { maskedEmail: 'n***@example.test', expiresAt: new Date(Date.now() + 6 * day).toISOString() } }),
  entry(2, 'REVOKE_PLATFORM_OPERATOR', 9, { actorName: 'Hugo Lambert', result: 'REFUSED', reasonCode: 'LAST_PLATFORM_OPERATOR' }),
  entry(3, 'REVOKE_PLATFORM_OPERATOR', 9, { changes: { status: { from: 'ACTIVE', to: 'REVOKED' }, self: false } }),
  entry(4, 'ACCEPT_PLATFORM_INVITATION', 20, { actorName: 'Inès Morel' }),
  entry(5, 'BOOTSTRAP_PLATFORM_OPERATOR', 40, { actorKind: 'SYSTEM', actorName: 'Mise en service' }),
];
const receipts = new Map<string, unknown>();
const lost = new Set<string>();
// Opération d'invitation en cours : le code vit ici, comme dans la session du relais, et jamais dans la liste.
let issuing: { operationId: string; email: string; validityDays?: number; code: string } | null = null;
let join: { accepted: boolean; submitted: boolean } = { accepted: false, submitted: false };
const previewCode = 'DEMNK-ABC23';

const active = () => operators.filter(item => item.status === 'ACTIVE');
const mask = (email: string) => `${email[0] ?? '*'}***${email.slice(email.lastIndexOf('@'))}`;
const record = (action: string, extra: Partial<Entry> = {}) => journal.unshift({ ...entry(journal.length + 1, action, 0, extra), id: previewId(960 + journal.length + receipts.size) });

/** Console des opérateurs de la plateforme (R01-T01) : données fictives, jamais d'appel à l'API. */
export const platformFamily: PreviewFamily = {
  name: 'platform',
  async bff(request, tools) {
    if (!request.path.startsWith('platform/')) return undefined;
    const path = request.path.slice('platform/'.length);
    const joining = path.startsWith('join');
    // Un opérateur retiré (ou refusé par le scénario) perd tout de suite l'accès, comme côté serveur.
    if (!joining && (operators[0]?.status !== 'ACTIVE' || (request.method === 'GET' && request.scenario === 'refused'))) return tools.reply(403, { code: 'PLATFORM_OPERATOR_REQUIRED' });
    if (request.method === 'GET') {
      if (path === 'me') return tools.reply(200, { data: { operator: operators[0], ...rights } });
      if (path === 'operators') return tools.reply(200, { data: { items: structuredClone(operators) } });
      if (path === 'invitations') return tools.reply(200, { data: { items: structuredClone(invitations) },
        ...(issuing ? { pending: { operationId: issuing.operationId, email: issuing.email, ...(issuing.validityDays ? { validityDays: issuing.validityDays } : {}) } } : {}) });
      if (path === 'journal') {
        const refusedOnly = request.query.get('result') === 'REFUSED';
        return tools.reply(200, { data: { items: structuredClone(refusedOnly ? journal.filter(item => item.result === 'REFUSED') : journal), nextCursor: null } });
      }
      if (path === 'join') return tools.reply(200, { pending: !join.accepted && join.submitted, uncertain: !join.accepted && join.submitted, accepted: join.accepted });
      return offersRead(request, path, tools) ?? clientsRead(request, path, tools) ?? tools.reply(404, { code: 'NOT_FOUND' });
    }
    if (request.method !== 'POST') return tools.reply(405, { code: 'METHOD_NOT_ALLOWED' });
    await new Promise(resolve => setTimeout(resolve, request.scenario === 'slow' ? 2500 : 150));
    if (request.scenario === 'refused') return tools.reply(403, { code: joining ? 'EMAIL_VERIFICATION_REQUIRED' : 'PLATFORM_OPERATOR_REQUIRED' });
    if (request.scenario === 'conflict' && /\/(revoke|update|attach-school|archive|restore|cancel|lift)$|\/(assignments|adjustments)$/.test(path)) {
      // Un autre opérateur a déjà modifié la ligne : la version attendue ne correspond plus.
      return tools.reply(412, { code: 'VERSION_CONFLICT' });
    }
    const clientWrite = clientsWrite(request, path, tools, (action, extra) => record(action, extra ?? {}));
    if (clientWrite) return clientWrite;
    const offerWrite = offersWrite(request, path, tools, (action, extra) => record(action, extra ?? {}));
    if (offerWrite) return offerWrite;

    if (path === 'invitations/clear') { issuing = null; return tools.reply(200, { ok: true }); }
    if (path === 'invitations') {
      const body = request.body as { operationId: string; email: string; validityDays?: number };
      if (issuing && issuing.operationId !== body.operationId) return tools.reply(409, { code: 'PLATFORM_INVITE_IN_PROGRESS' });
      const known = receipts.get(body.operationId) as Invitation | undefined;
      if (!issuing) {
        if (active().some(item => item.maskedEmail === mask(body.email))) return tools.reply(409, { code: 'PLATFORM_OPERATOR_EXISTS' });
        if (invitations.some(item => item.status === 'AVAILABLE' && item.maskedEmail === mask(body.email))) return tools.reply(409, { code: 'PLATFORM_INVITATION_PENDING' });
        const created: Invitation = { id: tools.nextId(), status: 'AVAILABLE', level: 'COMMERCIAL', maskedEmail: mask(body.email), createdAt: new Date().toISOString(),
          expiresAt: new Date(Date.now() + (body.validityDays ?? 7) * day).toISOString(), version: 1, usedAt: null, revokedAt: null, createdByName: 'Camille Aubry' };
        invitations.unshift(created); receipts.set(body.operationId, created);
        // Ce code est explicitement fictif et n'ouvre rien : le vrai code est tiré par le relais.
        issuing = { operationId: body.operationId, email: body.email, ...(body.validityDays ? { validityDays: body.validityDays } : {}), code: 'DEMNK-X7K42' };
        record('CREATE_PLATFORM_INVITATION', { changes: { maskedEmail: created.maskedEmail, expiresAt: created.expiresAt } });
        if (request.scenario === 'lost-reply') throw new TypeError('Synthetic invitation response lost');
      }
      return tools.reply(201, { data: known ?? receipts.get(issuing!.operationId), code: issuing!.code });
    }
    const revoke = /^(invitations|operators)\/([^/]+)\/revoke$/.exec(path);
    if (revoke) {
      const body = request.body as { operationId: string; version: number };
      const target = (revoke[1] === 'operators' ? operators : invitations).find(item => item.id === revoke[2]);
      if (!target) return tools.reply(404, { code: 'NOT_FOUND' });
      if (receipts.has(body.operationId)) return tools.reply(200, { data: structuredClone(target) });
      if (target.version !== body.version) return tools.reply(412, { code: 'VERSION_CONFLICT' });
      if (revoke[1] === 'operators') {
        const operator = target as Operator;
        if (operator.status !== 'ACTIVE') return tools.reply(409, { code: 'PLATFORM_OPERATOR_REVOKED' });
        if (active().length <= 1) { record('REVOKE_PLATFORM_OPERATOR', { result: 'REFUSED', reasonCode: 'LAST_PLATFORM_OPERATOR' }); return tools.reply(409, { code: 'LAST_PLATFORM_OPERATOR' }); }
        operator.status = 'REVOKED'; operator.revokedAt = new Date().toISOString(); operator.version += 1;
        record('REVOKE_PLATFORM_OPERATOR', { changes: { status: { from: 'ACTIVE', to: 'REVOKED' }, self: operator.self } });
      } else {
        const invitation = target as Invitation;
        if (invitation.status !== 'AVAILABLE') return tools.reply(409, { code: invitation.status === 'REVOKED' ? 'PLATFORM_INVITATION_REVOKED' : 'PLATFORM_INVITATION_USED' });
        invitation.status = 'REVOKED'; invitation.revokedAt = new Date().toISOString(); invitation.version += 1;
        record('REVOKE_PLATFORM_INVITATION', { changes: { status: { from: 'AVAILABLE', to: 'REVOKED' }, maskedEmail: invitation.maskedEmail } });
      }
      receipts.set(body.operationId, target);
      if (request.scenario === 'lost-reply' && !lost.has(body.operationId)) { lost.add(body.operationId); throw new TypeError('Synthetic revoke response lost'); }
      return tools.reply(200, { data: structuredClone(target) });
    }

    if (path === 'join/preview') {
      const { code } = request.body as { code: string };
      if (code !== previewCode) return tools.reply(404, { code: 'PLATFORM_INVITATION_INVALID' });
      return tools.reply(200, { confirmation: 'preview-confirmation', data: { status: 'AVAILABLE', maskedEmail: 'n***@example.test',
        expiresAt: new Date(Date.now() + 6 * day).toISOString(), matchesAccount: true, alreadyMember: false, ...rights } });
    }
    if (path === 'join/accept') {
      const body = request.body as { confirmation?: string };
      if (!join.accepted) {
        if (!join.submitted && body.confirmation !== 'preview-confirmation') return tools.reply(409, { code: 'PLATFORM_PREVIEW_CHANGED' });
        const replay = join.submitted;
        join = { accepted: true, submitted: true };
        if (!replay && request.scenario === 'lost-reply') { join.accepted = false; throw new TypeError('Synthetic acceptance response lost'); }
      }
      return tools.reply(201, { data: { operator: { ...operators[0], addedVia: 'INVITATION' }, ...rights } });
    }
    return tools.reply(404, { code: 'NOT_FOUND' });
  },
};
