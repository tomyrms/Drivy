# Journal de consolidation : de la V1 à Drivy V2

> **Historique conservé, non normatif pour la technologie mobile.** La décision Swift de la [V3.4](changements-v3-4.md) remplace les recommandations mobiles antérieures ; les constats et résultats ci-dessous restent ceux de leur version d’origine.
> Historique V1→V2 conservé. La référence active est V3.1 ; voir [la revue corrective](audit-corrections-v3-1.md).

> Drivy · Référence de conception 3.0 · 19 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

## Périmètre de remplacement

Ce dossier remplace la référence proposée en V1 et absorbe le complément GPS/auto-écoles. Il n’est pas nécessaire de combiner les règles de trois dossiers pour comprendre le cœur. Les originaux restent intacts comme historique ; aucun code de l’application n’est modifié.

## Changements motivés par le porteur

| Point V1 | Décision V2 | Conséquences propagées |
|---|---|---|
| Normalisation du nom (ancienne passe) | Annulée en V3.13 | Le nom officiel reste Drivy ; la passe précédente avait interprété le brief à tort. |
| GPS/replay en U01 | F15/F16 dans le cœur | Vision, parcours, états, UX, modèle, ingestion, API, sécurité, prototype précoce et recette. |
| Socle surtout administratif | Leçon et apprentissage à partir du trajet | Carte fonctionnelle au bon contexte ; alternative complète sans enregistrement. |
| Packs reportés avec PSP | F17 distinct des paiements en ligne | Services versionnés, achats, droits, comptes et tests de double facturation. |
| Auto-réservation globalement différée | F18 pour séries collectives, U04 pour leçons individuelles | Places atomiques, présence par bloc, reconfirmation et calendrier élève. |
| Agenda uniquement d’engagements | F19 : engagements + offres | Une offre visible ne réserve rien, pas de doublon après inscription. |
| Push secondaire | Service et ciblage dans F11/F19 | Outbox/campagnes, préférences et statuts d’exigence, refus push supporté. |
| Prérequis secondaires | Exigences nécessaires aux cours intégrées | Preuves externes, multi-permis et validation humaine. |
| Carte comme risque à éviter | Risque à qualifier en G0 | Client RN/Expo reste conditionnel à la capture appareil. |

## Traçabilité et compatibilité documentaire

F01–F14, R01–R40, J01–J11, E01–E21, AP01–AP95 et T001–T096 sont conservés ; leur définition est mise à jour lorsqu’une nouvelle exigence change le comportement. F15–F19, R41–R72, J12–J18 et E22–E32 complètent le cœur. U01 reste un identifiant historique reclassé, pas une extension active à faire plus tard. Les nouvelles API et recettes figurent dans les registres générés.

Les preuves statiques de l’archive et leurs empreintes sont conservées sans prétendre à un nouvel audit dynamique. La recherche d’écoles est intégrée avec faits/inférences séparés. Les contraintes réglementaires 2027 non complètement qualifiées restent une question ciblée, et non une fausse certitude.

## Points volontairement non réalisés

Aucune compilation iOS/Android, aucun serveur, aucune migration réelle, aucun test de conduite, aucune inscription réelle et aucun envoi de notification à un élève. Pas d’entretien revendiqué avec Luc’s ou les autres écoles. Les contrôles exécutés portent sur la documentation et sont listés dans la revue.
