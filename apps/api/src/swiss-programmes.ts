/** Référentiel pédagogique Drivy. Recherche et limites : docs/implementation/regles-suisses-20261028.md.
 * Les règles d'admission restent distinctes de ces compétences observables ; aucune note ni certification n'est déduite.
 */
export const swissProgrammeVersion = '2026-10-28.1';
export const swissCategories = ['A1','A35','A','B','B1','BE','C1','C','C1E','CE','D1','D','D1E','DE','F','G','M'] as const;
export type SwissCategory = typeof swissCategories[number];
type Item = {key:string;label:string;description:string;sortOrder:number};
const item = (key:string,label:string,description:string):Omit<Item,'sortOrder'> => ({key,label,description});
const observation = item('observation','Observer et anticiper','Chercher les indices utiles, contrôler les angles morts et anticiper les autres usagers.');
const speed = item('speed','Adapter son allure','Garder une marge de sécurité selon la visibilité, l’adhérence et les autres usagers.');
const intersections = item('intersections','Franchir les intersections','Identifier la priorité, communiquer son intention et franchir sans imposer de freinage.');
const road = [observation,speed,intersections];
const car = [item('preparation','Préparer la conduite','Régler le poste de conduite et vérifier le véhicule avant le départ.'),...road,
  item('position','Placement et trajectoire','Choisir sa voie et tenir une trajectoire avec une marge suffisante.'),
  item('manoeuvres','Manœuvrer','Stationner, reculer et repartir après observation de l’espace disponible.'),
  item('independent-driving','Conduire de façon autonome','Suivre une direction et préparer ses décisions sans guidage permanent.'),
  item('driver-assistance','Utiliser les aides à la conduite','Identifier les limites des aides présentes et garder la responsabilité de la conduite.')];
const motorcycle = [item('preparation','Préparer la moto et son équipement','Contrôler la moto, ajuster son équipement et choisir une installation stable.'),...road,
  item('position','Trajectoire et équilibre','Placer le regard et adapter sa trajectoire avec une marge latérale suffisante.'),
  item('manoeuvres','Manœuvrer à basse vitesse','Démarrer, tourner et s’arrêter en coordonnant regard, équilibre et commandes.'),
  item('motorcycle-braking','Freiner et éviter','Doser les freins et travailler l’évitement dans un espace adapté et encadré.'),
  item('motorcycle-conditions','Adapter la conduite moto','Reconnaître les risques d’adhérence, de visibilité et de prise au vent propres à la moto.')];
const heavy = [item('preparation','Contrôler le véhicule lourd','Vérifier les points de sécurité, les dimensions, la charge et les documents utiles au trajet.'),...road,
  item('position','Gérer le gabarit','Anticiper les angles morts, le déport et les contraintes de hauteur et de largeur.'),
  item('manoeuvres','Manœuvrer le véhicule lourd','Préparer le recul et l’approche d’un emplacement avec une zone sécurisée.'),
  item('heavy-braking','Maîtriser le freinage','Préparer les ralentissements et descentes selon la masse et les systèmes du véhicule.'),
  item('load-security','Sécuriser le chargement','Contrôler la répartition de la charge et son arrimage avant et pendant le transport.')];
const passenger = [item('preparation','Préparer le transport de personnes','Contrôler le véhicule, les accès, les places et les équipements de sécurité.'),...road,
  item('position','Gérer le gabarit du véhicule','Anticiper le déport, les angles morts et les dégagements à chaque changement de direction.'),
  item('manoeuvres','Approcher les arrêts','Placer le véhicule et sécuriser la montée et la descente des passagers.'),
  item('passenger-comfort','Conduire avec des passagers','Anticiper les variations d’allure et maintenir une conduite régulière.'),
  item('passenger-safety','Protéger les passagers','Vérifier les accès et préparer la réaction à une panne ou une évacuation.')];
const trailer = (heavyVehicle:boolean) => [item('preparation','Préparer l’ensemble','Vérifier les masses, la compatibilité du véhicule tracteur et de la remorque et les documents utiles.'),...road,
  item('position','Guider l’ensemble','Anticiper la longueur, le déport et les dégagements de la remorque.'),
  item('manoeuvres','Reculer avec la remorque','Préparer et conduire le recul de l’ensemble dans un espace sécurisé.'),
  item('trailer-coupling','Atteler et dételer','Sécuriser l’immobilisation, l’accouplement et les liaisons avant de contrôler l’ensemble.'),
  item('trailer-load','Contrôler la remorque','Contrôler la répartition et la fixation de la charge ainsi que le freinage de la remorque.'),
  ...(heavyVehicle?[item('heavy-combination','Conduire un ensemble lourd','Préparer les virages et les descentes en tenant compte de la masse de l’ensemble.')]:[])];
