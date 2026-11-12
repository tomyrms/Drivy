# Épic UX médias #472 — lot A : photos et PDF dans le fil (#473)

Branche `tomyrms/ux-medias-473-fil`. Le fil de messagerie affiche les photos en bulles à espace réservé et les PDF en cartes lisibles. Le protocole UI gelé `MessagingMediaRuntime` n'est pas modifié ; l'ouverture reste `thread.openMedia`, le visualiseur et l'aperçu appartiennent au lot #474.

## Capacité de miniature (interne, additive)

```swift
protocol MessagingMediaThumbnailProviding: Sendable {
    func thumbnail(for message: MessagingWireMessage) async throws -> Data
}
```

Découverte par cast optionnel (`runtime as? any MessagingMediaThumbnailProviding`), comme `MessagingMediaRevocationReceiving`. `MessagingMediaCoordinator` l'implémente.

Contrat :

- Octets rendus : miniature JPEG ou PNG bornée (≤ 512 px par axe, ≤ 128 Kio), lue dans le cache protégé chiffré.
- Absente du cache : l'original autorisé est téléchargé, validé, la miniature produite puis mise en cache chiffré (même chemin que `open`, sans second code de téléchargement).
- Aucune URL publique, aucun fichier en clair, aucun cache standard.
- Refus : message supprimé pour tous ou média révoqué (`removed`), PDF (`invalidFormat`), mauvaise provenance ou taille (`integrity`), école différente (`contextChanged`).
- Le contexte (`ensureActive`) et la révocation sont relus après chaque `await` ; une invalidation ou une révocation survenue pendant l'écriture de la miniature se traduit par un refus et une purge, jamais par une miniature rendue.
- Les dimensions viennent du contenu chiffré (`MessagingMediaAttachment.width/height`) ; aucune métadonnée publique n'est ajoutée.

## Chargeur d'interface

`MessagingMediaThumbnailLoader` (`@MainActor @Observable`), un par conversation, créé par `MessagingThreadModel` (`thread.thumbnails`).

- État par pièce : `Slot` observable (`phase` : `idle`, `loading`, `loaded`, `unavailable(retryable:)` ; `image`).
- Chargement déclenché par l'apparition de la cellule (`appear`, tête de file) ; voisines en `prefetch` (queue de file) ; `disappear` retire une demande encore en file.
- Concurrence bornée à 3 (travail réel en vol compté, même après annulation), file bornée à 12, une seule demande par pièce.
- Mémoire : 24 images décodées au plus, éviction de la plus ancienne non visible ; une pièce visible n'est jamais évincée. Une pièce évincée revient du cache protégé, sans téléchargement.
- Décodage ImageIO hors du `body` et hors du MainActor.
- Invalidation : `suspend()` (changement de contexte ou d'accès) annule tout et libère les images ; `discard(keeping:)` retire les médias supprimés ou révoqués ; un résultat tardif est ignoré (billet par demande, génération globale, `isAuthorized` relu à l'arrivée).
- Reprise ciblée (`retry`) seulement pour les échecs pouvant être transitoires (`unavailable`, `unreadable`, `protectionUnavailable`, `resultUnknown`).

## Règles de ratio (bulle photo)

Largeur maximale 260 pt, hauteur maximale 340 pt, ratio largeur/hauteur borné à [0,6 ; 2].

| Cas | Ratio réservé | Recadrage | Taille (colonne ≥ 260) |
|---|---|---|---|
| Paysage 4:3 | 4/3 | aucun | 260 × 195 |
| Portrait 3:4 | 0,75 | aucun | 255 × 340 |
| Carré | 1 | aucun | 260 × 260 |
| Capture longue (< 0,6) | 0,6 | on garde le haut | 204 × 340 |
| Panorama (> 2) | 2 | on garde le centre | 260 × 130 |
| Dimensions absentes ou nulles | 4/3 | aucun | 260 × 195 |

Colonne plus étroite : la largeur suit, la hauteur reste bornée. L'espace est réservé avant le chargement, la bulle ne saute donc pas à l'arrivée de l'image. Transparence : la miniature est posée sur le fond `surfaceCard` de la bulle.

