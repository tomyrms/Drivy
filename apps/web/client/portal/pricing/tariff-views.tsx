import { ChevronRight, Pencil } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import type { Tariff, TariffVersion } from '../../formation-api';
import { parseCents } from '../../command-core';
import { tariffStatusBadge, tariffTypeLabels, type TariffDraft } from '../../console/formation-model';
import { useConsole } from '../../console/context';
import { StateBadge } from '../formations/catalogue-ui';
import { dateTime, duration, plural, priceLabel, shortDate, validity } from '../formations/formation-format';
import { statusExplanations, tariffGroups } from './tariff-groups';
import { tariffMarkLabels, wantedValues, type ProjectedTariff, type TariffMark } from './pricing-projection';
import '../formations/formations.css';
import './pricing.css';

const badgeOf = (tariff: Tariff) => tariffStatusBadge(tariff.status, tariff.head, shortDate);
/** Valeurs voulues, avec le même libellé monétaire que le reste du catalogue : un prix absent n'est jamais 0. */
const wantedLine = (draft: TariffDraft) => {
  const wanted = wantedValues(draft);
  return `${priceLabel(wanted.priceCents)} par ${wanted.unitLabel} · ${wanted.enabled ? 'proposé' : 'non proposé'}`;
};
const typeLine = (head: TariffVersion) => [head.label.trim().toLocaleLowerCase('fr') === tariffTypeLabels[head.type].toLocaleLowerCase('fr') ? null : tariffTypeLabels[head.type], head.durationMinutes ? duration(head.durationMinutes) : null].filter(Boolean).join(' · ');
const markBadge = (mark: TariffMark) => ({ tone: 'neutral' as const, label: tariffMarkLabels[mark] });

/**
 * Prix, unité, durée et état effectif lisibles sans ouvrir le détail. Un prix absent n'est jamais affiché comme 0.
 * La marque d'une intention (« Enregistrement en cours », « À confirmer ») est du texte : jamais une couleur seule.
 */
export function TariffRow({ row, onOpen, archived = false }: { row: ProjectedTariff & { tariff: Tariff }; onOpen: (tariff: Tariff) => void; archived?: boolean }) {
  const { tariff, mark } = row;
  return <li>
    <button type="button" className="cat-row cat-tariff-row" data-archived={archived || undefined} onClick={() => onOpen(tariff)}
      aria-label={`Ouvrir le tarif ${tariff.head.label}${mark ? ` · ${tariffMarkLabels[mark]}` : ''}`}>
      <span className="cat-row-main"><strong>{tariff.head.label}</strong><span className="cat-row-meta">{typeLine(tariff.head)}</span></span>
      <span className="cat-row-state"><StateBadge badge={badgeOf(tariff)} />{mark && <StateBadge badge={markBadge(mark)} />}</span>
      <span className="cat-row-offer"><strong>{priceLabel(tariff.head.unitPriceCents)}</strong><span className="cat-row-meta">par {tariff.head.unitLabel}</span></span>
      <ChevronRight aria-hidden="true" className="cat-chevron" />
    </button>
  </li>;
}

/**
 * Une création n'est qu'une ligne provisoire : aucun identifiant de l'école, aucune action, donc rien d'ouvrable ni de réservable
 * avant le reçu. Le prix affiché est la valeur voulue, avec sa marque.
 */
export function ProvisionalTariffRow({ row }: { row: ProjectedTariff }) {
  const wanted = row.wanted;
  if (!wanted) return null;
  const state = row.mark ? tariffMarkLabels[row.mark] : 'Confirmé par l’école';
  return <li>
    <div className="cat-row cat-tariff-row" data-provisional="true" aria-label={`${wanted.label.trim() || 'Nouveau tarif'} · ${state}`}>
      <span className="cat-row-main"><strong>{wanted.label.trim() || 'Nouveau tarif'}</strong><span className="cat-row-meta">{tariffTypeLabels[wanted.type]}</span></span>
      <span className="cat-row-state"><StateBadge badge={{ tone: 'neutral', label: state }} /></span>
      <span className="cat-row-offer"><strong>{priceLabel(parseCents(wanted.price))}</strong><span className="cat-row-meta">par {wanted.unitLabel.trim() || 'unité'}</span></span>
    </div>
  </li>;
}

/** Liste des tarifs telle que la personne la voit : les publiés groupés comme avant, puis les créations provisoires. */
export function TariffList({ rows, onOpen }: { rows: readonly ProjectedTariff[]; onOpen: (tariff: Tariff) => void }) {
  const published = rows.flatMap(row => row.tariff ? [{ row: row as ProjectedTariff & { tariff: Tariff }, tariff: row.tariff }] : []);
  const groups = tariffGroups(published.map(item => item.tariff));
  const rowOf = (tariff: Tariff) => published.find(item => item.tariff.productKey === tariff.productKey)!.row;
  const provisional = rows.filter(row => row.tariff === null);
  return <>
    {groups.current.length > 0 && <ul className="cat-list" aria-label="Tarifs en cours">{groups.current.map(tariff =>
      <TariffRow key={tariff.productKey} row={rowOf(tariff)} onOpen={onOpen} />)}</ul>}
    {provisional.length > 0 && <ul className="cat-list" aria-label="Tarifs en attente de confirmation">{provisional.map(row =>
      <ProvisionalTariffRow key={row.key} row={row} />)}</ul>}
    {groups.archived.length > 0 && <Collapsible className="cat-collapsible cat-archives">
      <CollapsibleTrigger render={<Button variant="ghost" className="cat-collapsible-trigger" />}>Archives ({groups.archived.length})</CollapsibleTrigger>
      <CollapsibleContent><ul className="cat-list" aria-label="Tarifs archivés">{groups.archived.map(tariff =>
        <TariffRow key={tariff.productKey} row={rowOf(tariff)} onOpen={onOpen} archived />)}</ul></CollapsibleContent>
    </Collapsible>}
  </>;
}

/**
 * Fiche d'un tarif : l'essentiel d'abord (prix, unité, durée, état), puis les conditions en lecteur complet et les versions.
 * Les conditions qui engagent le client ne sont jamais cachées derrière une icône. Une intention en cours ne remplace jamais le
 * prix publié : elle s'affiche à côté, avec sa marque, et disparaît avec son résultat.
 */
export function TariffDetail({ tariff, today, canConfigure, busy, blockedReason, pending, onEdit, onToggle, onConsultVersion, onOpenTerms }: {
  tariff: Tariff; today: string; canConfigure: boolean; busy: boolean; blockedReason?: string | null;
  pending: { readonly mark: TariffMark | null; readonly wanted: TariffDraft } | null;
  onEdit: () => void; onToggle: (enabled: boolean) => void; onConsultVersion: (versionId: string) => void; onOpenTerms: (termsId: string) => void;
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
    {pending?.mark && <p className="cat-pending" role="status">{tariffMarkLabels[pending.mark]} · {wantedLine(pending.wanted)}</p>}
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
    {canConfigure && busy && blockedReason && <p className="cat-hint">{blockedReason}</p>}
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
