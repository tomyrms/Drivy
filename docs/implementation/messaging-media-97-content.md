# Médias #97 - T2b1 : contenu natif v3, provenance, bornes du vrai protocole

Base : `883581ad321b67ae3b7efe15ef2c6b89970b1e20` (T2a revue), branche de travail
`tomyrms/issues-medias-contenu-97`. **Correction 1/2** demandée par le coordinateur après revue du candidat
`ce3c9e09`. Cible iOS 26.0 / Swift 6. Aucune dépendance, aucun lockfile, aucun `project.yml`, aucun workflow,
aucune sélection de tests modifiés.

Périmètre : le **contenu applicatif** d'un message porteur d'un média, sa lecture avec **provenance explicite**,
et les bornes mesurées sur les enveloppes réellement produites. La sélection photo, la préparation ImageIO/PDFKit,
le transport binaire, le coffre, le cache, les miniatures, l'UI et l'activation produit restent hors de ce lot.

## 0. Modèle, skills et Codebase Memory (preuves de cette passe)

| Élément | Valeur observée |
|---|---|
| Modèle effectif | `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash), sans model/effort additionnel |
| Skills Superpowers chargés | `systematic-debugging` (`.../superpowers/skills/systematic-debugging/SKILL.md`), `test-driven-development`, `verification-before-completion` |
| Projet Codebase Memory | `drivy-t2b1-contenu-97-20261104`, **même racine** : `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-contenu-97` |
| Fraîcheur après ré-indexation | `status: ready`, `indexed_at: 2026-11-04T18:10:30Z`, 39 073 nœuds / 167 542 arêtes |
| Couverture | `MessagingMediaContent`, `MessagingThreadModels`, `MessagingContracts`, `MessagingOutboxCoordinator`, `MessagingHTTPTransport` : `no_recorded_issue` + `metadata_match` ; `MatrixMessagingCryptography` : `partial` (ligne 100) → source relue |
| Impact | `detect_changes` (inbound, 2 sauts) : 265 symboles graine, 244 symboles impactés dans le module messagerie (`MessagingOutboxCoordinator.enqueue`, `MessagingQualificationFixture.decrypt`, `MessagingProtectedStore`, `MessagingWorkspace`…) — les consommateurs relus sont `MessagingWorkspace.content(for:)`, `MessagingReportInbox`, `MessagingConversationView`, `MessagingOutboxCoordinator` |
| Preuve serveur des bornes | `apps/api/src/messaging-routes.ts:21` (`payload: z.string().min(4).max(12000)`), `:171-175` (`bodyLimit: 655_360`, items 1..50, chaque item = `envelope`) |

## 1. Les trois causes corrigées

1. **Borne du payload absente au transport.** `send()` ne gardait que le corps sérialisé (16 Kio). Un payload de
   11 000 octets devient 14 668 caractères base64 et 14 840 octets de corps : sous 16 Kio, mais refusé par le
   serveur (`400 INVALID_REQUEST`). La reproduction HTTP réelle du coordinateur l'a établi ; le test qui
   l'acceptait était faux.
2. **Signalement : plafond par item ignoré.** Le lot garde 640 Kio de corps, mais **chaque** `envelope.payload`
   reste plafonné à 12 000 caractères. Un item de 20 000 octets n'est pas valide, même si le corps tient sous
   640 Kio.
3. **Provenance devinée sur des octets utilisateur.** `decode(Data)` interprétait un `body` qui *ressemblait* à un
   contenu namespacé : un ancien texte valide `{"msgtype":"m.text","body":"Photo","ch.drivy.messaging":{"v":4}}`
   devenait « Photo » (et un lookalike v3 pouvait devenir un média ou un message illisible), tandis que l'émetteur
   générique refusait ce même texte. L'heuristique est supprimée : la provenance vient de la structure authentifiée
   de l'événement déchiffré.

## 2. Interfaces exactes et consommateurs futurs

```swift
// MessagingContracts.swift (additif, aucun conformer existant modifié)
struct MessagingDecryptedContent: Sendable, Equatable {
    enum Provenance: Sendable, Equatable { case legacyBody, matrixContent }
    let bytes: Data
    let provenance: Provenance
    static func legacyBody(_:) -> MessagingDecryptedContent
    static func matrixContent(_:) -> MessagingDecryptedContent
}

