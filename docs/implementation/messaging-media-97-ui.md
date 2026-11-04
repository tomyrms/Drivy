# Médias #97 — parcours natif U97

Travail en cours, base `7cb065a2a43b532cb800b81b2b907c7cc9e90499`. Aucun raccordement au fil avant réception du checkpoint M97. Aucun changement de Workspace, de contrat, de projet, de workflow ni d'activation.

## Préflight réellement effectué

- `orca orchestration worker-show --dispatch ctx_d7b2b1d79825 --json --full` confirme `launch.effective.model = gpt-6-astra`, `effort = high`.
- Instructions lues : AGENTS.md, COMMENCER_ICI.md, DESIGN.md, décisions messagerie des 23 et 25 octobre, contrat partagé M97 du 5 novembre dans bristleworm, arbitrages du coordinateur dans sealion.
- Superpowers chargés : `C:/Users/jtoma/.codex/skills/test-driven-development/SKILL.md`, référence `writing-good-tests.md`, `C:/Users/jtoma/.codex/skills/verification-before-completion/SKILL.md`. Fonctionnalité nouvelle, sans bug reproduit : systematic-debugging non applicable à ce stade.
- UI chargée : `C:/Users/jtoma/.codex/skills/impeccable/SKILL.md` et références `operate.md`, `craft-floor.md` ; `C:/Users/jtoma/.codex/skills/uncodixfy/SKILL.md` ; skills `swiftui-ui-patterns` (référence async-state) et `swift-native-components` (référence calendars-media) dans le même répertoire de skills. Aucun sous-agent.
- `impeccable.cmd context --target apps/ios/Drivy/MessagingUI/MessagingConversationView.swift` exécuté : DESIGN.md lu intégralement ; PRODUCT.md absent, aucun nouveau fichier de design créé pour cette extension circonscrite.
- Codebase Memory indexé par chemin absolu de CE worktree : projet `C-Users-jtoma-orca-workspaces-Drivy-issues-medias-interface-97`, 53 137 nœuds et 202 982 arêtes. Index best effort, 88 parsings partiels et quatre inutilisables hors fichiers UI concernés ; ne constitue pas une preuve de compilation.
- `search_graph` : MessagingPreparedMedia, MessagingThreadModel, MessagingConversationView ; `trace_path` entrant de MessagingPreparedMedia : préparateurs image et PDF. Sources de préparation, fil, thème et tests existants relues directement.

## Composants indépendants préparés

Import en lecture seule et par blocs de 64 Kio : contrôle de taille avant lecture lorsque disponible, puis plafond effectif 4 Mio et un octet de détection même si la taille fournisseur est absente/fausse. Accès document security-scoped et coordonné, lecture sur tâche détachée avec propagation d'annulation. Représentations Photos JPEG/PNG par fichier fournisseur dans la durée du callback, sans temporaire créé par l'application ni conversion d'image dans ce code. Le runtime reste responsable du contrôle du contenu et de sa préparation.

Aperçu : données validées en mémoire, image native, PDFDocument(data:) dans PDFView avec interception des actions et liens. Le nom et le poids informent la décision ; fermeture native, couleurs sémantiques Drivy, texte Dynamic Type. Les dimensions web, polices de présentation, effets de survol et interdictions de bleu d'Uncodixfy ne remplacent pas le design natif existant ; pas de nouvelle palette, carte décorative, dégradé, section d'aide ou animation. Le détecteur web d'Impeccable ne qualifie pas SwiftUI.

Sources Apple consultées : [FileRepresentation](https://developer.apple.com/documentation/coretransferable/filerepresentation/init(importedcontenttype:shouldattempttoopeninplace:importing:)), [PhotosPicker](https://developer.apple.com/documentation/swiftui/view/photospicker(ispresented:selection:matching:preferreditemencoding:photolibrary:)), [PDFDocument](https://developer.apple.com/documentation/pdfkit/pdfdocument/init(data:)), [PDFView.perform](https://developer.apple.com/documentation/pdfkit/pdfview/perform(_:)), [PDFViewDelegate](https://developer.apple.com/documentation/pdfkit/pdfviewdelegate), [accès security-scoped](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()). Les pages markdown FileRepresentation et perform ont aussi été lues par HTTP après échec du lecteur web sur leur type MIME.

## Vérifications et limites actuelles

Sept tests d'import écrits avant l'implémentation : original inchangé, vide, borne exacte 4 Mio, dépassement d'un octet, annulation avant lecture et entre blocs, URL non locale. `Get-Command swift,xcodebuild -ErrorAction SilentlyContinue` : aucun outil disponible. RED/GREEN, compilation Swift, tests UI, captures iPhone/iPad, clair/sombre, grandes tailles, clavier, contrastes et focus **NON EXÉCUTÉS**. Aucun résultat serveur ni VoiceOver physique déduit de ces préparatifs.

`git diff --check` : sortie vide ; les nouveaux fichiers sont encore non suivis à ce stade. Aucun commit de livraison et aucun succès produit revendiqué. À compléter : modèle injecté, raccordement au vrai runtime, sélection Photos/documents dans le composeur existant, reçus/reprise, ouverture des messages reçus et invalidation, tests du modèle et scénario UI synthétique.

Point d'injection : `MessagingThreadFixtureView.swift` absent ; extension autorisée par le coordinateur (réponse msg_d109fececc1e) à `MessagingQualificationFixture.swift` et au nouveau `MessagingMediaQualificationFixture.swift`, exclusivement sous DEBUG/simulateur, via `-messaging-ui-fixture` et `-messaging-ui-media`. Générateurs PNG/PDF en mémoire préparés ; runtime synthétique et branchement encore en attente du checkpoint contrat.

Checkpoint indépendant sauvegardé dans `b778eddd` ; socle M97 `40110735998fc8614737bfc98326baf7a380aaaf` fusionné localement sans conflit. Ce socle n'est pas le checkpoint de contrat. Quatre tests UI préparés avant raccordement (sélection/aperçu/retrait photo, PDF sombre/grand texte, reprise explicite sans légende, préparation/clavier), tous NON EXÉCUTÉS et dépendants du raccordement à venir. Aucun workflow modifié.
