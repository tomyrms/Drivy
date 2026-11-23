import { useRef, useState } from 'react';
import { request } from '../../protocol';
import { platformDashboardResult, presetRange, type DashboardPreset, type DashboardSituation, type PlatformDashboard } from '../../platform-dashboard-model';

export type DashboardFilters = { query: string; situation: DashboardSituation | null; onlyActions: boolean };
const noFilters: DashboardFilters = { query: '', situation: null, onlyActions: false };

/**
 * Tableau de bord commercial (R01-T10). Sa lecture ne bloque pas la console : un échec reste un échec affiché, jamais des zéros.
 * Période et filtres vivent ici, au-dessus de l'onglet : ils sont retrouvés au retour d'une fiche.
 */
export function usePlatformDashboard() {
  const [preset, setPreset] = useState<DashboardPreset | null>('month');
  const [range, setRange] = useState(() => presetRange('month'));
  const [filters, setFilters] = useState<DashboardFilters>(noFilters);
  const [data, setData] = useState<PlatformDashboard | null>(null);
  const [readAt, setReadAt] = useState<string | null>(null);
  const [status, setStatus] = useState<'idle' | 'loading' | 'ready' | 'failed'>('idle');
  const ticket = useRef(0);

  async function read(next = range) {
    const mine = ++ticket.current;
    setStatus('loading');
    try {
      const result = await request(`platform/dashboard?from=${next.from}&to=${next.to}`, platformDashboardResult);
      if (mine !== ticket.current) return;
      setData(result.data); setReadAt(result.serverTime); setStatus('ready');
    } catch {
      if (mine !== ticket.current) return;
      setData(null); setReadAt(null); setStatus('failed');
    }
  }
  function choosePreset(value: DashboardPreset) { const next = presetRange(value); setPreset(value); setRange(next); void read(next); }
  function chooseRange(next: { from: string; to: string }) {
    setPreset(null); setRange(next);
    if (next.from && next.to && next.from <= next.to) void read(next);
  }
  function reset() { ticket.current += 1; setData(null); setReadAt(null); setStatus('idle'); setFilters(noFilters); setPreset('month'); setRange(presetRange('month')); }
  return { preset, range, filters, setFilters, data, readAt, status, read, choosePreset, chooseRange, reset };
}
export type PlatformDashboardState = ReturnType<typeof usePlatformDashboard>;
