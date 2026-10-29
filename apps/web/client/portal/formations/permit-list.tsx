import { BookOpen, ChevronRight, Plus, Search } from 'lucide-react';
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
  const searchable = !!data && data.categories.length > 6;
  return <section className="cat-page">
    <h1 className="visually-hidden" tabIndex={-1}>Formations</h1>
    <ReadFeedback loaded={state.loaded} label="Lecture des formations" />
    {data && (data.categories.length === 0
      ? <Empty className="cat-empty"><EmptyHeader><EmptyMedia variant="icon"><BookOpen /></EmptyMedia><EmptyTitle>Aucun permis préparé</EmptyTitle>
          <EmptyDescription>Préparez le premier permis enseigné par l’école.</EmptyDescription></EmptyHeader>
          {data.canConfigureCatalog && <EmptyContent><Button onClick={() => prepare()}>Préparer un permis</Button></EmptyContent>}</Empty>
      : <>
        <div className="cat-toolbar">
          {searchable && <Field className="cat-search"><FieldLabel className="sr-only" htmlFor="cat-search">Rechercher un permis</FieldLabel><Search aria-hidden="true" />
            <Input id="cat-search" type="search" placeholder="Rechercher un permis" value={state.search} onChange={event => state.setSearch(event.target.value)} /></Field>}
          {searchable && <span className="cat-count" role="status">{state.categories.length === data.categories.length ? plural(data.categories.length, 'permis', 'permis') : `${state.categories.length} sur ${data.categories.length}`}</span>}
          {data.canConfigureCatalog && <Button className="cat-toolbar-action" onClick={() => prepare()}><Plus data-icon="inline-start" />Préparer un permis</Button>}
        </div>
        {state.categories.length === 0
          ? <Empty className="cat-empty"><EmptyHeader><EmptyTitle>Aucun permis trouvé</EmptyTitle></EmptyHeader><EmptyContent><Button variant="outline" onClick={() => state.setSearch('')}>Effacer la recherche</Button></EmptyContent></Empty>
          : <ul className="cat-list" aria-label="Permis préparés par l’école">{state.categories.map(item => {
            const lessons = item.lessonTariffs.slice(0, 2), more = item.lessonTariffs.length - lessons.length;
            return <li key={item.categoryCode}>
              <button type="button" className="cat-row cat-permit-row" onClick={() => navigate('formations', { category: item.categoryCode })}>
                <PermitMark code={item.categoryCode} />
                <span className="cat-row-main">
                  <strong>Permis {item.categoryCode}</strong>
                  <span className="cat-row-meta">{[item.competencyCounts.length === 1 ? plural(item.competencyCounts[0]!, 'compétence') : item.competencyCounts.length > 1 ? `${item.competencyCounts.length} parcours` : null,
                    item.tariffCount > 0 ? plural(item.tariffCount, 'tarif') : null].filter(Boolean).join(' · ')}</span>
                </span>
                <span className="cat-row-offer">{lessons.length
                  ? <>{lessons.map((lesson, index) => <span key={index} className="cat-offer-line"><strong>{priceLabel(lesson.unitPriceCents)}</strong>
                    <span className="cat-row-meta">{[lesson.durationMinutes ? duration(lesson.durationMinutes) : lesson.label, lesson.upcoming ? 'à venir' : null].filter(Boolean).join(' · ')}</span></span>)}
                    {more > 0 && <span className="cat-row-meta">+ {plural(more, 'autre tarif', 'autres tarifs')}</span>}</>
                  : <span className="cat-row-meta">Aucun tarif de leçon</span>}</span>
                <span className="cat-row-count">{item.activeTrainings === 0 ? 'Aucun élève' : plural(item.activeTrainings, 'élève')}</span>
                <span className="cat-row-state"><StateBadge badge={categoryBadge(item.state)} /></span>
                <ChevronRight aria-hidden="true" className="cat-chevron" />
              </button>
            </li>;
          })}</ul>}
      </>)}
  </section>;
}
