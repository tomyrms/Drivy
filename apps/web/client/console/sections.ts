export const sectionKeys = ['apercu', 'configuration', 'champs-profil', 'formations', 'offres', 'referentiels', 'procedures', 'prestations', 'conditions', 'equipe', 'invitations', 'eleves', 'agenda', 'trajets', 'disponibilites'] as const;
export type SectionKey = typeof sectionKeys[number];
