import { useSyncExternalStore } from 'react';

export type ThemePreference = 'light' | 'dark' | 'system';
export const themeStorageKey = 'drivy.web.theme';
export function parseTheme(value: unknown): ThemePreference {
  return value === 'light' || value === 'dark' ? value : 'system';
}
export function resolveTheme(preference: ThemePreference, systemDark: boolean): 'light' | 'dark' {
  return preference === 'system' ? systemDark ? 'dark' : 'light' : preference;
}
const listeners = new Set<() => void>();
let preference: ThemePreference = 'system';
let storageError = false;
const media = typeof window !== 'undefined' ? window.matchMedia('(prefers-color-scheme: dark)') : null;
if (typeof window !== 'undefined') {
  try { preference = parseTheme(window.localStorage.getItem(themeStorageKey)); } catch { /* Nothing persisted. */ }
}
function apply() {
  if (typeof document === 'undefined') return;
  const effective = resolveTheme(preference, media?.matches ?? false);
  document.documentElement.dataset.theme = effective;
  document.documentElement.dataset.themePreference = preference;
  document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]').forEach(meta => {
    meta.removeAttribute('media'); meta.content = effective === 'dark' ? '#191b1e' : '#f2f4f7';
  });
}
function emit() { apply(); listeners.forEach(listener => listener()); }
media?.addEventListener('change', () => { if (preference === 'system') emit(); });
if (typeof window !== 'undefined') window.addEventListener('storage', event => {
  if (event.key !== themeStorageKey && event.key !== null) return;
  preference = parseTheme(event.newValue); storageError = false; emit();
});
apply();
export function setTheme(next: ThemePreference) {
  preference = next; storageError = false;
  try { window.localStorage.setItem(themeStorageKey, next); } catch { storageError = true; }
  emit();
}
function subscribe(listener: () => void) { listeners.add(listener); return () => { listeners.delete(listener); }; }
export function useTheme() {
  useSyncExternalStore(subscribe, () => `${preference}/${media?.matches}/${storageError}`, () => 'system/false/false');
  return { preference, effective: resolveTheme(preference, media?.matches ?? false), storageError, setTheme };
}
