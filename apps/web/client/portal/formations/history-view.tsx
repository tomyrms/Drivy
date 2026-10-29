import { useMemo } from 'react';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import type { FormationSheet } from '../../formation-api';
import { programmeName } from '../../console/formation-model';
import { useConsole } from '../../console/context';
import { useReference } from '../pricing/pricing-controllers';
import { ReadFeedback } from './catalogue-ui';
import { dateTime, plural, priceLabel, validity } from './formation-format';
import { ReferenceView } from './reference-view';

function ConsultButton({ id, label, selected, onConsult }: { id: string; label: string; selected: string | undefined; onConsult: (id: string) => void }) {
  return <Button variant="outline" size="sm" aria-pressed={id === selected} aria-label={label} onClick={() => onConsult(id)}>Consulter</Button>;
}

/**
 * Versions enregistrées d'un permis : niveau secondaire. Chaque enregistrement crée une version ; les élèves, leçons et bilans
 * gardent celle qu'ils utilisent. Consulter ne modifie rien.
 */
export function HistoryView({ sheet, selection }: { sheet: FormationSheet; selection: string | undefined }) {
  const { school, setRouteQuery } = useConsole();
  const reference = useReference(selection);
  const consult = (id: string | undefined) => setRouteQuery?.({ category: sheet.categoryCode, view: 'historique', ...(id ? { selection: id } : {}) }, false, true);
  const tariffRows = useMemo(() => sheet.tariffs.flatMap(tariff => tariff.history.map(version => ({ tariff, version }))), [sheet]);
  const detached = sheet.unattached.curricula.length > 0 || sheet.unattached.procedures.length > 0;
  const zone = school.timeZone;
  return <section className="cat-section">
    <h2 className="visually-hidden">Versions enregistrées</h2>
    {selection && <div className="cat-surface cat-consulted">
      <ReadFeedback loaded={reference} label="Lecture de la version" />
      {reference.data && <ReferenceView reference={reference.data} onClose={() => consult(undefined)} />}
    </div>}
    {sheet.programmes.map(programme => <div key={programme.offeringKey} className="cat-history-block">
      <h3>{sheet.programmes.length > 1 ? programmeName(programme, sheet.programmes) : 'Programme'}</h3>
      <ul className="cat-history">{programme.history.map((item, index) => <li key={item.id} data-selected={item.id === selection || undefined}>
        <span className="cat-history-main"><strong>Version {item.version}</strong>{index === 0 && <Badge variant="secondary" className="cat-badge" data-tone="neutral">Actuelle</Badge>}{!item.enabled && <Badge variant="secondary" className="cat-badge" data-tone="neutral">Non proposée</Badge>}</span>
        <span className="cat-muted">{dateTime(item.createdAt, zone)}</span>
        <span className="cat-muted">{item.trainings ? plural(item.trainings, 'élève') : '—'}</span>
        <ConsultButton id={item.id} label={`Consulter la version ${item.version} du programme`} selected={selection} onConsult={consult} />
      </li>)}</ul>
      {programme.historyTruncated && <p className="cat-muted">Seules les 100 dernières versions sont listées.</p>}
    </div>)}
    {tariffRows.length > 0 && <div className="cat-history-block"><h3>Tarifs</h3>
      <ul className="cat-history">{tariffRows.map(({ tariff, version }) => <li key={version.id} data-selected={version.id === selection || undefined}>
        <span className="cat-history-main"><strong>{version.label}</strong><span className="cat-muted">v{version.version}</span>{version.id === tariff.head.id && <Badge variant="secondary" className="cat-badge" data-tone="neutral">Actuelle</Badge>}{!version.enabled && <Badge variant="secondary" className="cat-badge" data-tone="neutral">Non proposé</Badge>}</span>
        <span className="cat-muted">{priceLabel(version.unitPriceCents)} · {validity(version.validFrom, version.validUntil)}</span>
        <span className="cat-muted">{dateTime(version.createdAt, zone)}</span>
        <ConsultButton id={version.id} label={`Consulter la version ${version.version} de ${version.label}`} selected={selection} onConsult={consult} />
      </li>)}</ul></div>}
    {detached && <div className="cat-history-block"><h3>Éléments non rattachés</h3>
      <ul className="cat-history">
        {sheet.unattached.curricula.map(item => <li key={item.id} data-selected={item.id === selection || undefined}><span className="cat-history-main"><strong>Compétences · révision {item.number}</strong></span><span className="cat-muted">{dateTime(item.createdAt, zone)}</span><span /><ConsultButton id={item.id} label={`Consulter la révision ${item.number} des compétences`} selected={selection} onConsult={consult} /></li>)}
        {sheet.unattached.procedures.map(item => <li key={item.id} data-selected={item.id === selection || undefined}><span className="cat-history-main"><strong>Règles · version {item.number}</strong></span><span className="cat-muted">{dateTime(item.createdAt, zone)}</span><span /><ConsultButton id={item.id} label={`Consulter la version ${item.number} des règles`} selected={selection} onConsult={consult} /></li>)}
      </ul></div>}
  </section>;
}
