# Messagerie #68 : cadrage de l'hébergement, des sauvegardes et de la conservation

12 novembre 2026. Documentation seulement : aucun code, aucune infrastructure, aucun déploiement. Ce document ne contient ni adresse, ni identifiant, ni secret, ni donnée de personne. Il complète [la note de résidence du 23 octobre](messaging-residency-20261023.md) (cartographie cible, exigences) et [la preuve de restauration du 5 novembre](messaging-restore-replay-20261105.md) sans les répéter. **Rien ici ne prouve une résidence suisse** : l'issue #68 reste ouverte.

## 1. Orientations du porteur, telles que données

- Aujourd'hui, les données vivent sur son homelab.
- En production, elles iront sur un serveur dédié situé en Suisse.
- Conservation des messages : pas d'historique illimité. Il hésite entre deux ans et cinq ans ; **non tranché**.

## 2. Ce que demande l'issue #68 (critères d'acceptation)

1. Inventaire des données, copies, destinations et services tiers démontrant la résidence et le traitement suisses côté service.
2. Déploiement reproductible en test, revue des accès et secrets.
3. Sauvegarde chiffrée et restauration réellement testées ; révocations et suppressions cohérentes.
4. Conservation, export et purge testés sur données synthétiques, selon des décisions validées.
5. Aucun contenu ni clé dans les journaux et rapports de plantage ; flux externes contrôlés et documentés.
6. Procédures d'exploitation, de reprise et de retour arrière ; limites honnêtes sur appareils et réseau.

