# Échéance avant réservation individuelle — S12, 28 octobre 2026

Le récapitulatif d’une nouvelle leçon affiche « Annulation : prévenir l’école au plus tard… » lorsque la version de procédure sélectionnée contient une règle structurée `CONTACT` avec un nombre d’heures connu. La date vient exclusivement de `plannedStart − cancellationHours × 3600 secondes`, puis est présentée dans le fuseau de l’école. Une traversée de changement d’heure ne transforme pas 24 heures en un jour civil.

`school_policy_version.cancellation_rules` est un JSONB nullable :

```json
{"cancellationHours":24,"lateAction":"CONTACT"}
```

La migration `20261028_individual_cancellation_rules.sql` accepte seulement ces deux propriétés, `lateAction` valant `CONTACT` ou `NO_FEE`, et un nombre entier d’heures de 0 à 8760 ou `null`. Elle ne remplit aucune ancienne ligne et ne déduit rien des textes. `NULL`, champ absent, heures inconnues et `NO_FEE` ne produisent aucune échéance. Les décodeurs Swift/web acceptent les anciennes réponses sans ce champ.

La publication de nouvelles procédures par le guide conserve la règle relue avec sa version. Le récapitulatif consulte la procédure associée à l’offre choisie, pas une règle globale plus récente. Les déplacements restent hors de cette lecture : leurs conditions existantes ne sont pas remplacées par celles de l’offre actuelle. Les anciennes réservations gardent leur référence de procédure.

Cette échéance n’annule aucune leçon, ne réserve aucun droit à une indemnité et ne facture aucun montant. Les textes d’annulation restent consultables ; contacter l’école ne confirme pas une annulation. Les routes et les décisions d’annulation existantes ne sont pas modifiées par cette sous-tranche.

Vérification exécutée : contrôle TypeScript API et web, réussi. Fixtures web et Swift préparées pour les deux changements d’heure à Zurich, zéro heure, règle absente/null, absence de frais et ancien JSON ; **non exécutées**. Migration SQL **non exécutée**, comportement PostgreSQL **non qualifié**. Swift et l’affichage natif doivent être compilés sur le runner Apple ; aucune recette physique ou d’accessibilité revendiquée.

La migration doit précéder la release API qui lit cette colonne. Aucun déploiement ou changement de données existantes n’a été réalisé par cette sous-tranche.
