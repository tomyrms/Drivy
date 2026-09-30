# Architecture de travail du web · 30 septembre 2026

Le retour du porteur porte sur les parcours et le placement des informations, au-delà du changement visuel. La gestion web doit permettre de retrouver une personne, une leçon ou une formation sans réapprendre la structure technique du catalogue. Cette décision concerne le web responsive uniquement. L’identité et la navigation de l’application native sont conservées.

## Constats et décision

La lecture des sources a confirmé quatorze destinations au premier niveau, une page d’accueil centrée sur la préparation même après activation, des noms d’élèves non cliquables dans l’agenda et les trajets, et des dossiers sélectionnés uniquement dans l’état local. Sur écran étroit, la liste complète précédait le dossier. Les liens de prérequis du catalogue quittaient un formulaire sans garder son contexte.

L’inspection est une revue de sources et du retour exprimé par le porteur. Elle ne constitue ni un entretien utilisateur supplémentaire ni une mesure du temps nécessaire pour accomplir une tâche. L’hypothèse retenue est de réduire les retours au menu général et de rendre les relations entre les objets visibles dans leur contexte.

## Cinq espaces stables

| Espace | Entrée | Navigation locale | Informations contextuelles |
| --- | --- | --- | --- |
| Planning | Agenda de l’école | Agenda ; disponibilités et absences | Leçon vers dossier élève ; filtre moniteur et semaine conservés lors du retour. |
| Élèves | Liste des dossiers | Dossiers ; invitations ; trajets | Formation, moniteurs affectés, permis, progression et bilans appartiennent au dossier. Les trajets peuvent être limités à cet élève. |
| Équipe | Membres et accès | Membres et accès ; invitations | Disponibilités d’un moniteur accessibles avec le moniteur présélectionné. Les invitations du personnel sont distinctes de celles des élèves. |
| Formations et tarifs | Vue par catégorie enseignée | Formations ; tarifs | Chaque formation mène à son programme de compétences et à sa procédure. Un tarif mène à ses conditions. Ces éditeurs ne deviennent pas cinq onglets de premier niveau. |
| Réglages | École et confidentialité | École et confidentialité ; informations des élèves ; préparation | Coordonnées, textes de données, règles de profil et activation. La préparation n’est plus l’accueil quotidien d’une école active. |

La racine d’une école active ouvre Planning. Pour une école en préparation, elle ouvre la préparation dans Réglages. `/apercu` reste une adresse explicite pour revenir à cette préparation. Le logo retourne à l’accueil de l’école ; le nom du compte rejoint l’espace personnel.

## La formation comme point de départ

Le hub `formations.tsx` réunit les catégories présentes dans les formations, compétences, procédures et tarifs. Il affiche la version la plus récente de chaque offre et de chaque référence tarifaire. Les éditeurs conservent l’accès aux versions historiques : ce regroupement n’efface ni les versions ni leurs engagements.

Sous chaque catégorie, les leçons proposées renvoient aux identifiants exacts du programme et de la procédure qui leur sont associés. Les tarifs de cette catégorie figurent à côté, avec leur durée, prix et unité. Un tarif désactivé, hors de sa période ou lié à des conditions non approuvées n’est pas présenté comme actuellement proposé. Lorsque ses conditions ne sont pas chargées, le texte demande de les vérifier au lieu d’en déduire une disponibilité.

Une catégorie sans offre permet de retrouver les compétences et la procédure déjà préparées. Les prestations sans catégorie ont leur propre section. Un filtre de catégorie reste visible, peut être retiré et suit les liens vers les éditeurs ; le retour vers la formation ou le tarif d’origine est explicite.

Les associations commerciales restent déterminées par les contrats et le serveur. La proximité dans cette vue ne crée aucune nouvelle relation entre une offre et un tarif et ne remplace pas la validation d’une réservation.

## Continuité et retour

`navigation.ts` définit les cinq espaces et leurs destinations locales ; `route.ts` valide les paramètres de navigation. Les adresses ne transportent que les identifiants et filtres autorisés : sélection, élève, moniteur, catégorie, origine, public d’une invitation et semaine. Aucun nom, code d’invitation, texte de bilan ou brouillon n’est enregistré dans l’URL.