## États et accessibilité

- Chargement : espace réservé neutre, valeur VoiceOver « Chargement ».
- Indisponible : icône et « Aperçu indisponible » ; bouton de reprise (≥ 44 pt, identifiant `messaging.media.thumbnail.retry`) seulement si l'échec est reprenable.
- Toucher : toujours `thread.openMedia`, identifiant conservé `messaging.media.received.open`, libellé « Photo, nom », indice « Ouvre la pièce jointe ».
- Carte PDF : icône `doc.richtext`, nom sur 3 lignes (8 en tailles d'accessibilité) avec troncature au milieu, « PDF · taille », hauteur minimale 44 pt, même identifiant, libellé « Document PDF, nom, taille ». Aucune miniature de première page.
- Sans capacité de miniature dans la composition : état indisponible sans reprise.

## Fichiers

- `MessagingCore/MessagingMediaRuntimeContracts.swift`, `MessagingCore/MessagingMediaCoordinator.swift` : capacité.
- `MessagingUI/MessagingMediaThumbnailLoader.swift` : chargeur et décodeur.
- `MessagingUI/MessagingMediaBubbleViews.swift` : géométrie, bulle photo, carte PDF, vue de pièce jointe, aperçus synthétiques (`#Preview`, DEBUG).
- `MessagingUI/MessagingConversationView.swift` : intégration dans `MessagingThreadRow` et `MessagingThreadModel`.
- `MessagingUI/MessagingMediaQualificationFixture.swift` : la fixture du simulateur fournit aussi la capacité (miniature synthétique, sans compter de requête de fichier).
- Tests : `DrivyTests/MessagingMediaThumbnailLoaderTests.swift` (géométrie, chargeur), `MessagingMediaThumbnailCapabilityTests` à la fin de `MessagingMediaCoordinatorTests.swift` ; ajoutés à la portée `messaging` de `scripts/ios/test-selection.sh`. `project.yml` référence les dossiers entiers, aucun fichier à déclarer.

## Pièce visible : jamais d'attente sans fin

Une cellule encore à l'écran ne reste pas sur l'indicateur d'attente quand sa demande s'arrête :

- `suspend()` (changement de contexte ou d'accès) : les pièces visibles passent à `unavailable(retryable: true)` et gardent leur message pour une reprise sur geste ; les pièces hors écran repassent à `idle`.
- Pièce non autorisée au dépilage ou à l'arrivée du résultat : `unavailable(retryable: false)` si elle est visible, `idle` sinon, jamais redemandée.
- Résultat `.cancelled` avec un billet encore valide (annulation extérieure) : la pièce visible est redemandée.

## Exécuté / non vérifié

- Écrit sur un poste Windows sans compilateur Swift : relu, non compilé ni exécuté localement.
- Run Apple 43230205594 (SHA `016c39f4`, portée `messaging`) : compilation réussie, 253 tests, un seul échec : `MessagingMediaThumbnailLoaderTests.testConcurrencyIsBoundedAndQueuedItemsFollow`. Cause : défaut du test, pas du produit. Le fournisseur factice retient chaque appel ; le test ne libérait qu'une fois les deux premiers appels, puis les deux suivants (démarrés ensuite par le chargeur) restaient retenus, d'où deux demandes en vol et des pièces jamais chargées jusqu'à l'échéance. Le test libère maintenant à chaque tour d'attente. `scripts/ios/test_test_selection.py` aligné sur les trois classes ajoutées (27 tests Python passent en local).
- Suite : nouveau run de la portée `messaging` sur la branche (résultat à consigner).
- Non essayé : rendu réel des `#Preview`, VoiceOver, grandes tailles de texte, gestes, appareil physique, performance de défilement sur un long fil.
- Hors périmètre : `MessagingMediaPreview`, `MessagingMemoryPDF`, la feuille d'aperçu (lot #474), compositeur et intentions en attente (lots #475/#476). Le texte de repli « Photo » / « PDF » de la bulle texte au-dessus d'une pièce jointe n'est pas modifié.
