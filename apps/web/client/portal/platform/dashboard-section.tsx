import { useMemo } from 'react';
import { Search } from 'lucide-react';
import { chf } from '../../platform-model';
import {
  actionLabel, dashboardPresets, dashboardSituations, situationLabel, type PlatformDashboard, type PlatformDashboardClient,
} from '../../platform-dashboard-model';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Input } from '../../components/ui/input';
import { Skeleton } from '../../components/ui/skeleton';
import type { PlatformDashboardState } from './use-platform-dashboard';

const shortDay = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(`${value}T00:00:00Z`));
const clock = (value: string) => new Intl.DateTimeFormat('fr-CH', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Europe/Zurich' }).format(new Date(value));
const urgent = new Set(['SUSPENSION_UPCOMING', 'OVERDUE', 'DELIVERY_FAILED']);

function monthlyText(client: PlatformDashboardClient) {
  if (client.monthlyState === 'MISSING') return 'À compléter';
  if (client.monthlyState === 'PAUSED') return 'En pause';
  return client.monthly === null ? '—' : chf(client.monthly);
}

function Ledger({ data }: { data: PlatformDashboard }) {
  const { totals } = data;
  const notes = [totals.monthlyMissing > 0 ? `${totals.monthlyMissing} à compléter` : null, totals.monthlyPaused > 0 ? `${totals.monthlyPaused} en pause` : null].filter(Boolean).join(' · ');
  return <div className="platform-ledger">
    <section aria-label="Sur la période"><h3>{shortDay(data.from)} – {shortDay(data.to)}</h3><dl>
      <div><dt>Facturé</dt><dd>{chf(totals.invoiced)}</dd></div>
      <div><dt>Avoirs</dt><dd>{chf(totals.credited)}</dd></div>
      <div><dt>Encaissé</dt><dd>{chf(totals.collected)}</dd></div>
      <div><dt>Régularisé</dt><dd>{chf(totals.regularized)}</dd></div>
    </dl></section>
    <section aria-label="Aujourd’hui"><h3>Au {shortDay(data.today)}</h3><dl>
      <div><dt>Restant dû</dt><dd>{chf(totals.outstanding)}</dd></div>
      <div><dt>En retard</dt><dd>{chf(totals.overdue)}</dd></div>
      <div><dt>Revenu mensuel</dt><dd>{chf(totals.monthly)}{notes && <small>{notes}</small>}</dd></div>
    </dl></section>
    <section aria-label="Échéances à 30 jours"><h3>D’ici le {shortDay(data.horizonOn)}</h3><dl>
      <div><dt>Renouvellements</dt><dd>{totals.renewalsSoon}</dd></div>
      <div><dt>Fins d’essai</dt><dd>{totals.trialsEndingSoon}</dd></div>
      <div><dt>À traiter</dt><dd>{totals.withActions}</dd></div>
    </dl></section>
  </div>;
}

export function DashboardSection({ dashboard, busy, openClient }: { dashboard: PlatformDashboardState; busy: boolean; openClient: (id: string) => void }) {
  const { data, filters, setFilters, range, status } = dashboard;
  const rangeInvalid = !range.from || !range.to || range.from > range.to;
  const rows = useMemo(() => {
    const needle = filters.query.trim().toLocaleLowerCase('fr');
    return (data?.clients ?? []).filter(item => (!filters.situation || item.situation === filters.situation)
      && (!filters.onlyActions || item.actions.length > 0) && (!needle || item.name.toLocaleLowerCase('fr').includes(needle)));
  }, [data, filters]);
  const shown = useMemo(() => rows.reduce((sum, item) => ({ invoiced: sum.invoiced + item.invoiced, collected: sum.collected + item.collected, outstanding: sum.outstanding + item.outstanding }),
    { invoiced: 0, collected: 0, outstanding: 0 }), [rows]);
  const filtered = filters.situation !== null || filters.onlyActions || filters.query.trim() !== '';

  return <div className="platform-dashboard">
    <div className="platform-dashboard-period">
      <div role="group" aria-label="Période">
        {dashboardPresets.map(item => <Button key={item.value} size="sm" variant={dashboard.preset === item.value ? 'secondary' : 'ghost'} aria-pressed={dashboard.preset === item.value}
          onClick={() => dashboard.choosePreset(item.value)}>{item.label}</Button>)}
      </div>
      <div className="platform-dashboard-dates">
        <Input type="date" aria-label="Début de la période" aria-invalid={rangeInvalid} value={range.from} onChange={event => dashboard.chooseRange({ ...range, from: event.target.value })} />
        <Input type="date" aria-label="Fin de la période" aria-invalid={rangeInvalid} value={range.to} onChange={event => dashboard.chooseRange({ ...range, to: event.target.value })} />
      </div>
      {dashboard.readAt && <span className="platform-count" role="status">Calculé le {clock(dashboard.readAt)}</span>}
    </div>
    {rangeInvalid && <p className="platform-dashboard-error" role="alert">La fin de la période doit suivre son début.</p>}
    {status === 'failed' && <Alert variant="destructive"><AlertTitle>Tableau de bord indisponible</AlertTitle><AlertDescription>Les montants n’ont pas pu être calculés.</AlertDescription>
      <Button variant="outline" className="mt-3" disabled={busy} onClick={() => void dashboard.read()}>Réessayer</Button></Alert>}
    {!data && (status === 'loading' || status === 'idle') && <div className="grid gap-3" role="status" aria-label="Chargement du tableau de bord"><Skeleton className="h-28 w-full" /><Skeleton className="h-48 w-full" /></div>}
    {data && <>
      <Ledger data={data} />
      <div className="platform-dashboard-filters">
        <div role="group" aria-label="Situation">
          <Button size="sm" variant={filters.situation === null ? 'secondary' : 'ghost'} aria-pressed={filters.situation === null} onClick={() => setFilters({ ...filters, situation: null })}>Toutes {data.totals.clients}</Button>
          {dashboardSituations.map(key => <Button key={key} size="sm" variant={filters.situation === key ? 'secondary' : 'ghost'} aria-pressed={filters.situation === key}
            onClick={() => setFilters({ ...filters, situation: key })}>{situationLabel(key)} {data.situations[key]}</Button>)}
        </div>
        <div className="platform-dashboard-search">
          <Search aria-hidden="true" />
          <Input type="search" aria-label="Rechercher une école" placeholder="Rechercher" value={filters.query} onChange={event => setFilters({ ...filters, query: event.target.value })} />
          <Button size="sm" variant={filters.onlyActions ? 'secondary' : 'outline'} aria-pressed={filters.onlyActions} onClick={() => setFilters({ ...filters, onlyActions: !filters.onlyActions })}>À traiter</Button>
        </div>
      </div>
      {data.truncated && <p className="platform-dashboard-error" role="alert">Seules les 500 premières écoles sont listées. Les totaux portent sur toutes.</p>}
      {rows.length === 0 ? <p className="platform-count" role="status">{data.totals.clients === 0 ? 'Aucune école.' : 'Aucune école pour ces filtres.'}</p>
        : <ul className="platform-dashboard-list">{rows.map(item => <li key={item.id}>
          <button type="button" disabled={busy} onClick={() => openClient(item.id)}>
            <span className="platform-dashboard-name"><strong>{item.name}</strong><span>{situationLabel(item.situation)}</span></span>
            <span className="platform-dashboard-actions">{item.actions.map(action => <Badge key={`${action.kind}:${action.codes.join()}`} variant={urgent.has(action.kind) ? 'destructive' : 'outline'}>
              {actionLabel(action)}{action.onDate ? ` · ${shortDay(action.onDate)}` : ''}</Badge>)}</span>
            <span className="platform-dashboard-figures">
              <span><small>Facturé</small>{chf(item.invoiced)}</span><span><small>Encaissé</small>{chf(item.collected)}</span>
              <span><small>Dû</small>{chf(item.outstanding)}</span><span><small>Mensuel</small>{monthlyText(item)}</span>
            </span>
          </button>
        </li>)}</ul>}
      {filtered && rows.length > 0 && <p className="platform-count" role="status">{rows.length} sur {data.clients.length} · facturé {chf(shown.invoiced)} · encaissé {chf(shown.collected)} · dû {chf(shown.outstanding)}</p>}
    </>}
  </div>;
}
