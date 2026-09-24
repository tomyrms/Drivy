# Revue corrective de la version 3.11

> 19 septembre 2026 · Source : archive v3.10 fournie par le porteur. Aucun code applicatif livré ou modifié. [Index](../README.md).

## Objet et corrections retenues

La refonte est explicite. Le premier périmètre, la roadmap et les écrans sont consolidés par usage, non par ajout chronologique. Les 56 scénarios initiaux sont précisés et 16 scénarios de saisie pendant la leçon sont ajoutés, tous au statut NOT_EXECUTED.

Les observations privées pendant la leçon sont distinguées de la qualification à l’arrêt et de l’évaluation publiée. Leur besoin a été exprimé par le porteur ; les interactions, statuts et mécanismes détaillés sont des propositions non validées auprès des moniteurs. Les quatre routes existantes AP161–AP164 et l’entité logique GeoObservation sont réutilisées. Les tests de formes JSON et les simulations HTML ne démontrent pas les transactions ni la persistance native.

## Alertes retirées, à ne pas réintroduire

Les vérifications initiales de l’archive passent dans l’environnement de cette révision. L’absence d’une dépendance de format avait donné un échec explicite dans le retour d’audit, pas un faux succès ; FormatChecker était déjà activé. La correction porte sur l’environnement reproductible, les encodages et un précontrôle explicite, pas sur une agrégation défectueuse. Les tokens 3.8 restent inchangés et compatibles, sans renumérotation artificielle. La suppression globale est déjà spécifiée par R103/AP193–AP198 ; DM06 concerne les règles opérationnelles restant à approuver et tester.

## Consolidation et limites

Les six groupes de compléments d’écrans sont intégrés dans les fiches concernées. La roadmap regroupe neuf couches chronologiques dans les étapes G0–G5 et GA0. Le modèle rassemble 113 lignes de tableaux en 101 entrées logiques distinctes, qui comprennent attributs, projections, DTO et groupes : ce n’est pas un décompte de tables physiques ni une expansion de 88 à 101 entités de production. Les autres titres de sections sont clarifiés par sujet et leurs anciennes ancres sont conservées. Il s’agit d’une consolidation ciblée, pas d’une affirmation que chaque paragraphe du dossier est réécrit ou que toute contradiction sémantique est éliminée.

Les méthodes de preuve répétées sont regroupées sans déclarer les cas exécutés. La documentation reste volumineuse ; COMMENCER_ICI et le périmètre de première livraison servent de portes d’entrée. L’historique reste dans l’archive et est identifié séparément dans le lecteur.

## Reproduction et preuves

