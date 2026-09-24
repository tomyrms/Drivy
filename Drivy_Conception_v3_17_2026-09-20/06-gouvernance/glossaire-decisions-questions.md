# Glossaire, décisions et questions de validation

> Drivy · Référence de conception 3.16 · 20 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

## Statuts documentaires

**ACCEPTÉ** : choix explicitement confirmé par le porteur. **EXIGENCE** : besoin explicitement demandé. **OBS** : fait observé dans un fichier ou une page identifiée. **REC** : solution recommandée, non approuvée par silence. **HYP** : hypothèse de terrain à éprouver. **OUVERT** : arbitrage nécessaire avant la gate indiquée. **NON VÉRIFIÉ** : capacité, règle détaillée ou usage non établi. La présente V3 intègre les exigences nouvelles ; elle ne transforme pas les recommandations techniques en décisions déjà validées.

## Glossaire canonique

| Terme | Sens | À ne pas confondre |
|---|---|---|
| Drivy | Nom visible et officiel du produit | D-R-I-V-Y. Aucun alias concurrent dans la référence active. |
| Personne | Identité globale | Appartenance ou formation scolaire. |
| Dossier élève | Relation d’une personne à une école | Tous les dossiers inter-écoles. |
| Formation | Parcours pour un permis dans une école | Exigence commune telle que sensibilisation. |
| Leçon | Engagement et résultat individuel de conduite | Capture ou facture. |
| Capture | Collecte volontaire, bornée, segments/points | Leçon réalisée ou preuve juridique de conduite. |
| Replay | Relecture des mesures disponibles et observations | Reconstitution certaine d’un trou de signal. |
| Bilan publié | Révision choisie et consultable | Brouillon ou chunk transféré. |
| Prestation | Service commercial versionné | Catégorie de permis ou occurrence datée. |
| Pack | Offre composée de droits | Réservation automatique des prestations. |
| Droit | Unité de service accordée, réservée ou utilisée | Argent encaissé. |
| Série collective | CourseSession avec toutes ses occurrences | Leçon multipliée par le nombre d’élèves. |
| Offre calendrier | Possibilité publiée non réservée | Engagement personnel. |
| Inscription | Place confirmée dans une série | Présence, paiement ou validation finale. |
| Présence | Constat d’un bloc par le formateur | Clic S’inscrire ou passage de date. |
| Exigence | Condition de formation avec preuve/statut | Produit acheté. |
| Profil réglementaire | Règles datées et approuvées | Réglage libre de l’école. |
| Campagne | Intention d’annoncer à une audience éligible | Liste d’élèves automatiquement inscrits. |
| Complet | Aucune place disponible maintenant | Événement auquel l’élève serait inscrit. |
| Workspace web | Interface de gestion selon accès | Ce n’est pas un rôle ADMIN par défaut |
| Onboarding | Parcours d’accueil/configuration reprenable | Ce n’est pas une formation validée |
| Readiness | Préparation pour une capacité précise | Pas un agrément juridique ni un score utilisateur |
| Profil administratif | Identité/coordonnées dans une école | Pas Person globale ni dossier pédagogique inter-écoles |
| TrainingRequest | Intention de formation à valider | Pas Training déjà ouverte automatiquement |
| ArchivePreview | Impacts connus avec durée limitée | Pas un verrou ou jeton d’autorisation |
| ArchiveJob | Ensemble borné de résultats individuels | Pas transaction atomique de tout un lot |
| DeviceAssessment | Diagnostic lié au build et au matériel | Pas une garantie GPS permanente ni un relais |
| Encaissements enregistrés nets | Agrégat signé du journal F10 | Pas bénéfice, chiffre d’affaires fiscal ou solde bancaire |

## Registre de décisions

Les identifiants D01–D33 sont conservés et regroupés ici par ordre numérique. La V1 demeure une archive historique distincte ; ses anciennes priorités ne s’appliquent plus.

<a id="d01"></a>
### D01 · Conception indépendante

