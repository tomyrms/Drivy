# R01-T09 — Relances, suspension et réactivation (#461)

Branche `tomyrms/r01-t09-relances-suspension`, issue de la tête de `tomyrms/r01-t08-espace-ecole`. Rien n'a été poussé, fusionné ni déployé.
Règle du porteur du 13 novembre : aucun test n'est exécuté avant la fin de l'épic R01. La migration, les routes et les écrans n'ont donc jamais tourné.

## Règle retenue

- Suspension après deux mois calendaires depuis l'échéance de la plus ancienne somme encore due. Le délai se règle globalement (1 à 12 mois) et par exception d'école (1 à 24 mois).
- Fin de mois bornée : 31 décembre + 2 mois donne le 28 ou 29 février. Le calcul porte sur des dates, le jour courant est celui de Zurich.
- Un paiement partiel laisse la facture en tête : l'ancienneté ne repart pas de zéro. Un rappel ne la modifie pas non plus.
- La politique est créée **désactivée** : ni rappel, ni avertissement, ni suspension tant qu'un opérateur ne l'a pas activée. La suspension automatique exige les rappels actifs.

## Modèle

Migration `20261121_platform_dunning_suspension.sql`. Aucune donnée n'est créée, `school.status` n'est jamais modifié.

- `platform_dunning_policy` : paliers de rappel (3, 15 et 30 jours par défaut), délai, avertissement (14 jours), alerte de fin d'essai (7 jours), versionnés.
- `platform_dunning_exception` : `DELAY` ou `HOLD`, temporaire, motivée, une seule active par fiche, révocable.
- `platform_dunning_step` : une étape par facture, cycle et palier. Cette unicité rend un passage relancé sans double effet.
- `platform_commercial_suspension` : causes `PAYMENT` et `MANUAL` distinctes, seul le passage `ACTIVE` vers `LIFTED` est permis.
- `platform_commercial_alert` : fin d'essai, nouveau retard, remise en échec, suspension à venir ou effective.
- RLS forcée sur ces tables, aucun droit direct pour l'application.

## Décisions

- Une date de suspension annoncée n'est jamais avancée.
- Seul un avertissement lu, envoyé ou confirmé par un opérateur autorise la suspension automatique. Une remise en échec ouvre une alerte et attend une confirmation motivée.
- Le règlement qui solde la dette lève la suspension `PAYMENT` dans la même transaction. Il ne lève ni une suspension `MANUAL`, ni une résiliation, ni un archivage.
- Facturation pendant la suspension : selon le paramètre du contrat. En `PAUSE`, aucune période n'est préparée et les factures émises restent intactes.

## Opérations pendant une suspension

- Fermées au serveur, quel que soit l'âge du client : création, leçon improvisée, déplacement, invitation et renvoi, formation, attribution, examen. Les modules sont fermés par leur propre droit.
- Permises : lecture, rejeu d'un reçu, démarrage et fin d'une leçon déjà planifiée, capture et envoi du trajet, observations, bilan, annulation, demande de changement d'un élève, synchronisation.
- Le refus est un 403 `MODULE_NOT_ENTITLED`. L'iPhone et l'iPad affichent le motif renvoyé par le serveur au lieu de « Tes accès ont changé ».

## Routes et interfaces

- `/v1/platform/dunning/policy`, `/v1/platform/dunning/run`, `/v1/platform/commercial-alerts` et les commandes du dossier de relance d'une fiche.
- Contrat `platform-dunning.json` généré, OpenAPI canonique 3.11.0 non modifié. Routes déclarées dans la passerelle web.
- Console : rubrique des relances et dossier de la fiche. Espace école : facture, échéance et reste dû, sans motif, auteur ni exception.
- Le service `billing-worker` enchaîne la facturation puis les relances, avec des compteurs seulement dans les journaux.

## Limites

- Les rappels sont des avis dans l'espace école et des notifications push. Aucun courriel n'est envoyé (pas de SMTP sur le homelab) et le rappel avec QR au solde n'est pas réalisé.
- Sans responsable joignable, l'avertissement reste sans remise : la suspension automatique attend alors la confirmation d'un opérateur.

## Tests écrits, jamais exécutés

- `apps/api/test/platform-dunning.integration.test.ts` : 17 cas (politique, droits, fin de mois, fuseau, paiement partiel, idempotence, avertissement, remise en échec, causes distinctes, exceptions, archivage, pause, opérations permises et fermées, alertes, vue école, garde-fous).
- Compléments dans `subscription-model.test.ts` et `SchoolEntitlementsTests.swift`.

## Reste à qualifier

- Migration et scénarios sur PostgreSQL, dont la concurrence paiement contre suspension.
- Console et espace école dans un navigateur, sur mobile et ordinateur, avec clavier et lecteur d'écran.
- Code Swift : non compilé. Refus affiché sur iPhone et iPad à vérifier.
- Notification push réelle.
