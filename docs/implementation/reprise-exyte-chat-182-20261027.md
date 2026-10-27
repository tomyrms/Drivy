# Exyte Chat dans le fil Messages (#182) — décisions et reprise

Demande du porteur (27 octobre 2026) : étudier [Exyte Chat](https://github.com/exyte/Chat) et l'intégrer comme
composant de **présentation** du fil, sans remplacer la messagerie Drivy (#182). Branche `claude/182-exyte-chat`,
partie de `claude/integration-20261027` à `4014c52` (contient la refonte #98, #100–#104, #141/#169/#170 et #180).
La dernière IPA compilée sur l'intégration est `01109b1` ; celle réellement installée n'est pas connue de cette session.

## Dépendance verrouillée

| Paquet | Version | Révision | Licence | Rôle dans Drivy |
|---|---|---|---|---|
| exyte/Chat (produit `ExyteChat`) | 3.3.0 exacte | `259188eff6064605899044440e44e4e22f023d8c` | MIT | liste, menu, réactions |
| exyte/MediaPicker | 3.4.7 | `3d1db8d5b1f553d066d67a57590f211ab534a531` | MIT | lié, jamais présenté |
| Giphy/giphy-ios-sdk | 2.2.16 (exacte côté Exyte) | `37f5b1ff6cf8bc4a78c0bc5eb1b814381bac9580` | **MPL 2.0, binaire** | lié et embarqué, jamais configuré |
| onevcat/Kingfisher | 8.14.0 | `3feb743b5c92c2b443614d10a00e605212a2b4b1` | MIT | lié, aucune URL fournie |
| exyte/AnchoredPopup | 1.3.1 | `f93c51e75ff4e5242328ac24c8fb12f1f1e84eda` | MIT | interne Exyte |
| exyte/ActivityIndicatorView | 2.0.2 | `41f89372c018decaf965e8dddeb6e5347741beb4` | MIT | interne Exyte |
| SDWebImage/libwebp-Xcode | 1.6.0 | `2b5256c29ff4e20f2a0d5ee863b62b1a22144434` | BSD 3 clauses | dépendance de Giphy |

`apps/ios/project.yml` déclare seulement le produit `ExyteChat`, pour la cible Drivy (pas la cible de tests).
`apps/ios/Package.resolved` porte les sept épingles, lues par le CI avec `-onlyUsePackageVersionsFromResolvedFile`.
Graphe relevé à la main dans le `Package.swift` de chaque tag : la machine Windows n'a pas de toolchain Swift.

**À trancher avant toute diffusion hors iLoader** : Giphy est une dépendance obligatoire du produit `ExyteChat`
3.3.0 et SPM ne permet pas de l'exclure. Le binaire `GiphyUISDK.framework` est donc embarqué (IPA zippée de 17,5 Mo
contre 14,8 Mo pour `01109b1`) avec ses obligations MPL 2.0. Option recommandée si Exyte est retenu : fork minimal
d'Exyte sans Giphy (`Views/Giphy/*`, `giphyConfig`, entrée `.giphy` d'`InputView`), tag interne, et remise à niveau
documentée à chaque version d'Exyte.

## Architecture

- `MessagingUI/MessagingThreadProjection.swift` : projection pure, sans Exyte. Identité d'affichage = envoi local
  après l'accusé (`sendStates` → `.accepted`) ; identités uniques avant Exyte, dont le `fatalError` sur doublon devient
  inatteignable ; ordre serveur conservé ; envoi en attente sous le dernier message reçu ; groupes de cinq minutes.
- `MessagingUI/MessagingComposerModel.swift` : seul propriétaire du brouillon. Texte, mentions et réponse ne sont
  retirés qu'après `workspace.enqueue` réussi ; une frappe faite pendant la mise en file est gardée. Un sondage
  n'emporte plus les mentions du brouillon texte (le fil actuel les joignait).
- `MessagingUI/MessagingExyteConversationView.swift` : `ChatView` d'Exyte ; `messageBuilder` = `MessagingBubble` et
  `MessagingPendingBubble` existantes ; `inputViewBuilder` = composeur Drivy ; menu Exyte à actions Drivy.
- `MessagingUI/MessagingExyteTheme.swift` : `ChatTheme.drivy` et `ChatLocalization.drivy`, tokens `DrivyTheme`.
- `MessagingViews.swift` : réglage « Fil Exyte (essai) » dans le menu Plus de Messages (`@AppStorage
  messaging.thread.exyte`, faux par défaut). Les deux rendus lisent le même `MessagingWorkspace` ; un seul est affiché.
- `MessagingThreadViews.swift` : `MessagingBubble.showsNativeMenu` (vrai par défaut) retire le menu contextuel natif
  sous celui d'Exyte. Le fil actuel est inchangé.

Les builders sont capturés **une fois** par `UIList.Coordinator` : ils ne lisent que `MessagingExyteThreadModel` et
le workspace (classes observées), jamais une valeur figée au premier rendu. L'égalité de `Message` ignore
`customData` : `triggerRedraw` reçoit une révision déterministe (actions, signalement, groupes, suppression, épingle,
déchiffrement) pour reconfigurer la cellule sans changer d'identité.

## Matrice fonctions actuelles / Exyte / adaptation

| Fonction | Fil actuel | Exyte 3.3.0 | Adaptation retenue |
|---|---|---|---|
| Liste, bas du fil, clavier | `ScrollView` + `LazyVStack`, ancrage manuel | `UITableView` inversée | Exyte ; décalage nul = bas du fil, suivi par `onContentOffsetChange` |
| Anciens messages | bouton « Charger les messages précédents » | `enableLoadMoreOlderMessages`, insertion à position conservée | pagination automatique d'Exyte et même bouton en tête (`mainHeaderBuilder`), accessible et sans blocage si une page échoue |
| Séparateurs de jour | capsule Drivy | sections par `createdAt.startOfDay()` | `dateHeaderBuilder` = capsule Drivy ; dates serveur réelles |
| Bulle, sondage, réactions, accusés, états | `MessagingBubble` | bulle par défaut | bulle Drivy dans la cellule ; aucun contenu déchiffré confié à Exyte (`text` vide) |
| Envoi en attente | `MessagingPendingBubble` | statut `.sending` | bulle Drivy, même identité jusqu'au message confirmé |
| Composeur, brouillon, mentions, réponse | `@State` de la vue | `InputView` puis `reset()` synchrone | composeur Drivy via `inputViewBuilder`, modèle observé, aucun champ Exyte |
| Menu et réactions | `contextMenu` + palette `ControlGroup` | `MessageMenu` + `ReactionDelegate` | menu Exyte ; actions calculées selon les droits puis revérifiées ; palette `MessagingReactionPalette` ; recherche d'emoji et aperçu des réactions coupés |
| Suppression pour tous | dialogue Drivy | alerte Exyte, bouton « Cancel » non traduit | action non destructive côté Exyte, confirmation Drivy |
| Épingles, recherche, citation | saut et mise en évidence | `scrollTo(ScrollToParams)` | chargement des pages (10 au plus), `scrollTo(.middle)`, mise en évidence 1,5 s |
| Signalement, lecture seule | pied dédié | — | pied Drivy via `inputViewBuilder` ; menu Exyte coupé pendant la sélection |
| Lecture et notifications | bas du fil et scène active | `onWillDisplayCell` | inchangé : bas du fil et scène active, jamais la préparation d'une cellule ; `showLastReadIndicator` non activé |
| Avatars | `DrivyAvatar` (mentions, recherche) | Kingfisher par URL | `avatarURL` nil, aucun avatar dans le fil |

## Points relus dans le code d'Exyte (lecture, non exécutés)

- `ChatView` crée toujours `ChatViewModel` → `LiveLocationBroadcaster` → `LocationManager`, donc un
  `CLLocationManager` (délégué, précision maximale). Aucune demande d'autorisation ni mise à jour sans partage de
  position, absent de Drivy. À confirmer sur appareil pendant une leçon (NOT_EXECUTED).
- Giphy n'est configuré que si `.giphy` figure dans les entrées et qu'une clé est fournie : ni l'un ni l'autre ici.
  Comportement du binaire au chargement non vérifiable sans capture réseau (NOT_EXECUTED).
- Kingfisher et LinkPresentation ne servent que la bulle par défaut et les avatars par URL : inutilisés ici.
- `NetworkMonitor` (`NWPathMonitor`) est créé par chaque `ChatView` : local, sans trafic.
- Les boutons du menu Exyte sont des `onTapGesture` (sans trait bouton), d'une largeur fixe de 208 pt. VoiceOver passe
  par les actions d'accessibilité de `MessagingBubble`, conservées ; Dynamic Type du menu à vérifier.

## Résultats

- PASS : résolution du verrou et compilation de l'IPA avec Exyte et le thème,
  [run 40560998430](https://github.com/tomyrms/Drivy/actions/runs/40560998430) sur `05bf364`.
- PASS : compilation de l'IPA avec la vue Exyte, sans avertissement sur les nouveaux fichiers,
  [run 40562721790](https://github.com/tomyrms/Drivy/actions/runs/40562721790) sur `96de414` (IPA zippée de 17,6 Mo).
- NOT_EXECUTED : `MessagingExyteThreadTests` (l'IPA ne compile pas la cible de tests), captures, VoiceOver, iPad,
  clavier matériel, mesures de fluidité et de mémoire, capture réseau, GPS pendant une leçon.

## Reste à faire (lots C et D de #182)

1. Installer l'IPA, activer « Fil Exyte (essai) » et parcourir : envoi hors ligne puis en ligne, pagination, saut
   depuis la recherche et l'épingle, réaction depuis le menu (fermeture immédiate), suppression pour tous,
   signalement, lecture seule, général avec mentions, iPad en paysage, clavier ouvert, VoiceOver.
2. Vérifier dans une cellule Exyte les présentations portées par la bulle (« Voir les votes », dialogue « Réagir »
   des actions d'accessibilité, « Clore le sondage ? ») ; si `UIHostingConfiguration` les ignore, les remonter au
   niveau de la vue.
3. Tests UI : rejouer les parcours messagerie critiques avec le réglage activé (argument de lancement à ajouter).
4. Trancher Giphy (fork minimal ou acceptation de la MPL) avant toute diffusion publique.
5. Basculer seulement après parité : retirer `MessagingConversationView`, le réglage et `showsNativeMenu`.

Phrase pour Codex : « Lis `docs/implementation/reprise-exyte-chat-182-20261027.md`, travaille sur
`claude/182-exyte-chat` et reprends au premier point de « Reste à faire » sans modifier le fil actuel. »
