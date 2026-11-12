# Epic UX médias #472 — lot B : visionneuse de photos et lecteur PDF (#474)

Branche `tomyrms/ux-medias-474-visionneuse`, base `950d999b`. Rien déployé, aucune issue fermée.

## Ce qui change

- `MessagingUI/MessagingMediaViewer.swift` (nouveau) : visionneuse plein écran, géométrie du zoom pure, décodeur ImageIO, lecteur PDF.
- `MessagingMediaViews.swift` : `MessagingMediaPreview` et le lecteur PDF en sortent (le panneau du composeur et `MessagingMediaFileLabel` sont inchangés).
- `MessagingConversationView.swift` : seul le point de présentation change, `.sheet(item:)` devient `.fullScreenCover(item:)` sur le même `mediaComposer?.preview`.
- `DrivyTests/MessagingMediaViewerTests.swift` (nouveau), ajouté à la sélection `unit_test_scope=messaging` (`scripts/ios/test-selection.sh` et `test_test_selection.py`). XcodeGen prend `DrivyTests` et `Drivy` par dossier : rien à déclarer.

## Comportement

- **Photo** : `UIScrollView` + `UIImageView` (API Apple, aucun package). Échelle 1 = image ajustée au cadre sans déformation, centrée ; pincement natif jusqu'au zoom maximal (de 3 à 8 selon les pixels de l'image) ; double toucher : agrandit (au moins 2,5×, ou le remplissage du cadre pour une capture haute) en centrant le point touché, un second double toucher revient à l'ajustement ; déplacement natif, bornes du `UIScrollView` plus marge de centrage quand l'image est plus petite que le cadre. Au changement de taille du cadre (rotation, redimensionnement iPad), retour à l'ajustement au nouveau cadre, sans conserver le zoom.
- **Zones sûres** : la barre (Fermer à gauche, nom tronqué au milieu, sur trois lignes aux grandes tailles) est dans la zone sûre ; l'image occupe le reste ; le fond est `DrivyTheme.canvas`.
- **Réduire les animations** : les zooms par double toucher ne sont pas animés.
- **Accessibilité** : bouton « Fermer » (identifiant `messaging.media.close`, cible 44 pt) toujours présent ; l'image porte le nom du fichier et deux actions « Agrandir » / « Réduire » ; identifiant `messaging.media.preview` conservé sur le conteneur.
- **Fermeture** : par le bouton uniquement. Le glisser-pour-fermer n'est pas implémenté (choix : aucune concurrence possible avec le déplacement). Les gestes vivent dans la couverture plein écran, hors du fil : aucun risque de réponse par glissement ni de menu contextuel du fil.
- **Fil, brouillon, réponse** : la couverture est présentée par-dessus le fil sans le modifier ; la fermeture ne déclenche aucun défilement.
- **Invalidation** : inchangée, `preview = nil` par `dismissRemovedPreview`, `removeSelection`, `suspend` ferme la couverture. Un résultat d'ouverture périmé est déjà écarté par la génération du modèle (non modifié). `.id(preview.id)` recrée la vue pour chaque nouvel aperçu.
- **PDF** : PDFKit sur `PDFDocument(data:)` en mémoire, `MessagingReadOnlyPDFView` et délégué neutralisant liens, actions distantes et impression, conservés tels quels ; aucun fichier temporaire ni QuickLook. Ajouts : défilement continu multi-pages, zoom jusqu'à 4×, dézoom limité à la page entière, indicateur « Page n sur N » (au-dessus d'une page) mis à jour par `PDFViewPageChanged`.

## Décodage

`MessagingImageDecoder.decode` (ImageIO, `CGImageSourceCreateThumbnailAtIndex`, orientation EXIF appliquée, décodage immédiat) tourne dans une `Task.detached` lancée une seule fois par `.task` de la surface, jamais dans `body`. Le plus grand côté décodé vaut deux fois le plus grand côté du cadre en pixels, plafonné à 4096 et à la taille de la source, plancher 512 ; une image plus petite n'est pas agrandie. `UIImageView` est vidé à la disparition de la vue (`dismantleUIView`).

## Interface d'état pour #476

```swift
enum MessagingMediaViewerState: Equatable { case loading; case ready(MessagingPreparedMedia); case failed(String) }

struct MessagingMediaViewer: View {
    init(state: MessagingMediaViewerState, title: String, retry: (() -> Void)? = nil, close: @escaping () -> Void)
}

struct MessagingMediaPreview: View {   // état « prêt » seulement, branché aujourd'hui
    init(media: MessagingPreparedMedia, close: @escaping () -> Void)
}
```

`loading` affiche « Ouverture… » ; `failed(message)` affiche « Aperçu indisponible », le message (français court, sans nom de fichier) et, si `retry` est fourni, « Réessayer » (`messaging.media.retry-open`) ; `ready` ouvre la photo ou le PDF. Le titre est toujours fourni par l'appelant. #476 remplacera `opening` par un état par média : la présentation pourra passer de `fullScreenCover(item:)` sur `preview` à un item portant `MessagingMediaViewerState` et réutilisera `MessagingMediaViewer` tel quel (changer de `state` recrée la surface correspondante). Aujourd'hui rien n'alimente `loading` ni `failed` : le panneau du composeur affiche encore « Ouverture… » et l'erreur près du composeur. Le modèle du composeur n'est pas modifié.

## Exécuté / non vérifié

Exécuté en local : `scripts/ios/test_test_selection.py` (27 tests, sélection incluant la nouvelle classe). Aucune toolchain Swift sur la machine de travail ; la compilation et les 16 tests de `MessagingMediaViewerTests` (géométrie, bornes, double toucher, taille de décodage, décodeur sur PNG synthétiques) dépendent du run Apple, voir `STATUS.md`.

Non essayé : pincement, double toucher, déplacement, rotation et redimensionnement iPad sur appareil ou simulateur ; VoiceOver (étiquettes, actions Agrandir/Réduire) ; grandes tailles de texte ; qualité visuelle de la barre et de l'indicateur de page ; PDF multi-pages réel (dézoom minimal, indicateur) ; capture vidéo demandée par l'issue ; parcours sur le build intégré (#478). Les tests UI existants (`MessagingMediaUITests`, `MessagingReportScreensUITests`) cherchent « Fermer » et ne sont pas modifiés ; leur exécution contre la couverture plein écran reste à faire.
