import type { ReactNode, RefObject } from 'react';
import { Button } from '../../components/ui/button';
import type { CatalogueReference } from '../../formation-api';
import { tariffStatusBadge, tariffTypeLabels } from '../../console/formation-model';
import { useConsole } from '../../console/context';
import { StateBadge } from '../formations/catalogue-ui';
import { dateTime, duration, priceLabel, shortDate, validity } from '../formations/formation-format';

/** Une version de tarif telle qu'elle était : les réservations faites avec elle gardent ce prix et ces conditions. */
export function TariffReference({ reference, badge, onClose, headingRef }: {
  reference: Extract<CatalogueReference, { kind: 'TARIFF' }>; badge: ReactNode; onClose: (() => void) | undefined; headingRef: RefObject<HTMLHeadingElement | null>;
}) {
  const { school } = useConsole();
  const { tariff } = reference;
  const state = reference.current ? tariffStatusBadge(reference.status, tariff, shortDate) : null;
  return <article className="cat-reference" aria-label="Version consultée">
    <header className="cat-reference-head">
      <div><h2 ref={headingRef} tabIndex={-1}>{tariff.label} · version {tariff.version}</h2><p className="cat-muted">Enregistré le {dateTime(tariff.createdAt, school.timeZone)}</p></div>
      {badge}{state && <StateBadge badge={state} />}{onClose && <Button variant="outline" onClick={onClose}>Fermer</Button>}
    </header>
    <p className="cat-price"><strong>{priceLabel(tariff.unitPriceCents)}</strong><span>par {tariff.unitLabel}</span></p>
    <dl className="cat-facts">
      <div><dt>Type</dt><dd>{tariffTypeLabels[tariff.type]}</dd></div>
      {tariff.durationMinutes && <div><dt>Durée</dt><dd>{duration(tariff.durationMinutes)}</dd></div>}
      <div><dt>Valable</dt><dd>{validity(tariff.validFrom, tariff.validUntil)}</dd></div>
    </dl>
    <section className="cat-detail-section"><h3>Conditions commerciales</h3>
      {reference.terms ? <p className="cat-reader">{reference.terms.termsText}</p> : <p className="cat-muted">Non visibles avec vos accès.</p>}</section>
    <p className="cat-muted">Les réservations faites avec cette version gardent ce prix et ces conditions.</p>
  </article>;
}
