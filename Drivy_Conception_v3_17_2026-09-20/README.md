# Drivy · Dossier de conception V3.17

> 20 septembre 2026 · 88 documents Markdown · Refonte en Swift natif pour iPhone/iPad, Android ultérieurement.

## Voir l’application

**[Ouvrir le prototype unifié](DESIGN/APPLICATION.html)** : Séance, Agenda, Élèves, dossiers, bilans, documents, compte et espace élève. **[Accéder directement à la carte](DESIGN/LECON.html)** utilise les mêmes sources et composants.

![Séance, agenda, élèves et dossier](DESIGN/assets/application-v3-17/00_parcours_moniteur_clair.png)

[Vue sombre](DESIGN/assets/application-v3-17/00_parcours_moniteur_sombre.png) · [Bilans et parcours élève](DESIGN/assets/application-v3-17/00_bilans_et_eleve.png) · [Dossier sur iPad](DESIGN/assets/application-v3-17/17_ipad_dossier.png).

Cette passe applique la direction appréciée de V3.15/V3.16 aux autres parcours. **Même fonction, même composant source ; variation documentée seulement lorsque l’action ou l’espace l’exige.** La carte reste dominante pendant la leçon, pas sur un formulaire ou une liste de documents. Les détails pédagogiques restent dans le bilan plutôt que dans les commandes.

## Commencer

Lire [COMMENCER_ICI](COMMENCER_ICI.md), la [synthèse](00-synthese.md), l’[audit courant](06-gouvernance/audit-corrections-v3-17.md) ou ouvrir [LIRE_DOSSIER.html](LIRE_DOSSIER.html). La [matrice des écrans](DESIGN/couverture-ecrans.json) et le [registre des composants](DESIGN/composants-usage.json) distinguent ce qui est composé, historique ou seulement spécifié.

**20 compositions actuelles couvrent 17 écrans métier existants.** La galerie complémentaire apporte six autres écrans illustrés : 23/49 ont au moins une illustration, 26 n’en ont pas encore. Les 49 fiches reçoivent une correspondance de composants, ce qui n’équivaut pas à 49 écrans redessinés. La planche de composants de l’atelier est un outil de revue, pas une destination utilisateur.

## Recherche et cohérence

La [recherche complémentaire](01-recherche/coherence-application.md) s’appuie sur les pages et captures officielles de Fantastical, Cardhop, Bear, Linear et Things, puis sur les recommandations Apple de listes et d’onglets. Ces sources inspirent la composition, pas de nouvelles fonctions à ajouter arbitrairement.

La navigation moniteur conserve Séance / Agenda / Élèves / École ; celle de l’élève conserve Mes leçons / Agenda / Mon parcours. Les champs, lignes, confirmations, observations et sélecteurs partagent leurs sources. Les différences entre navigation, sélection, enregistrement et publication restent explicites.

<a id="reproduire-les-contrôles"></a>

## Fabriquer et contrôler

`python annexes/generer-atelier.py` génère les deux entrées depuis `DESIGN/atelier/`. `python annexes/exporter-application.py --chromium CHEMIN` produit les captures des nouvelles compositions. `python annexes/generer-lecteur.py` régénère le lecteur. La [revue de cohérence](06-gouvernance/revue-coherence.md) détaille les contrôles, les dépendances et les rapports de cette passe.

La source V3.16 est vérifiée avant transformation. OpenAPI **3.11.0**, tokens **3.8** et registres métier conservent leur version et leur contenu. Le numéro de livraison n’est pas recopié dans les artefacts inchangés. Les exports SVG déjà présents sont ceux des quatre vues V3.16 ; aucun fichier Figma natif ni nouveau jeu SVG des autres écrans n’est revendiqué.

## Limites

HTML local et données fictives en mémoire : aucun compte réel, serveur, stockage durable, GPS/MapKit, notification push ou paiement. La réservation et la publication sont simulées explicitement ; la séparation visuelle des rôles n’est pas une autorisation serveur. La capture du 21 septembre et le bilan du 18 septembre sont des fixtures séparées, pas un parcours de conversion automatique implémenté. Les cours, packs, finances, onboarding et administration complète ne sont pas redessinés ici.

