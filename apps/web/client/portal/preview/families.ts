import type { PreviewFamily } from './family';
import { teamFamily } from './families/team';
import { planningFamily } from './families/planning';
import { catalogueFamily } from './families/catalogue';
import { signalsFamily } from './families/signals';
import { tripsFamily } from './families/trips';
import { overviewFamily } from './families/overview';

/** Rebuilt families add their synthetic behaviour here, one import per family. Pilots stay in transport.ts. */
export const previewFamilies: readonly PreviewFamily[] = [teamFamily, planningFamily, catalogueFamily, signalsFamily, tripsFamily, overviewFamily];
