# Médias #97 — raccord du média au message (T2b5)

> Base : `e2edc85ed092237016620079d52d11eb7a2d02b5`, branche `tomyrms/issues-medias-raccord-97`.
> Candidat corrigé : `500e0c4273120b051020fb3f8d5f808785a496f2` (correction 1/2).
> Portée : logique et transport natifs uniquement. Aucun écran, aucune crypto nouvelle, aucun dépôt binaire,
> aucun stockage, aucune file, aucun coordinateur média. La conception et l'OpenAPI 3.11.0 sont inchangées.

## Ce qui est livré

Le backend T1 attachait déjà `media: {mediaId, byteSize}` au POST message et restituait
`media: {mediaId, byteSize, deleted}`. Le client natif ignorait ces champs. Ce raccord les transporte :

- `MessagingMediaMessageIntent` — intention d'envoi (`mediaId`, `byteSize`), bornes `1…4 194 304` vérifiées à
  l'initialisation **et** au décodage. Aucun MIME, nom, clé, IV, hash, légende ni contenu clair.
- `MessagingMessageMediaReference` — référence serveur (`mediaId`, `byteSize`, `deleted`), `deleted` obligatoire.
  Absence ou `null` = pas de média ; objet présent invalide = échec fermé, jamais un `nil` silencieux.
- `MessagingSendDTO.media` (défaut `nil`) et `MessagingAcknowledgementDTO.media` (défaut `nil`).
- `MessagingMessageMeta.media` (défaut `nil`), conservé de bout en bout HTTP → DTO → `MessagingWireMessage`.
- `MessagingMediaMessageSending.sendMedia(scope:pending:media:)` sur `MessagingAPIClient`. Aucun appel
  automatique n'est ajouté. Le protocole de transport garde ses trois primitives d'origine : l'envoi média
  emprunte le même `send` que le chemin ordinaire, avec le DTO porteur du média.

Le codec de contenu v1/v2/v3, `MessagingContracts.swift`, les outbox/cache, le transport binaire, la crypto,
le coordinateur et l'interface ne sont pas modifiés.

## Encodage et réception

- Le POST média encode exactement `media: {mediaId, byteSize}`. Un texte ou sondage sans média omet la clé
  (Encodable synthétisé : `encodeIfPresent`). Les autres champs et leurs limites restent identiques.
- Sondage + média est refusé localement avant tout jeton ou requête : `MessagingMediaTransportFailure.invalidIntent`
  via la capacité cliente, `MessagingFailure.invalidResponse` via un `send` direct. Une légende vide n'est pas
  inspectée par cette couche : le contenu chiffré v3 porte le repli.
- Le reçu vérifie, en plus des contrôles existants (clientID, conversation, école, expéditeur, ciphertext,
  mentions), le même `mediaId` et la même `byteSize`. Un reçu absent, incohérent ou invalide échoue fermé.
- La validation est **symétrique** : une intention sans média n'accepte pas un reçu qui en porte un, et
  inversement. Le client vérifie la même symétrie sur un accusé injecté.
- `deleted` est conservé comme fait du serveur : il n'est ni déduit, ni corrigé, ni interprété comme une preuve
  de réception par le destinataire. Aucune attache reconnue n'active un rendu.
- Historique : absence ou `null` reste lisible ; média actif ou tombstone conserve exactement identifiant,
  taille et `deleted`. Un message supprimé pour tous ne garde aucun ciphertext. Aucune URL, miniature ou
  métadonnée de fichier clair n'est ajoutée au DTO serveur.

## Limites et refus

- `ciphertext.payload` ≤ 12 000 caractères base64 et corps `SendBody` ≤ 16 384 octets, mesurés sur le JSON
  réellement émis **avec** média, avant jeton et requête. Le signalement garde sa forme et ses limites ; le
  plafond de réponse ordinaire de 2 Mio n'est pas élargi.
