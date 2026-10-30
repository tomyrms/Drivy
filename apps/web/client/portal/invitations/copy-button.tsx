import { useEffect, useRef, useState } from 'react';
import { Check, Copy, TriangleAlert } from 'lucide-react';
import { Button } from '../../components/ui/button';

/** Clipboard API first; a temporary selection when the browser refuses it (insecure page, missing permission). */
async function copyText(value: string): Promise<boolean> {
  try { await navigator.clipboard.writeText(value); return true; } catch { /* try the selection below */ }
  const opener = document.activeElement;
  const area = document.createElement('textarea');
  area.value = value; area.readOnly = true; area.style.position = 'fixed'; area.style.opacity = '0';
  document.body.append(area); area.select();
  try { return document.execCommand('copy'); } catch { return false; }
  finally { area.remove(); if (opener instanceof HTMLElement) opener.focus(); }
}

/**
 * Explicit copy of a secret the person asked for. The value goes to the clipboard only; the confirmation
 * is announced and fades, and nothing here stores or logs the value.
 */
export function CopyButton({ value, label, variant = 'outline' }: { value: string; label: string; variant?: 'outline' | 'default' }) {
  const [state, setState] = useState<'idle' | 'copied' | 'failed'>('idle');
  const timer = useRef<number | undefined>(undefined);
  useEffect(() => () => window.clearTimeout(timer.current), []);
  async function copy() {
    setState(await copyText(value) ? 'copied' : 'failed');
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setState('idle'), 2500);
  }
  const Icon = state === 'copied' ? Check : state === 'failed' ? TriangleAlert : Copy;
  return <>
    <Button type="button" variant={variant} onClick={() => void copy()}><Icon aria-hidden="true" />{state === 'copied' ? 'Copié' : state === 'failed' ? 'Copie impossible' : label}</Button>
    <span className="visually-hidden" role="status">{state === 'copied' ? 'Copié' : state === 'failed' ? 'Copie impossible' : ''}</span>
  </>;
}
