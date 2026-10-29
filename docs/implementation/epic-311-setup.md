# R09 · Ouverture et préparation de l’école (#320)

## Reprise du 29 octobre 2026

Base intégrée `33232416`, sauvegarde `backup/311-setup-20261029-2050` (`8b2d7fd9`) récupérée sans réécriture de son guide. Le lot ajoute le nouveau rendu d’ouverture et d’opérateur ; il conserve les routes, schémas, droits serveur et commandes existants.

Le guide `portal/setup` utilise les mêmes étapes courtes Permis → Prix et règles → Résumé. L’identité, les textes de confidentialité et les informations élèves sont modifiables depuis le résumé. Un nouveau tarif pour une formation existante conserve son programme et ses règles. Les brouillons restent en mémoire scolaire ou dans le `setup-draft` du serveur ; aucune persistance de données scolaires en stockage navigateur n’est ajoutée. La sauvegarde exige la version attendue, la revue provient du serveur, et l’adoption exige son digest et une confirmation explicite. Une commande encore suivie bloque les nouveaux changements. Une relecture échouée retire la revue précédente.

L’ouverture `portal/opening` réutilise le BFF et le nouveau parcours d’entrée #319. État d’identité, liste et code sont purgés avant un changement de session. Les informations envoyées restent verrouillées si la réponse de création et sa relecture sont toutes deux perdues. Une reprise renvoie la même intention conservée par le BFF. La révocation réutilise le même identifiant d’opération après une réponse incertaine. Les textes de copie annoncent un succès uniquement après confirmation du presse-papiers. Aucun privilège opérateur n’est déduit du rôle d’administrateur scolaire : la liste et les commandes demandent toujours l’autorisation serveur.

## Raccords d’intégration

- Importer `SchoolOpeningPage` depuis `portal/opening/opening-page` pour `/app/ouvrir` et `/app/operateur` ; les props `link` et `operator` sont conservées. Le composant dépend des exports `EntryFrame`, `AccountEntryPanel` et `entryRoutes` du lot #319.
- Importer `SetupGuide` depuis `portal/setup/setup-guide` ; prop `catalogueOnly: boolean`. Remplacer les `NotRebuilt` du mode préparation de `PortalConsole` et des branches école DRAFT / catalogue de `OverviewPilot`. Le contexte métier existant reste unique.
- Ajouter `setupFamily` **avant** `overviewFamily` dans le transport d’aperçu : elle remplace le `setup-draft` ancien, limité à une liste de formations différées. Ajouter `openingFamily` pour les seules routes BFF d’ouverture et d’opérateur. Ces fichiers sont exclusivement sous `portal/preview/families`.
- Routes synthétiques proposées : `?page=ouverture`, `?page=operateur`, `?page=preparation`. La dernière initialise le statut de l’école fictive à DRAFT. Pour l’ouverture synthétique, passer une destination vers cette dernière page, sans naviguer vers le BFF réel.

## Références et portée

R01/R02/R03/R04/R05/R11 et contrats conservés dans le dossier de conception ; schémas réels `school-opening-model`, `server/opening-routes`, `setup-model`, commandes et reçus `saveSetupDraft` / `applySetupDraft`. Les cas d’ouverture postérieurs au dossier sont couverts par les tests BFF existants : perte de réponse, compte différent, reçu durable relu, secret absent des listes, contrôle opérateur et origine/CSRF.

Les contrôles composent les sources shadcn Base UI installées, notamment [Field](https://ui.shadcn.com/docs/components/base/field), [Checkbox](https://ui.shadcn.com/docs/components/base/checkbox), [Dialog](https://ui.shadcn.com/docs/components/base/dialog) et [Button](https://ui.shadcn.com/docs/components/base/button). Aucune ancienne feuille CSS ni présentation `ui.tsx` n’est importée.

## Vérification effectuée

Sous Node 24.22.1 : 32 tests ciblés PASS (`school-opening-model`, `school-opening-bff`, `setup-model`, `setup-guide-model`) ; 3 tests de frontière du portail PASS. Typages client et serveur/tests PASS après correction de la prop optionnelle stricte du guide, avec copie locale des modules d’entrée #319 non incluse dans ce lot. La dépendance d’entrée doit être intégrée avant le lot d’ouverture.

Recette visuelle du guide et de l’opérateur, raccord authentifié, interaction clavier et essai du porteur sur le homelab restent à effectuer sur le commit d’intégration. Cette note ne revendique ni campagne complète, ni nouvelle qualification PostgreSQL, ni déploiement. Le coordinateur reporte cet état dans `STATUS.md` pour éviter un conflit de ce fichier partagé.

## Correction de l’aperçu après intégration

Le contrôle visuel a révélé une collision de route : la famille catalogue répondait à `setup-draft/templates` avant le guide, avec seulement les formations. Cette réponse échouait au contrat de préparation, qui attend aussi la version, la confidentialité et les champs du profil. La famille préparation devient l’unique propriétaire de cette lecture ; sa réponse conserve les propositions pédagogiques et réglementaires B/BE du catalogue ainsi que les exemples A/A1. Les contrôleurs de production et la validation stricte restent identiques.

Deux tests ciblés passent par la même priorité catalogue/préparation/aperçu : réponse commune validée par les deux schémas et brouillon complet de la bonne école. La recette visuelle intégrée doit être relancée après ce correctif.
