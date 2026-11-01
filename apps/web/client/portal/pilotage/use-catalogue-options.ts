import { useCommandSnapshot } from '../../command-store';
import { useConsole, useLoad } from '../../console/context';
import { offeringSchema, productSchema, readAll } from '../../school-api';
import type { FilterOption } from './components';

/**
 * Choix des filtres Permis et Prestation : ce que le catalogue de l'école propose aujourd'hui. Une lecture qui échoue retire le filtre,
 * elle ne bloque pas les chiffres. Une valeur déjà présente dans l'adresse reste proposée même si le catalogue ne la connaît plus.
 */
export function useCatalogueOptions(selected: { category?: string | undefined; product?: string | undefined }) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const offerings = useLoad(() => readAll(schoolId, 'offerings', offeringSchema), [schoolId, revision]);
  const products = useLoad(() => readAll(schoolId, 'service-products', productSchema), [schoolId, revision]);
  const categories = new Map<string, string>();
  for (const offering of offerings.data?.items ?? []) if (!categories.has(offering.categoryCode)) categories.set(offering.categoryCode, offering.label?.trim() || `Permis ${offering.categoryCode}`);
  if (selected.category && !categories.has(selected.category)) categories.set(selected.category, `Permis ${selected.category}`);
  const services = new Map<string, string>();
  for (const product of (products.data?.items ?? []).filter(item => item.type === 'INDIVIDUAL_LESSON').sort((a, b) => b.version - a.version)) if (!services.has(product.productKey)) services.set(product.productKey, product.label);
  if (selected.product && !services.has(selected.product)) services.set(selected.product, selected.product);
  const options = (values: Map<string, string>): FilterOption[] => [...values].map(([value, label]) => ({ value, label })).sort((a, b) => a.label.localeCompare(b.label, 'fr'));
  return { categoryOptions: options(categories), productOptions: options(services) };
}
