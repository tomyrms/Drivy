import type { Page } from '../../../infra/dev/browser.js';
import type { AccessVerdict } from './guards.js';
/** A transport reply alone never satisfies this bounded product-store observation. */
export async function waitForAccessVerdict(page: Page, expected: AccessVerdict, timeout = 22000): Promise<void> {
  await page.waitForFunction(verdict => (window as any).q.matches(verdict), expected, { timeout });
}