- Origine, scope/époque, renouvellement unique après 401, idempotence et annulation existants sont préservés.
  Aucun header d'appareil n'est ajouté : le POST message réel ne l'exige pas et le serveur relit les droits.
- Le mode média est déduit du contenu réellement émis (`body.media != nil`), jamais de l'entrée appelée :
  un même POST média n'a qu'une interprétation, que l'appel vienne de `send` ou de `sendMedia`.
- Les codes média fermés sont traduits vers `MessagingMediaTransportFailure` uniquement dans le chemin média,
  via un paramètre privé `mediaFailures` valant `false` par défaut, **et seulement pour une paire exacte
  (statut, code)** réellement émise par T1. Un 2xx n'est jamais mappé : son corps est un reçu à décoder. Un
  401 garde la priorité de l'authentification et du renouvellement ; un 403 garde son refus d'accès ; une
  combinaison inconnue ou incohérente garde le refus de son statut. `MESSAGING_MEMBERS_CHANGED`, les chemins
  texte/sondage/actions et les refus ordinaires gardent leur sens.
- Aucun message d'erreur libre, identifiant, URL ou hash dans les diagnostics ; aucune suppression de file sur
  refus.

### Traduction des refus média du POST

Les paires média réellement émises par T1 sont traduites ci-dessous ; toute autre combinaison garde le refus
de son statut HTTP, sans fait média final inventé.

| HTTP | Code serveur | Refus natif |
|---|---|---|
| 400 | `INVALID_MEDIA` | `invalidIntent` |
| 404 | `MEDIA_NOT_FOUND` | `notFound` |
| 409 | `MEDIA_INTENT_CONFLICT` | `intentConflict` |
| 409 | `MEDIA_ALREADY_ATTACHED` | `alreadyAttached` |
| 409 | `MEDIA_SIZE_MISMATCH` | `sizeConflict` |
| 409 | `MEDIA_PURGED` | `purged` |
| 403 | `MESSAGING_DEVICE_REQUIRED` | `deviceRequired` |
| 503 | `MESSAGING_NOT_ENABLED`, `SERVICE_UNAVAILABLE` | `unavailable` |
| 409 | `MESSAGING_MEMBERS_CHANGED` | `MessagingFailure.membersChanged` (inchangé) |
| 401 | `AUTHENTICATION_REQUIRED` | `MessagingFailure.accessChanged` après renouvellement refusé |
| 403 | `ACCESS_DENIED` | `MessagingFailure.accessChanged` |
| 200 | tout code d'erreur | `MessagingFailure.invalidResponse` : aucun mapping, reçu invalide |

## Fichiers

- `apps/ios/Drivy/MessagingCore/MessagingMediaMessageContracts.swift` (nouveau)
- `apps/ios/Drivy/MessagingCore/MessagingThreadModels.swift` (ajout du champ `media`, défaut `nil`)
- `apps/ios/Drivy/MessagingAPI/MessagingAPIClient.swift` (DTO, capacité cliente, symétrie des accusés)
- `apps/ios/Drivy/MessagingAPI/MessagingHTTPTransport.swift` (encodage, décodage, reçu symétrique, paires de refus)
- `apps/ios/DrivyTests/MessagingMediaMessageTransportTests.swift` (nouveau)
- `apps/ios/DrivyTests/MessagingMediaMessageClientTests.swift` (nouveau)
- `docs/implementation/messaging-media-97-message-bridge.md` (ce rapport)

## Correction 1/2

1. **Refus HTTP cohérents.** `request` ne traduit un code média que pour les paires exactes du contrat T1 et
   jamais sur un 2xx. Un 401 conserve la priorité de l'authentification (renouvellement unique puis
   `accessChanged`), un 403 conserve `accessChanged`, et une paire inconnue garde le refus de son statut.
2. **Un seul chemin média.** La primitive `sendMedia` a été retirée du protocole `MessagingAPITransport` :
   `MessagingAPIClient.sendMedia` construit le DTO et appelle le même `send` que le chemin ordinaire. Le mode
   média est déduit de `body.media != nil`, donc un appel direct à `send` avec un DTO média obtient exactement
   les mêmes contrôles et le même mapping.
