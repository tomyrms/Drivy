# Exyte Chat dans le fil Messages (#182) — décisions et reprise

Demande du porteur (27 octobre 2026) : étudier [Exyte Chat](https://github.com/exyte/Chat) et l'intégrer comme
composant de **présentation** du fil, sans remplacer la messagerie Drivy (#182). Puis, le même jour : « met exyte par
défaut et enlève le paramètre, et utilise plus de choses d'Exyte, toujours avec la DA de Drivy ». Branche
`claude/182-exyte-chat`, partie de `claude/integration-20261027` (`4014c52`), `origin/master` fusionné ensuite
(`54b6ea9`, PR #181 et #180). PR brouillon [#184](https://github.com/tomyrms/Drivy/pull/184).

## Dépendance verrouillée

| Paquet | Version | Révision | Licence | Rôle dans Drivy |
|---|---|---|---|---|
| exyte/Chat (produit `ExyteChat`) | 3.3.0 exacte | `259188eff6064605899044440e44e4e22f023d8c` | MIT | liste, bulles, menu, réactions |
| exyte/MediaPicker | 3.4.7 | `3d1db8d5b1f553d066d67a57590f211ab534a531` | MIT | lié, jamais présenté |
| Giphy/giphy-ios-sdk | 2.2.16 (exacte côté Exyte) | `37f5b1ff6cf8bc4a78c0bc5eb1b814381bac9580` | **MPL 2.0, binaire** | lié et embarqué, jamais configuré |
| onevcat/Kingfisher | 8.14.0 | `3feb743b5c92c2b443614d10a00e605212a2b4b1` | MIT | lié, aucune URL fournie |
| exyte/AnchoredPopup | 1.3.1 | `f93c51e75ff4e5242328ac24c8fb12f1f1e84eda` | MIT | interne Exyte |
| exyte/ActivityIndicatorView | 2.0.2 | `41f89372c018decaf965e8dddeb6e5347741beb4` | MIT | interne Exyte |
| SDWebImage/libwebp-Xcode | 1.6.0 | `2b5256c29ff4e20f2a0d5ee863b62b1a22144434` | BSD 3 clauses | dépendance de Giphy |

`apps/ios/project.yml` déclare seulement le produit `ExyteChat`, pour la cible Drivy (la cible de tests compile sans le
lier). `apps/ios/Package.resolved` porte les sept épingles, lues par le CI avec `-onlyUsePackageVersionsFromResolvedFile` ;
graphe relevé à la main dans le `Package.swift` de chaque tag (pas de toolchain Swift sur la machine Windows).

**À trancher avant toute diffusion hors iLoader** : Giphy est une dépendance obligatoire du produit `ExyteChat` 3.3.0 et
SPM ne permet pas de l'exclure. `GiphyUISDK.framework` est embarqué (IPA zippée de 17,5 Mo contre 14,8 Mo pour
`01109b1`) avec ses obligations MPL 2.0. Option recommandée : fork minimal d'Exyte sans Giphy (`Views/Giphy/*`,
`giphyConfig`, entrée `.giphy` d'`InputView`), tag interne, remise à niveau documentée à chaque version d'Exyte.

## Architecture (fil Exyte par défaut, ancien fil retiré)

- `MessagingUI/MessagingConversationView.swift` : `ChatView` d'Exyte. `MessagingThreadModel` traduit chaque ligne en
  `ExyteChat.Message` ; `MessagingThreadRow` pose la bulle par défaut d'Exyte et les ajouts Drivy alignés sur elle.
- `MessagingUI/MessagingThreadProjection.swift` : projection pure. Identité d'affichage = envoi local après l'accusé ;
  identités uniques avant Exyte (son `fatalError` sur doublon devient inatteignable) ; ordre serveur conservé ; envoi
  en attente sous le dernier message reçu. Le regroupement par auteur est celui d'Exyte.
- `MessagingUI/MessagingComposerModel.swift` : seul propriétaire du brouillon. Texte, mentions et réponse retirés
  seulement après `workspace.enqueue` réussi. Un sondage n'emporte plus les mentions du brouillon texte.
- `MessagingUI/MessagingExyteTheme.swift` : `ChatTheme.drivy` (bulle émise `accentSoft` + encre, reçue `surfaceMuted`
  car la bulle Exyte n'a pas de filet) et `ChatLocalization.drivy`.
- `MessagingThreadViews.swift` : `MessagingBubble` et `MessagingBubbleShape` supprimées ; `MessagingPollCard` délègue
  la confirmation de clôture (`onClose`). `MessagingPendingBubble` et le réglage « Fil Exyte (essai) » supprimés.

Les builders d'Exyte sont capturés **une fois** par `UIList.Coordinator` : ils ne lisent que `MessagingThreadModel` et
le workspace, jamais une valeur figée. L'égalité de `Message` ignore `customData` : `triggerRedraw` reçoit une révision
déterministe (actions, signalement, épingle, citation, sondage).

## Ce qui vient d'Exyte, ce qui reste Drivy

| Élément | Rendu | Détail |
|---|---|---|
| Liste, bas du fil, clavier, pagination | Exyte | `UITableView` inversée ; anciens messages chargés en remontant, position gardée ; bouton « Charger les messages précédents » conservé en tête |
| Bulle, heure, regroupement par auteur | Exyte | texte déchiffré passé en `AttributedString` (mentions en gras), en mémoire seulement ; aperçus de lien coupés |
| États d'envoi | Exyte | icône d'envoi en cours, coche après l'accusé, double coche après un reçu de lecture, icône d'erreur qui réessaie le même envoi |
| Réactions | Exyte | une réaction Exyte par personne sur la bulle, la mienne en pointillés tant qu'elle n'est pas confirmée ; aperçu « qui a réagi » dans le menu |
| Avatars et auteur (général) | Exyte + Drivy | avatar Exyte rendu par `DrivyAvatar` (photo du chargeur autorisé, jamais d'URL) ; nom au premier message d'un groupe |
| Menu par appui long, palette | Exyte | actions selon les droits, revérifiées ; recherche d'emoji coupée ; aucune action marquée destructive |
| Glisser pour répondre | Exyte | action de liste avec l'icône Drivy, seulement si l'on peut écrire |
| Citation | Drivy, dessin Exyte | un appui mène au message cité (pages chargées au besoin) ; « Message indisponible » ou « supprimé » explicites |
| Sondage | Drivy | `MessagingPollCard` dans une bulle de même forme et mêmes couleurs |
| Supprimé, suppression en cours, illisible | Exyte | texte en italique atténué dans la bulle Exyte |
| Épingle, synchronisation, refus, envoi à reprendre | Drivy | ligne sous la bulle, mêmes identifiants qu'avant (`messaging.mutation.*`, `messaging.pending.retry`) |
| Signalement, lecture seule, composeur, mentions | Drivy | pied via `inputViewBuilder` |
| Suppression pour tous, clôture, votants | Drivy | présentés par la conversation, pas depuis une cellule |
| VoiceOver | Drivy | une bulle = un élément (auteur, texte, heure, réactions, état) et toutes les actions du menu, du glisser et des réactions |
| Lecture et notifications | Drivy | inchangé : bas du fil et scène active ; `showLastReadIndicator` non activé |

Perdu par rapport à l'ancien fil : l'appui direct sur une réaction pour la retirer (passer par le menu, la même réaction
la retire), « Lu par N » visible dans le général (reste dans l'étiquette VoiceOver) et la fenêtre de 5 minutes du
regroupement.

## Retours du porteur sur l'IPA `908aad3` (corrigés en `b4a2e9d`, IPA `f86d68d`)

- Répondre : glisser vers la **gauche**, en un geste. `MessagingReplySwipeGesture` (`UIPanGestureRecognizer` qui ne
  démarre que vers la gauche et à l'horizontale ; la liste attend son échec) remplace l'action de liste d'Exyte.
- Menu trop lent : `MessagingMenuPressGesture` (0,25 s au lieu des 0,5 s figés chez Exyte) ouvre le menu dès la
  reconnaissance, via `MessageBuilderParameters.showContextMenuClosure` ; animation 0,15 s ; réaction sans délai.
- Clavier ouvert : le composeur perd le focus, puis le menu s'ouvre 320 ms plus tard ; Exyte ignore le clavier pendant
  son menu (`ignoresSafeArea(.keyboard)`), ce qui faisait sauter le fil.
- Réaction retirée d'un appui : les pastilles d'Exyte n'ont pas d'action ; un appui dans leur bande (au-dessus de la
  bulle, hauteur calculée sur `MessageView` 3.3.0) retire ma réaction ou reprend la seule présente, sinon ouvre le menu.
- Non exécuté : tests Swift et UI (IPA seule, à la demande du porteur).

## Affichage des réponses (`08e9fdb`)

Retour du porteur : la citation en petite bulle séparée au-dessus de la réponse n'était pas convaincante. Une réponse
est maintenant une bulle Drivy (`MessagingReplyBubble`) aux mesures de `MessageView` d'Exyte 3.3.0 (rayon 20, marges
12/8, heure 10 pt, coches du thème, réactions en pastilles) qui porte en tête `MessagingQuoteBlock` : bandeau d'accent
de 4 pt, auteur (« Vous » pour soi), une ou deux lignes du message cité, « indisponible » ou « supprimé » en italique.
`MatchWidthStack` fait épouser à la bulle son contenu tout en étendant la citation à sa largeur. Les pastilles de
réaction de ces bulles sont des boutons (ajout ou retrait direct). La bande « Répondre à… » du composeur reprend le même
dessin. Messages sans citation : bulle Exyte inchangée. Non exécuté : tests, comparaison visuelle sur appareil.

## Points relus dans le code d'Exyte (lecture, non exécutés)

- `ChatView` crée toujours un `CLLocationManager` (via `LiveLocationBroadcaster`) sans demande d'autorisation ni mise à
  jour tant que rien n'est partagé. À confirmer sur appareil pendant une leçon (NOT_EXECUTED).
- Giphy n'est configuré que si `.giphy` figure dans les entrées et qu'une clé est fournie : ni l'un ni l'autre.
- Kingfisher ne sert qu'aux avatars par URL (aucune ici) ; LinkPresentation est coupé (`linkPreviewsEnabled(false)`).
- Les boutons du menu Exyte sont des `onTapGesture` de largeur fixe 208 pt ; VoiceOver passe par les actions de la bulle.
- L'alerte destructive d'Exyte affiche « Cancel » en dur : non utilisée.

## Résultats

- PASS : verrou et compilation, [run 40560998430](https://github.com/tomyrms/Drivy/actions/runs/40560998430) (`05bf364`).
- PASS : tests métier `messaging` avant la bascule, 72 tests dont 10 nouveaux,
  [run 40567843643](https://github.com/tomyrms/Drivy/actions/runs/40567843643) (`430e5d7`).
- PASS : IPA avec accès Messages, fil Exyte par défaut, aucun avertissement sur les fichiers de messagerie,
  [run 40574156686](https://github.com/tomyrms/Drivy/actions/runs/40574156686) (`908aad3`). **Toute IPA de ce
  chantier se lance avec `-f messaging_qualification=true`** : sans l'option, l'IPA n'a pas d'accès Messages.
- PASS : tests métier `messaging` après la bascule, 71 tests dont 9 de la projection et du composeur, zéro échec,
  [run 40575602130](https://github.com/tomyrms/Drivy/actions/runs/40575602130) (`908aad3`).
- NOT_EXECUTED : tests UI (voir ci-dessous), captures, VoiceOver, iPad, clavier matériel, fluidité et mémoire,
  capture réseau, GPS pendant une leçon.

## Reste à faire

1. Parcours sur appareil : envoi hors ligne puis en ligne, pagination, saut depuis la recherche, l'épingle et la
   citation, réaction depuis le menu, glisser pour répondre, suppression pour tous, signalement, lecture seule, général
   avec avatars et mentions, sondage (vote, votants, clôture), iPad en paysage, clavier ouvert, VoiceOver.
2. Adapter les tests UI écrits pour l'ancien fil : `MessagingFeatureCheckUITests`, `MessagingThreadUITests`,
   `MessagingLatencyUITests` (menu contextuel, palette, accusé `messaging.read`), puis les rejouer sur iPhone et iPad.
3. Trancher Giphy (fork minimal ou acceptation de la MPL) avant toute diffusion publique.

Phrase pour Codex : « Lis `docs/implementation/reprise-exyte-chat-182-20261027.md`, travaille sur
`claude/182-exyte-chat` et reprends au premier point de « Reste à faire ». »