const special:Record<'F'|'G'|'M',Omit<Item,'sortOrder'>[]> = {
  F:[item('preparation','Préparer le véhicule lent','Contrôler le véhicule et identifier les limites de son utilisation.'),...road,
    item('position','Partager la route à faible vitesse','Choisir son placement en tenant compte du différentiel de vitesse.'),item('manoeuvres','Manœuvrer le véhicule','Sécuriser l’espace de manœuvre et les déplacements autour du véhicule.')],
  G:[item('agricultural-rules','Connaître les règles agricoles','Reconnaître les véhicules, les usages et les limitations applicables à la catégorie G.'),
    item('agricultural-signs','Lire la signalisation','Reconnaître les priorités et la signalisation rencontrées lors des déplacements agricoles.'),
    item('agricultural-risks','Repérer les risques agricoles','Identifier les risques liés aux accès, au gabarit, à la charge et aux autres usagers.'),
    item('agricultural-equipment','Préparer les déplacements agricoles','Identifier les contrôles utiles du véhicule et de ses équipements ; le cours agréé G40 reste distinct.')],
  M:[item('moped-rules','Connaître les règles du cyclomoteur','Reconnaître les véhicules autorisés et les règles applicables à la catégorie M.'),
    item('moped-signs','Lire les priorités et les signaux','Résoudre les situations de priorité et reconnaître la signalisation utile.'),
    item('moped-risks','Repérer les risques à deux roues','Identifier les angles morts, les intersections et les risques d’adhérence.'),
    item('moped-equipment','Préparer le cyclomoteur','Identifier les contrôles de sécurité et l’équipement adaptés au véhicule.')],
};
const coverage:Record<SwissCategory,string> = {
  A1:'Variantes 15/16 ans, IPB et dispense d’examen après B/B1 à relire selon le dossier.',
  A35:'Restriction de la catégorie A à 35 kW ; accès et anciens droits à confirmer.',
  A:'Accès après A limitée, dispositions 2020/2021 et accès professionnels à confirmer.',
  B:'Durée d’apprentissage selon l’âge et transition du CTC 2027 à vérifier au dossier.',
  B1:'Sous-catégorie distincte ; véhicule, dispenses et examen à confirmer.',
  BE:'Conditions du véhicule tracteur, de la remorque et des dispenses à confirmer.',
  C1:'Aptitudes d’examen détaillées et exceptions professionnelles OACP à qualifier.',
  C:'Aptitudes d’examen détaillées et exceptions professionnelles OACP à qualifier.',
  C1E:'Ensemble limité à 12 tonnes ; équivalences et aptitudes détaillées à qualifier.',
  CE:'Ensemble lourd ; équivalences et aptitudes détaillées à qualifier.',
  D1:'Sous-catégorie 9 à 16 passagers ; anciens droits et OACP à qualifier.',
  D:'Pratique préalable, formation minimale selon le permis détenu et OACP à qualifier.',
  D1E:'Ensemble D1 avec remorque ; équivalences et aptitudes détaillées à qualifier.',
  DE:'Ensemble D avec remorque ; équivalences et aptitudes détaillées à qualifier.',
  F:'Âge selon le véhicule ; aptitudes d’examen détaillées à qualifier.',
  G:'Préparation théorique ; cours agréé G40 distinct, sans validation officielle dans Drivy.',
  M:'Préparation théorique ; exceptions selon le véhicule à qualifier.',
};
export function swissProgrammeTemplates() {
  return swissCategories.map(categoryCode => {
    const competencies = categoryCode==='A'||categoryCode==='A1'||categoryCode==='A35'?motorcycle
      :categoryCode==='B'?car:categoryCode==='B1'?car.filter(c=>c.key!=='driver-assistance')
      :categoryCode==='BE'?trailer(false):['C1E','CE','D1E','DE'].includes(categoryCode)?trailer(true)
      :categoryCode==='C'||categoryCode==='C1'?heavy:categoryCode==='D'||categoryCode==='D1'?passenger
      :special[categoryCode as 'F'|'G'|'M'];
    const url=categoryCode==='A35'?'https://www.vd.ch/mobilite/automobile-et-navigation/permis/motocycles-a1-et-a':`https://lepermisdeconduire.ch/categories-de-permis/categorie-${categoryCode.toLowerCase()}/`;
    const examSource=['G','M'].includes(categoryCode)?null:['C1','C','C1E','CE','D1','D','D1E','DE'].includes(categoryCode)
      ?'https://www.vd.ch/mobilite/automobile-et-navigation/permis/permis-professionnel-c-c1-d-d1-tpp/criteres-devaluation-c-ce-c1-c1e-d-de-d1-d1e-tpp'
      :'https://www.vd.ch/mobilite/automobile-et-navigation/permis/criteres-devaluation-a-a1-b-b1-be-f';
    return {id:`pedagogy-${categoryCode.toLowerCase()}`,version:swissProgrammeVersion,categoryCode,
      label:categoryCode==='A35'?'Permis A limité à 35 kW':`Permis ${categoryCode}`,
      competencies:competencies.map((c,index)=>({...c,sortOrder:index*10})),durationMinutes:45,
      sourceUrls:[url,...(examSource?[examSource]:[])],qualification:'NOT_QUALIFIED' as const,verifiedOn:'2026-10-28',
      coverageNote:coverage[categoryCode],
      change:{kind:'PEDAGOGICAL' as const,effectiveFrom:null,summary:'Programme propre au permis, avec conservation des adaptations déjà enregistrées.',
        application:'Nouvelles inscriptions après confirmation de l’école. Aucune modification des dossiers et évaluations existants.'}};
  });
}
