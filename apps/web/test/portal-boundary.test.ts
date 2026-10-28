import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

/** #311: the rebuilt portal never reaches the historical presentation, and production code never reaches the synthetic preview. */
const client = resolve(dirname(fileURLToPath(import.meta.url)), '../client');
const portal = join(client, 'portal');
const posix = (path: string) => relative(client, path).split(sep).join('/');
const specifiers = /(?:import|export)\s[^'"`]*?from\s*['"]([^'"]+)['"]|import\s*\(\s*['"]([^'"]+)['"]\s*\)|import\s+['"]([^'"]+)['"]/g;

function files(directory: string): string[] {
  return readdirSync(directory).flatMap(name => {
    const path = join(directory, name);
    return statSync(path).isDirectory() ? files(path) : /\.(ts|tsx)$/.test(name) && !/\.test\.tsx?$/.test(name) ? [path] : [];
  });
}

function resolveImport(from: string, specifier: string): string | null {
  const base = specifier.startsWith('@/') ? join(client, specifier.slice(2)) : specifier.startsWith('.') ? resolve(dirname(from), specifier) : null;
  if (!base) return null;
  for (const candidate of [base, `${base}.ts`, `${base}.tsx`, join(base, 'index.ts'), join(base, 'index.tsx')]) {
    if (existsSync(candidate) && statSync(candidate).isFile()) return candidate;
  }
  return base.replace(/\.js$/, '') !== base ? resolveImport(from, specifier.replace(/\.js$/, '')) : null;
}

function graph(entries: string[]) {
  const seen = new Map<string, string>();
  const queue = entries.map(entry => [entry, posix(entry)] as const);
  for (const [file, path] of queue) {
    if (seen.has(file)) continue;
    seen.set(file, path);
    if (file.endsWith('.css')) continue;
    for (const match of readFileSync(file, 'utf8').matchAll(specifiers)) {
      const target = resolveImport(file, match[1] ?? match[2] ?? match[3]!);
      if (target && !seen.has(target)) queue.push([target, `${path} → ${posix(target)}`]);
    }
  }
  return seen;
}

function legacy(path: string) {
  return path === 'ui.tsx' || path === 'legacy-styles.ts' || /^console\/.*\.tsx$/.test(path)
    || path.endsWith('.css') && !path.startsWith('portal/')
    || path.endsWith('.tsx') && !path.startsWith('portal/') && !path.startsWith('components/ui/') && path !== 'BrandSymbol.tsx';
}

describe('rebuilt portal boundary', () => {
  const production = files(portal).filter(file => !posix(file).startsWith('portal/preview/') && posix(file) !== 'portal/access-preview.tsx');
  const reached = graph(production);

  it('never imports the historical presentation, even transitively', () => {
    const violations = [...reached].filter(([file]) => legacy(posix(file))).map(([, chain]) => chain);
    expect(violations).toEqual([]);
  });

  it('keeps the synthetic preview out of production code', () => {
    const violations = [...reached].filter(([file]) => posix(file).startsWith('portal/preview/') || posix(file) === 'portal/access-preview.tsx').map(([, chain]) => chain);
    expect(violations).toEqual([]);
  });

  it('covers the authenticated entry and every registered page', () => {
    expect(reached.has(join(portal, 'portal-console.tsx'))).toBe(true);
    expect(reached.has(join(portal, 'pages.tsx'))).toBe(true);
  });
});
