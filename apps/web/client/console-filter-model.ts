/** A missing directory cannot establish that a lesson fails a name search. */
export function agendaSearchQuery(directory: { data?: unknown }, search: string): string {
  return directory.data !== undefined && search.trim() ? search : '';
}

/** Explain the existing filters without creating a second source of filter state. */
export function learnerFilterContext({ search, statusFilter, readinessFilter }: {
  search: string; statusFilter: 'active' | 'archived' | 'all'; readinessFilter: 'all' | 'incomplete';
}): string | null {
  const criteria = [
    search.trim() ? `Recherche « ${search.trim()} »` : null,
    statusFilter === 'archived' ? 'dossiers archivés' : statusFilter === 'all' ? 'tous les dossiers' : null,
    readinessFilter === 'incomplete' ? 'profil à compléter' : null,
  ].filter((value): value is string => value !== null);
  return criteria.length ? criteria.join(' · ') : null;
}
