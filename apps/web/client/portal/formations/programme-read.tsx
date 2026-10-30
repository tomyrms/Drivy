import { ExternalLink } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { Badge } from '../../components/ui/badge';
import type { FormationSheet, Programme } from '../../formation-api';
import { useConsole } from '../../console/context';
import { dateTime, duration, plural, priceLabel } from './formation-format';

/** Compétences enseignées, dans l'ordre enregistré : une liste à lire, pas un formulaire. */
export function CompetencyList({ items }: { items: readonly { id?: string; key: string; label: string; description: string }[] }) {
  return <ol className="cat-numbered">{items.map((item, index) => <li key={item.id ?? `${item.key}-${index}`}>
    <span className="cat-number" aria-hidden="true">{index + 1}</span>
    <div><h3>{item.label}</h3><p>{item.description}</p></div>
  </li>)}</ol>;
}

/** Déroulement et annulation en lecteur confortable ; les sources sont un détail secondaire. */
export function RulesReader({ procedure }: { procedure: { procedureText: string; cancellationPolicyText: string; sourceUrls: readonly string[] } }) {
  return <div className="cat-rules">
    <section><h3>Déroulement d’une leçon</h3><p className="cat-reader">{procedure.procedureText}</p></section>
    <section><h3>Conditions d’annulation</h3><p className="cat-reader">{procedure.cancellationPolicyText}</p></section>
    {procedure.sourceUrls.length > 0 && <Collapsible className="cat-collapsible">
      <CollapsibleTrigger render={<Button variant="ghost" className="cat-collapsible-trigger" />}>Sources ({procedure.sourceUrls.length})</CollapsibleTrigger>
      <CollapsibleContent><ul className="cat-sources">{procedure.sourceUrls.map(url => <li key={url}><a href={url} target="_blank" rel="noreferrer noopener">{url}<ExternalLink aria-hidden="true" /></a></li>)}</ul></CollapsibleContent>
    </Collapsible>}
  </div>;
}

/**
 * Comprendre l'offre d'un parcours : ce qui est proposé, la durée, ce que paie l'élève, qui est inscrit.
 * Le prix vient des tarifs de leçon du permis ; un parcours sans tarif ne se voit attribuer aucun prix.
 */
export function ProgrammeOverview({ sheet, programme, onTariffs, onHistory }: { sheet: FormationSheet; programme: Programme; onTariffs: () => void; onHistory: () => void }) {
  const { school } = useConsole();
  const lessons = sheet.tariffs.filter(item => item.head.type === 'INDIVIDUAL_LESSON' && ['OFFERED', 'NOT_YET', 'TERMS_NOT_YET'].includes(item.status));
  const enrolled = programme.enrollments.current + programme.enrollments.previous;
  return <dl className="cat-facts">
    <div><dt>Nouvelles inscriptions</dt><dd>{programme.head.enabled ? 'Proposé' : <Badge variant="secondary" className="cat-badge" data-tone="neutral">Non proposé</Badge>}</dd></div>
    <div><dt>Durée habituelle</dt><dd>{duration(programme.head.defaultDurationMinutes)}</dd></div>
    <div><dt>Prix d’une leçon</dt><dd>{lessons.length === 0 ? <span className="cat-muted">Aucun tarif de leçon</span> : <ul className="cat-fact-list">{lessons.map(item => <li key={item.productKey}>
      <strong>{priceLabel(item.head.unitPriceCents)}</strong><span className="cat-muted">{[item.head.durationMinutes ? duration(item.head.durationMinutes) : null, item.status !== 'OFFERED' ? 'à venir' : null].filter(Boolean).join(' · ')}</span></li>)}</ul>}
      <Button variant="link" className="cat-inline-link" onClick={onTariffs}>Voir les tarifs</Button></dd></div>
    {!programme.head.hasReferencePrice && <div><dt>Prix de référence</dt><dd><span className="cat-muted">Non défini</span></dd></div>}
    <div><dt>Élèves en formation</dt><dd>{enrolled === 0 ? 'Aucun' : [programme.enrollments.current ? `${plural(programme.enrollments.current, 'élève')} sur la version actuelle` : null,
      programme.enrollments.previous ? `${plural(programme.enrollments.previous, 'élève')} sur une version précédente` : null].filter(Boolean).join(' · ')}</dd></div>
    <div><dt>Dernière modification</dt><dd>{dateTime(programme.head.createdAt, school.timeZone)}<Button variant="link" className="cat-inline-link" onClick={onHistory}>Historique</Button></dd></div>
  </dl>;
}
