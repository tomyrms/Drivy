/**
 * Pictogrammes des thèmes de signalement : `client/assets/observation-themes/<clé>.svg` (fill="currentColor"),
 * chargés à la compilation. Un fichier absent donne un repère neutre : la liste et l'aperçu restent complets.
 */
const files = import.meta.glob<string>('../assets/observation-themes/*.svg', { query: '?raw', import: 'default', eager: true });

const icons = new Map<string, string>();
for (const [path, source] of Object.entries(files)) {
  const name = path.split('/').pop()?.replace(/\.svg$/, '');
  // Fichiers du dépôt, jamais du contenu saisi : on écarte tout de même ce qui ne ressemble pas à un pictogramme.
  if (name && /^\s*(?:<\?xml[^>]*>\s*)?<svg[\s>]/i.test(source) && !/<script|\son\w+\s*=/i.test(source)) icons.set(name, source);
}

export const hasThemeIcon = (key: string): boolean => icons.has(key);

export function ThemeIcon({ themeKey }: { themeKey: string }) {
  const source = icons.get(themeKey);
  if (source) return <span className="theme-icon" aria-hidden="true" dangerouslySetInnerHTML={{ __html: source }} />;
  return <span className="theme-icon is-fallback" aria-hidden="true">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="4" y="4" width="16" height="16" rx="4" /></svg>
  </span>;
}
