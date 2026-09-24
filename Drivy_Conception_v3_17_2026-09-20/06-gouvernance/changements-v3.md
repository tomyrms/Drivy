# Journal de consolidation : Drivy V2 vers V3

> **Historique conservé, non normatif pour la technologie mobile.** La décision Swift de la [V3.4](changements-v3-4.md) remplace les recommandations mobiles antérieures ; les constats et résultats ci-dessous restent ceux de leur version d’origine.
> Drivy · Référence de conception 3.0 · 19 septembre 2026
> Exigences intégrées ; solutions proposées à valider. [Index](../README.md).

> **Historique conservé.** La référence active est désormais la V3.1 ; voir [audit et corrections](audit-corrections-v3-1.md).

## Référence livrée

V3 remplace V2 pour développer la nouvelle application. Le journal [V1→V2](changements-v2.md) reste un historique, pas une seconde référence active. Les archives et le code d’origine restent inchangés. Le nom du produit reste **Drivy**, sans e.

## Exigences conservées

GPS/replay comme cœur pédagogique, collecte facultative par leçon, adaptation des prestations/packs aux écoles, cours collectifs publiés comme offres, notification ciblée, inscription volontaire et capacité serveur, séparation présence/paiement/validation. La recherche des dix écoles est conservée avec ses limites et dates.

## Changements de conception

| Sujet | V2 | V3 |
|---|---|---|
| Web | Client cible, gestion détaillée moins spécifiée | Workspace selon rôle : élèves, cours, offres, paramètres, activité ; même compte/services |
| Tablette | Adaptation générale, capture centrée hypothèse téléphone | Support premier rang de tous modules, composition dédiée et qualification appareil GPS |
| Architecture client | Mutualisation RN/Expo incluant web envisagée | Natif RN/Expo + web React DOM ; contrats/tokens partagés, pas UI forcée identique |
| Onboarding | Invitation et configuration fonctionnelles | F20 école, F21 élève/moniteur, sauvegarde/reprise, capacité et politique bornées |
| Profil élève | Dossier minimal et pièces | Identité administrative séparée, champs conditionnels, photo facultative privée |
| Formation souhaitée | Création personnel | Demande élève puis validation F03, sans approbation automatique |
| Archive | Principes F14 | Preview, blocages, lot50, restauration ; archive ne révoque pas Membership |
| Statistiques | U06 secondaire dans l’ensemble | F23 pour M01–M09 définis ; avancé seulement reste U06 |
| Recette | T001–T162 | T163–T232 ajoutés, tous encore non exécutés |

## Identifiants

F20–F23, B12–B15, C61–C72, J19–J28, E33–E48, R73–R100, AP165–AP191, T163–T232, D25–D32, S48–S58 sont ajoutés. R29/R70 distinguent archive et accès ; R42 est complétée par R83. C06/C39/C40/C47 sont explicitement reclassées/élargies. Les identifiants historiques ne sont pas réassignés.

Les schémas OpenAPI nommés avec suffixe V2 restent des noms techniques conservés ; le contrat courant est3.0. Le chemin HTTP /v1 ne signifie pas compatibilité avec l’ancienne API Drivy : il est le namespace proposé d’une application nouvelle, non implémentée.

## Arbitrages proposés et non validés par silence

Pilote iPhone+iPad+web, Android ultérieurement qualifié ; React DOM/Vite côté web ; archive sans révocation automatique ; limites15min preview/50lignes lot/10klignes export/24h export ; champs de profil et métriques retenues. Le porteur a demandé les capacités, pas chacune de ces valeurs. Les validations terrain, technique, juridique et commerciale sont dans le registre/roadmap.

## Vérifications

Les contrôles effectivement exécutés sont consignés dans [Revue de cohérence](revue-coherence.md), avec rapport JSON et manifeste d’intégrité. Les tests de produit, visites d’auto-écoles, qualification iPad et builds natifs ne sont pas revendiqués comme réalisés.
