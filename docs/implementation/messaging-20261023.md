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
4. **Sondages** : proposition à valider de votes nominatifs, choix unique, vote modifiable par son auteur avant clôture, clôture par le créateur et résultats aux participants. Ne pas activer ce comportement avant arbitrage. Aucun lien avec réservation/inscription.
5. **Notifications** : réutiliser #44, pas de préférences parallèles. Contrat consommateur sans transport push tant que socle commun et flux APNs non validés. Silence ne réactive jamais un refus global. Aucun reçu visible ni indicateur de saisie.
6. **Données** : conservation, suppression, export, restauration et flux hors Suisse nécessitent décisions et preuves. Aucun délai inventé. Aucun service tiers activé.
7. **Enrichissements** : #75/#76, web, audio, appels, vocaux, groupes libres et IA restent hors réalisation active faute de confirmation.

## Propriété des fichiers

- Backend : nouveaux modules `apps/api/src/messaging*` hors `messaging-notifications.ts`, migration chat et tests dédiés.
- iOS : nouveaux dossiers `MessagingCore/`, `MessagingAPI/`, `MessagingUI/` et tests dédiés.
- Sécurité : `messaging-security-20261023.md`, `messaging-residency-20261023.md`, prototype isolé coordonné.
- Coordinateur : raccord `app.ts`, configuration, navigation, contrat, notifications consommateur, STATUS et qualification.
- #44 : stockage/API communs laissés au chantier notifications. Coordination déposée dans l'issue. Pas de duplication durable.
- Migrations : `20261023_messaging_foundation.sql`, nom horodaté réservé après vérification du runner, aucune réécriture de migration existante. Revalidation à l'intégration des cours.

## Compilation et qualification #84

Les workflows actuels ne lancent pas les suites sur les push `openai/**`. Les jobs de tests des PR sont déjà exclus pour une PR en brouillon. IPA possible par déclenchement manuel. Aucun workflow modifié, aucun scanner/protection désactivé, aucun usage systématique de `[skip ci]`.

Tests écrits avec chaque lot, exécution différée à #84. Typage/build possibles pendant réalisation. Compilation Swift sur runner Apple, aucune preuve Swift/VoiceOver/GPS inventée depuis Windows. Activation réelle bloquée par décisions #66/#67, garanties #68 et recette #78.

## Agents effectifs

Trois agents initialement créés via connexion existante OpenAI : sécurité `openai-oauth:gpt-6-astra`, backend et iOS `openai-oauth:gpt-6-sol`. Un quatrième agent `openai-oauth:gpt-6-astra` relit les droits et la concurrence dès disponibilité du code. Aucun réglage d'effort par agent n'est exposé dans l'outil. La liste des agents rapporte un effort hérité `low`, non un réglage modéré ou élevé appliqué par le coordinateur. Aucun sous-agent récursif ni autre fournisseur autorisé.

## État de reprise de l'intégration

PR en brouillon : #96. Commits intégrés : `4e87051` (périmètre et consommateur #44), `60e845f` (comparaison/résidence et prototype SDK), `f01b047` (migration, API, droits), `797563a` (composition native), `b55465c` (ordre des verrous), `7e886a6` (sourdine, reprise bornée, corrections Swift), `53b564e` (barrière de concurrence préparée), `ffa40d8` (préservation des intentions après refus ciblé).

- API : contacts autorisés, paire privée unique, général unique par école, historique paginé, événements incrémentaux, enveloppes opaques persistées, idempotence et état de lecture interne/silence avec version. Les noms des conversations privées proviennent de la projection de contacts autorisée. Compte et époque d'accès attendus sont contrôlés sous verrou à chaque requête. Ce transport n'est pas une implémentation Matrix ni un protocole E2EE.
- Confidentialité : le prototype standard Matrix est isolé du produit. Quatre scénarios sont écrits et leurs binaires compilés, mais aucun n'a été exécuté. Les clés/appareils/cross-signing ne sont pas raccordés à Drivy. Le coffre local chiffré ne remplace pas l'E2EE.
- Activation : `buildApp` n'injecte aucun mode actif. Seule une composition de test sous `NODE_ENV=test` peut utiliser les routes. Aucun drapeau de production n'ouvre la messagerie. La présentation native est réservée au simulateur DEBUG avec argument explicite. L'IPA Release ne montre pas Messages.
- Natif : transport HTTP réel, cache de brouillons/file chiffré AES-GCM et clé Keychain dédiée, hors sauvegarde, aucun repli clair. Le verrou local coordonne les différentes instances du même fichier. Reprise bornée à 20 intentions lors du retour au premier plan/réseau pendant l'écran Messages, même identifiant et même enveloppe. Un refus de conversation conserve son intention sans effacer les brouillons ou bloquer le général autorisé. Lecture/silence fusionnent les réponses hors ordre. Cela reste à tester, pas un résultat de fiabilité démontré.
- Synchronisation : rafraîchissement de liste/historique au retour et à la demande, endpoint serveur d'événements incrémentaux. Pas de souscription temps réel, pas d'avatars photo raccordés ; composant partagé DrivyAvatar avec initiales seulement.
- #44 : politique consommatrice seulement, aucun second stockage de préférences, aucune émission APNs. Lecture interne et reçus visibles restent séparés.
- Non réalisés : attribution administrative auditée du contact ADMIN, raccord SDK de production, politique d'appareils/historique/récupération, sondages #73, modération #77, extras #75/#76. Les options produit restent à valider. Pas de déploiement ni de procédure de restauration exécutée.

### Suite sans réaudit général

1. Examiner les seuls arbitrages #66/#67 regroupés ci-dessus et la recommandation de sécurité. Une validation du protocole doit aussi approuver les hypothèses de confiance et les métadonnées visibles, notamment les UUID de mentions dans le transport expérimental.
2. Après décision, intégrer le SDK complet ou son architecture de transport approuvée, les appareils et les clés. Ne pas brancher directement le harness synthétique au produit. Si un homeserver Matrix est retenu, l'API d'enveloppes actuelle ne le remplace pas : établir le raccord d'autorisation et de synchronisation avant activation.
3. Raccorder le propriétaire #44 puis implémenter les règles validées de sondages, signalements et contact ADMIN. Aucune inscription/leçon ne découle d'un vote ou d'une action de modération.
4. Qualifier les scénarios #78 dans la campagne #84, y compris vraie PostgreSQL, appareils Apple, restauration, résidence et absence de fuite dans les diagnostics. Garder l'epic et les issues ouvertes jusqu'aux preuves pertinentes.