Les suites exécutées portent sur Chromium chargé via `page.set_content` ; `file://` n’est pas qualifié dans cet environnement. Les **434 scénarios métier et 68 scénarios mobiles restent NOT_EXECUTED** sur le produit. Aucun essai utilisateur, route, SwiftUI, Safari, Windows, VoiceOver natif, batterie ou validation juridique. Les anciens rapports non rejoués restent historiques.

## Index des documents

### Entrées principales

- [Synthèse : Drivy, sur le terrain et au bureau](00-synthese.md)
- [Fonctionnalités prévues de Drivy](01-fonctionnalites-prevues.md)
- [Commencer ici : refonte de Drivy](COMMENCER_ICI.md)

### 01-recherche

- [Cohérence de l’application et recherche complémentaire](01-recherche/coherence-application.md)

- [Benchmark visuel des applications et transposition](01-recherche/benchmark-visuel-apps.md)
- [Recherche visuelle complémentaire et affinage](01-recherche/affinage-visuel.md)

- [Audit fonctionnel de l’archive et limites de preuve](01-recherche/audit-existant.md)
- [Dix auto-écoles suisses : observations et traduction dans Drivy](01-recherche/auto-ecoles-suisses.md)
- [Benchmark observé et enseignements de conception](01-recherche/benchmark.md)
- [Inventaire fonctionnel et matrice de décision](01-recherche/inventaire-decisions.md)
- [Recherche UI/UX et mobile : décisions pour Drivy](01-recherche/ui-ux-mobile-etat-art.md)
- [Vision produit et périmètre de référence](01-recherche/vision-perimetre.md)
- [Web, tablettes et accueil : fondements et limites de preuve](01-recherche/web-tablette-onboarding.md)

### 02-experience

- [Architecture de l’information : terrain, apprentissage et gestion](02-experience/architecture-information.md)
- [Système de design, états et accessibilité](02-experience/design-system.md)
- [Direction choisie et historique des explorations](02-experience/directions-artistiques.md)
- [Spécifications des 49 écrans et de leurs états](02-experience/ecrans.md)
- [Parcours de bout en bout et exceptions](02-experience/parcours.md)
- [Patterns appliqués : téléphone, tablette et web](02-experience/patterns-mobile-parcours.md)
- [Une expérience cohérente sur téléphone, tablette et web](02-experience/plateformes-tablette-web.md)
- [Qualité UI/UX et prévention de l’AI slop](02-experience/qualite-ui-ux-anti-slop.md)
- [Wireframes documentaires du cœur GPS et des cours](02-experience/wireframes.md)

### 03-fonctionnel

- [Bilans, progression et documents](03-fonctionnel/bilans-documents.md)
- [F19 : calendrier d’offres et notifications ciblées](03-fonctionnel/calendrier-notifications.md)
- [F17 : prestations, packs composites et droits de consommation](03-fonctionnel/catalogue-packs.md)
- [Supprimer son compte Drivy : parcours global](03-fonctionnel/compte-suppression-globale.md)
- [F18 : cours collectifs, inscription volontaire et présences](03-fonctionnel/cours-collectifs.md)
- [Extensions, reclassements et exclusions](03-fonctionnel/extensions.md)
- [Espace web de gestion et cycle de vie des élèves](03-fonctionnel/gestion-web-archivage.md)
- [F15 et F16 : capture volontaire, replay et apprentissage](03-fonctionnel/gps-replay.md)
- [Hors ligne, archivage et droits sur les données](03-fonctionnel/hors-ligne-vie-privee.md)
- [Identités, formations et administration](03-fonctionnel/identites-formations.md)
- [Accueil progressif : école, moniteur et élève](03-fonctionnel/onboarding.md)
- [Journal de règlements et communications](03-fonctionnel/paiements-communications.md)
- [Disponibilités, réservation, préparation et résultat](03-fonctionnel/planning-lecons.md)
- [Règles métier et machines à états](03-fonctionnel/regles-etats.md)
- [Rôles, périmètres et changements d’accès](03-fonctionnel/roles-permissions.md)
- [Statistiques d’activité : définitions, portée et contrôle](03-fonctionnel/statistiques.md)

### 04-technique