// MessagingMediaContent.swift (capacités additives, optionnelles)
protocol MessagingMatrixContentEncryption: Sendable {
    func encryptMatrixContent(_ content: MessagingMediaContentV3, mentions: [UUID],
                              scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext
}
protocol MessagingContentProvenanceDecryption: Sendable {
    func decryptContent(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> MessagingDecryptedContent
}

// MessagingThreadModels.swift
func encoded() throws -> Data                      // enveloppe APPLICATIVE : refuse un média
static func decode(_:) -> MessagingPlainContent?   // legacy : texte v1, enveloppe v2, rien d'autre
static func decodeMatrixContent(_:) -> MessagingPlainContent?  // contenu Matrix authentifié uniquement

// MatrixMessagingCryptography (conforme aux deux capacités)
func encryptMatrixContent(...) ; func decryptContent(...)
static func plaintext(from:) -> Data               // legacy : body seul
static func content(from:) -> MessagingDecryptedContent
static let maximumOrdinaryPayloadBase64Length = 12_000

// MessagingHTTPTransport (privé)
maximumEnvelopePayloadCharacters = 12_000 ; maximumSendBodyByteCount = 16_384 ; maximumReportBodyByteCount = 655_360
```

Consommateurs futurs, nommés pour que le lot suivant n'ait pas à deviner :

| Interface | Consommateur prévu |
|---|---|
| `MessagingMatrixContentEncryption` | coordinateur média/coffre (T2b2/T3) : construit `MessagingMediaContentV3` puis chiffre, sans passer par le chemin texte |
| `MessagingContentProvenanceDecryption` | lecture d'un média (T3) et boîte de signalement (T3) : `decodeMatrixContent` sur `.matrixContent` |
| `MessagingDecryptedContent` | `MessagingWorkspace.content(for:)` et `MessagingReportInbox` (lot UI) : remplacent l'appel `decrypt` + `decode` legacy |
| `MessagingOutboxCoordinator.enqueue(content:)` | garde fermée à remplacer par le coordinateur média |

## 3. Écriture : deux chemins séparés, aucune heuristique

- **Texte générique** (`encrypt(_ plaintext: Data, …)`) : les octets applicatifs vont dans `body`, tels quels.
  Aucun octet n'est relu comme un contenu Matrix. Un texte qui reproduit exactement un lookalike v3/v4 part et
  revient **identique**, sans média et sans refus.
- **Contenu structuré** (`encryptMatrixContent(_ value: MessagingMediaContentV3, …)`) : le type porte la légende et
  la pièce jointe ; le contenu produit est `{"msgtype":"m.text","body":<repli lisible>,
  "ch.drivy.messaging":{"v":3,"text":…,"media":…}}`, réellement passé à `machine.encrypt`. `m.mentions` vient
  uniquement du paramètre contrôlé. Le contenu encodé est borné à 6 000 octets **avant** chiffrement.
- `MessagingPlainContent.encoded()` refuse un média (`invalidResponse`) : l'enveloppe applicative v2 ne le porte pas,
  et un média ne doit pas être stocké dans une forme qui ne le représente pas.
- Messages sans média : `messageContent(text:mentions:)` est inchangée, donc **aucun octet d'une intention
  existante ne change** et aucun retry ne rechiffre (`MessagingOutboxCoordinator.retry` renvoie l'enveloppe stockée).

## 4. Lecture : provenance explicite

`plaintext(from:)` rend **toujours** les octets du `body` (texte v1, enveloppe v2, contenu de récupération local) :
c'est l'API legacy, ses octets et sa sémantique ne changent pas. `content(from:)` rend la provenance :

| Événement déchiffré | Provenance | Lecture |
|---|---|---|
| contenu sans `ch.drivy.messaging` | `.legacyBody` + octets du `body` | `decode(_:)` : texte v1 ou enveloppe v2 |
| contenu avec `ch.drivy.messaging` | `.matrixContent` + JSON du `content` | `decodeMatrixContent(_:)` |

`decodeMatrixContent` : v3 valide → contenu + pièce jointe ; version namespacée inconnue → `body` de repli (jamais
le JSON technique) ; v3 connu mais invalide **ou au-delà de 6 000 octets canoniques** → `nil` (échec fermé) ; octets
non Matrix → `nil` (mauvais décodeur).

Conséquences vérifiées par les tests écrits :

- un ancien `body` qui est **exactement** un lookalike v3 complet ou v4 reste le texte d'origine, réémis octet pour
  octet, sans pièce jointe et sans échec ;
- le même JSON comme **vrai `content` Matrix** est reconnu par la provenance et produit le média validé ;
- aucune modification des messages stockés, du `recoveryContent` local v2 ni des enveloppes de signalement.

Résultat attendu côté future UI (aucune UI modifiée) : un v3 connu et invalide rend `nil`, donc aucun faux succès ni
JSON technique ; un média n'est pas encore rendu (le fil lit le `body` de repli). Le mapping fin relève du lot UI.

## 5. Bornes : où chacune est mesurée

| Borne | Valeur | Où | Sur quoi |
|---|---|---|---|
| contenu Matrix v3 (écriture **et** lecture) | ≤ 6 000 octets | `encryptMatrixContent` (refus avant chiffrement) ; `MessagingMediaContent.reading` (échec fermé du v3 connu) | le contenu Matrix complet canonique, mentions comprises — jamais le seul `body` ni le nombre de caractères |
| légende | ≤ 1 000 caractères | `MessagingMediaContentV3` | `text.count` |
| taille de pièce | 1 … 4 194 304 octets | `MessagingMediaAttachment` | `size` |
| nom | ≤ 255 caractères, C0/DEL/C1, U+202A–202E, U+2066–2069, séparateurs retirés | `MessagingMediaName` | nom assaini à la construction |
| dimensions | 1 … 12 000 par axe, ≤ 40 M pixels, `multipliedReportingOverflow` | `MessagingMediaAttachment.validate` | image seulement |
| MIME | `image/jpeg`, `image/png`, `application/pdf` | `MIME` | enum |
| crypto | T2a (`validatedMaterial()`), aucun alphabet normalisé | `MessagingMediaAttachment` | en-tête, alphabets, longueurs |
| `ciphertext.payload` (message **et** item de signalement) | base64 ≤ 12 000 caractères | `MessagingHTTPTransport.send` / `report` **et** `encrypt` après chiffrement | la chaîne réellement émise |
| corps d'un message ordinaire | ≤ 16 384 octets | `send`, avant `request()` | `JSONEncoder().encode(SendBody(…))` |
| corps d'un signalement | ≤ 655 360 octets | `report`, avant `request()` | le lot complet |

Le sérialiseur `MessagingMediaContent.messageContent` **ne borne rien** : il fournit les octets à mesurer. La
garde de 6 000 octets appartient à la capacité de chiffrement (avant toute ouverture de session ou appel de
relais) et à la lecture d'un v3 connu (échec fermé, rien n'est décodé ni exposé).

Les deux bornes du transport sont vérifiées **avant** tout jeton et toute requête ; le refus laisse l'intention
dans la file existante (comportement inchangé de `retry`, aucun succès annoncé).

## 6. Signalement (#77)

- Le lot garde sa limite de corps (640 Kio) : un corps de plusieurs items au-delà de 16 Kio reste valide.
- Chaque item respecte 12 000 caractères base64, sinon le lot est refusé avant émission. Cette borne est
  mesurée sur la sortie réelle : le payload est le JSON Matrix qui contient déjà le chiffré en base64, puis le
  transport encode ce JSON en base64 (double expansion). Aucune longueur de clair n'est un seuil de contrat.
- `sealForSchoolAdmins` ne change pas et **ne borne pas l'item** : il recopie l'enveloppe. Un clair trop grand
  produit donc un item hors plafond, que la frontière `report()` refuse. Le cas nominal se vérifie sur la taille
  produite, pas sur une estimation.
- Un contenu v3 signalé garde son enveloppe octet pour octet ; le lecteur **typé** appelé manuellement en
  retrouve les métadonnées (nom, type, taille, clé de fichier), le décodeur legacy n'en fabrique jamais. Aucun
  consommateur branché (fil, boîte de signalement) n'utilise encore cette provenance : la lecture et le
  signalement d'un média restent **non intégrés**, et l'adaptation typée de la boîte de signalement reste à
  spécifier dans le lot UI. Aucun consommateur ne doit interpréter un ancien `body` ressemblant au v3 par
  heuristique.

## 7. Signalement média typé (#97, raccord)

Le signalement d'un média ne passe plus par l'enveloppe applicative (qui refuse un média) : le lot est
**typé de bout en bout**, du producteur à la boîte de l'administrateur.

| Élément | Contenu |
|---|---|
| `MessagingReportPayload` | `.legacy(Data)` (texte v1, sondage v2 : octets conservés) ou `.media(MessagingMediaContentV3)` (contenu Matrix v3 validé) |
| `MessagingTypedReportSealing` | capacité additive : `sealReport(_:scope:conversationID:)`, une seule session pour tout le signalement |
| `MatrixMessagingCryptography.sealReport` | contenu construit **avant** toute ouverture de session : `.legacy` → `body` comme avant, `.media` → contenu Matrix v3 borné à 6 000 octets ; ordre, rotation, destinataires et `backupOrMarkPending` inchangés |
| `sealForSchoolAdmins(_:)` / `(_ plaintexts:)` | **inchangées** : elles délèguent au lot typé en déclarant `.legacy`, donc aucun octet legacy ne change |
| `MessagingWorkspace.report` | construit un `.media` quand le contenu porte une pièce jointe, un `.legacy` sinon ; garde l'intention durable, l'ordre des identifiants et l'acquittement existants |
| Sans capacité typée | un lot qui contient un média est **refusé fermé** (`protectionUnavailable`) : aucun contenu n'est scellé à sa place, aucune intention n'est écrite ; un lot purement legacy reste accepté |

Boîte de l'administrateur : `MessagingReportInboxModel` consomme la **provenance authentifiée**
(`decryptContent`) et décode `decodeMatrixContent` pour un contenu Matrix, le décodeur legacy sinon. Un ancien
`body` qui ressemble à un v3 reste donc du texte, jamais une pièce jointe. Le modèle de présentation
`MessagingReportLine` porte en plus `media: MessagingReportAttachment?` :

- `nature` (`photo` | `pdf`), `name` (déjà assaini par le contenu), `caption` (légende ou `nil`),
- `bytesTransmitted` : **toujours `false` dans cette livraison** — aucun octet de fichier n'est demandé, copié,
  téléchargé ni transmis aux administrateurs.

Ni clé de fichier, ni IV, ni hash, ni URL n'entrent dans ce modèle : la clé reste dans l'enveloppe chiffrée que
seuls les appareils destinataires déchiffrent. La vue appartient au lot UI (Codex) : ce lot ne modifie aucun
fichier de vue, aucune fixture UI et aucune suite `MessagingReportScreensUITests`.

## 8. Tests écrits — **NON EXÉCUTÉS côté Apple**

40 méthodes de test dans le lot (36 précédentes + 4 pour ce raccord, plus les étapes média ajoutées au cas de
relais), toutes écrites et relues, **aucune compilée ni exécutée** (aucun outil Apple sur ce poste).

| Fichier | Cas ajoutés |
|---|---|
| `MessagingMediaContentTests.swift` (nouveau) | 18 : forme namespacée et `body` lisible, repli par MIME, synthèse, aller-retour par le décodeur structuré, enveloppe v2 inchangée (`text`/`poll` nuls omis), refus du média par l'enveloppe applicative, légende 1 000/1 001, sérialiseur qui **mesure** sans borner (unicode lourd), **v3 connu au-delà de 6 000 octets illisible à la lecture**, taille 0/1/4 Mio/4 Mio+1/−1, MIME hors liste, nom assaini, dimensions, métadonnées crypto, version future → `body`, v3 incomplet → `nil`, décodeur structuré qui refuse des octets legacy, lookalike v3/v4 complet → texte |
| `MessagingThreadTests.swift` | 7 : 4 sur le contenu (legacy seulement, contenu Matrix par le décodeur dédié, `recoveryContent` texte inchangé, enveloppe applicative qui refuse un média) + 3 sur le raccord : média scellé par la capacité typée, refus fermé sans capacité, lot mixte texte + média dans l'ordre |
| `MatrixMessagingCryptographyTests.swift` | 5 : média namespacé chiffré par la capacité typée (Megolm réel, deux appareils, mentions contrôlées), legacy/lookalike octet pour octet avec provenance `.legacyBody`, bornes après chiffrement, contenu média > 6 000 refusé par `encryptMatrixContent`, extraction `plaintext`/`content` avec gardes |
| `MatrixMessagingCryptographyTests.swift` (signalement) | 5 : mesure de l'enveloppe scellée, conservation des octets d'un v3 par le lecteur typé, **lot typé texte + média dans une session**, **lookalike legacy conservé comme texte**, **média > 6 000 refusé avant scellement** |
| `MessagingReportInboxTests.swift` | 3 : pièce jointe présentée (nature, nom, légende, `bytesTransmitted == false`) sans clé/IV/hash, lookalike legacy rendu comme texte sans pièce jointe, message illisible sans pièce jointe |
| `MatrixMessagingSealedReportRelayTests.swift` | étapes média ajoutées au cas unique existant : message média réel, scellement typé, POST, boîte administrateur avec légende et métadonnées |
| `MessagingHTTPTransportTests.swift` | 6 : payload 12 000 accepté / 12 004 refusé (zéro requête, zéro jeton), corps 16 Kio refusé (garde défensive), signalement de 4 items > 16 Kio accepté, item > 12 000 refusé, 50 items sous 640 Kio acceptés |
| `MessagingCoreTests.swift` | 1 : refus fermé du média par la file existante, avant chiffrement et sans écriture |

Inscriptions : `MatrixMessagingCryptographyTests`, `MessagingMediaContentTests` et `MessagingThreadTests`
rejoignent la sélection `messaging` dans `scripts/ios/test-selection.sh` **et** dans
`scripts/ios/test_test_selection.py` (les deux listes restent identiques, les noms existent réellement).

## 9. Commandes réellement exécutées

| Commande | Résultat | Code |
|---|---|---|
| `git rev-parse HEAD` / `git status --porcelain` | `b562c0e0…`, arbre propre avant édition | 0 |
| `index_repository` + `index_status` + `check_index_coverage` | projet `drivy-t2b1-contenu-97-20261104`, même racine, `ready` | — |
| `python scripts/ios/test_test_selection.py` | **25 tests, OK**, 12,6 s — sélection `messaging` identique entre le shell et Python, noms de suites présents dans les sources Swift | 0 |
| `Select-String` sur `apps/api/src/messaging-routes.ts` | `max(12000)` par enveloppe, `bodyLimit: 655_360`, items 1..50 | — |
| `Select-String` sur `apps/api/src/messaging.ts` | cadence des signalements : 3 par conversation et par heure, 10 par école et par jour | — |
| `Get-Command swift,xcodebuild,xcrun` | **0 outil** | — |
| `git diff --check` / `git diff` / `git status` après édition | aucune erreur d'espace, diff relu, seuls les chemins autorisés | 0 |

### NON EXÉCUTÉ

- **Swift / Xcode / simulateur** : aucun outil Apple ici. Aucune compilation, aucun RED/GREEN, aucun GREEN sur
  les cas ajoutés ; la preuve Apple reste à produire sur le SHA de cette branche.
- **Cas de relais HTTPS** : nécessite `DRIVY_RELAY_QUALIFICATION_URL` ; les étapes média sont écrites, non
  exécutées.
- **Chiffrement Megolm réel** : non exécuté ici ; les bornes finales restent à démontrer par Apple.

## 10. Limites, risques et écarts de périmètre

- **Aucune preuve Apple du nouveau raccord de signalement `457ce9c4`.** Les preuves Q8/Q11 des lots
  médias déjà intégrés restent attachées à leurs SHA ; elles ne qualifient pas ce delta. La sélection
  `messaging` doit compiler puis exécuter le candidat publié avant tout verdict sur ce raccord.
- **La file des messages ordinaires refuse les médias** (`MessagingOutboxCoordinator.enqueue(content:)`, refus
  fermé explicite). Le parcours média possède déjà son coordinateur dédié, son coffre et ses preuves
  antérieures ; ce refus du chemin ordinaire ne signifie pas que ces lots restent à implémenter.
- **Aucune UI modifiée** : aucune vue, aucune fixture UI, aucune suite `MessagingReportScreensUITests`. La vue du
  signalement ne compose pas encore la ligne média (nature, nom, « pièce jointe non transmise ») : elle relève du
  lot UI Codex, à partir du modèle `MessagingReportAttachment` livré ici.
- **Aucun champ `media` serveur, aucun transport binaire, aucun cache, aucun coffre** dans ce raccord.
- **Le fil dispose déjà du lecteur typé** dans `MessagingWorkspace.content(for:)`, avec contrôle de la
  référence média serveur et des retraits. Ce raccord ajoute la lecture typée dans la **boîte de
  signalement** ; il ne réimplémente pas le parcours du fil déjà intégré.
- **Lecture d'un v3 connu au-delà de 6 000 octets** : échec fermé (`nil`), rien n'est décodé. Le legacy, lui,
  affiche le `body` de repli ; aucun décodeur ne fabrique de média à partir d'un `body`.
- **Garde de corps du message (16 Kio)** : défensive, jamais atteinte par un message conforme au schéma serveur
  (payload ≤ 12 000 + champs bornés). Elle est testée avec un cas fabriqué, signalé comme tel.
- **Garde de corps du signalement (640 Kio)** : inatteignable avec 50 items de 12 000 caractères ; conservée comme
  borne défensive et éprouvée à sa frontière haute admissible (50 items).
- La borne de 12 000 est appliquée deux fois (après chiffrement, puis au transport) : la première évite de mettre
  en file une intention inenvoyable, la seconde protège les appels directs (ancien cache, reprise, tests).
- Erreurs : `MessagingFailure.invalidResponse` pour tous les refus de contenu et de taille ; mapping UI détaillé
  (`M-SIZE`, `M-INTEGRITY`) et copy produit restent hors lot.
- `MessagingSearchExcerpt` ne cherche pas dans une pièce jointe sans légende : recherche média hors lot.
