import { ChevronRight, Plus, ReceiptText, Search, BookOpen } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { categoryBadge } from '../../console/formation-model';
import { useConsole } from '../../console/context';
import { PermitMark, ReadFeedback, StateBadge } from './catalogue-ui';
import { useCatalogueList } from './formation-controllers';
import { duration, plural, priceLabel } from './formation-format';

/** Catalogue : les permis que l'école prépare, pas une table de paramètres. Un clic ouvre la fiche du permis. */
export function PermitList() {
  const { navigate } = useConsole();
  const state = useCatalogueList();
  const data = state.loaded.data;
  const prepare = (category?: string) => navigate('apercu', { from: 'formations', ...(category ? { category } : {}) });
  return <section className="cat-page">
    <header className="cat-heading">
      <h1 tabIndex={-1}>Formations</h1>
      {data && <div className="cat-heading-actions">
        <Button disabled={!data.canConfigureCatalog} onClick={() => prepare()} aria-describedby={data.canConfigureCatalog ? undefined : 'cat-prepare-right'}><Plus data-icon="inline-start" />Préparer un permis</Button>
      </div>}
    </header>
    {data && !data.canConfigureCatalog && <p className="cat-hint" id="cat-prepare-right">L’autorisation de configurer les tarifs est nécessaire pour préparer un permis.</p>}
    <ReadFeedback loaded={state.loaded} label="Lecture des formations" />
    {data && (data.categories.length === 0
      ? <Empty className="cat-empty"><EmptyHeader><EmptyMedia variant="icon"><BookOpen /></EmptyMedia><EmptyTitle>Aucun permis préparé</EmptyTitle>
          <EmptyDescription>Préparez le premier permis enseigné par l’école.</EmptyDescription></EmptyHeader>
          {data.canConfigureCatalog && <EmptyContent><Button onClick={() => prepare()}>Préparer un permis</Button></EmptyContent>}</Empty>
      : <>
        <div className="cat-toolbar">
          <Field className="cat-search"><FieldLabel className="sr-only" htmlFor="cat-search">Rechercher un permis</FieldLabel><Search aria-hidden="true" />
            <Input id="cat-search" type="search" placeholder="Rechercher un permis" value={state.search} onChange={event => state.setSearch(event.target.value)} /></Field>
          <span className="cat-count" role="status">{state.categories.length === data.categories.length ? plural(data.categories.length, 'permis', 'permis') : `${state.categories.length} sur ${data.categories.length}`}</span>
        </div>
        {state.categories.length === 0
          ? <Empty className="cat-empty"><EmptyHeader><EmptyTitle>Aucun permis trouvé</EmptyTitle></EmptyHeader><EmptyContent><Button variant="outline" onClick={() => state.setSearch('')}>Effacer la recherche</Button></EmptyContent></Empty>
          : <ul className="cat-list" aria-label="Permis préparés par l’école">{state.categories.map(item => {
            const lesson = item.lessonTariffs[0], more = item.lessonTariffs.length - 1;
            return <li key={item.categoryCode}>
              <button type="button" className="cat-row" onClick={() => navigate('formations', { category: item.categoryCode })}>
                <PermitMark code={item.categoryCode} />
                <span className="cat-row-main">
                  <strong>Permis {item.categoryCode}</strong>
                  <span className="cat-row-meta">{[item.competencyCounts.length === 1 ? plural(item.competencyCounts[0]!, 'compétence') : item.competencyCounts.length > 1 ? `${item.competencyCounts.length} parcours` : null,
                    plural(item.tariffCount, 'tarif')].filter(Boolean).join(' · ')}</span>
                </span>
                <span className="cat-row-offer">{lesson
                  ? <><strong>{priceLabel(lesson.unitPriceCents)}</strong><span className="cat-row-meta">{[lesson.durationMinutes ? duration(lesson.durationMinutes) : lesson.label, lesson.upcoming ? 'à venir' : null, more > 0 ? `+ ${more}` : null].filter(Boolean).join(' · ')}</span></>
                  : <span className="cat-row-meta">Aucun tarif de leçon</span>}</span>
                <span className="cat-row-count">{plural(item.activeTrainings, 'élève')}</span>
                <span className="cat-row-state"><StateBadge badge={categoryBadge(item.state)} /></span>
                <ChevronRight aria-hidden="true" className="cat-chevron" />
              </button>
            </li>;
          })}</ul>}
        <button type="button" className="cat-link-row" onClick={() => navigate('prestations', {})}>
          <ReceiptText aria-hidden="true" /><span><strong>Prestations sans permis</strong><span className="cat-row-meta">{data.uncategorizedTariffCount === 0 ? 'Aucune prestation' : plural(data.uncategorizedTariffCount, 'prestation')}</span></span>
          <ChevronRight aria-hidden="true" className="cat-chevron" />
        </button>
      </>)}
  </section>;
}
