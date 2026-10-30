import { ids, previewId } from '../fixtures';
import type { PreviewFamily } from '../family';

/** Synthetic preparation (#321): next actions decided by the server and one deferred formation in the setup draft. */
const nextActions = { schoolId: ids.school, planningReady: true, actions: [
  { code: 'PLAN_FIRST_LESSON', label: 'Planifier une leçon', section: 'agenda' },
  { code: 'COMPLETE_AVAILABILITY', label: 'Compléter les disponibilités de Simon Favre', section: 'disponibilites', query: { instructor: previewId(6) } },
  { code: 'REVIEW_PROFILE_POLICY', label: 'Relire les informations demandées aux élèves', section: 'champs-profil' },
] };
const draft = { id: previewId(810), schoolId: ids.school, version: 3, status: 'APPLIED', content: { formations: [
  { categoryCode: 'B', label: 'Permis B', apply: true }, { categoryCode: 'A1', label: 'Permis A1', apply: false },
] } };

export const overviewFamily: PreviewFamily = {
  name: 'overview',
  read(request, tools) {
    if (request.path === 'setup-draft/next-actions') return tools.reply(200, tools.envelope(nextActions));
    if (request.path === 'setup-draft') return tools.reply(200, tools.envelope(draft));
    return undefined;
  },
};