Le présent cadrage couvre le point 1 en partie (inventaire de l'existant, lu dans le dépôt, sans connexion au serveur) et prépare les décisions des points 3 et 4.

## 3. Inventaire de l'existant (lu dans le dépôt)

| Sujet | Constat | Source |
|---|---|---|
| Messages | Événements chiffrés de bout en bout (Matrix Olm/Megolm, transport Drivy, sans homeserver Matrix) stockés dans PostgreSQL ; le serveur ne lit pas le contenu. Métadonnées lisibles par le service : membres, horaires, tailles, identifiants. | `decisions-messaging-20261023.md`, migrations `apps/api/migrations/20261023*_messaging_*.sql` |
| Médias | Octets chiffrés stockés dans PostgreSQL (colonne `ciphertext`, table `messaging_media`), avec une table de purge. Pas de stockage objet ni de CDN dans le dépôt. Pièces jointes de messagerie : hors périmètre tant qu'une issue séparée ne les reprend pas. | `apps/api/migrations/20261104_messaging_media_97.sql`, `decisions-messaging-20261023.md` §7 |
| Clés | Appareil : coffre local (Keychain, base SQLCipher, `IdentityVault`) ; sauvegarde des clés utilisateur par secret que seul l'utilisateur détient (choix #67). Serveur : clés de chiffrement des captures GPS provisionnées sur l'hôte applicatif par script ; secrets d'exploitation dans les fichiers d'environnement des services, hors dépôt. Inventaire des emplacements et des accès non fait. | `MessagingCore/*`, `infra/deploy/provision-capture-keys.mjs`, `infra/deploy/*.service` |
| Hébergement actuel | Homelab : API et identité (Keycloak) sur un conteneur, PostgreSQL sur un autre avec TLS vérifié, reverse proxy Caddy sur un troisième. Localisation physique, opérateur des accès et fournisseurs annexes (DNS, certificats) non documentés dans le dépôt. | `deploiement-refonte.md`, `messaging-residency-20261023.md` §2 |
| Notifications push | APNs (Apple) : payload sans texte, identifiants techniques seulement. Principe accepté par le porteur ; **résidence suisse d'APNs non démontrée**, Apple ne la garantit pas dans les sources lues. Code : notifications de messagerie et de cours. | `apps/api/src/messaging-notifications.ts`, `course-push.ts`, `decisions-messaging-20261023.md` §6 |
| Recalage routier | Mapbox abandonné le 21 octobre 2026 au profit d'OSRM auto-hébergé : aucune position ne quitte l'hébergement. Le code garde l'option Mapbox, désactivée par la configuration. | `apps/api/src/map-matching-client.ts`, `diagnostic-gps-osrm-20261021.md` |
| Cartes dans l'app | Affichage par MapKit (Apple) : les tuiles viennent des serveurs d'Apple. Les positions affichées sont des positions déjà connues de l'appareil ; flux à décrire dans l'inventaire des sorties. | `SchoolCaptureUI/DrivyRouteMapView.swift`, `SchoolCaptureLiveMap.swift` |
| Autres sorties réseau | Aucun relais e-mail (SMTP) configuré. Bibliothèque de conversation (Exyte) avec composant GIF embarqué : usage réseau éventuel à vérifier avant toute activation. GitHub Actions compile et teste avec des données synthétiques seulement. | règle CI d’`AGENTS.md` ; dépendances de l’app (à relire) |
| Journaux | API Fastify : journal d'accès désactivé par défaut dans la construction de l'application ; messagerie : codes d'erreur et identifiants techniques, pas de contenu. Journaux des services système sur l'hôte : non inventoriés. | `apps/api/src/app.ts`, `MessagingDiagnostics.swift` |
| Rapports de plantage | Aucun SDK de rapport de plantage ni de télémétrie tiers trouvé dans le dépôt. L'IPA est installée hors App Store ; les rapports système Apple de l'appareil ne sont pas exploités. | recherche dans `apps/` |
| Sauvegardes existantes | Un `pg_dump` du format personnalisé est pris avant chaque déploiement et gardé sur l'hôte de la base. Il est compressé, **non chiffré**, et **sur le même serveur** que les données. Une restauration synthétique avec rejeu des suppressions et révocations a été exécutée en local (PostgreSQL réel). Il n'existe pas de sauvegarde chiffrée, ni de copie hors du serveur, ni d'archive indépendante durable de production. | `STATUS.md` (entrées de déploiement), `messaging-restore-replay-20261105.md` §§ RES04, RES05 |
| Conservation | Historique gardé tant que la conversation existe ; « supprimer pour tout le monde » efface l'enveloppe côté serveur ; les copies rechiffrées d'un signalement sont gardées comme preuve. Aucun délai automatique. | `decisions-messaging-20261023.md` §§ 5-6 |
| Export | Non implémenté. Sous chiffrement de bout en bout, le service ne peut exporter que le chiffré ; un export lisible se fait sur un appareil qui détient les clés. | `messaging-residency-20261023.md` §5 |

## 4. Décisions encore ouvertes, avec une proposition par défaut

| # | Décision | Proposition par défaut |
|---|---|---|
| D1 | Durée de conservation des messages (deux ou cinq ans) | Deux ans après le dernier message d'une conversation, puis purge automatique du serveur, des médias et des index ; cinq ans seulement si une obligation légale précise est établie. À valider avec #66. |
| D2 | Ce qui suit les messages à la purge : médias, réactions, votes, copies de sauvegarde, preuves de signalement | Même échéance que les messages pour tout, sauf une preuve de signalement, gardée selon sa propre durée distincte (à fixer avec #77) ; les sauvegardes expirent au plus tard une rotation après la purge. |
| D3 | Sauvegarde hors du serveur | Sauvegarde quotidienne chiffrée avant envoi (clé gardée hors du serveur de données), copie sur un second site suisse indépendant du premier ; rotation alignée sur D1 ; restauration d'essai trimestrielle sur un environnement réservé. |
| D4 | Choix de l'hébergeur suisse pour le serveur dédié | Un hébergeur de droit suisse, avec centre de données en Suisse, sans sous-traitant hors de Suisse pour le support ni la supervision, contractuellement écrit. Comparer deux ou trois offres sur ces seuls critères avant de signer. |
| D5 | Objectifs de reprise (RPO, RTO) | Perte maximale d'une journée et reprise sous une journée ouvrée pour un cabinet de cette taille ; à mesurer sur une restauration d'essai avant de s'engager. |
| D6 | Exception APNs | Garder le principe accepté (payload sans texte), l'écrire comme exception documentée dans l'inventaire, sans prétendre à une résidence suisse pour ce flux. |
| D7 | Export et suppression à la demande d'une personne | Export du chiffré par le service plus export lisible depuis l'appareil ; suppression de ses messages côté serveur sous trente jours, copies déjà reçues par les autres participants exclues et dites telles. |
| D8 | Migration du homelab vers le serveur suisse | Sauvegarde, restauration sur le serveur suisse, bascule du nom de domaine, arrêt du homelab après une période de lecture seule ; aucune donnée de personne n'y reste. |

## 5. Ce qui reste hors de ce document

Mesures, restauration d'essai sur le futur serveur, revue des accès, preuve de localisation du fournisseur, purge testée sur données synthétiques et procédures d'exploitation : travaux de l'issue elle-même, soumis à une autorisation distincte. Rien n'est déclaré qualifié.