**Clarification du brief : refonte assumée demandée par le porteur.** Le ZIP ne prescrit pas d’améliorer seulement l’ancien code ; il conserve les besoins utiles sans reconduire automatiquement architecture, design ou navigation. Réutilisation sélective et bascule à instruire dans [la transition du code](../05-realisation/migration.md#transition-code). Cette décision ne valide pas toute la complexité proposée.

**Statut :** EXIGENCE. **Choix :** Nouvelle architecture/UX, archive utilisée comme preuve de besoins et risques, pas modèle à copier.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d02"></a>
### D02 · Valeur centrée sur GPS et apprentissage

**Statut :** EXIGENCE. **Choix :** Le trajet et sa relecture pédagogique sont centraux. Remplace l’hypothèse administrative de V1 ; utilité terrain encore à mesurer.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d03"></a>
### D03 · Premier périmètre complet

**Statut :** EXIGENCE + REC. **Choix :** Deux parcours : conduite avec/sans capture et cours collectifs. Le détail F01–F23 ajoute web, tablette et accueil ; il reste une proposition de réalisation.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d04"></a>
### D04 · Information organisée par tâches

**Statut :** REC. **Choix :** Séance/Agenda/Élèves/École et Mes leçons/Agenda/Mon parcours. Carte dans le contexte utile, pas fond décoratif permanent.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d05"></a>
### D05 · Cartographie native, option A

**Statut :** ACCEPTÉ. **Choix :** Direction A claire et bleue, choisie dans la conversation. Remplace la recommandation ivoire/pétrole. Les détails des maquettes et de la palette étendue sont des spécifications de référence à éprouver, pas une validation de rendu natif. Voir [DESIGN](../DESIGN/README.md).

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d06"></a>
### D06 · GPS facultatif et interaction sûre

**Statut :** EXIGENCE + REC. **Choix :** Collecte facultative demandée ; conception sans saisie obligatoire en mouvement. Préparer avant, consigner à l’arrêt/après.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d07"></a>
### D07 · Personne, école, formation, exigence

**Statut :** REC. **Choix :** Séparer les concepts et les droits ; plusieurs permis n’impliquent pas plusieurs sensibilisations identiques.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d08"></a>
### D08 · Bilans et observations versionnés

**Statut :** REC. **Choix :** Notes privées, révisions publiées et sélection du trajet séparées. Effacement légal/prudent des coordonnées n’est pas bloqué par immutabilité logique.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d09"></a>
### D09 · Serveur arbitre des engagements

**Statut :** REC. **Choix :** Places, droits et occupations atomiques. Les offres visibles ne sont pas des engagements.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d10"></a>
### D10 · Offline borné

**Statut :** REC. **Choix :** Capture déjà autorisée et brouillons possibles sans réseau ; nouvelles inscriptions et démarrage GPS initial exigent serveur au pilote.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d11"></a>
### D11 · Swift natif confirmé pour Apple

**Statut :** ACCEPTÉ. **Choix :** application iPhone/iPad en Swift natif. SwiftUI avec UIKit ciblé, MapKit et Core Location sont les recommandations d’intégration. Web React DOM/TypeScript et backend restent séparés. Android sera un client futur distinct, Kotlin/Compose proposé sans engagement de date. L’ancienne recommandation de client mobile partagé est abandonnée ; contrats et fixtures restent communs. [Architecture Apple](../04-technique/architecture-client-swift.md).

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d12"></a>
### D12 · Identité déléguée, droits locaux

**Statut :** REC. **Choix :** Fournisseur d’identité pour authentification, Drivy contrôle rôles/affectations/grants courants.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d13"></a>
### D13 · Fichiers et traces privés

**Statut :** REC. **Choix :** Pipelines avec staging, accès authentifié, journaux minimisés et purge des dérivés.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d14"></a>
### D14 · Journal commercial interne

**Statut :** REC. **Choix :** Comptes Lesson/Purchase/Enrollment et ledger de droits ; ni PSP ni factures fiscales au pilote.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d15"></a>
### D15 · Notifications indépendantes

**Statut :** EXIGENCE + REC. **Choix :** Annonces ciblées et confirmation séparées ; refus technique de push ne bloque pas l’app.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d16"></a>
### D16 · Politiques avant données réelles

**Statut :** REC. **Choix :** Responsabilités, conservation, fournisseurs, mineurs et salariés qualifiés avant pilote ; pas de certification juridique revendiquée.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d17"></a>
### D17 · Migration conditionnelle

**Statut :** REC. **Choix :** Pas de consentement, présence, précision GPS ou solde inventés à partir de données anciennes ; source de capacité unique pendant transition.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d18"></a>
### D18 · Documentation et preuves

**Statut :** EXIGENCE. **Choix :** Référence liée, tests explicitement non exécutés, contrôles documentaires reproductibles et limitations visibles.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d19"></a>
### D19 · Packs adaptés aux écoles

**Statut :** EXIGENCE + REC. **Choix :** Prestations et packs configurables demandés ; unités, snapshots et ledger proposés pour éviter double facturation.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d20"></a>
### D20 · Cours visibles sans inscription

**Statut :** EXIGENCE. **Choix :** Publication dans l’agenda élève, notification ciblée et bouton S’inscrire. Aucun achat/publication ne réserve automatiquement une place.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d21"></a>
### D21 · Série multi-dates comme unité

**Statut :** REC. **Choix :** Une place pour toute la formation ; toutes les dates acceptées ; présence par bloc et validation finale séparées.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d22"></a>
### D22 · Capacité transactionnelle

**Statut :** EXIGENCE + REC. **Choix :** Refus Complet demandé ; implementation proposée sous verrou école/ressources/droits, à tester réellement.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d23"></a>
### D23 · Profil réglementaire daté

**Statut :** REC. **Choix :** Règles approuvées par période ; régime 2027 annoncé mais détails/transitions à qualifier avant activation.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d24"></a>
### D24 · Pas de liste d’attente implicite

**Statut :** REC. **Choix :** Attente et rattrapage autonome différés ; aucune inscription automatique à libération d’une place.

**Application :** [règles](../03-fonctionnel/regles-etats.md), [roadmap](../05-realisation/roadmap-backlog.md), [traçabilité](tracabilite.md).

<a id="d25"></a>
### D25 · Workspace de gestion, pas nouvel administrateur

**Statut :** EXIGENCE + REC. **Choix :** Le web de gestion détaillée est demandé ; navigation, limites des lots et grants sont proposés. Même compte, même école, mêmes services et aucune lecture pédagogique globale accordée par le support web.

**Application :** [onboarding](../03-fonctionnel/onboarding.md), [plateformes](../02-experience/plateformes-tablette-web.md), [gestion web](../03-fonctionnel/gestion-web-archivage.md), [règles](../03-fonctionnel/regles-etats.md).

<a id="d26"></a>
### D26 · Tablette première classe

**Statut :** EXIGENCE + REC. **Choix :** Téléphone et tablette couvrent les usages quotidiens ; carte, replay et tous modules sont adaptés. Qualification matérielle et technique avant disponibilité de capture. Aucune fréquence d’usage suisse prétendue mesurée.

**Application :** [onboarding](../03-fonctionnel/onboarding.md), [plateformes](../02-experience/plateformes-tablette-web.md), [gestion web](../03-fonctionnel/gestion-web-archivage.md), [règles](../03-fonctionnel/regles-etats.md).

<a id="d27"></a>
### D27 · Onboardings par rôle et contexte

**Statut :** EXIGENCE + REC. **Choix :** École, élève et moniteur ont des parcours adaptés et reprenables dans app/web. Provision école pilote contrôlée, configuration autonome ensuite ; choix de catégorie élève = demande à valider.

**Application :** [onboarding](../03-fonctionnel/onboarding.md), [plateformes](../02-experience/plateformes-tablette-web.md), [gestion web](../03-fonctionnel/gestion-web-archivage.md), [règles](../03-fonctionnel/regles-etats.md).

<a id="d28"></a>
### D28 · Collecte progressive

**Statut :** REC. **Choix :** Prénom/nom au profil minimum, coordonnées et naissance selon finalité/action ; photo toujours facultative. GPS/push ne sont pas un péage d’entrée ni une signature unique générale.

**Application :** [onboarding](../03-fonctionnel/onboarding.md), [plateformes](../02-experience/plateformes-tablette-web.md), [gestion web](../03-fonctionnel/gestion-web-archivage.md), [règles](../03-fonctionnel/regles-etats.md).

<a id="d29"></a>
### D29 · Archiver sans révoquer ni effacer

**Statut :** REC. **Choix :** Archive porte sur dossier scolaire après contrôles ; historique publié consultable tant que Membership active. Restauration ne réactive rien d’autre. Lot explicite, résultat par ligne, pas force.

**Application :** [onboarding](../03-fonctionnel/onboarding.md), [plateformes](../02-experience/plateformes-tablette-web.md), [gestion web](../03-fonctionnel/gestion-web-archivage.md), [règles](../03-fonctionnel/regles-etats.md).

<a id="d30"></a>
### D30 · Métriques de gestion, pas promesses de rentabilité

**Statut :** EXIGENCE + REC. **Choix :** Statistiques demandées ; M01–M09 définis et sourcés par entités. Argent compté une fois dans journal ; pas chiffre d’affaires comptable ou évaluation moniteur déduits.

**Application :** [onboarding](../03-fonctionnel/onboarding.md), [plateformes](../02-experience/plateformes-tablette-web.md), [gestion web](../03-fonctionnel/gestion-web-archivage.md), [règles](../03-fonctionnel/regles-etats.md).

<a id="d31"></a>
### D31 · Deux clients, lancement séquencé

**Statut :** REC. **Choix :** Client natif téléphone/tablette et web React DOM avec BFF ; contrats et domaine partagés. Pilote proposé iPhone+iPad+web, Android prévu mais disponibilité après qualification distincte.

**Application :** [onboarding](../03-fonctionnel/onboarding.md), [plateformes](../02-experience/plateformes-tablette-web.md), [gestion web](../03-fonctionnel/gestion-web-archivage.md), [règles](../03-fonctionnel/regles-etats.md).

<a id="d32"></a>
### D32 · Politique de profil bornée

**Statut :** REC. **Choix :** Configuration d’école n’est pas un moteur de formulaires arbitraires. Champs, stades, finalités et changements sont versionnés et contrôlés ; préserver les acquis et achats historiques.

**Application :** [onboarding](../03-fonctionnel/onboarding.md), [plateformes](../02-experience/plateformes-tablette-web.md), [gestion web](../03-fonctionnel/gestion-web-archivage.md), [règles](../03-fonctionnel/regles-etats.md).

<a id="d33"></a>
### D33 · Carte centrale et signalement pédagogique

**Statut :** EXIGENCE + REC. **Exigence du porteur confirmée le 20 septembre 2026 :** enregistrer les trajets, signaler rapidement depuis une bulle sur la carte les erreurs/situations par thème et statut, puis les retrouver dans le replay et le bilan. Inspiration Waze sur le principe d’interaction, identité propre à Drivy et aucune communauté de signalements. Une expérience animée avec soin est souhaitée ; le GPS reste facultatif.

**Direction visuelle acceptée le 20 septembre 2026 :** composition cartographique de référence Plans, principe de signalement Waze, hiérarchie Flighty, sobriété Things. Textes courts au premier niveau ; détails et explications révélés selon la tâche. Quatre vues prioritaires sont matérialisées dans [LECON.html](../DESIGN/LECON.html). Le porteur a ensuite exprimé son appréciation des quatre vues V3.15 et demandé l’application du plan d’affinage. V3.16 garde cette base, retire les chevrons des actions de statut, relie le thème au point sélectionné et maintient un panneau continu. Ce mandat de retouche ne vaut pas validation des détails nouvellement produits, de la taxonomie ou de la sécurité ; la disposition des commandes GPS et les formes de symboles restent à éprouver.

**Proposition de référence :** figer instant/ancre à l’ouverture sans créer d’événement ; catégories stables, statut explicitement choisi, retour après enregistrement local, repère privé alternatif, qualification complémentaire et publication relue. Aucun bouton photo live. Aucun score déduit du nombre d’erreurs. **Non qualifié :** usage en mouvement, taxonomie, taille cible de 60 unités, durées d’animation, gestes réels et charge de relecture. X04 ne supprime pas la saisie pendant la leçon ; elle interdit de la rendre obligatoire ou de la prétendre sûre sans preuve.

**Responsable :** porteur avec moniteurs recrutés ; qualification avant fermeture de G0/G2 selon le risque. **Preuve attendue :** protocole hors circulation, choix motivés et T407–T434 exécutés sur le produit. La galerie HTML teste seulement une présentation et des données en mémoire. Référence unique : [R46](../03-fonctionnel/regles-etats.md#r46) et [signalement](../03-fonctionnel/gps-replay.md#saisie-pendant-lecon).

## Hypothèses de travail non acquises

H01 révisée : téléphone ou tablette native qualifiée du moniteur ; la fréquence réelle des tablettes dans les écoles suisses n’est pas mesurée. H02 : l’autorisation initiale en ligne est praticable. H03 : la plupart des premières séries sont réservées entières, pas par bloc. H04 : les écoles peuvent valider leurs propres conditions de packs. H05 : un journal interne suffit sans intégration PSP au pilote. H06 : les publics comprennent la couche d’offres après test. H07 : les contraintes de carte et stockage sont compatibles avec le budget. H08 : les administrateurs/formateurs peuvent être différenciés par grants. H09 : le nombre d’opérations de planning d’une école permet un verrou de coordination simple, à mesurer.

Les hypothèses « préparation/bilan plutôt que GPS » et « téléphone seul avant tablette » sont retirées. Le support tablette et le web de gestion sont intégrés comme exigences. Aucune hypothèse n’est présentée comme entretien réalisé. H10 : les enseignants peuvent disposer d’un appareil natif qualifié ou continuer sans capture. H11 : le web connecté suffit à l’administration initiale. H12 : la politique de profil bornée couvre le pilote sans moteur générique. H13 : les agrégats SQL bornés sont suffisamment rapides, à mesurer. H14 : le responsable peut configurer seul l’école après une provision contrôlée, à tester avec une école volontaire. Aucune de ces hypothèses n’est un entretien ou un résultat de recette.

## Questions précises à valider

### Tableau de pilotage des questions ouvertes

Ce tableau indique **quand** une question doit être fermée. « Responsable » désigne le rôle chargé d’obtenir la preuve, pas nécessairement la personne qui décide seule. Une gate ne peut pas être déclarée franchie si une ligne qui la bloque reste sans décision tracée.

| Question | Bloque au plus tard | Responsable de preuve | Preuve minimale attendue |
|---|---|---|---|
| Q01 Ressources et plateformes | G0 | Tech lead + porteur | Matrice appareils/OS/builds testés et choix de support |
| Q02 Reprise réelle | avant migration / G5 | Porteur + école pilote | Inventaire réel et choix M0/M1/M2 approuvé |
| Q03 Règles commerciales | G3 | Porteur + école pilote | Conditions versionnées sur cas réels anonymisés |
| Q04 Profils de cours | G3 | Responsable métier qualifié | Profil approuvé, période et preuves associées |
| Q05 Fournisseurs et budget | avant données réelles / G5 | Tech lead + porteur | Fournisseurs choisis, coûts et limites documentés |
| Q06 Données, mineurs et salariés | G5 | Responsable produit + conseil compétent | Responsabilités, accès, conservation et parcours mineur qualifiés |
| Q07 DA et parcours | G0 puis G2 | Produit/design + utilisateurs recrutés | Essais de compréhension et décisions de correction |
| Q08 Organisation et cas particuliers | G3/G4 selon capacité | École pilote + produit | Procédures retenues et cas non couverts explicitement différés |
| Q09 GPS totalement hors ligne | G0 si requis au pilote | Tech lead + moniteurs recrutés | Fréquence d’usage, prototype et politique de révocation |
| Q10 Consommation du droit collectif | G3 | École pilote + produit | Politique commerciale acceptée et scénarios exécutés |
| Q11 Usage tablette | G0 | Produit + moniteurs recrutés | Appareils réels, installation et usages observés |
| Q12 Champs et preuves utiles | G1 | École pilote + responsable données | Finalité et nécessité de chaque champ activé |
| Q13 Délégations et archive | G4 | École pilote + produit | Matrice d’habilitations et politique d’accès historique |
| Q14 Indicateurs pilote | G4/G5 | Porteur + école pilote | Liste M01–M09 retenue et qualité des sources vérifiée |
| DM06 Suppression globale | G5 | Produit + exploitation + conseil compétent | Délais, rétentions, dernier ADMIN et exercices bout en bout |
| DM07 Budgets non fonctionnels | G0/G2/G5 selon mesure | Tech lead + produit | Budget cible approuvé puis mesures sur environnements qualifiés |

<a id="q01"></a>
### Q01 · Ressources et plateformes

**Question :** Le web et la tablette sont demandés. Quels modèles/OS, ressources et ordre iOS/Android seront validés pour le lancement ?

**Proposition et impact :** Recommandation : pilote iPhone+iPad+web, Android téléphone/tablette à qualifier ensuite ; clients Apple et web distincts, Android futur ; contrat et règles serveur communs. G0 fixe modèles, seuils et versions après essais. Le besoin web/tablette n’est plus une question ouverte.

<a id="q02"></a>
### Q02 · Utilisateurs et reprise réelle

**Question :** Existe-t-il des élèves, achats et cours réels à migrer ? Qui valide leurs soldes et accès ?

**Proposition et impact :** Choisir M0 sans migration, M1 reprise minimale ou M2 continuité, sans transformer l’archive en production supposée.

<a id="q03"></a>
### Q03 · Règles commerciales de chaque école

**Question :** Quelles conditions pour double leçon, reliquats de pack, annulation, cours commencé, remboursement et prépaiement ?

**Proposition et impact :** Le modèle les fige par achat ; pas de règle universelle inventée. Faire valider au moins un cas composite et un remboursement partiel.

<a id="q04"></a>
### Q04 · Profils de cours et autorisations

**Question :** Qui valide le contenu, les plafonds, la qualité du formateur, les preuves et les transitions 2027 par catégorie/canton ?

**Proposition et impact :** Profil 2027 non activable sans revue détaillée ; les profils approuvés restent séparés du catalogue commercial.

<a id="q05"></a>
### Q05 · Fournisseurs et budget

**Question :** Quel fournisseur de cartes, stockage, identité, email/push et hébergement, avec quelles licences et coûts ?

**Proposition et impact :** Aucun contrat ni coût récurrent supposé ; qualifier aussi les tuiles offline avant promesse de cartes hors réseau.

<a id="q06"></a>
### Q06 · Données, mineurs et salariés

**Question :** Qui est responsable de traitement ? Quelles politiques de conservation/accès et de refus GPS ?

**Proposition et impact :** Durées GPS proposées, pas imposées ; procédure de choix distincte des permissions OS ; analyse des risques avant données réelles.

<a id="q07"></a>
### Q07 · DA et validation du parcours

**Direction décidée :** option A, Cartographie native. **Question restante :** les maquettes, leur densité et leurs interactions sont-elles confortables avec et sans trace sur les appareils pilotes ?

**Proposition et impact :** éprouver les [maquettes de la direction retenue](../DESIGN/README.md) ; les autres pistes sont historiques. Tester compréhension du calendrier, état de capture et alternative sans GPS avant gel visuel. Le choix A ne vaut pas validation de chaque pixel ou du logo définitif.

<a id="q08"></a>
### Q08 · Organisation et cas particuliers

**Question :** Quelles salles, sites, délégations, élèves sans app/email et procédures de rattrapage ?

**Proposition et impact :** Inscription manuelle sur demande incluse ; invitations sans email, blocs à la carte et GPS de groupe demandent cadrage supplémentaire.

<a id="q09"></a>
### Q09 · Démarrage GPS entièrement hors ligne

**Question :** Le départ sans réseau est-il fréquent et indispensable au pilote ?

**Proposition et impact :** Recommandation actuelle : autorisation initiale en ligne puis continuation offline. Élargir exige une autorisation préchargée bornée et gestion de choix/révocation explicitement testée.

<a id="q10"></a>
### Q10 · Consommation du droit collectif

**Question :** L’école accepte-t-elle le passage HOLD→CONSUME à la première présence ?

**Proposition et impact :** Proposition R54, pas usage établi de Luc’s ; adapter par conditions versionnées sans confondre consommation et accomplissement final.

<a id="q11"></a>
### Q11 · Usage réel des tablettes

**À valider :** modèles réellement utilisés par les écoles pilotes, OS, GNSS/permission, installation dans véhicule et fenêtrage. **Proposition :** établir une petite liste de matériels qualifiés en G0 ; ne pas annoncer « tous iPad compatibles GPS ». L’usage fréquent rapporté par le porteur reste une hypothèse, pas une enquête réalisée.

<a id="q12"></a>
### Q12 · Champs et preuves utiles par prestation

**À valider :** quelles informations l’école a réellement besoin de collecter, à quel stade et sous quelle responsabilité, notamment pour mineurs/attestations. **Proposition :** catalogue de champs/finalités borné, absence de collecte massive, pas photo obligatoire ni règle universelle de majorité inventée.

<a id="q13"></a>
### Q13 · Délégations et archive

**À valider :** quelles personnes peuvent archiver, lire les montants scolaires et exporter ; quelle politique d’accès aux historiques après fin de relation. **Proposition :** archive sans révocation automatique, accès publié sous Membership active ; révocation explicitement séparée. Les soldes, engagements et droits résiduels sont présentés avant confirmation.

<a id="q14"></a>
### Q14 · Indicateurs à utiliser au pilote

**À valider :** utilité de chaque M01–M09 et qualité réelle de ses sources. **Proposition :** démarrer avec définitions stables, montants internes non assimilés à comptabilité et aucune ventilation de pack non justifiée. Les champs absents sont signalés ; les données ne sont pas inventées pour obtenir une courbe.

## Entretien de la référence

Modifier d’abord la règle canonique, puis ses contrats, tests et parcours liés. Un changement réglementaire ajoute une version et ne réécrit pas les inscriptions passées. Ne pas réattribuer un identifiant à un autre besoin. Les rapports de contrôle distinguent validation de structure et recette produit.

<a id="arbitrages-explicités-par-la-revue-v32"></a>
## Arbitrages de transactions et conditions commerciales
**Conservation des engagements en cas de prépaiement corrigé.** Proposition : suspendre les nouvelles réservations mais honorer celles déjà confirmées jusqu’à décision explicite. L’école doit approuver cette politique ; l’alternative consiste en une procédure de résolution annoncée, jamais une annulation automatique cachée.

**Présence définitive après occurrence.** Proposition conservatrice : PRESENT/ABSENT validés après fin, EXCUSED possible en amont ; les brouillons de préparation ne sont pas des preuves. À tester avec le rythme réel du formateur avant pilote.

**Révision de durée.** Le produit reste adaptable : l’augmentation/réduction d’une séance encore PLANNED est possible avec nouveau contrat commercial explicite et transaction atomique, pas un recalcul automatique depuis le GPS. Aucun prix horaire ou prorata universel n’est inventé.

**Limites inchangées.** Les entretiens, les appareils réels, les fournisseurs, les politiques de conservation et les profils réglementaires restent à valider. La revue V3.2 n’atteste pas que les tarifs des écoles sont à jour ni que le futur service est prêt à déployer. Voir [audit V3.2](audit-corrections-v3-2.md).

<a id="décisions-et-termes-mobiles-v34"></a>
## Décisions et termes mobiles
Les exigences du porteur ajoutent une recherche UI/UX, iOS 26/27, préparation Android et prévention de l’AI slop. Le [registre courant DM01–DM08](changements-v3-4.md#decisions) distingue Swift natif accepté des détails encore ouverts. Le registre V3.3 est historique ; le changement vient de la confirmation du porteur, pas du seul ajout d’un document.

| Terme | Sens dans cette référence |
|---|---|
| SDK | APIs disponibles à la compilation, distinctes du minimum OS utilisateur. |
| Binaire natif | Code Swift et dépendances Apple signés ; version de build distincte du schéma local et du contrat API. |
| Profil de collecte | Implémentation native choisie, permissions, cycle de vie et limites à qualifier sur le binaire. |
| Support qualifié | Appareil/OS/binaire avec résultats d’essais, pas simple cible annoncée. |
| AI slop | Production IA médiocre/non examinée dans le sens de la recherche ; pas un style visuel détectable avec certitude. |
| Suppression globale de compte | Traitement d’identité et données associées, distinct de l’archive d’un dossier scolaire. |

La définition externe et les critères de revue sont dans la [charte](../02-experience/qualite-ui-ux-anti-slop.md). Le contrôle de qualité s’applique aussi au code ou texte écrit manuellement. Aucune nouvelle fonction d’intelligence artificielle n’est ajoutée au produit.


<a id="décisions-techniques-de-réalisation-v34"></a>
## Décisions techniques de réalisation
La pile Apple ne fait plus partie des questions ouvertes : D11 est confirmée. Les décisions DM01–DM08 sont suivies dans le [registre courant V3.13](audit-corrections-v3-13.md#decisions) ; le registre V3.3 est historique. Les minimums d’OS, appareils, bibliothèques et paramètres de capture restent à qualifier. Android ne constitue pas un prérequis de build Apple. DM06 possède désormais un contrat global détaillé ; son implémentation, ses responsabilités, délais, rétentions et le cas du dernier ADMIN restent un blocage avant publication publique.

## Référence des arbitrages et compléments courants

Le [registre courant V3.13](audit-corrections-v3-13.md#decisions) remplace les formulations de « registre courant » des historiques. **Swift natif demeure accepté.** Les détails R106–R108 et les valeurs initiales de préférences sont des propositions pour lever des lacunes, à valider avec les responsables du produit et des écoles. Leur présence dans un schéma n’atteste ni accord commercial ni implémentation.

Le système sait maintenant représenter une remise manuelle de service, le prix détaillé d’un pack et une clôture libérant les droits jamais consommés. Il ne sait pas pour autant réserver un examen officiel, appliquer toute règle de frais déclenchée à la énième leçon, ni régulariser automatiquement une correction pédagogique après libération de droits : R109 prévoit maintenant une résolution explicite séparée de la présence. Ces points restent explicitement bornés dans le catalogue.

DM06 reste ouvert pour la procédure opérationnelle, les délais, les rétentions et le dernier administrateur. La revue peut être interne et manuelle ; le dépôt de la demande ne nécessite pas un appel au support ni une réduction artificielle du nombre d’écoles. Les seuils proposés ne sont jamais une durée légale de conservation.

<a id="arbitrages-et-vocabulaire-v37"></a>
## Arbitrages sur preuves et corrections
**DEC37-A, proposé :** une présence corrigée est conservée indépendamment du crédit. ADMIN résout le droit par décompte disponible du lot d’origine ou renonciation explicite à consommer, jamais remise financière implicite. Faire approuver cette habilitation et la politique avant mise en service. Le parcours auparavant absent est désormais spécifié ; son implémentation et sa validation commerciale ne sont pas acquises.

**DEC37-B, proposé :** une correction d’une preuve source rend la validation courante à réexaminer ; elle ne supprime pas automatiquement des rendez-vous acquis. Valider les règles de contrôle documentaire et les rétentions avec le responsable. Une nouvelle version de profil ne change pas à elle seule les preuves déjà acceptées.

**Glossaire :** `rightSettlement` = suivi d’un droit pédagogique/commercial à régulariser, distinct du solde financier. `basis` = versions des éléments réellement contrôlés pour une décision d’accomplissement. `deliveryEnvironment` = contexte fournisseur d’un token natif. `bindingVersion` = révision serveur du propriétaire de sa liaison technique, pas preuve cryptographique d’appareil.

DM01/DM05/DM06 restent ouverts sur appareils/outils, clés/rétentions et suppression praticable du compte ; ni ces règles supplémentaires ni des schémas valides ne suffisent à les clôturer. Les restrictions de démarrage en ligne, capture unique par bilan et palette commune restent des propositions identifiées, non des exigences nouvellement attribuées au porteur.

<a id="compléments-de-réalisation-v310"></a>
## Décisions de fichiers, export et protection native
Le scellement des fichiers, le PUT conditionnel, la politique des deux sessions HTTP et la couverture des scènes sont des recommandations explicites de réalisation. Fournisseur, plafonds de traitement et nettoyage doivent être qualifiés avant données réelles ; leur choix ne rouvre pas Swift natif ni la direction A. [Décisions et preuves encore nécessaires](audit-corrections-v3-13.md#decisions).