Les brouillons de catalogue peuvent survivre à un aller-retour vers un prérequis dans une Map en mémoire. Cette Map est recréée si la personne, l’école, l’appartenance, l’époque d’accès ou l’état de connexion change. Elle n’utilise ni `localStorage` ni `sessionStorage` ; un rechargement complet ne promet pas de restaurer une saisie non enregistrée. Les confirmations, versions, droits et résultats de commandes restent portés par les mécanismes existants.

Le fil d’Ariane décrit la hiérarchie. Un lien de retour distinct rappelle le formulaire d’origine. Sur écran étroit, `SplitView` montre la liste ou son détail, avec « Retour à la liste ». Ce retour remet le focus sur la ligne qui avait été sélectionnée, sinon sur un contrôle de la liste ou la liste elle-même. Sur grand écran, les deux panneaux restent visibles.

## Limites fonctionnelles maintenues

L’agenda web reste en lecture seule dans cet incrément ; aucun bouton « Planifier » n’annonce une commande absente. L’enregistrement GPS appartient à l’application native. Les invitations par e-mail restent indisponibles tant que le relais n’est pas opérationnel : le parcours de création d’un code élève ne doit pas être présenté comme une invitation de moniteur. L’organisation des écrans ne crée aucun droit supplémentaire.

## Guides mobilisés

- `ui-skills-root` : catégories architecture, interaction et systems parcourues avec la CLI ; sélection selon le problème de parcours.
- `improve-ui` : audit initial en lecture seule, suivi des propriétaires des routes et vérification des constats. L’implémentation suit ensuite le mandat explicitement confirmé.
- `better-layout`, dont `grouping-and-alignment` : entrée courte, hiérarchie entre espaces et sous-pages, informations rattachées à leur tâche, séparation liste/détail responsive.
- `better-writing` et `balise-ux-writing`, dont `interface-patterns` : titres de destinations stables, liens qui annoncent leur résultat, distinction entre hiérarchie et retour d’origine.
- `balise-ux-writing/research-measurement` : distinction entre source observée, difficulté rapportée, hypothèse proposée et comportement effectivement vérifié.
- `interface-design` : partir du travail concret de l’administration de l’auto-école ; traiter la navigation comme une partie du produit.
- `shape` : clarifier la tâche, le résultat et les frontières avant l’implémentation ; la direction et les cinq espaces ont été coordonnés avant les modifications.

Les guides de couleur, typographie et accessibilité de la passe précédente restent applicables. Aucun nouveau thème natif, système d’animation ou framework de routage n’est introduit.

## Qualification

La fixture `apps/web/test/visual.tsx` propose le shell réel avec des données synthétiques pour Planning, Formations, dossiers et préparation. Elle contient deux catégories, des associations de compétences/procédures et plusieurs versions de tarif. Ses identifiants changent à chaque chargement : un rechargement d’une adresse réécrite par la fixture n’est pas une preuve de reprise du produit réel.

La vérification TypeScript, les tests de navigation et la revue navigateur sont intégrés au lot web. Aucun résultat Apple, GPS physique ou de recherche utilisateur n’est déduit de cette réorganisation. Les résultats exécutés sont consignés par la vérification d’intégration du lot.

## Vérification d’intégration exécutée

Typecheck, build de production et **100 tests web** réussis. Le navigateur a vérifié les allers-retours Planning/dossier/trajets, la sélection des références de formation, la reprise des brouillons non soumis, la séparation des invitations et les deux accueils. Inspection à 320, 390, 834 et 1440 px, clair et sombre ; aucun débordement horizontal constaté dans les scènes contrôlées. Les résultats et limites exacts figurent dans la [preuve web](proofs/web-architecture-20260930.json).

Le dossier présente d’abord formation, moniteur, permis et suivi pédagogique. L’affectation et le changement d’état sont sous « Gérer cette formation » ; l’ouverture d’une autre formation est secondaire. Le composant liste/détail mobile est appliqué aussi aux informations demandées aux élèves.

Deux cas de continuité corrigés lors de la revue : un lien vers un objet précis prime sur le brouillon d’une autre formation ; changer le public des invitations réinitialise la création en cours. Les filtres inchangés ne créent pas une étape supplémentaire dans l’historique. Un brouillon envoyé sort du cache local afin qu’un reçu tardif ne le fasse pas réapparaître comme une nouvelle version.

Le filtre de trajets par élève utilise les 1 000 derniers trajets autorisés de l’école ; si la liste est tronquée, une alerte le dit explicitement et renvoie à la pagination de tous les trajets. Le serveur actuel ne propose pas de filtre élève sur cet inventaire.
