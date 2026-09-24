# V3.8 · Direction A et dossier design concret

> 19 septembre 2026 · [Index](../README.md) · [Dossier DESIGN](../DESIGN/README.md).

## Décision acceptée et portée

Le porteur choisit **A · Cartographie native**, claire, précise et bleue. La V3.8 remplace la recommandation ivoire/pétrole dans les références actives. Les dimensions, la palette sombre, les détails de composants et les maquettes sont une proposition de réalisation de cette direction, pas un résultat déjà validé avec les écoles.

Cette passe complète le design, **pas un nouvel audit exhaustif de tous les domaines métier**. Swift natif, GPS facultatif, web, tablette, cours volontaires, packs et Android futur sont conservés. Aucun code de l’application d’origine n’est modifié. Le HTML/CSS/SVG livré sert de prototype documentaire, sans service réel, API ou collecte de positions.

## Ce qui est livré

`DESIGN` devient l’entrée visible : direction, composants détaillés, langage cartographique, compositions, microtextes et recette. La palette canonique reste dans `02-experience/design-system.md` et `annexes/tokens-proposition.json`, pour conserver les liens existants et éviter un second jeu de valeurs contradictoire.

Le prototype contient **14 compositions** en clair et sombre : séance avant départ, capture, alternative sans GPS, replay, agenda élève, cours collectif, bilan, profil, pack, capture iPad, agenda iPad, élèves web, activité et configuration école. Elles illustrent **15 des 49 références E**, parfois plusieurs compositions pour un même écran. Les **34 autres écrans** gardent leurs spécifications fonctionnelles et une famille graphique attribuée ; ils ne sont pas prétendus dessinés. Le JSON de couverture est contrôlable.

DS01–DS16 sont conservés et détaillés ; DS17–DS24 complètent les besoins visuels du cœur. Le symbole « D » de la galerie est un repère de présentation provisoire, **pas une icône App Store approuvée**. Aucun fichier de police ou fond de carte tiers n’est livré. Les tracés, noms, prix et dates des maquettes sont fictifs.

## Contradictions visuelles résolues

| Référence | Résolution |
|---|---|
| Ancienne DA encore proposée | Direction A acceptée dans le système de design, D05, Q07, synthèse et index ; anciennes pistes explicitement historiques. |
| Ancienne palette ivoire/pétrole | Valeurs sémantiques bleues claires/sombres propagées aux tokens et au prototype ; pas de remplacement aveugle dans les anciennes preuves. |
| Accent scolaire sous-entendu | Nom/logo/contacts conservés ; pas de recoloration libre de la carte ou des états par l’école au pilote. |
| Design uniquement textuel | Prototype et captures réellement créés ; couverture illustrée distincte de la spécification des autres écrans. |
| États simulés ambigus | Aucune trace avant une mesure fictive admissible ; offre et engagement séparés ; confirmation en cours non assimilée à inscrit ; retrait de trajet sans géométrie. |
| GPS et bilan | L’arrêt de capture ne déclare pas la leçon réalisée. Le passage vers le bilan simulé demande de choisir le scénario de séance réalisée ; aucune évaluation n’est présélectionnée. |

Les corrections du prototype ne prouvent pas des bugs de l’ancienne application. Elles font correspondre une nouvelle représentation visuelle aux règles existantes.

## Contrat, statuts et historique

Le contrat OpenAPI est **identique octet pour octet à V3.7**, avec `info.version=3.7.0` : 201 opérations et 374 schémas. La documentation passe à 3.8 et le registre documentaire l’indique. Aucun endpoint, règle métier, scénario T ou MOB n’est ajouté pour gonfler le périmètre d’une passe graphique.

Les 382 scénarios métier et 60 scénarios mobiles restent NOT_EXECUTED. Les vingt critères UX du design sont à appliquer au produit, non des tests natifs réussis. Les anciens rapports demeurent historiques ; les résultats de cette passe figurent dans la [revue courante](revue-coherence.md).

## Recherche et limites

Huit sources primaires Apple/W3C, [S118–S125](sources.md#s118), soutiennent les règles de matériaux, typographie, contraste, couleur, reflow et focus. Les pages HTML Apple nécessitant JavaScript ont été complétées par leurs documents JSON officiels. Ce n’est ni une étude utilisateur ni une nouvelle vérification de toutes les versions iOS, tarifs ou règles suisses.

Les contrôles calculent 36 paires de couleurs opaques et vérifient les liens et registres. Les tests du navigateur examinent le prototype : rendu, scénarios, recherche et navigation. Ils ne certifient pas l’accessibilité de l’app, le rendu Liquid Glass ou l’équivalence avec VoiceOver/Dynamic Type. Le rendu MapKit reste à intégrer et qualifier sur matériel Apple.

## Ce qui reste à décider ou réaliser

La direction est choisie ; restent la validation visuelle avec le porteur, les essais moniteur/élève, les maquettes détaillées des états non illustrés selon les tranches, l’icône/les actifs de marque finaux et le premier parcours Swift réellement exécuté. Les responsabilités, conditions commerciales, minimums d’OS et questions GPS de V3.7 restent au [registre](glossaire-decisions-questions.md). Une capture de navigateur ne les résout pas.