3. **Reçu symétrique.** Une intention sans média refuse un reçu qui en porte un, au transport concret comme
   dans la capacité cliente ; une intention média exige le même identifiant et la même taille, `deleted`
   restant un fait serveur.

## Exécution, modèle et preuves de méthode

- **Modèle actif** : `opencode-go/deepseek-v4.1-flash` (vérifié dans le catalogue OpenCode). Aucun paramètre
  d'effort n'est exposé par la tâche.
- **Skills Superpowers chargés** : `test-driven-development`, `systematic-debugging` et
  `verification-before-completion`, lus via l'outil `skill` avant toute modification. Le correctif traite
  trois défauts identifiés par la revue (mapping hors paire, double interprétation du POST, reçu asymétrique).
- **Codebase Memory** : projet `drivy-media-message-97-20261104`, racine
  `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-raccord-97`, `status: ready`, réindexé après écriture.
  Recherches de graphe : `MessagingSendDTO`, `MessagingAcknowledgementDTO`, `MessagingMessageMeta`,
  `MessagingAPITransport`, `MessagingHTTPTransport`, `MessagingPending`, `MessagingMediaTransportFailure`,
  `MessagingMediaMessageIntent`. Couverture des quatre fichiers Swift touchés par la correction :
  `no_recorded_issue`, `metadata_match`.
- **Commandes réellement exécutées** : `git diff --check` et `git diff --cached --check` (code 0),
  `git rev-parse HEAD`, `git log -1`, `rg -c "    func test"` sur les deux nouveaux fichiers (25 et 9),
  `Get-Command swift, swiftc, xcodebuild` (aucun outil trouvé).
- **Commit local** : HEAD de la branche `tomyrms/issues-medias-raccord-97` après ce rapport ; le SHA exact est
  transmis au coordinateur. Aucun push, CI, PR, fusion ou déploiement.

## Vérifications réellement effectuées

- Environnement : Windows, sans Swift ni Xcode. **Aucune compilation Swift, aucun RED/GREEN natif, aucune suite
  XCTest exécutée.** Les preuves Apple de la base (`1515/1515` etc.) ne sont pas transférées à ces fichiers.
- Tests écrits avant le code (ordre de rédaction), mais **non compilés** : leur résultat réel est `NOT_EXECUTED`.
- Cas de correction couverts par les tests préparés : paires nominales et paires incohérentes (400/MEDIA_NOT_FOUND,
  404/NOT_FOUND, 409/MEDIA_NOT_FOUND, 403/MEDIA_PURGED, 500/MEDIA_PURGED, 503/MEDIA_PURGED), 200 portant un code
  d'erreur sans reçu, 401/MEDIA_PURGED après renouvellement refusé, envoi direct `send` avec DTO média, et reçu
  média inattendu sur une intention ordinaire (transport et client).

## Tests Apple restant à exécuter

1. Compiler `Drivy` et `DrivyTests` sur runner Apple au SHA du commit de livraison.
2. Exécuter `MessagingMediaMessageTransportTests` et `MessagingMediaMessageClientTests`.
3. Rejouer les suites partagées touchées ou dépendantes : `MessagingHTTPTransportTests`,
   `MessagingThreadTests`, `MessagingDiagnosticsTests`, `MatrixMessagingRelayIntegrationTests`,
   `MatrixMessagingSealedReportRelayTests`, `MessagingMediaContentTests`.
4. Vérifier sur appareil/réseau synthétique que le POST média réel, le retry 401 et les refus T1 produisent
   les reçus attendus (aucune preuve simulée ne remplace ce contrôle).

## État du parcours

Ce raccord est une pièce du parcours média, pas le parcours complet. Le dépôt binaire réel, le coffre, la file,
le coordinateur, l'UI et la qualification restent à assembler et à revoir après les interfaces livrées ici.
