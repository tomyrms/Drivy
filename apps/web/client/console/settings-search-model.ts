import type { SectionKey } from './sections.js';

export interface SettingDestination {
  id: string; label: string; group: string; section?: SectionKey; target?: string; keywords: string;
}
/** Destinations and field names only. No school content, personal search history or nonexistent settings. */
export const settingsIndex: readonly SettingDestination[] = [
  { id: 'name', label: 'Nom de l’école', group: 'École · Coordonnées', section: 'configuration', target: 'school-name', keywords: 'identité organisation auto-école' },
  { id: 'email', label: 'E-mail de l’école', group: 'École · Coordonnées', section: 'configuration', target: 'school-email', keywords: 'adresse contact courriel' },
  { id: 'phone', label: 'Téléphone de l’école', group: 'École · Coordonnées', section: 'configuration', target: 'school-phone', keywords: 'contact numéro mobile' },
  { id: 'privacy', label: 'Textes de confidentialité', group: 'École · Confidentialité', section: 'confidentialite', target: 'policy-title', keywords: 'notice information données personnelles protection consentement' },
  { id: 'gps', label: 'Trajets GPS', group: 'École · Confidentialité', section: 'confidentialite', target: 'school-gps', keywords: 'activer désactiver enregistrement localisation carte capture moniteur leçon' },
  { id: 'retention', label: 'Conservation des données', group: 'École · Confidentialité', section: 'confidentialite', target: 'privacy-retention', keywords: 'durée rétention suppression texte' },
  { id: 'data-contact', label: 'Contact pour les données', group: 'École · Confidentialité', section: 'confidentialite', target: 'privacy-contact', keywords: 'email courriel demande données personnelles' },
  { id: 'fields', label: 'Informations demandées aux élèves', group: 'École · Informations élèves', section: 'champs-profil', target: 'fields-title', keywords: 'profil champs obligatoires facultatifs naissance adresse téléphone requis avant leçon finalité' },
  { id: 'themes', label: 'Thèmes de signalement', group: 'École · Pédagogie', section: 'signalements', keywords: 'observations ordre activer masquer catégories moniteur' },
  { id: 'hours', label: 'Horaires des moniteurs', group: 'Planning · Disponibilités', section: 'disponibilites', keywords: 'hebdomadaire jour travail horaire récurrent' },
  { id: 'absence', label: 'Absences des moniteurs', group: 'Planning · Absences', section: 'absences', keywords: 'congé vacances indisponible dates' },
  { id: 'access', label: 'Rôles et autorisations', group: 'Équipe · Membres et accès', section: 'equipe', keywords: 'droits administrateur moniteur retirer accès permissions équipe' },
  { id: 'offerings', label: 'Formations proposées', group: 'Formations · Offres', section: 'offres', keywords: 'permis catégorie durée validité leçon' },
  { id: 'curricula', label: 'Compétences enseignées', group: 'Formations · Programme', section: 'referentiels', keywords: 'pédagogie référentiel apprentissage objectifs' },
  { id: 'cancellation', label: 'Déroulement et annulation', group: 'Formations · Procédures', section: 'procedures', keywords: 'conditions annuler réservation procédure règle' },
  { id: 'prices', label: 'Prestations et tarifs', group: 'Formations · Tarifs', section: 'prestations', keywords: 'prix CHF montant durée unité leçon' },
  { id: 'terms', label: 'Conditions commerciales', group: 'Formations · Conditions', section: 'conditions', keywords: 'texte prix contrat commercial' },
  { id: 'setup', label: 'Préparation de l’école', group: 'École · Préparation', section: 'apercu', keywords: 'activation première configuration ouvrir' },
  { id: 'appearance', label: 'Apparence', group: 'Préférences personnelles', keywords: 'thème clair sombre système couleur affichage dark mode' },
];
export const settingTargets = settingsIndex.flatMap(item => item.target ? [item.target] : []);
const normalized = (text: string) => text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('fr').replace(/[’'-]/g, ' ');
export function searchSettings(query: string): readonly SettingDestination[] {
  const words = normalized(query).trim().split(/\s+/).filter(Boolean);
  if (!words.length) return settingsIndex.filter(item => ['name', 'privacy', 'fields', 'hours', 'access', 'prices', 'appearance'].includes(item.id));
  return settingsIndex.map(item => {
    const label = normalized(item.label), corpus = `${label} ${normalized(item.group)} ${normalized(item.keywords)}`;
    return { item, score: words.every(word => corpus.includes(word)) ? words.reduce((score, word) => score + (label.includes(word) ? 3 : 1), 0) : 0 };
  }).filter(result => result.score > 0).sort((a, b) => b.score - a.score).map(result => result.item);
}
