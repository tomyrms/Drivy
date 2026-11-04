import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { test } from 'vitest';

// Real React presentation and command store in locked Chromium; only storage/network boundaries are synthetic.
for (const scenario of ['metadata', 'race']) {
  test(`pending recovery: ${scenario}`, () => {
    execFileSync(process.execPath, [resolve('node_modules/tsx/dist/cli.mjs'),
      resolve('../../scripts/dev/check-pending-recovery-106.ts'), scenario],
    { cwd: resolve('../..'), stdio: 'pipe', timeout: 120_000 });
  }, 130_000);
}
