/**
 * Observation theme pictograms from `client/assets/observation-themes/<key>.svg` (fill="currentColor"), bundled at build time.
 * A missing file gives a neutral mark so the list and the preview stay complete.
 */
const files = import.meta.glob<string>('../../assets/observation-themes/*.svg', { query: '?raw', import: 'default', eager: true });

const icons = new Map<string, string>();
for (const [path, source] of Object.entries(files)) {
  const name = path.split('/').pop()?.replace(/\.svg$/, '');
  // Repository files, never user content; anything that does not look like a pictogram is still discarded.
  if (name && /^\s*(?:<\?xml[^>]*>\s*)?<svg[\s>]/i.test(source) && !/<script|\son\w+\s*=/i.test(source)) icons.set(name, source);
}

export function ThemeIcon({ themeKey }: { themeKey: string }) {
  const source = icons.get(themeKey);
  if (source) return <span className="signals-icon" aria-hidden="true" dangerouslySetInnerHTML={{ __html: source }} />;
  return <span className="signals-icon" aria-hidden="true">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="4" y="4" width="16" height="16" rx="4" /></svg>
  </span>;
}
