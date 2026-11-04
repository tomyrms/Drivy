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

## 7. Tests écrits — **NON EXÉCUTÉS**

36 méthodes de test au total dans le lot après la correction 2, toutes écrites et relues, **aucune compilée ni
exécutée** (aucun outil Apple sur ce poste).

| Fichier | Cas ajoutés |
|---|---|
| `MessagingMediaContentTests.swift` (nouveau) | 18 : forme namespacée et `body` lisible, repli par MIME, synthèse, aller-retour par le décodeur structuré, enveloppe v2 inchangée (`text`/`poll` nuls omis), refus du média par l'enveloppe applicative, légende 1 000/1 001, sérialiseur qui **mesure** sans borner (unicode lourd), **v3 connu au-delà de 6 000 octets illisible à la lecture**, taille 0/1/4 Mio/4 Mio+1/−1, MIME hors liste, nom assaini, dimensions, métadonnées crypto, version future → `body`, v3 incomplet → `nil`, décodeur structuré qui refuse des octets legacy, lookalike v3/v4 complet → texte |
| `MessagingThreadTests.swift` | 4 : legacy seulement, contenu Matrix par le décodeur dédié, `recoveryContent` texte inchangé, enveloppe applicative qui refuse un média |
| `MatrixMessagingCryptographyTests.swift` | 5 : média namespacé chiffré par la capacité typée (Megolm réel, deux appareils, mentions contrôlées, aucune valeur média dans le payload), legacy/lookalike octet pour octet avec provenance `.legacyBody`, bornes après chiffrement (contenu 6 000 accepté ; 9 000 et 16 000 refusés), contenu média > 6 000 refusé par `encryptMatrixContent`, extraction `plaintext`/`content` avec gardes |
| `MatrixMessagingCryptographyTests.swift` (signalement) | 2 : mesure de l'enveloppe scellée (cas nominal sous 12 000, cas trop grand **mesuré** au-delà, refus par la frontière du transport), conservation des octets d'un contenu v3 relu par le lecteur typé appelé manuellement |
| `MessagingHTTPTransportTests.swift` | 6 : payload 12 000 accepté / 12 004 refusé (zéro requête, zéro jeton), corps 16 Kio refusé (garde défensive), signalement de 4 items > 16 Kio accepté, item > 12 000 refusé, 50 items sous 640 Kio acceptés |
| `MessagingCoreTests.swift` | 1 : refus fermé du média par la file existante, avant chiffrement et sans écriture |

## 8. Commandes réellement exécutées

| Commande | Résultat | Code |
|---|---|---|
| `git rev-parse HEAD` / `git status --porcelain` | `7120c3a4…`, arbre propre avant édition | 0 |
| `index_repository` + `index_status` + `check_index_coverage` | projet `drivy-t2b1-contenu-97-20261104`, même racine, `ready`, 39 105 nœuds | — |
| `Select-String` sur `apps/api/src/messaging-routes.ts` | `max(12000)` par enveloppe, `bodyLimit: 655_360`, items 1..50 | — |
| `Get-Command swift,xcodebuild,xcrun` | **0 outil** | — |
| `git diff --check` / `git diff` / `git status` après édition | aucune erreur d'espace, diff relu, seuls les chemins autorisés | 0 |

### NON EXÉCUTÉ

- **Swift / Xcode / simulateur** : aucun outil Apple ici. Aucune compilation, aucun RED/GREEN, aucun GREEN.
- **Chiffrement Megolm réel des cas v3** : écrit, non exécuté. Les bornes finales (12 000 base64 sur le payload
  produit, 16 384 octets de `SendBody`) restent à **démontrer** par l'exécution Apple, pas par estimation.
- **Aucun calcul arithmétique n'est présenté comme mesure du SDK** : la taille d'un item de signalement dépend du
  chiffré réel et se vérifie à l'exécution (le double encodage est seulement décrit, pas simulé).
- **CommonCrypto / CryptoKit / Keychain** : hors lot (T2a), inchangés.

## 9. Limites, risques et écarts de périmètre

- **Aucune preuve Apple.** La prochaine exécution doit viser le SHA de cette branche ; le run `41861281984`
  couvre T2a (`883581ad`), pas ce code.
- **La file existante refuse les médias** (`MessagingOutboxCoordinator.enqueue(content:)`, refus fermé explicite).
  Le coordinateur média/coffre et l'activation du parcours restent à faire ; aucun envoi partiel n'est activé.
- **Aucune UI, aucun champ `media` serveur, aucun transport binaire, aucun cache, aucun coffre.**
- **Le fil et la boîte de signalement lisent encore la forme legacy** (`decrypt` + `decode`) : un média y apparaît
  comme son `body` de repli, jamais comme une pièce jointe ; le signalement d'un média n'est pas branché sur le
  lecteur typé. Le passage au lecteur typé et l'adaptation de la boîte de signalement restent à spécifier (lot UI).
- **Lecture d'un v3 connu au-delà de 6 000 octets** : échec fermé (`nil`), rien n'est décodé. Le legacy, lui, affiche
  le `body` de repli ; aucun décodeur ne fabrique de média à partir d'un `body`.
- **Garde de corps du message (16 Kio)** : défensive, jamais atteinte par un message conforme au schéma serveur
  (payload ≤ 12 000 + champs bornés). Elle est testée avec un cas fabriqué, signalé comme tel.
- **Garde de corps du signalement (640 Kio)** : inatteignable avec 50 items de 12 000 caractères ; conservée comme
  borne défensive et éprouvée à sa frontière haute admissible (50 items).
- La borne de 12 000 est appliquée deux fois (après chiffrement, puis au transport) : la première évite de mettre
  en file une intention inenvoyable, la seconde protège les appels directs (ancien cache, reprise, tests).
- Erreurs : `MessagingFailure.invalidResponse` pour tous les refus de contenu et de taille ; mapping UI détaillé
  (`M-SIZE`, `M-INTEGRITY`) et copy produit restent hors lot.
- `MessagingSearchExcerpt` ne cherche pas dans une pièce jointe sans légende : recherche média hors lot.
