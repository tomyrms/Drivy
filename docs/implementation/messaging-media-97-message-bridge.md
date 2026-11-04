# Médias #97 — raccord du média au message (T2b5)

> Base : `e2edc85ed092237016620079d52d11eb7a2d02b5`, branche `tomyrms/issues-medias-raccord-97`.
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
- `MessagingMediaMessageSending.sendMedia(scope:pending:media:)` sur `MessagingAPIClient`, avec défaut de
  protocole pour les transports injectés. Aucun appel automatique n'est ajouté.

Le codec de contenu v1/v2/v3, `MessagingContracts.swift`, les outbox/cache, le transport binaire, la crypto,
le coordinateur et l'interface ne sont pas modifiés.

## Encodage et réception

- Le POST média encode exactement `media: {mediaId, byteSize}`. Un texte ou sondage sans média omet la clé
  (Encodable synthétisé : `encodeIfPresent`). Les autres champs et leurs limites restent identiques.
- Sondage + média est refusé localement (`MessagingMediaTransportFailure.invalidIntent`) avant tout jeton ou
  requête. Une légende vide n'est pas inspectée par cette couche : le contenu chiffré v3 porte le repli.
- Le reçu vérifie, en plus des contrôles existants (clientID, conversation, école, expéditeur, ciphertext,
  mentions), le même `mediaId` et la même `byteSize`. Un reçu absent, incohérent ou invalide échoue fermé.
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
- Les codes média fermés sont traduits vers `MessagingMediaTransportFailure` uniquement dans le chemin média,
  via un paramètre privé `mediaFailures` valant `false` par défaut. `MESSAGING_MEMBERS_CHANGED`, les chemins
  texte/sondage/actions et les refus ordinaires gardent leur sens.
- Aucun message d'erreur libre, identifiant, URL ou hash dans les diagnostics ; aucune suppression de file sur
  refus.

### Traduction des refus média du POST

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

## Fichiers

- `apps/ios/Drivy/MessagingCore/MessagingMediaMessageContracts.swift` (nouveau)
- `apps/ios/Drivy/MessagingCore/MessagingThreadModels.swift` (ajout du champ `media`, défaut `nil`)
- `apps/ios/Drivy/MessagingAPI/MessagingAPIClient.swift` (DTO, capacité, défaut de protocole)
- `apps/ios/Drivy/MessagingAPI/MessagingHTTPTransport.swift` (encodage, décodage, validation, mapping média)
- `apps/ios/DrivyTests/MessagingMediaMessageTransportTests.swift` (nouveau)
- `apps/ios/DrivyTests/MessagingMediaMessageClientTests.swift` (nouveau)
- `docs/implementation/messaging-media-97-message-bridge.md` (ce rapport)

## Exécution, modèle et preuves de méthode

- **Modèle actif** : `opencode-go/deepseek-v4.1-flash` (vérifié dans le catalogue OpenCode). Aucun paramètre
  d'effort n'est exposé par la tâche.
- **Skills Superpowers chargés** : `test-driven-development` et `verification-before-completion`, lus via
  l'outil `skill` avant toute modification. `systematic-debugging` n'est pas invoqué : aucun bug à reproduire,
  la tâche est une implémentation additive.
- **Codebase Memory** : projet `drivy-media-message-97-20261104`, racine
  `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-raccord-97`, HEAD `e2edc85e`, `status: ready`,
  `indexed_at: 2026-11-04T21:10:13Z`, puis réindexé après écriture. Recherches de graphe :
  `MessagingSendDTO`, `MessagingAcknowledgementDTO`, `MessagingMessageMeta`, `MessagingAPITransport`,
  `MessagingHTTPTransport`, `MessagingPending`, `MessagingMediaTransportFailure`, `MessagingMediaMessageIntent`.
  Couverture des six fichiers Swift touchés : `no_recorded_issue`, `metadata_match`.
- **Commandes réellement exécutées** : `git diff --check` (code 0), `git diff --cached --check` (code 0),
  `git rev-parse HEAD`, `git log -1`, `rg -c "    func test"` sur les deux nouveaux fichiers (21 et 8),
  `Get-Command swift, swiftc, xcodebuild` (aucun outil trouvé).
- **Commit local** : HEAD de la branche `tomyrms/issues-medias-raccord-97` après ce rapport ; le SHA exact est
  transmis au coordinateur. Aucun push, CI, PR, fusion ou déploiement.

## Vérifications réellement effectuées

- Environnement : Windows, sans Swift ni Xcode. **Aucune compilation Swift, aucun RED/GREEN natif, aucune suite
  XCTest exécutée.** Les preuves Apple de la base (`1515/1515` etc.) ne sont pas transférées à ces fichiers.
- Tests écrits avant le code (ordre de rédaction), mais **non compilés** : leur résultat réel est `NOT_EXECUTED`.

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
