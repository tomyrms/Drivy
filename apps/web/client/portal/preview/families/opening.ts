import type { z } from 'zod';
import { openingFieldErrors, openingLinkSchema, type OpeningFields, type OpeningReceipt } from '../../../school-opening-model';
import { ids, previewId, previewSchool, stamp } from '../fixtures';
import type { PreviewFamily } from '../family';

type Link = z.infer<typeof openingLinkSchema>;
const expiresAt = new Date(Date.now() + 7 * 86_400_000).toISOString();
const links: Link[] = [{ id: previewId(910), status: 'AVAILABLE', createdAt: stamp, expiresAt, usedAt: null, revokedAt: null }];
let generated: { operationId: string; data: Link; link: string; code: string } | null = null;
let creation: { fields: OpeningFields; result: OpeningReceipt; uncertain: boolean } | null = null;
const revoked = new Set<string>();
export const openingFamily: PreviewFamily = {
  name: 'opening',
  async bff(request, tools) {
    if (!request.path.startsWith('opening') && !request.path.startsWith('operator/school-opening-links')) return undefined;
    if (request.method === 'GET' && request.path === 'opening') return tools.reply(200, creation ? {
      pending: false, uncertain: false, result: creation.result,
    } : { pending: true, uncertain: false });
    if (request.method === 'GET' && request.path === 'opening/result') return creation ? tools.reply(200, { data: creation.result }) : tools.reply(404, { code: 'NOT_FOUND' });
    if (request.method === 'GET' && request.path === 'operator/school-opening-links') return tools.reply(200, { data: { items: links }, ...(generated ? { pendingOperationId: generated.operationId } : {}) });
    if (request.method !== 'POST') return tools.reply(405, { code: 'METHOD_NOT_ALLOWED' });
    if (request.path === 'opening') return tools.reply(200, { ok: true });
    if (request.path === 'opening/preview') return tools.reply(200, { data: creation ? { status: 'USED', school: creation.result } : { status: 'AVAILABLE', expiresAt } });
    await new Promise(resolve => setTimeout(resolve, request.scenario === 'slow' ? 2500 : 150));
    if (request.scenario === 'refused') return tools.reply(403, { code: request.path.startsWith('operator/') ? 'OPERATOR_REQUIRED' : 'OPENING_LINK_REVOKED' });
    if (request.scenario === 'conflict') return tools.reply(409, { code: 'OPENING_IN_PROGRESS' });
    if (request.path === 'opening/create') {
      if (creation) return tools.reply(200, { data: creation.result });
      const fields = request.body as OpeningFields;
      if (Object.keys(openingFieldErrors(fields)).length) return tools.reply(400, { code: 'INVALID_REQUEST' });
      const result: OpeningReceipt = { schoolId: ids.school, schoolName: fields.schoolName, status: 'DRAFT', membershipId: ids.admin,
        roles: fields.instructs ? ['ADMIN', 'INSTRUCTOR'] : ['ADMIN'], grants: ['CONFIGURE_CATALOG'], accessEpoch: 1, operationId: tools.nextId(), committedAt: new Date().toISOString() };
      creation = { fields, result, uncertain: request.scenario === 'lost-reply' };
      Object.assign(previewSchool, { name: fields.schoolName, contactEmail: fields.contactEmail, contactPhone: fields.contactPhone, timeZone: fields.timeZone, status: 'DRAFT' });
      if (request.scenario === 'lost-reply') throw new TypeError('Synthetic opening response lost');
      return tools.reply(201, { data: result });
    }
    if (request.path === 'operator/school-opening-links/clear') { generated = null; return tools.reply(200, { ok: true }); }
    if (request.path === 'operator/school-opening-links') {
      if (generated && generated.operationId !== request.body.operationId) return tools.reply(409, { code: 'OPENING_IN_PROGRESS' });
      if (!generated) {
        const data: Link = { id: tools.nextId(), status: 'AVAILABLE', createdAt: new Date().toISOString(), expiresAt, usedAt: null, revokedAt: null };
        // This explicitly synthetic code never grants access to the real BFF.
        generated = { operationId: request.body.operationId, data, code: 'DEMN-ABCD', link: `${window.location.origin}${window.location.pathname}?page=ouverture#token=DEMN-ABCD` };
        links.unshift(data);
        if (request.scenario === 'lost-reply') throw new TypeError('Synthetic operator response lost');
      }
      return tools.reply(200, { data: generated.data, code: generated.code, link: generated.link });
    }
    const match = /^operator\/school-opening-links\/([^/]+)\/revoke$/.exec(request.path);
    if (match) {
      const row = links.find(item => item.id === match[1]);
      if (!row) return tools.reply(404, { code: 'NOT_FOUND' });
      const replayed = revoked.has(request.body.operationId);
      row.status = 'REVOKED'; row.revokedAt ??= new Date().toISOString(); revoked.add(request.body.operationId);
      if (!replayed && request.scenario === 'lost-reply') throw new TypeError('Synthetic revocation response lost');
      return tools.reply(200, { data: row });
    }
    return tools.reply(404, { code: 'NOT_FOUND' });
  },
};
