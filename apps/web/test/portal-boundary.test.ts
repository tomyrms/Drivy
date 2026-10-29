import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

/** #311/R23: check the actual production entry as well as every portal module, including lazy imports and CSS imports. */
const client = resolve(dirname(fileURLToPath(import.meta.url)), '../client');
const portal = join(client, 'portal');
const posix = (path: string) => relative(client, path).split(sep).join('/');

function files(directory: string): string[] {
  return readdirSync(directory).flatMap(name => {
    const path = join(directory, name);
    return statSync(path).isDirectory() ? files(path) : /\.(ts|tsx|css)$/.test(name) && !/\.test\.tsx?$/.test(name) ? [path] : [];
  });
}

function dependencies(file: string): { specifiers: string[]; dynamic: boolean } {
  const text = readFileSync(file, 'utf8');
  if (file.endsWith('.css')) return { specifiers: [...text.matchAll(/@import\s+(?:url\(\s*)?["']([^"']+)["']/g)].map(match => match[1]!), dynamic: false };
  const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true);
  const specifiers: string[] = [];
  let dynamic = false;
  const visit = (node: ts.Node) => {
    if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) {
      if (node.moduleSpecifier && ts.isStringLiteralLike(node.moduleSpecifier)) specifiers.push(node.moduleSpecifier.text);
    } else if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword) {
      const specifier = node.arguments[0];
      if (specifier && ts.isStringLiteralLike(specifier)) specifiers.push(specifier.text);
      else dynamic = true;
    }
    ts.forEachChild(node, visit);
  };
  visit(source);
  return { specifiers, dynamic };
}

function resolveImport(from: string, specifier: string): string | null {
  const base = specifier.startsWith('@/') ? join(client, specifier.slice(2)) : specifier.startsWith('.') ? resolve(dirname(from), specifier) : null;
  if (!base) return null;
  for (const candidate of [base, `${base}.ts`, `${base}.tsx`, join(base, 'index.ts'), join(base, 'index.tsx')]) {
    if (existsSync(candidate) && statSync(candidate).isFile()) return candidate;
  }
  return base.endsWith('.js') ? resolveImport(from, specifier.slice(0, -3)) : null;
}

function graph(entries: string[]) {
  const reached = new Map<string, string>();
  const unresolved: string[] = [];
  const dynamic: string[] = [];
  const queue = entries.map(entry => [entry, posix(entry)] as const);
  for (const [file, path] of queue) {
    if (reached.has(file)) continue;
    reached.set(file, path);
    const imported = dependencies(file);
    if (imported.dynamic) dynamic.push(path);
    for (const specifier of imported.specifiers) {
      if (!specifier.startsWith('.') && !specifier.startsWith('@/')) continue;
      const target = resolveImport(file, specifier);
      if (!target) unresolved.push(`${path} → ${specifier}`);
      else if (!reached.has(target)) queue.push([target, `${path} → ${posix(target)}`]);
    }
  }
  return { reached, unresolved, dynamic };
}

function retiredPresentation(path: string) {
  return ['legacy-styles.ts', 'presentation.ts', 'portal/components/not-rebuilt.tsx'].includes(path)
    || path.endsWith('.css') && !path.startsWith('portal/')
    || path.endsWith('.tsx') && !path.startsWith('portal/') && !path.startsWith('components/ui/') && !['main.tsx', 'BrandSymbol.tsx'].includes(path);
}
function synthetic(path: string) { return path.startsWith('portal/preview/') || path === 'portal/access-preview.tsx'; }

describe('rebuilt portal boundary', () => {
  const production = files(portal).filter(file => !synthetic(posix(file)));
  const roots = {
    'actual main entry': graph([join(client, 'main.tsx')]),
    'all production portal modules': graph(production),
  };

  for (const [label, result] of Object.entries(roots)) {
    it(`${label}: never reaches a retired renderer or stylesheet`, () => {
      expect([...result.reached].filter(([file]) => retiredPresentation(posix(file))).map(([, chain]) => chain)).toEqual([]);
    });
    it(`${label}: never reaches the synthetic preview`, () => {
      expect([...result.reached].filter(([file]) => synthetic(posix(file))).map(([, chain]) => chain)).toEqual([]);
    });
    it(`${label}: every local dependency is resolved and dynamic imports are statically bounded`, () => {
      expect(result.unresolved).toEqual([]);
      expect(result.dynamic).toEqual([]);
    });
  }

  it('routes the real entry to the rebuilt public, account, operator and school surfaces', () => {
    const reached = roots['actual main entry'].reached;
    for (const page of ['entry/entry-page.tsx', 'entry/recovery-page.tsx', 'entry/not-found-page.tsx', 'account/preferences-page.tsx',
      'opening/opening-page.tsx', 'setup/setup-guide.tsx', 'portal-console.tsx', 'pages.tsx']) expect(reached.has(join(portal, page)), page).toBe(true);
  });

  it('physically removes the retired renderers, styles and legacy selector', () => {
    expect(files(client).map(posix).filter(retiredPresentation)).toEqual([]);
  });
});
