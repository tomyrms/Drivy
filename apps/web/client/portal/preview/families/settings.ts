import { previewSchool } from '../fixtures';
import type { PreviewFamily } from '../family';

/** Synthetic school settings (#330): coordinates saved with If-Match on the school itself. */
export const settingsFamily: PreviewFamily = {
  name: 'settings',
  write(request, tools) {
    if (request.path !== '' || request.method !== 'PATCH') return undefined;
    if (!tools.versionMatches(previewSchool)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
    const { name, contactEmail, contactPhone } = request.body;
    if (typeof name !== 'string' || !name.trim() || typeof contactEmail !== 'string' || !contactEmail.includes('@')) return tools.reply(400, { code: 'INVALID_REQUEST' });
    Object.assign(previewSchool, { name, contactEmail, contactPhone: contactPhone ?? null, version: previewSchool.version + 1 });
    return tools.commit('updateSchool', previewSchool);
  },
  refusalCode: request => request.path === '' ? 'SCHOOL_UPDATE_REJECTED' : undefined,
};
