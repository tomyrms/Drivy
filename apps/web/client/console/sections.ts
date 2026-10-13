export const sectionKeys = ['apercu', 'configuration', 'champs-profil', 'confidentialite', 'formations', 'offres', 'referentiels', 'procedures', 'prestations', 'conditions', 'equipe', 'invitations', 'eleves', 'agenda', 'trajets', 'disponibilites', 'signalements'] as const;
export type SectionKey = typeof sectionKeys[number];