Les résultats de la présente révision sont enregistrés dans les rapports `verification-*-v3-11.json`, le rapport documentaire courant et le bilan de livraison. Les rapports des versions antérieures restent historiques. [Reproduction](../README.md#reproduire-les-contrôles) · [Traçabilité](tracabilite.md) · [Contrats ajoutés](../annexes/cas-contrats-v3-11.json).

Les contrôles listés dans la revue de cohérence ont été exécutés dans l’environnement Linux indiqué dans les rapports. Ils concernent les fichiers livrés, pas une application fonctionnelle.

<a id="decisions"></a>
## Décisions qui restent ouvertes

| Sujet | Statut courant et prochaine preuve utile |
|---|---|
| Swift natif / DA A | Décisions conservées, pas remises en concurrence. Détails de rendu et intégration à tester. |
| Stockage et scellement | Profil proposé à qualifier sur le fournisseur réel : PUT conditionnel imposé, copies/versions, taille/quota, nettoyage, scan et concurrence. Aucun abonnement AWS imposé par l’exemple. |
| Limites des fichiers | Taille de contrat conservée ; plafonds de décodage/mémoire/pages/temps, durée d’intention et purge à fixer avant données réelles. Pas de valeurs légales inventées. |
| Cache et snapshot | Preuve par inspection du build, de ses fichiers et de ses scènes sur appareils, y compris verrouillage et capture active. Aucun test navigateur ne la remplace. |
| GPS et interruptions | Autorisation initiale en ligne et une capture par publication restent limites explicites ; préautorisation/fusion nécessitent arbitrage avant modification. |
| Droits et conditions commerciales | Les politiques de régularisation/renonciation, frais et conservation restent proposées aux écoles ; aucun nouveau prélèvement automatique. |
| DM06 | Suppression globale contractualisée ; responsabilités, délais, rétentions et dernier ADMIN restent à qualifier avant publication publique. |
| Écrans non dessinés | Toujours 15 compositions pour 16 références sur 49 ; les nouveaux états de fichiers/exports sont spécifiés, pas tous illustrés. |
| Android | Client futur distinct ; aucun essai Apple ne qualifie Android. |


Aucun entretien utilisateur, validation de prix, coût fournisseur, chiffrage d’équipe, test sur route, audit juridique ni build Swift n’a été inventé. Le protocole de recherche, l’hypothèse commerciale, l’internationalisation, les mineurs et représentants légaux, l’estimation par lots et la transition du code sont maintenant explicités. DM06, la qualification native et la sécurité d’utilisation restent des portes de validation. Le détail des choix d’interaction live est à confirmer avec le porteur puis avec les usages.

## Mesures de la correction

| Élément | Avant | Après |
|---|---|---|
| Documents Markdown, historique inclus | 75 | 78 : guide de départ, périmètre par objet, audit courant ajoutés |
| « Quand » génériques dans les scénarios | 56 | 0 pour cette formulation ; T001–T056 réécrits |
| Paragraphes de preuve génériques | Répétés dans les scénarios | 350 factorisés vers un protocole partagé ; 56 preuves spécifiques réécrites et 16 nouvelles |
| Scénarios métier spécifiés | 406 | 422, tous NOT_EXECUTED |
| Cas JSON de contrôle documentaire | 278 | 298, dont 20 spécifiques au parcours live |
| Lectures/écritures texte implicites corrigées | 35 scripts concernés | 209 appels rendus explicitement UTF-8 |
| Catalogue de tests, octets UTF-8 | 338 148 | 267 032 |
| Roadmap, octets UTF-8 | 15 693 | 10 255 |
| Contrat | 201 opérations / 376 schémas | Même nombre ; quatre schémas existants adaptés, pas de nouvelles routes |

Les neuf familles de contrôles couvrent environnement, documentation, référence héritée, fichiers, spécifications mobiles, design, prototype existant, saisie live du prototype et lecteur. Les assertions incluent **298 cas JSON** (115 positifs et 183 négatifs), **72 contrôles du prototype existant**, **23 contrôles du parcours live**, **128 variantes de rendu ordinaire** et **120 variantes à texte agrandi**, ainsi que la navigation du lecteur. Ces ensembles sont de natures différentes et ne sont pas additionnés pour annoncer un faux nombre de tests produit.

Les quatre formes de commandes live extraites du navigateur sont également vérifiées contre le contrat. Les données restent fictives et volatiles ; les commandes ne sont envoyées à aucun service. Le replay élève ne reçoit pas les observations privées de la démonstration. Aucun résultat de recette native n’est créé.

Le [relevé des mesures](../annexes/mesures-corrections-v3-11.json), le [registre des corrections de scénarios](../annexes/consolidation-tests-v3-11.json) et le [registre des consolidations](../annexes/consolidation-sections-v3-11.json) rendent ces changements consultables. Le [diff des sources textuelles](../annexes/corrections-v3-10-vers-v3-11.patch) permet de les relire. Les octets de l’archive originale restent intacts ; les changements d’encodage concernent uniquement la copie révisée.

## Versions et compatibilité à ne pas surinterpréter

La version documentaire 3.11 ne valide pas le déploiement d’un service. Les anciens corps REVIEW restent compatibles avec les schémas de cette proposition ; la saisie LIVE exige les nouveaux champs et les règles de service décrites. Cette compatibilité de forme ne démontre ni migration de données réussie, ni absence de régression d’une application existante. Les états de fermeture, d’arrivée tardive et de conflit restent des scénarios à implémenter et tester.
