import type { PreviewFamily } from './family';
import { teamFamily } from './families/team';

/** Rebuilt families add their synthetic behaviour here, one import per family. Pilots stay in transport.ts. */
export const previewFamilies: readonly PreviewFamily[] = [teamFamily];
