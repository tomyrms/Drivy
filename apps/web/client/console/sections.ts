export const sectionKeys = ['tableau-de-bord', 'statistiques', 'apercu', 'configuration', 'confidentialite', 'champs-profil', 'formations', 'offres', 'referentiels', 'procedures', 'prestations', 'conditions', 'equipe', 'invitations', 'eleves', 'agenda', 'trajets', 'disponibilites', 'absences', 'signalements', 'abonnement'] as const;
export type SectionKey = typeof sectionKeys[number];
