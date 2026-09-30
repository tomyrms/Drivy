import { useCommandSnapshot } from '../command-store';
import { formatCents } from '../command-core';
import { civilDateIn } from '../agenda-model';
import {
  catalogPolicySchema, curriculumSchema, offeringSchema, productSchema, readAll, termsSchema,
  type Offering, type ServiceProduct,
} from '../school-api';
import { EmptyState, Notice, StatusBadge, formatDuration } from '../ui';
import { useConsole, useLoad, type SectionKey } from './context';
import { LoadState, SectionHeading } from './layout';
import { consolePath, type NavigationQuery } from './route';

function latestByKey<T extends { version: number }>(items: readonly T[], key: (item: T) => string): T[] {
  const latest = new Map<string, T>();
  for (const item of items) if ((latest.get(key(item))?.version ?? 0) < item.version) latest.set(key(item), item);
  return [...latest.values()];
}

/** One place to understand how each taught category connects to its programme, procedures and prices. */
export function FormationsSection() {
  const { schoolId, school, navigate, routeQuery = {} } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    const [offerings, curricula, procedures, products, terms] = await Promise.all([
      readAll(schoolId, 'offerings', offeringSchema), readAll(schoolId, 'curricula', curriculumSchema),
      readAll(schoolId, 'policy-versions', catalogPolicySchema), readAll(schoolId, 'service-products', productSchema),
      readAll(schoolId, 'commercial-terms', termsSchema),
    ]);
    return { offerings: latestByKey(offerings.items, item => item.offeringKey), curricula: curricula.items, procedures: procedures.items,
      products: latestByKey(products.items, item => item.productKey), terms: terms.items,
      truncated: [offerings, curricula, procedures, products, terms].some(page => page.truncated) };
  }, [schoolId, revision]);
  const today = civilDateIn(school.timeZone);
  const link = (section: SectionKey, text: string, query: NavigationQuery = {}, className = 'text-link') => {
    const target = { ...query, from: 'formations' as const };
    return <a className={className} href={consolePath(schoolId, section, target)} onClick={event => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
      event.preventDefault(); navigate(section, target);
    }}>{text}</a>;
  };
  return <div className="section-stack">
    <SectionHeading title="Formations et tarifs" actions={link('offres', 'Préparer une formation', {}, 'button primary')} />
    <LoadState loaded={loaded} label="Lecture des formations…">{data => {
      const allCategories = [...new Set([
        ...data.offerings.map(item => item.categoryCode), ...data.curricula.map(item => item.categoryCode),
        ...data.procedures.map(item => item.categoryCode), ...data.products.flatMap(item => item.categoryCode ? [item.categoryCode] : []),
      ])].sort((a, b) => a.localeCompare(b, 'fr'));
      const categories = routeQuery.category ? allCategories.filter(category => category === routeQuery.category) : allCategories;
      const priceRow = (product: ServiceProduct) => {
        const terms = data.terms.find(item => item.id === product.termsVersionId);
        const current = product.enabled && product.validFrom <= today && (!product.validUntil || product.validUntil >= today)
          && terms?.approved && terms.validFrom <= today && (!terms.validUntil || terms.validUntil >= today);
        return <li key={product.id}>
          <div className="row-text">{link('prestations', product.label, { selection: product.id, ...(product.categoryCode ? { category: product.categoryCode } : {}) })}
            <span className="row-meta block">{formatDuration(product.durationMinutes)}{!terms ? ' · Conditions à vérifier' : !current ? ' · Non proposé actuellement' : ''}</span>
          </div>
          <span className="price">{formatCents(product.unitPriceCents)}<span className="row-meta block">/ {product.unitLabel}</span></span>
        </li>;
      };
      const offeringRow = (offering: Offering) => {
        const curriculum = data.curricula.find(item => item.id === offering.curriculumVersionId);
        const procedure = data.procedures.find(item => item.id === offering.policyVersionId);
        return <li key={offering.id} className="formation-offering">
          <div className="formation-offering-heading">
            {link('offres', `Leçons de ${formatDuration(offering.defaultDurationMinutes)}`, { category: offering.categoryCode, selection: offering.id })}
            {!offering.enabled && <StatusBadge tone="neutral" symbol="dot">Désactivée</StatusBadge>}
          </div>
          <div className="formation-related">
            {link('referentiels', curriculum ? `${curriculum.competencies.length} compétence${curriculum.competencies.length === 1 ? '' : 's'}` : 'Compétences à vérifier', { category: offering.categoryCode, selection: offering.curriculumVersionId })}
            {link('procedures', procedure ? 'Déroulement et annulation' : 'Procédure à vérifier', { category: offering.categoryCode, selection: offering.policyVersionId })}
          </div>
        </li>;
      };
      return <>
        {data.truncated && <Notice tone="warning" title="Catalogue partiel" live={false}><p>Certaines versions ne sont pas chargées. Ouvrez la formation ou le tarif concerné pour vérifier ses références.</p></Notice>}
        {routeQuery.category && <div className="filter-context"><span>Permis {routeQuery.category}</span>{link('formations', 'Toutes les formations')}</div>}
        {categories.length === 0 ? <EmptyState symbol="book" title={routeQuery.category ? 'Aucune formation dans cette catégorie' : 'Aucune formation préparée'}
          message={routeQuery.category ? 'Consultez les autres formations de l’école.' : 'Commencez par les compétences enseignées.'}
          action={routeQuery.category ? link('formations', 'Toutes les formations', {}, 'button secondary') : link('referentiels', 'Préparer les compétences', {}, 'button secondary')} />
          : <div className="formation-list">{categories.map(category => {
            const offerings = data.offerings.filter(item => item.categoryCode === category);
            const products = data.products.filter(item => item.categoryCode === category);
            const curriculum = data.curricula.filter(item => item.categoryCode === category).sort((a, b) => b.revision - a.revision)[0];
            const procedure = data.procedures.filter(item => item.categoryCode === category).sort((a, b) => b.version - a.version)[0];
            return <section key={category} className="formation-group" aria-label={`Permis ${category}`}>
              <div className="formation-heading"><h2><span className="formation-category-label">Permis</span> <span className="formation-category">{category}</span></h2>{link('offres', 'Gérer la formation', { category }, 'button secondary')}</div>
              <div className="formation-content">
                <div><h3 className="formation-label">Enseignement</h3>
                  {offerings.length ? <ul className="formation-offerings">{offerings.map(offeringRow)}</ul> : <div className="formation-related empty-related">
                    {link('referentiels', curriculum ? 'Consulter les compétences' : 'Préparer les compétences', { category, ...(curriculum ? { selection: curriculum.id } : {}) })}
                    {link('procedures', procedure ? 'Consulter la procédure' : 'Préparer la procédure', { category, ...(procedure ? { selection: procedure.id } : {}) })}
                    {link('offres', 'Ouvrir la formation', { category })}
                  </div>}
                </div>
                <div><h3 className="formation-label">Tarifs</h3>
                  {products.length ? <ul className="formation-prices">{products.map(priceRow)}</ul> : link('prestations', 'Préparer un tarif', { category })}
                </div>
              </div>
            </section>;
          })}</div>}
        {!routeQuery.category && data.products.some(item => !item.categoryCode) && <section className="formation-group">
          <div className="formation-heading"><h2>Autres prestations</h2>{link('prestations', 'Tous les tarifs', {}, 'button quiet')}</div>
          <ul className="formation-prices">{data.products.filter(item => !item.categoryCode).map(priceRow)}</ul>
        </section>}
      </>;
    }}</LoadState>
  </div>;
}
