import { useEffect, useRef } from 'react';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import type { CatalogueReference } from '../../formation-api';
import { useConsole } from '../../console/context';
import { TariffReference } from '../pricing/tariff-reference';
import { dateTime } from './formation-format';
import { CompetencyList, RulesReader } from './programme-read';

/**
 * Contenu exact d'une version enregistrée, avec ses usages réels. Lecture seule : une ancienne version ne se réécrit pas,
 * les élèves, leçons et bilans qui la référencent la gardent.
 */
export function ReferenceView({ reference, onClose }: { reference: CatalogueReference; onClose?: () => void }) {
  const { school, navigate } = useConsole();
  const title = useRef<HTMLHeadingElement>(null);
  useEffect(() => { title.current?.focus({ preventScroll: false }); }, [reference.id]);
  const badge = <Badge variant="secondary" className="cat-badge" data-tone="neutral">{reference.current ? 'Version actuelle' : 'Version précédente'}</Badge>;
  const usage = reference.programmes.length > 0 && <section className="cat-reference-usage"><h3>Utilisé par</h3><ul>{reference.programmes.map(item => <li key={item.offeringKey}>
    <span>{item.label ?? 'Parcours'} · permis {item.categoryCode} · {item.current ? 'version actuelle' : 'version précédente'}</span>
    <Button variant="link" className="cat-inline-link" onClick={() => navigate('formations', { category: item.categoryCode, view: 'general', programme: item.offeringKey })}>Ouvrir le parcours</Button></li>)}</ul></section>;
  const head = (heading: string, meta: string) => <header className="cat-reference-head">
    <div><h2 ref={title} tabIndex={-1}>{heading}</h2><p className="cat-muted">{meta}</p></div>{badge}{onClose && <Button variant="outline" onClick={onClose}>Fermer</Button>}</header>;
  switch (reference.kind) {
    case 'OFFERING': return <article className="cat-reference" aria-label="Version consultée">
      {head(`Programme · version ${reference.offering.version}`, `Enregistrée le ${dateTime(reference.offering.createdAt, school.timeZone)}${reference.offering.label ? ` · ${reference.offering.label}` : ''}${reference.offering.enabled ? '' : ' · non proposée'}`)}
      {reference.curriculum ? <section><h3>Compétences</h3><CompetencyList items={reference.curriculum.competencies} /></section> : <p className="cat-muted">Sans compétences enregistrées.</p>}
      {reference.procedure ? <RulesReader procedure={reference.procedure} /> : <p className="cat-muted">Sans règles enregistrées.</p>}
    </article>;
    case 'CURRICULUM': return <article className="cat-reference" aria-label="Version consultée">
      {head(`Compétences · révision ${reference.curriculum.revision}`, `Enregistrées le ${dateTime(reference.curriculum.createdAt, school.timeZone)}${reference.curriculum.approved ? '' : ' · jamais appliquées'}`)}
      {reference.programmes.length === 0 && <p className="cat-muted">Élément non rattaché à un parcours.</p>}
      <CompetencyList items={reference.curriculum.competencies} />{usage}
    </article>;
    case 'PROCEDURE': return <article className="cat-reference" aria-label="Version consultée">
      {head(`Règles · version ${reference.procedure.version}`, `Enregistrées le ${dateTime(reference.procedure.createdAt, school.timeZone)}${reference.procedure.approved ? '' : ' · jamais appliquées'}`)}
      {reference.programmes.length === 0 && <p className="cat-muted">Élément non rattaché à un parcours.</p>}
      <RulesReader procedure={reference.procedure} />{usage}
    </article>;
    case 'TARIFF': return <TariffReference reference={reference} badge={badge} onClose={onClose} headingRef={title} />;
    case 'TERMS': return <article className="cat-reference" aria-label="Version consultée">
      {head(`${reference.terms.label} · version ${reference.terms.version}`, 'Conditions commerciales')}
      <Button variant="outline" onClick={() => navigate('conditions', { selection: reference.id })}>Ouvrir les conditions</Button>
    </article>;
  }
}
