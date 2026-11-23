# Tableau de bord commercial (R01-T10, #462)

Lecture seule de la console plateforme, ouverte par défaut. `GET /v1/platform/dashboard?from&to` appelle `drivy.platform_commercial_dashboard`, sans nouvelle table. La fonction relit l'opérateur et réutilise les calculs des droits, du règlement des factures, de la dette, des conditions et des relances.

## Définitions

| Indicateur | Définition |
| --- | --- |
| Situation | État commercial exclusif : résiliée, archivée, suspendue, essai terminé, essai, active, préparation. L'état métier de l'école (`preparation`) reste un champ distinct. |
| Facturé, avoirs | Documents émis dont la date d'émission est dans la période. |
| Encaissé | Règlements enregistrés reçus dans la période. |
| Régularisé | Régularisations actives créées dans la période, au jour de Zurich. |
| Restant dû, en retard | Situation du jour, indépendante de la période. |
| Revenu mensuel | Mensualité moins remise récurrente de la période en cours, pour une école payante. Hors montant initial et encaissements. |
| Échéances | Renouvellements et derniers jours d'essai dans les 30 prochains jours. |

Une mensualité absente (`MISSING`) ou en pause (`PAUSED`) n'est jamais comptée comme un zéro : elle est dénombrée à part. Un échec de lecture affiche une erreur, jamais des montants à zéro.

## Prochaines actions

Par ordre de priorité : suspension à venir (seulement si la suspension automatique est active), retard, envoi en échec ou incertain, demande ouverte, conditions à compléter, ouverture inachevée.

## Limites

- Période de 367 jours au plus. La liste s'arrête à 500 écoles et le signale ; les totaux portent sur toutes.
- Recherche et filtres s'appliquent côté navigateur à la liste relue. La somme affichée sous un filtre est celle des lignes visibles.
- Aucun compteur d'usage : aucun agrégat défini n'existe aujourd'hui, et aucun accès aux élèves, trajets ou messages n'a été ajouté.

## État

Compilé (`tsc` API et web, build, contrat généré). Migration, requête et 5 cas d'intégration écrits, **jamais exécutés** (règle du porteur du 13 novembre). Interface non vue dans un navigateur.