- [Contrats API, erreurs et exemples de transaction](04-technique/api.md)
- [Architecture du client Apple en Swift natif](04-technique/architecture-client-swift.md)
- [Architecture cible et décisions techniques argumentées](04-technique/architecture-decisions.md)
- [Fichiers, temps, formats et communications](04-technique/fichiers-temps-communications.md)
- [Intégration Swift native : iOS et iPadOS 26 / 27](04-technique/integration-ios-ipados.md)
- [Intégration mobile transverse : frontières, cycle de vie et distribution](04-technique/integration-mobile-transverse.md)
- [Modèle de données, contraintes et cycles de vie](04-technique/modele-donnees.md)
- [Préparer Android : client futur distinct et contrats communs](04-technique/preparation-android.md)
- [Sécurité, données personnelles et cadre suisse à valider](04-technique/securite-vie-privee.md)
- [Synchronisation, concurrence et continuité hors ligne](04-technique/synchronisation.md)
- [Transactions critiques : GPS, packs et places de cours](04-technique/transactions-v2.md)
- [Transactions V3 : accueil, archivage, appareils et mesures](04-technique/transactions-v3.md)

### 05-realisation

- [Déploiement, observabilité et procédures d’exploitation](05-realisation/deploiement-exploitation.md)
- [Migration éventuelle, conservation et transition](05-realisation/migration.md)
- [Périmètre de la première livraison : objets et justification](05-realisation/perimetre-premiere-livraison.md)
- [Qualification mobile et UI/UX](05-realisation/qualification-mobile-ui-ux.md)
- [Roadmap : décisions et critères par tranche](05-realisation/roadmap-backlog.md)
- [Stratégie de tests, fixtures et recettes détaillées](05-realisation/tests-recette.md)

### Historique conservé

- [Audit et corrections : Drivy V3 vers V3.1](06-gouvernance/audit-corrections-v3-1.md)
- [Audit V3.10 : fichiers fiables, exports cohérents et confidentialité native](06-gouvernance/audit-corrections-v3-10.md)
- [Deuxième revue : corrections de Drivy V3.1 vers V3.2](06-gouvernance/audit-corrections-v3-2.md)
- [Revue complète et compléments : Drivy V3.4 vers V3.5](06-gouvernance/audit-corrections-v3-5.md)
- [Audit et consolidation : Drivy V3.5 vers V3.6](06-gouvernance/audit-corrections-v3-6.md)
- [Recherches et corrections : Drivy V3.6 vers V3.7](06-gouvernance/audit-corrections-v3-7.md)
- [Audit V3.9 : relier le design aux vrais états de Drivy](06-gouvernance/audit-corrections-v3-9.md)
- [Journal de consolidation : de la V1 à Drivy V2](06-gouvernance/changements-v2.md)
- [Enrichissement V3.3 : UI/UX, iOS 26/27 et préparation Android](06-gouvernance/changements-v3-3.md)
- [V3.4 : Swift natif devient la référence Apple](06-gouvernance/changements-v3-4.md)
- [V3.8 · Direction A et dossier design concret](06-gouvernance/changements-v3-8.md)
- [Journal de consolidation : Drivy V2 vers V3](06-gouvernance/changements-v3.md)

### 06-gouvernance

- [Audit courant V3.17 : application et composants communs](06-gouvernance/audit-corrections-v3-17.md)

- [Historique de la direction V3.15](06-gouvernance/audit-corrections-v3-15.md)

- [Historique de l’affinage V3.16](06-gouvernance/audit-corrections-v3-16.md)
- [Revue corrective de la version 3.11](06-gouvernance/audit-corrections-v3-11.md) [historique]
- [Glossaire, décisions et questions de validation](06-gouvernance/glossaire-decisions-questions.md)
- [Revue de cohérence documentaire V3.17](06-gouvernance/revue-coherence.md)
- [Sources, provenance et limites](06-gouvernance/sources.md)
- [Traçabilité de la référence active](06-gouvernance/tracabilite.md)

### DESIGN

- [Passage vers Figma et exports vectoriels](DESIGN/PASSAGE_FIGMA.md)

- [Direction A · Cartographie native](DESIGN/01-direction-artistique.md)
- [Composants · Anatomie et comportement](DESIGN/02-composants.md)
- [Carte, capture et replay · Grammaire visuelle](DESIGN/03-cartographie.md)
- [Écrans de référence et couverture](DESIGN/04-ecrans-reference.md)
- [Contenu et états · Dire exactement ce qui se passe](DESIGN/05-contenu-etats.md)
- [Livraison du design et recette](DESIGN/06-livraison-validation.md)
- [DESIGN · Drivy / Cartographie native](DESIGN/README.md)

