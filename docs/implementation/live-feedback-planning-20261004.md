# Retours terrain : signalement, dossier et planification — 4 octobre 2026

## Demandes et choix

Le porteur demande de poursuivre la simplification des parcours, de rendre le profil et le tarif visibles sans menu, de déplacer le retour de signalement au-dessus des commandes, de permettre son annulation, et de vérifier la disponibilité avant le tarif. La carte active aura trois modes : libre, position centrée au nord, orientation du téléphone. Les confirmations binaires de fin et d’annulation passent en alertes natives compactes.

Le skill Impeccable (craft-floor : couverture des états et actions repérables ; layout : regroupement et divulgation progressive) guide l’ordre personne → rendez-vous → tarif. Les patterns SwiftUI gardent les modèles et présentations hors des branches conditionnelles. Les zones tactiles des nouvelles actions font au moins 44 points ; les compositions s’adaptent au grand texte. Ces choix conservent les tokens de DESIGN.md et les feuilles natives stables du build100.

## Disponibilité avant le tarif

L’extension de lecture `GET /v1/schools/{schoolId}/lessons/availability` prend formation, moniteur, début, fin, fuseau, tampon et éventuellement la leçon déplacée. Le contrat d’implémentation est `apps/api/contracts/lesson-availability.json`. Le contrat canonique 3.11.0 et la livraison de conception restent conservés.

La réponse indique uniquement disponible, hors disponibilités, ou conflit. Elle ne révèle ni l’identité ni le contenu d’un rendez-vous auquel le moniteur n’a pas accès. La fonction SQL gardée de la migration022 vérifie les occupations de la personne élève et du moniteur même quand leurs leçons ne sont pas lisibles par cet appelant. Aucun élargissement des politiques de lecture ; aucun créneau temporairement réservé. CREATE et MOVE refont leurs contrôles au commit.

Le déplacement ne peut exclure que sa leçon future modifiable de la même formation, avec son tampon inchangé. La durée et le fuseau suivent les règles de création. Les autorisations et prérequis refusés restent des erreurs, jamais une réponse disponible.

## Vérifications à ce stade

Typecheck et compilation API exécutés avec succès localement. Dix scénarios d’intégration PostgreSQL sont ajoutés : lecture sans écriture, bornes et tampons, fermetures, occupations privées élève/moniteur, exclusion sécurisée, conflit au commit, droits et paramètres. Leur exécution attend la CI PostgreSQL réelle ; aucune base de test locale n’est disponible. Les tests Apple et la qualification physique ne sont pas exécutés à ce stade. Livraison IPA rapide maintenue conformément à la demande du porteur.
