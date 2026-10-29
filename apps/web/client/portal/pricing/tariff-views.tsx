import { ChevronRight, Pencil } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import type { Tariff, TariffVersion } from '../../formation-api';
import { tariffStatusBadge, tariffTypeLabels } from '../../console/formation-model';
import { useConsole } from '../../console/context';
import { StateBadge } from '../formations/catalogue-ui';
import { dateTime, duration, plural, priceLabel, shortDate, validity } from '../formations/formation-format';
import { statusExplanations } from './tariff-groups';
import '../formations/formations.css';
import './pricing.css';

const badgeOf = (tariff: Tariff) => tariffStatusBadge(tariff.status, tariff.head, shortDate);
const typeLine = (head: TariffVersion) => [head.label.trim().toLocaleLowerCase('fr') === tariffTypeLabels[head.type].toLocaleLowerCase('fr') ? null : tariffTypeLabels[head.type], head.durationMinutes ? duration(head.durationMinutes) : null].filter(Boolean).join(' · ');

/** Prix, unité, durée et état effectif lisibles sans ouvrir le détail. Un prix absent n'est jamais affiché comme 0. */
export function TariffRow({ tariff, onOpen, archived = false }: { tariff: Tariff; onOpen: () => void; archived?: boolean }) {
  return <li>
    <button type="button" className="cat-row cat-tariff-row" data-archived={archived || undefined} onClick={onOpen} aria-label={`Ouvrir le tarif ${tariff.head.label}`}>
      <span className="cat-row-main"><strong>{tariff.head.label}</strong><span className="cat-row-meta">{typeLine(tariff.head)}</span></span>
      <span className="cat-row-state"><StateBadge badge={badgeOf(tariff)} /></span>
      <span className="cat-row-offer"><strong>{priceLabel(tariff.head.unitPriceCents)}</strong><span className="cat-row-meta">par {tariff.head.unitLabel}</span></span>
      <ChevronRight aria-hidden="true" className="cat-chevron" />
    </button>
  </li>;
}

export function TariffList({ current, archived, onOpen }: { current: readonly Tariff[]; archived: readonly Tariff[]; onOpen: (tariff: Tariff) => void }) {
  return <>
    {current.length > 0 && <ul className="cat-list" aria-label="Tarifs en cours">{current.map(tariff => <TariffRow key={tariff.productKey} tariff={tariff} onOpen={() => onOpen(tariff)} />)}</ul>}
    {archived.length > 0 && <Collapsible className="cat-collapsible cat-archives">
      <CollapsibleTrigger render={<Button variant="ghost" className="cat-collapsible-trigger" />}>Archives ({archived.length})</CollapsibleTrigger>
      <CollapsibleContent><ul className="cat-list" aria-label="Tarifs archivés">{archived.map(tariff => <TariffRow key={tariff.productKey} tariff={tariff} archived onOpen={() => onOpen(tariff)} />)}</ul></CollapsibleContent>
    </Collapsible>}
  </>;
}

/**
 * Fiche d'un tarif : l'essentiel d'abord (prix, unité, durée, état), puis les conditions en lecteur complet et les versions.
 * Les conditions qui engagent le client ne sont jamais cachées derrière une icône.
 */
export function TariffDetail({ tariff, today, canConfigure, busy, onEdit, onToggle, onConsultVersion, onOpenTerms }: {
  tariff: Tariff; today: string; canConfigure: boolean; busy: boolean; onEdit: () => void; onToggle: (enabled: boolean) => void;
  onConsultVersion: (versionId: string) => void; onOpenTerms: (termsId: string) => void;
}) {
  const { school } = useConsole();
  const { head } = tariff, note = statusExplanations[tariff.status];
  // Une fin de validité déjà passée se corrige par « Modifier le tarif », pas par une simple réactivation.
  const reactivatable = tariff.status === 'DISABLED' && (head.validUntil === null || head.validUntil >= today);
  return <article className="cat-tariff-detail" aria-label={head.label}>
    <header className="cat-detail-head">
      <div><h2 tabIndex={-1} id="cat-tariff-title">{head.label}</h2><p className="cat-muted">{typeLine(head)}</p></div>
      <StateBadge badge={badgeOf(tariff)} />
    </header>
    <p className="cat-price"><strong>{priceLabel(head.unitPriceCents)}</strong><span>par {head.unitLabel}</span></p>
    {note && <p className="cat-muted">{note}</p>}
    <dl className="cat-facts">
      <div><dt>Valable</dt><dd>{validity(head.validFrom, head.validUntil)}</dd></div>
      <div><dt>Réservations</dt><dd>{head.enabled ? 'Proposé' : 'Non proposé'}</dd></div>
    </dl>
    {canConfigure && <div className="cat-detail-actions">
      <Button variant="outline" disabled={busy} onClick={onEdit}><Pencil data-icon="inline-start" />Modifier le tarif</Button>
      {head.enabled ? <Button variant="ghost" disabled={busy} onClick={() => onToggle(false)}>Ne plus proposer</Button>
        : reactivatable ? <Button variant="ghost" disabled={busy} onClick={() => onToggle(true)}>Proposer à nouveau</Button> : null}
    </div>}
    <section className="cat-detail-section"><h3>Conditions commerciales</h3>
      {tariff.terms ? <p className="cat-reader">{tariff.terms.termsText}</p> : <p className="cat-muted">Ces conditions ne sont pas visibles avec vos accès.</p>}
      {tariff.terms && tariff.termsSharedWith > 0 && <p className="cat-muted">Conditions communes à {plural(tariff.termsSharedWith, 'autre tarif')}. <Button variant="link" className="cat-inline-link" onClick={() => onOpenTerms(head.termsVersionId)}>Voir les conditions communes</Button></p>}
    </section>
    {tariff.history.length > 1 && <Collapsible className="cat-collapsible">
      <CollapsibleTrigger render={<Button variant="ghost" className="cat-collapsible-trigger" />}>Versions ({tariff.history.length})</CollapsibleTrigger>
      <CollapsibleContent><ul className="cat-history">{tariff.history.map(version => <li key={version.id}>
        <span className="cat-history-main"><strong>v{version.version}</strong>{version.id === head.id && <span className="cat-muted">actuelle</span>}</span>
        <span className="cat-muted">{priceLabel(version.unitPriceCents)} · {validity(version.validFrom, version.validUntil)}</span>
        <span className="cat-muted">{dateTime(version.createdAt, school.timeZone)}</span>
        <Button variant="outline" size="sm" aria-label={`Consulter la version ${version.version} de ${head.label}`} onClick={() => onConsultVersion(version.id)}>Consulter</Button>
      </li>)}</ul>{tariff.historyTruncated && <p className="cat-muted">Seules les 100 dernières versions sont listées.</p>}</CollapsibleContent>
    </Collapsible>}
  </article>;
}
