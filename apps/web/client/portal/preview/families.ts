import type { PreviewFamily } from './family';
import { teamFamily } from './families/team';
import { planningFamily } from './families/planning';
import { catalogueFamily } from './families/catalogue';
import { signalsFamily } from './families/signals';
import { tripsFamily } from './families/trips';
import { overviewFamily } from './families/overview';
import { settingsFamily } from './families/settings';
import { privacyFamily } from './families/privacy';
import { setupFamily } from './families/setup';
import { openingFamily } from './families/opening';
import { metricsFamily } from './families/metrics';

/** Rebuilt families add their synthetic behaviour here, one import per family. Pilots stay in transport.ts. */
export const previewFamilies: readonly PreviewFamily[] = [teamFamily, planningFamily, catalogueFamily, signalsFamily, tripsFamily, setupFamily, overviewFamily, settingsFamily, privacyFamily, openingFamily, metricsFamily];
