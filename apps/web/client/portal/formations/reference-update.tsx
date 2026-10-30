import { RefreshCw } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import type { Programme } from '../../formation-api';
import { ReadFeedback, ReviewDialog } from './catalogue-ui';
import type { CatalogueCommand } from './catalogue-command';
import { useReferenceUpdate } from './formation-controllers';
import { civilDate, plural } from './formation-format';
import { CompetencyList } from './programme-read';

const changeKinds = { EDITORIAL: 'Correction rédactionnelle', PEDAGOGICAL: 'Amélioration pédagogique', REGULATORY: 'Évolution réglementaire' } as const;

/**
 * Mise à jour proposée à la demande. Seules les compétences dont la clé est absente sont ajoutées, à la suite des vôtres :
 * aucune formulation ni aucun ordre de l'école n'est écrasé, et les élèves déjà inscrits gardent leur programme.
 * La référence est une proposition pédagogique, pas une certification officielle.
 */
export function ReferenceUpdate({ programme, categoryCode, canConfigure, command, reload }: {
  programme: Programme; categoryCode: string; canConfigure: boolean; command: CatalogueCommand; reload: () => void;
}) {
  const update = useReferenceUpdate(programme, categoryCode, command);
  const { template, diff } = update;
  return <>
    <Button variant="outline" onClick={() => { command.runner.clearOutcome(); update.setOpen(true); }}><RefreshCw data-icon="inline-start" />Mettre à jour depuis la référence</Button>
    <ReviewDialog open={update.open} title={`Référence du permis ${categoryCode}`} runner={command.runner} busy={command.busy}
      confirmLabel={diff && diff.additions.length > 0 ? `Ajouter ${plural(diff.additions.length, 'compétence')}` : 'Ajouter'}
      disabled={!canConfigure || update.loaded.status !== 'ready' || !diff?.canApply} onClose={() => update.setOpen(false)} onConfirm={() => void update.apply(reload)}>
      <ReadFeedback loaded={update.loaded} label="Lecture de la référence" />
      {update.loaded.status === 'ready' && (!template || !diff
        ? <p className="cat-muted">Aucune référence n’est disponible pour ce permis.</p>
        : <div className="cat-update">
          <p className="cat-muted">Programme actuel : révision {programme.curriculum?.revision ?? '—'} · Référence Drivy : version {template.version}{template.verifiedOn ? ` · sources consultées le ${civilDate(template.verifiedOn)}` : ''}</p>
          {template.qualification === 'NOT_QUALIFIED' && <Alert><AlertTitle>Couverture réglementaire à qualifier</AlertTitle>{template.coverageNote && <AlertDescription>{template.coverageNote}</AlertDescription>}</Alert>}
          {template.change && <p><strong>{changeKinds[template.change.kind]}</strong>{template.change.effectiveFrom ? ` · dès le ${civilDate(template.change.effectiveFrom)}` : ''} · {template.change.summary}</p>}
          {diff.additions.length === 0
            ? <p>Votre programme contient déjà toutes les compétences de la référence.</p>
            : <section><h3>{plural(diff.additions.length, 'compétence')} à ajouter</h3><CompetencyList items={diff.additions} /></section>}
          {diff.differences.length > 0 && <Collapsible className="cat-collapsible">
            <CollapsibleTrigger render={<Button variant="ghost" className="cat-collapsible-trigger" />}>{plural(diff.differences.length, 'formulation différente conservée', 'formulations différentes conservées')}</CollapsibleTrigger>
            <CollapsibleContent><ul className="cat-compare">{diff.differences.map(({ previous, proposed }) => <li key={previous.key}>
              <p><span>École</span><strong>{previous.label}</strong> {previous.description}</p><p><span>Référence</span><strong>{proposed.label}</strong> {proposed.description}</p></li>)}</ul></CollapsibleContent>
          </Collapsible>}
          {diff.collisions.length > 0 && <Alert variant="destructive"><AlertTitle>Correspondance à vérifier</AlertTitle><AlertDescription>Une compétence proposée porte déjà le nom d’une compétence de l’école sous une autre référence. Les ajouts restent suspendus pour éviter un doublon.</AlertDescription></Alert>}
          {diff.additions.length > 0 && !diff.canApply && diff.collisions.length === 0 && <p className="cat-muted">Cette évolution n’est pas appliquée automatiquement : modifiez les compétences depuis leur éditeur.</p>}
          {template.sourceUrls && template.sourceUrls.length > 0 && <Collapsible className="cat-collapsible">
            <CollapsibleTrigger render={<Button variant="ghost" className="cat-collapsible-trigger" />}>Sources et portée</CollapsibleTrigger>
            <CollapsibleContent><p className="cat-muted">Proposition pédagogique, sans certification officielle. {template.change?.application}</p>
              <ul className="cat-sources">{template.sourceUrls.map(url => <li key={url}><a href={url} target="_blank" rel="noreferrer noopener">{new URL(url).hostname}</a></li>)}</ul></CollapsibleContent>
          </Collapsible>}
          <p className="cat-muted">Les compétences ajoutées s’appliquent aux nouvelles inscriptions. Les élèves déjà inscrits, leurs leçons et leurs évaluations gardent leur programme actuel.</p>
        </div>)}
    </ReviewDialog>
  </>;
}
