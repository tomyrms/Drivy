# Messagerie #65 : périmètre et reprise

Date : 23 octobre 2026. Base : `master` / `6d08b40`. Branche : `openai/65-messagerie`. Worktree séparé : `dv-65-openai`.

## Frontières

Les fichiers non commités du chantier cours collectifs restent intacts dans son worktree. Aucun stash, reset, transfert ou commit de ces fichiers. Les descriptions et commentaires de #65 à #78, #44 et #84 ont été lus. Aucun commentaire ne valide encore les choix ouverts de #66/#67. Les PR ouvertes inspectées concernent profil, GPS, connexion et corrections, pas une messagerie existante. Recherche ciblée du code et des historiques locaux : pas de socle de conversations ni de préférences #44 sur la base retenue.

Swift natif, API Fastify/PostgreSQL et identités existantes conservés. Aucun accès web de messagerie ajouté sans validation. Aucun achat, déploiement, changement d'infrastructure ou migration de production.

## Répartition et dépendances

| Issue | Existant au départ | Travail restant | Dépendances | Responsable |
| --- | --- | --- | --- | --- |
| #66 | Direction UI Drivy, dossiers et navigation | Parcours Messages réversible, arbitrages ci-dessous | #67 | Coordinateur + iOS |
| #67 | Stockage local SQLCipher et clés protégées, pas E2EE chat | Comparaison officielle, recommandation, prototype et validation | #66 | Sécurité |
| #68 | Infrastructure Drivy, pas environnement chat qualifié | Inventaire, configuration isolée, cycle de vie et preuves suisses | #67 | Sécurité + coordinateur |
| #69 | Identités, adhésions, affectations pédagogiques et RLS | Contacts et droits chat dynamiques, administrateur explicitement attribué | #66/#67 | Backend |
| #70 | Commandes métier existantes, pas file chat | Persistance opaque, idempotence, pagination, file indépendante et E2EE | #67–69 | Backend + iOS |
| #71 | Dossiers élèves et profils | Liste et conversation natives, ouverture contextuelle | #66/#69/#70 | iOS + coordinateur |
| #72 | Appartenances scolaires | Général unique, mentions stables et droits | #67/#69–71 | Backend + iOS |
| #73 | Aucun moteur sondage chat | Règles à valider puis sondages chiffrés cohérents | #66/#67/#70 | Coordinateur |
| #74 | #44 décrit, pas de stockage commun intégré | Contrat consommateur #44, non-lus/silence, livraison push conditionnée | #44/#67–73 | Coordinateur + backend |
| #75 | Non confirmé | Formats et inclusion à arbitrer, pas d'activation | #66–71 | Porteur puis coordinateur |
| #76 | Non confirmé | Sous-fonctions à arbitrer, pas d'activation | #66/#67/#70 | Porteur puis coordinateur |
| #77 | Aucun rôle de modération chat validé | Partage volontaire de preuves, droits et retrait du général | #66/#67/#69/#70 | Sécurité + coordinateur |
| #78 | Stratégie globale #84 | Fixtures, matrice, revue et preuves manuelles | Lots retenus | Coordinateur + revue |

## Arbitrages regroupés, non présentés comme validés

1. **Confidentialité** : choisir le protocole et la bibliothèque éprouvés recommandés par #67, vérifier les appareils, définir récupération et arrivée/retrait. Pas de remplacement implicite par du chiffrement lisible par le serveur. Aucun compte récupéré ne récupère automatiquement les anciennes clés.
2. **Accès** : politique d'historique après retrait, attribution explicite du contact ADMIN, identité minimale visible dans le général (mineurs compris), rôles/modération et destinataires des signalements. En attendant, refus des accès devenus inéligibles et aucun accès universel ADMIN.
3. **Navigation** : proposition d'entrée Messages secondaire et réversible, sans supprimer d'onglet. Entrée contextuelle depuis dossier conservée. Cette présentation de développement n'est pas la navigation finale approuvée.
4. **Sondages** : proposition à valider de votes nominatifs, choix unique, vote modifiable avant clôture par le créateur et résultats aux participants. Ne pas activer ce comportement avant arbitrage. Aucun lien avec réservation/inscription.
5. **Notifications** : réutiliser #44, pas de préférences parallèles. Contrat consommateur sans transport push tant que socle commun et flux APNs non validés. Silence ne réactive jamais un refus global. Aucun reçu visible ni indicateur de saisie.
6. **Données** : conservation, suppression, export, restauration et flux hors Suisse nécessitent décisions et preuves. Aucun délai inventé. Aucun service tiers activé.
7. **Enrichissements** : #75/#76, web, audio, appels, vocaux, groupes libres et IA restent hors réalisation active faute de confirmation.

## Propriété des fichiers

- Backend : nouveaux modules `apps/api/src/messaging*` hors `messaging-notifications.ts`, migration chat et tests dédiés.
- iOS : nouveaux dossiers `SchoolMessaging*` et tests dédiés.
- Sécurité : `messaging-security-20261023.md`, `messaging-residency-20261023.md`, prototype isolé coordonné.
- Coordinateur : raccord `app.ts`, configuration, navigation, contrat, notifications consommateur, STATUS et qualification.
- #44 : stockage/API communs laissés au chantier notifications. Coordination déposée dans l'issue. Pas de duplication durable.
- Migrations : nom horodaté réservé après vérification du runner, aucune réécriture de migration existante. Revalidation à l'intégration des cours.

## Compilation et qualification #84

Les workflows actuels ne lancent pas les suites sur les push `openai/**`. Les jobs de tests des PR sont déjà exclus pour une PR en brouillon. IPA possible par déclenchement manuel. Aucun workflow modifié, aucun scanner/protection désactivé, aucun usage systématique de `[skip ci]`.

Tests écrits avec chaque lot, exécution différée à #84. Typage/build possibles pendant réalisation. Compilation Swift sur runner Apple, aucune preuve Swift/VoiceOver/GPS inventée depuis Windows. Activation réelle bloquée par décisions #66/#67, garanties #68 et recette #78.

## Agents effectifs

Trois agents initialement créés via connexion existante OpenAI : sécurité `openai-oauth:gpt-6-astra`, backend et iOS `openai-oauth:gpt-6-sol`. Aucun réglage d'effort par agent exposé dans l'outil. Aucun sous-agent récursif ni autre fournisseur autorisé.
