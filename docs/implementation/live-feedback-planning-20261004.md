# Retours terrain : signalement, dossier et planification — 4 octobre 2026

## Demandes et choix

Le porteur demande de poursuivre la simplification des parcours, de rendre le profil et le tarif visibles sans menu, de déplacer le retour de signalement au-dessus des commandes, de permettre son annulation, et de vérifier la disponibilité avant le tarif. La carte active aura trois modes : libre, position centrée au nord, orientation du téléphone. Les confirmations binaires de fin et d’annulation passent en alertes natives compactes.

Le skill Impeccable (craft-floor : couverture des états et actions repérables ; layout : regroupement et divulgation progressive) guide l’ordre personne → rendez-vous → tarif. Les patterns SwiftUI gardent les modèles et présentations hors des branches conditionnelles. Les zones tactiles des nouvelles actions font au moins 44 points ; les compositions s’adaptent au grand texte. Ces choix conservent les tokens de DESIGN.md et les feuilles natives stables du build100.

## Disponibilité avant le tarif

L’extension de lecture `GET /v1/schools/{schoolId}/lessons/availability` prend formation, moniteur, début, fin, fuseau, tampon et éventuellement la leçon déplacée. Le contrat d’implémentation est `apps/api/contracts/lesson-availability.json`. Le contrat canonique 3.11.0 et la livraison de conception restent conservés.

La réponse indique uniquement disponible, hors disponibilités, ou conflit. Elle ne révèle ni l’identité ni le contenu d’un rendez-vous auquel le moniteur n’a pas accès. La fonction SQL gardée de la migration022 vérifie les occupations de la personne élève et du moniteur même quand leurs leçons ne sont pas lisibles par cet appelant. Aucun élargissement des politiques de lecture ; aucun créneau temporairement réservé. CREATE et MOVE refont leurs contrôles au commit.

Le déplacement ne peut exclure que sa leçon future modifiable de la même formation, avec son tampon inchangé. La durée et le fuseau suivent les règles de création. Les autorisations et prérequis refusés restent des erreurs, jamais une réponse disponible.

## Vérifications à ce stade

Typecheck et compilation API exécutés avec succès localement. Dix scénarios d’intégration PostgreSQL sont ajoutés : lecture sans écriture, bornes et tampons, fermetures, occupations privées élève/moniteur, exclusion sécurisée, conflit au commit, droits et paramètres. Les dix scénarios passent sur la CI PostgreSQL réelle (run37217180774), ainsi que les 234 tests API et 104 tests web. Les types, builds et contrôles documentaires passent également. Les tests Apple et la qualification physique ne sont pas exécutés à ce stade. Livraison IPA rapide maintenue conformément à la demande du porteur.


## Retours de signalement et accès directs

La palette se ferme immédiatement après l’écriture dans la file chiffrée. Un bandeau indépendant au-dessus des commandes affiche l’ajout et propose Annuler. Le retrait utilise une intention durable : la création initiale est rapprochée par sa clé, puis AP164 retire l’observation. Une confirmation de création n’acquitte jamais un retrait. L’état « Annulation en attente » reste visible tant que le retrait n’est pas confirmé ; erreurs et reprise ne disparaissent pas automatiquement. Les anciennes versions refusent une archive contenant une intention de retrait plutôt que l’ignorer. Le retour existe aussi pour un signalement sans GPS.

Le profil et les contacts sont visibles sous l’identité de l’élève, avant les leçons et la progression. Le tarif et son montant deviennent une ligne directe de la fiche de leçon. Les menus gardent les opérations secondaires. Les confirmations binaires des parcours leçon/profil/observations utilisent une alerte native centrale ; les motifs d’annulation restent dans leur formulaire et un arrêt GPS impossible y affiche une erreur.

Le premier appui sur le suivi de carte centre au nord, le suivant active le cap du téléphone, le troisième rend la carte libre. Un geste manuel rend également la carte libre. Aucun cap absent n’est inventé ; le replay conserve son fonctionnement propre. Le contrôle de position d’Aujourd’hui passe dans le coin inférieur de la carte, au-dessus du panneau.

## Planification native

Le choix du créneau déclenche une lecture serveur avec temporisation de 300 ms. Une réponse ne vaut que pour sa formation, son élève, son moniteur, son intervalle et son tampon. Pendant le contrôle, une erreur réseau ou un refus, tarif et validation sont masqués ; date, heure, durée et moniteur restent modifiables. Un créneau occupé expose immédiatement sa raison anonyme. La durée précède le tarif et reste corrigible, même quand le créneau est refusé ; seuls les tarifs compatibles suivent. Le bouton Planifier confirme les versions commerciales affichées : la case d’acceptation locale est retirée, les liens de consultation restent accessibles. Le déplacement conserve son accord explicite distinct.

## Déploiement serveur

La release `52c355f5e71028866ae9bdf6a7dd83d07ad66f9c` a été déployée après sauvegarde privée de `drivy_refonte` et vérification de l’archive par pg_restore. Les empreintes des 22 migrations correspondent au commit. API, web et identité sont actifs ; processus dans la bonne release, readiness interne 200, contrôles HTTPS attendus réussis. Configuration privée API et profil d’essai iPad conservés. Preuve : `proofs/deployment-availability-20261004.json`. Mandat de déploiement phase2 du 28 septembre, rappelé dans AGENTS.md.


## Livraison native

**IPA 0.7.0/build102** compilée Release avec succès sur `9dcad86e6bda6c303b9379040ee31b2c6d4b52bb` ([run37217708082](https://github.com/tomyrms/Drivy/actions/runs/37217708082)). Archive téléchargée ; les trois fichiers du manifeste, le ZIP, les binaires et la configuration de production sont vérifiés. SHA-256 IPA : `adff60719ab2e24cc4f0269be79c72d92f286fe5c4a6d33b2a61cb9a51575f26`. Emplacement local : `artifacts/ipa-20261004-feedback-planning/Drivy.ipa`.

La relecture indépendante a corrigé le retrait différé après finalisation : le reçu REMOVE est vérifié d’abord, puis la version courante est relue ; un conflit de version autorise une seule reprise, avec le même UUID. Les liens de contact restent visibles sans callback de profil et le bandeau existe aussi sans GPS. Sur la carte compacte, les commandes de suivi restent accessibles au-dessus du bandeau, avec un espace réservé à la ligne des mentions Apple Plans.

Les contrôles généraux passent sur ce commit ([run37217708094](https://github.com/tomyrms/Drivy/actions/runs/37217708094)). À la demande du porteur, aucune longue campagne Apple ni capture supplémentaire : tests Swift préparés mais non exécutés. Rendu, fluidité, VoiceOver et cap physique restent à qualifier sur l’appareil. L’IPA est non signée, à signer/installer avec iLoader. Preuve : `proofs/live-feedback-planning-20261004.json`.
