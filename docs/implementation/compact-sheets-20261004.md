# Feuilles ajustées au contenu — 4 octobre 2026

> Historique de build99 : le porteur a ensuite signalé des hauteurs incorrectes et des saccades au glissement. Le composant de mesure décrit ci-dessous est retiré ; [la décision active emploie des feuilles natives stables](stable-sheets-20261004.md). La compilation réussie ne qualifiait pas ces interactions.

## Retour et décision

Le porteur constate que Démarrer une leçon, le choix de l’élève, la préparation GPS, Signaler et plusieurs réglages occupent tout l’écran malgré leur contenu court. Il demande une proposition plus compacte, ainsi que la prise en compte de l’orientation du téléphone sur la carte active.

Les tâches courtes utilisent une feuille native ajustée à leur contenu ; les fiches complètes gardent leur navigation actuelle. Le choix de l’élève et de la formation devient explicitement un menu natif dans le panneau de démarrage. Les champs et l’action restent ensemble, sans grande zone vide entre eux.

## Composant partagé

`UI/DrivyComponents+Sheet.swift` contient `DrivySheetScrollView` et `.drivyFittedSheet()`. Le premier mesure la hauteur naturelle d’un contenu non lazy. Le second ajoute la différence réellement mesurée entre le conteneur et la zone défilante, qui représente la barre de navigation ou l’en-tête. Aucune hauteur n’est déduite d’un nombre de lignes ou d’un modèle de téléphone.

La hauteur compacte est bornée entre 160 et 640 pt (amorçage 320 pt pendant la première mesure). La fenêtre native borne encore les dimensions disponibles. Un cran grand format reste accessible ; les tailles d’accessibilité l’emploient. Le contenu défile quand il dépasse la place disponible et conserve l’évitement natif du clavier. Sur iPad, la présentation native de formulaire est ajustée verticalement. Ces bornes sont des choix d’implémentation à qualifier, pas des mesures physiques validées.

Surfaces migrées :
- Démarrer une leçon : élève, formation, lieu et action dans le même contenu ; menus natifs et adaptation verticale des champs en grand texte.
- Préparation du GPS, accord GPS, reprise de diagnostic et relecture du départ : hauteur suivant l’état réel, erreurs et détails extensibles conservés.
- Préférences de leçon : feuille depuis Profil, deux choix et Enregistrer ; fermeture protégée en présence de modifications ou d’une opération en cours.
- Période du dossier et changement d’école : feuilles courtes, listes longues défilantes.
- Signaler : rangées de deux thèmes, pictogramme à gauche et libellé à droite ; une colonne dès xxLarge. Après le choix du thème, le contenu se réduit aux trois appréciations. Plus de hauteur maximale imposée ni de hauteur fixe au popover iPad.

Le marqueur temporel, le retour aux thèmes, les erreurs, les libellés accessibles, l’instant figé et la confirmation après écriture durable sont conservés. Aucun changement serveur, contrat, référentiel ou partage. La boussole ne modifie pas les mesures du trajet : [décision et limites](live-device-heading-20261004.md).

## Références et relecture

AGENTS et COMMENCER_ICI lus. R46, GPS/replay et AP161–164, scénarios T423–T429 pour le panneau ; règles de planification, consentement et périmètre des accès conservées dans les lots. UI Skills : catégorie swiftui inspectée ; SwiftUI UI Patterns (sheets), Impeccable (layout, ios, craft-floor) appliqués. Le contexte Impeccable de la session reste celui de DESIGN.md, mode Operate.

API vérifiées dans les sources Apple : [hauteurs de feuille](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:selection:)), [dimensionnement](https://developer.apple.com/documentation/swiftui/view/presentationsizing(_:)), [mesure de géométrie](https://developer.apple.com/documentation/swiftui/view/ongeometrychange(for:of:action:)).

Deux relectures indépendantes du composant partagé et du panneau Signaler : aucun P0–P2 confirmé en source. Les propriétaires de chaque lot ont relu leurs fichiers entiers. `git diff --check` passe ; détecteur Impeccable layout : `[]` sur les fichiers ciblés. Ce détecteur principalement HTML/CSS ne valide pas SwiftUI.

## Qualification et livraison

Le porteur a demandé de privilégier l’IPA et de ne pas attendre les longues campagnes de tests/captures. La compilation Release Apple de l’IPA [37212556376](https://github.com/tomyrms/Drivy/actions/runs/37212556376) a réussi sur `a2dc49c246a28e5951620fa38fa9934ec4a18b69` : version 0.7.0/build99, non signée, téléchargée et empreinte vérifiée. Aucune campagne native de tests ou captures lancée. Les vérifications générales habituelles du dépôt se déclenchent automatiquement au push. Les cinq tests purs ajoutés sur le cap ne sont pas déclarés exécutés. Pas de capture nouvelle ni de rendu simulé présenté comme une capture native.

À vérifier sur appareil : hauteur réelle après changement d’état, clavier, popover iPad, grands textes, VoiceOver, rotation de la carte à l’arrêt, passage nord/359°, support de téléphone et perturbations magnétiques. Aucune performance, batterie ou qualité GPS physique revendiquée. Aucun déploiement homelab.

[Preuve de livraison](proofs/compact-sheets-20261004.json). IPA à signer et installer par le porteur avec iLoader.
