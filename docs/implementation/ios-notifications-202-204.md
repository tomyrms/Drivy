# Notifications : périmètres et synchronisation — #202, #203, #204

29 octobre 2026. Issues ouvertes, commentaires absents, aucune réalisation correspondante trouvée dans les commits/PR consultés. La page existante ne présentait que les quatre préférences de cours, leur état provisoire n’était annoncé que par VoiceOver et la portée personnelle de ces choix restait implicite.

## Réalisation

- Permission iOS regroupée sous « Cet appareil » ; catégories sous « Cours collectifs · Toutes mes écoles ». Le modèle reste `AccountIntentScope`, les alertes d’équipe restent affichées selon les rôles de l’école ouverte. Aucun stockage ni consentement supplémentaire.
- Section Messages : aide dépliable pour la sourdine propre à chaque conversation et accès explicite « Paramètres de Messages ». Cette destination existante concerne la sauvegarde des clés et les appareils ; elle ne représente pas un contrôle global de notifications. Sans entrée fournie par la composition, indisponibilité dite clairement.
- Le raccord de composition est fourni par le coordinateur : propriété optionnelle `SchoolMessagingEntry.makeSettingsView`, alimentée par le conteneur Messages protégé par son scope. La page Notifications ferme cette destination au changement de scope. Les appelants StaffSettings/LearnerProfileTab restent inchangés.
- La racine conserve une session de composition commune : Notifications et l’onglet Messages partagent les mêmes ressources ouvertes, dont la machine crypto et son état de sauvegarde. Référence faible dans la session, références fortes dans les vues ; nouvelle portée ou ancien contexte devenu invalide interdit la réutilisation. Cette correction évite qu’une sauvegarde activée depuis Notifications laisse la machine déjà ouverte de Messages inactive. Revue croisée statique du correctif `da98a0c0` : blocage levé ; essai physique encore requis.
- Chaque préférence affiche son état effectif, texte et pictogramme : à synchroniser, synchronisation, lenteur, non confirmé, conflit, refus, conservation locale impossible. Attente normale visible seulement après 600 ms ; aucune coche de succès ni clignotement des requêtes rapides. Le choix reste immédiatement modifiable, les autres lignes restent utilisables.
- La présentation suit les IDs d’intention de la file existante. Un refus confirmé peut rester indiqué sur sa catégorie après retrait de l’intention, en mémoire seulement ; un choix plus récent n’hérite pas du refus de l’ancien. Confirmation, nouvelle lecture ou invalidation de contexte effacent les états correspondants.

Références relues : `calendrier-notifications.md`, R65/R112, AP148–AP151, scénario T041 et `cours-collectifs-notifications-43-44.md`. Le contrat effectivement implémenté reste `GET/PUT /v1/me/notification-preferences`, sans mutation API. Composants SwiftUI Form/Toggle/DisclosureGroup et tokens Drivy, sans dépendance.

## Vérification et recette

`git diff --check` exécuté. `SchoolNotificationSettingsTests` enrichi : états par catégorie durant saisie rapide et réponse perdue, erreur chiffrée, invalidation de compte, refus confirmé, refus d’une ancienne intention conservant le dernier choix. **NOT_EXECUTED** : tests et compilation Apple ; compilation sur branche intégrée avec le raccord Messages du coordinateur. Aucune suite lancée.

À essayer dans l’IPA finale : modifier plusieurs catégories avec réseau rapide puis ralenti/coupé ; réessayer et vérifier disparition des seules intentions confirmées ; changer d’école (choix du même compte conservés, alertes d’équipe selon rôle), puis de compte (aucun ancien état) ; iOS refusé/accordé ; ouvrir les paramètres Messages depuis Notifications et changer d’école ; grand texte et VoiceOver. Aucune livraison push, conservation de clé, permission physique ni mesure d’accessibilité n’est déclarée qualifiée par ces contrôles statiques.

Périmètre iOS seulement, aucun web/EPIC #311, API, workflow, déploiement ou fusion.
