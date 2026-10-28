import type { PreviewFamily } from './family';
import { teamFamily } from './families/team';
import { planningFamily } from './families/planning';

/** Rebuilt families add their synthetic behaviour here, one import per family. Pilots stay in transport.ts. */
export const previewFamilies: readonly PreviewFamily[] = [teamFamily, planningFamily];
