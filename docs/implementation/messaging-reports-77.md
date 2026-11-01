# Messagerie #77 : signalements scellés pour les administrateurs

Date : 31 octobre 2026. Issue #77, dépend de #67 (E2EE), #69 (droits) et #68 (conservation, non tranchée).
Base : branche de #74. Aucune activation n'est modifiée par ce lot.

## 1. État de départ

- Le serveur sait déjà créer un signalement idempotent (`POST /reports`), limité à la plage lisible du signalant, et le lister aux seuls administrateurs de l'école (`GET /reports`). Les enveloppes sont opaques.
- L'app iOS sait choisir des messages, préparer un signalement durable avant tout POST et le reprendre. Mais `UnavailableMessagingReportSealing` échoue fermé : aucun signalement réel n'a jamais pu partir.
- Aucune boîte côté administrateur, aucun statut, aucune limite de cadence, aucune information du signalant sur les destinataires.

## 2. Choix de scellement

**Une session Megolm par signalement, partagée aux appareils des administrateurs par to-device Olm.** C'est le mécanisme que la recherche de sécurité du 23 octobre (`messaging-security-20261023.md`, § 8) propose pour #77 : un canal E2EE réservé aux appareils des modérateurs habilités, le serveur gardant le dossier et les actions minimales.

Concrètement, sur l'appareil du signalant :

1. Le serveur donne la liste des administrateurs actifs de l'école (identifiants seulement, route `crypto/report-recipients`).
2. L'appareil met à jour le suivi de ces personnes, interroge leurs clés d'appareil, réclame des clés à usage unique et ouvre des sessions Olm, exactement comme pour une conversation.
3. Il jette la session de groupe sortante du « salon de signalement » de l'école (`!{schoolId}:drivy`), en crée une neuve, la partage aux appareils connus des administrateurs (messages to-device chiffrés Olm), puis chiffre chaque message choisi avec cette session.
4. Les enveloppes obtenues (`megolm.v1`, identifiant de session) sont enregistrées durablement sur l'appareil avant tout POST, comme aujourd'hui, puis envoyées à `POST /reports`.

Sur l'appareil de l'administrateur : la clé de session arrive par sa file to-device (elle attend côté serveur, chiffrée, même appareil hors ligne). L'app déchiffre localement chaque enveloppe avec le moteur Matrix existant. Le serveur ne voit jamais le texte ni la clé.

Pourquoi une session par signalement : un administrateur révoqué ensuite ne lit aucun signalement postérieur, sans rotation de clés ailleurs. Il garde les copies qu'il a déjà reçues (aucune promesse d'effacement, cf. § 8 de la recherche).

Aucun protocole maison : ni boîte scellée CryptoKit, ni clé d'école partagée. Tout repose sur `matrix-sdk-crypto` déjà retenu (décision du 23 octobre, § 1).

## 3. Ce que le serveur voit et fait

Le serveur voit : qui signale, la conversation, la date, l'identifiant et l'auteur de chaque message choisi (contexte indispensable pour traiter), les enveloppes chiffrées, le statut et son historique. Il ne voit jamais le contenu. Il ne reçoit rien d'autre de la conversation que ce que le signalant a choisi.

Droits, relus à chaque requête, jamais fournis par l'interface :

- Liste, détail et changement de statut : administrateurs actifs de l'école (`ADMIN` dans l'adhésion), école et époque d'accès relues sous verrou. Un non-administrateur reçoit 403, une autre école n'est jamais atteinte (RLS forcée).
- Création : participant de la conversation, plage lisible seulement (inchangé).
- Un administrateur non participant ne lit toujours aucun message privé non rapporté : le signalement n'ouvre que les enveloppes choisies.

### 3.1 Pairs de clés : élargissement volontaire et borné

Pour que n'importe quel membre puisse partager une clé avec les administrateurs, `drivy.messaging_key_peer` accepte désormais aussi « la cible est un administrateur actif de l'école ». Conséquences assumées :

- Tout membre actif peut lire les **clés publiques** des appareils des administrateurs et leur envoyer un message to-device.
- Les administrateurs entrent dans la liste de pairs de chaque membre (suivi d'appareils, `device_lists`).
- Un membre malveillant peut vider les clés à usage unique d'un administrateur (le SDK retombe alors sur la clé de repli, à confidentialité future un peu plus faible pour le premier message) ou remplir sa file to-device. Plafonner cette file est une amélioration notée, non livrée ici ; la cadence de signalement n'y répond pas.
- Les contenus to-device sont chiffrés Olm : un tiers ne peut pas forger un message lisible par l'administrateur à la place d'un signalant légitime sans que l'appareil s'en aperçoive.

### 3.2 Statut de traitement et historique

Nouveau statut par signalement : `OPEN` (ouvert), `HANDLED` (traité), `DISMISSED` (classé). Migration additive, nom unique daté `20261031_messaging_report_moderation_77.sql`. Chaque changement est écrit dans `messaging_report_status_event` (qui, de quel statut vers lequel, quand) par une fonction `SECURITY DEFINER` qui verrouille le signalement, relit le droit et refuse un statut attendu périmé (409 `REPORT_STATUS_CONFLICT`). Rejouer le statut déjà posé ne crée pas d'événement. L'historique est conservé sans purge.

### 3.3 Cadence

Limites simples, côté serveur, avec erreur explicite (429 `REPORT_RATE_LIMITED`) :

- 3 signalements par heure glissante, par personne et par conversation ;
- 10 signalements par 24 heures glissantes, par personne et par école.

Un renvoi du même `clientReportId` (reprise après réponse perdue) est reconnu avant tout comptage : il n'est ni compté ni bloqué. Pas de moteur général, pas de configuration par école. Les seuils sont des constantes documentées ici ; la mention de plus de 8 personnes reste limitée par ailleurs.

## 4. Côté signalant (iOS)

Avant d'envoyer, une confirmation dit où va le signalement : « Administrateurs de l'école », avec ce qu'ils pourront lire (les messages choisis, leur auteur et leur date) et ce qu'ils ne lisent pas (le reste de la conversation). Sans administrateur joignable (aucun appareil publié), le signalement n'est pas préparé : erreur explicite, aucune fausse réussite. Une limite de cadence atteinte laisse l'intention durable en place et affiche l'erreur.

## 5. Côté administrateur (iOS)

Entrée « Signalements » dans Messages, visible seulement si le serveur confirme le droit (la route répond 403 sinon). Liste (ouverts d'abord, badge du nombre de signalements ouverts), détail avec déchiffrement local message par message, choix du statut, historique des changements avec le nom de la personne. Un message qui ne se déchiffre pas (clé jamais reçue sur cet appareil) est dit tel quel, sans contenu inventé.

## 6. Limites connues

- **Appareils administrateurs futurs ou nouveaux** : seuls les appareils connus au moment du signalement reçoivent la clé. Un administrateur nommé ou un appareil enregistré après coup ne lit pas les signalements antérieurs, sauf via la sauvegarde de clés de son compte si elle est active. Le partage ultérieur de clés entre administrateurs n'est pas livré.
- **Confiance des appareils** : comme pour le reste de Messages, le signalant ne vérifie pas l'identité des appareils des administrateurs (premier contact non vérifié). Un serveur malveillant pourrait substituer un appareil ; la vérification croisée existante ne couvre pas ce cas.
- **Aucun administrateur avec appareil** : le signalement ne part pas. Rien n'est dégradé vers du clair.
- **Révocation d'un administrateur** : il ne reçoit plus les clés des signalements suivants et perd l'accès à la boîte ; il garde ce qu'il a déjà déchiffré ou reçu.
- **Copies et suppression** : les copies rechiffrées restent comme preuve même si le message est ensuite supprimé pour tout le monde (décision du 23 octobre).
- **Aucune lecture par le signalant** après envoi : il n'a pas d'écran pour relire ni suivre son signalement.
- **Preuve de provenance** : un signalement est une déclaration contextualisée, pas une preuve de non-répudiation.

## 7. Conservation (#68, décision non prise)

Aucune purge, aucun export, aucun délai automatique n'est inventé : les signalements, leurs enveloppes, leurs statuts et leur historique restent conservés tant que l'école existe. Dès que #68 aura tranché durée, hébergement et suppression, une purge devra couvrir ensemble `messaging_report`, `messaging_report_item` et `messaging_report_status_event`. Le critère « preuves purgées selon la politique validée » de #77 reste donc ouvert.

## 8. Activation

Le général ne s'ouvre pas à de vrais utilisateurs sans ce minimum. L'activation reste celle de `messagingSchoolGate` : une liste explicite d'écoles en mode `qualification` (ou le mode synthétique des tests, jamais en production). Ce lot ne la modifie pas ; un test vérifie qu'une école absente de la liste reçoit 503 sur les routes de signalement et de statut, comme sur le reste de la messagerie.

## 9. Ce qui n'est pas vérifiable sans deux appareils réels

Le partage de clé to-device et le déchiffrement chez l'administrateur ne sont exercés en CI que par les tests unitaires du moteur et par le relais synthétique. Restent à qualifier sur deux téléphones : réception réelle de la clé par un administrateur hors ligne puis en ligne, déchiffrement d'un signalement, signalement avec l'administrateur sur un second appareil nouvellement enregistré, comportement après révocation d'un administrateur.

## 10. État de la réalisation (31 octobre 2026)

| Élément | État | Preuve |
| --- | --- | --- |
| API : migration `20261031_messaging_report_moderation_77`, routes, statuts, historique, cadence, destinataires de clés | Exécuté sur PostgreSQL réel | « Refonte · vérifications » verte sur `071401ca`, [run 41225134866](https://github.com/tomyrms/Drivy/actions/runs/41225134866) (dont `messaging-reports.integration.test.ts`) |
| iOS : scellement par session Megolm partagée (`MatrixMessagingCryptography`), forme par lot de `MessagingReportSealing`, refus sans administrateur joignable | Compile | compilation vérifiée par le workflow d'IPA sur `bd4e3e80`, [run 41225717502](https://github.com/tomyrms/Drivy/actions/runs/41225717502) : lancé seulement pour savoir si le Swift compile, l'IPA n'a été ni téléchargée ni livrée (la consigne de la tâche excluait toute IPA, ce lancement était une erreur, il n'a pas été renouvelé) |
| iOS : boîte « Signalements » (liste, détail avec déchiffrement local, statut, historique), confirmation avant transmission | Compile ; vue jamais affichée sur simulateur ni appareil | idem |
| Tests Swift : transport, modèle de la boîte, scellement par défaut | Écrits, voir ci-dessous | `MessagingReportTransportTests`, `MessagingReportInboxTests`, `MessagingReportSealingDefaultTests` |

Un défaut trouvé par la CI avant tout le reste : les tests de capture n'appliquent que les migrations numérotées, le compte de tables à RLS reste 67 (le lot l'avait relevé à 68 par erreur). Corrigé et vérifié en local puis en CI.

Ce qui n'est **pas** fait ni vérifié :

- (Levé le 1er novembre 2026, section 11) Le partage de clé to-device et le déchiffrement chez l'administrateur sont exercés par des tests contre le SDK Matrix réel et le relais jetable ; reste à les exercer sur deux téléphones (section 9).
- (Levé le 1er novembre 2026, section 11) Le parcours d'interface est automatisé sur une fixture synthétique ; il ne qualifie ni les droits serveur ni le chiffrement.
- Le critère « preuves protégées, hébergées dans le périmètre suisse et purgées selon la politique validée » reste ouvert : #68.
- Aucune modération du général (retrait, restriction de chat) n'est ajoutée par ce lot : elle existait déjà (`messaging-v2`), seul le signalement et sa boîte sont nouveaux.

## 11. Qualification du 1er novembre 2026 (branche `claude/qualif-77-20261101`)

**Prouvé en CI** (données synthétiques, simulateur ou PostgreSQL jetable) :

| Quoi | Preuve |
| --- | --- |
| API : le signalant joint l'appareil de l'administrateur (requête de clés, clé à usage unique, to-device) ; seul cet appareil reçoit l'enveloppe, qui disparaît à l'acquittement ; administrateur sans appareil, appareil révoqué, administrateur retiré de l'école, personne hors des destinataires. 6 tests, PostgreSQL réel, `messaging-report-keys.integration.test.ts` | « Refonte · vérifications » [run 41260549546](https://github.com/tomyrms/Drivy/actions/runs/41260549546), `0b3efb81` : succès |
| Swift, SDK Matrix réel : un signalement scellé est lu par l'appareil de l'administrateur et jamais par un tiers (`D-NOKEY`) ; sans administrateur joignable rien n'est scellé ni envoyé ; une session par signalement ; un appareil enregistré après coup ne le lit pas (limite documentée) ; le modèle de la boîte lit un signalement scellé et dit qu'un message est illisible. `MatrixMessagingReportSealingTests` (5 tests) | tests métier iPhone « messaging » [run 41260562839](https://github.com/tomyrms/Drivy/actions/runs/41260562839) (`0b3efb81`) puis [run 41305480743](https://github.com/tomyrms/Drivy/actions/runs/41305480743) (`01cfc4d5`, 91 tests, 0 échec) |
| Même parcours contre le relais jetable HTTPS, Fastify et PostgreSQL (signalant, administrateur, moniteur tiers). `MatrixMessagingSealedReportRelayTests` | mêmes runs |
| Parcours d'interface sur fixture : entrée « Signalements » de Messages, boîte, détail déchiffré, statut et historique, message illisible, sélection et confirmation avant transmission. `MessagingReportScreensUITests` (3 tests) | UI iPhone [run 41301709973](https://github.com/tomyrms/Drivy/actions/runs/41301709973) (`0991774f`, les 3 tests) ; boîte et détail encore verts sur `f4aaab3e` (run 41302920798) ; sélection et confirmation vertes sur `15d8f8fb` (run 41309165061) |

Le code de l'app de la tête (`15d8f8fb`) est identique à celui du run métier 41305480743 (`01cfc4d5`) : seul `MessagingReportScreensUITests.swift` a changé entre les deux.

**Défauts de l'app trouvés par les captures, corrigés** :

1. L'entrée « Signalements » n'ouvrait rien au toucher d'un test (run 41260808224 : la liste des conversations restait à l'écran). Cause : le bouton en style `.plain` n'avait pas de forme de toucher ; le `Spacer` du milieu de la ligne ne répondait pas, et XCUITest touche le centre de l'élément (x 201, entre le titre et le badge). Corrigé par un `contentShape` ; vérifié par le run 41301709973 où le toucher ouvre la boîte. Le même défaut valait pour un doigt posé au milieu de la ligne.
2. Pendant le choix des messages à signaler, le rond de sélection était un voisin de la ligne : elle perdait de la largeur, et Exyte, qui calcule la bulle sur la largeur du fil entier, coupait un message court (« Message 17 du gén… ») et laissait le rond du sondage à moitié hors de l'écran. Le rond est maintenant une superposition dans la marge libre de la bulle. Avant/après : `.local/captures-77/avant-correction/06-selection-des-messages.png` et `.local/captures-77/final/06-selection-des-messages.png`. Le mécanisme est lu dans le code d'Exyte 3.3.0 (`MessageView`) ; il n'a pas été isolé par un test.
3. Dans la boîte, la date se coupait au milieu (« 31 / oct. 2026 à 9:36 ») dès que le statut occupait la droite : elle a maintenant sa propre ligne.

**Défauts encore vus, non corrigés** (pas d'itération supplémentaire décidée) :

- Pendant le choix des messages, le rond d'un message reçu du général est centré sur la ligne entière, auteur compris : il se trouve environ 25 pt au-dessus du centre de la bulle (messages de Léa et de Marc dans `final/06`).
- Le bouton « Revenir en bas » masque le rond du sondage dans cette capture.
- La pastille épinglée recouvre la bulle du haut pendant la sélection (comportement existant du fil, hors de ce lot).
- Le test de sélection était vert sur `0991774f` (visant les messages par leur texte), mais sa capture montrait la pastille épinglée sur l'un d'eux. En le modifiant pour choisir deux messages hors de la pastille, il est resté rouge sur cinq runs (41302920798, 41304132896, 41305459276, 41306677916, 41307996593) avant le vert de `15d8f8fb`. Cause : à l'ouverture le fil peut rester plus d'un écran au-dessus du bas, la ligne visée était sous l'écran, et un balayage ne fait pas défiler la liste d'Exyte. Le test prend donc les lignes entièrement visibles à cet instant ; il reste sensible à la position initiale du fil et peut être instable.

**Non prouvé** : aucun résultat sur deux appareils réels (réception de la clé par un administrateur hors ligne puis en ligne, appareil enregistré après coup, révocation) ; le chiffrement des écrans de la fixture est celui de la fixture, pas du E2EE réel ; iPhone, apparence claire et texte de taille normale seulement (ni sombre, ni iPad, ni grandes tailles) ; `testUnreadableReportedMessageIsStatedPlainly` n'a passé que sur `0991774f` (le correctif de date ne touche pas son écran) ; aucune capture n'a été examinée avec VoiceOver ; la conservation des preuves attend #68. Aucun changement d'API, de contrat ni de migration dans ce lot : un seul fichier de test API ajouté.

Captures (hors dépôt, clone principal) : `.local/captures-77/final/` (`01` à `07`, `05b`), avant corrections dans `.local/captures-77/avant-correction/`.