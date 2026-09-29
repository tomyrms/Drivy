# Revue des rendus terrain natifs — 29 septembre 2026

**58 fichiers PNG ont été ouverts et examinés individuellement avec `view_image`, sans montage ni retouche : 28 du lot initial d769e14, 14 du contrôle fb809bc et 16 du lot iPad orienté e720c45.** Les preuves restent attachées à leur commit ; elles ne valident pas les modifications ultérieures.

La revue initiale ci-dessous concerne exclusivement le commit **`d769e144252e1ef45c31104ab31e9e9f8abbc726`**. Elle ne valide pas à elle seule les pixels des corrections plus récentes de `ed56802` ni ceux du HEAD courant.

Provenance : [run GitHub Actions 36578702250](https://github.com/tomyrms/Drivy/actions/runs/36578702250), terminé avec succès ; artefact `Drivy-native-results-d769e144252e1ef45c31104ab31e9e9f8abbc726`, identifiant `11038969334`. Téléchargement local : `artifacts/review-20260929/field-visual-d769/`. L’[inventaire vérifié](proofs/ui-field-renders-d769-20260929.json) contient les 28 noms, dimensions et empreintes SHA256. Originaux iPhone : 1206 × 2622 px ; iPad : 2064 × 2752 px, tous en portrait. L’outil d’affichage adapte leur résolution à la conversation ; les fichiers originaux sont conservés intacts.

Environnement déclaré par l’artefact : Xcode 26.6, build 17F113 ; Swift 6.3.3. Le script `scripts/ios/capture-screens.sh` capture le compositeur du simulateur avec `simctl io screenshot`. Le modèle précis du simulateur n’est pas déduit de la seule résolution. La campagne est visuelle : l’étape de tests natifs est volontairement sautée pour ce run ; sa réussite ne remplace pas une campagne de tests.

## Langage visuel et portée

- Surface examinée : préparation et accord GPS, signalement, liste d’observations, trajet actif, attente de position et replay de l’application SwiftUI.
- Références : `AGENTS.md`, direction Cartographie native acceptée dans `COMMENCER_ICI.md`, `DESIGN/02-composants.md` (DS17/18, texte et symbole pour les états, variantes de capture et surfaces), décisions d’implémentation du 28 septembre.
- Décisions suivies : GPS facultatif, pas de position présentée comme réelle sans mesure, commandes lisibles au-dessus de la carte, carte et panneaux côte à côte sur iPad, un choix de thème puis un statut explicite.
- Propriétaires réellement traversés : `SchoolFieldVisualReview` → `SchoolRecordingChoiceView`, `SchoolLiveObservationSheet`, `SchoolCapturePreparationView`, `SchoolObservationView`, `SchoolCaptureLiveView` ; fixture replay → `SchoolCaptureReplayView`. Les panneaux et commandes communs viennent de `DrivyTheme`, `DrivyComponents+Seance` et des styles partagés.
- Exceptions documentées : aucune exception utilisée pour écarter un défaut. Les personnes et données de trajet sont explicitement fictives dans ces contrôles ; le fond marin du replay correspond aux coordonnées synthétiques de sa fixture, pas à une panne cartographique prouvée.

Guides appliqués : `ui-skills-root`, `improve-ui` et les critères de disposition de `better-layout` déjà lus. Le rapport suit le chemin de livraison demandé dans `docs/implementation/`. Aucun code produit n’a été modifié pendant cette revue des PNG.

## Constats étayés

| # | Problème | Preuve | Correction déterminée | Portée | Confiance |
| --- | --- | --- | --- | --- | --- |
| 1 | **MEDIUM — historique** : l’attente GPS de l’iPad demande de placer « l’iPhone » près d’une vitre. | Texte visible dans `iPad-live-waiting-light-synthetic.png` et `iPad-live-waiting-dark-synthetic.png`. Contradiction directe avec l’appareil de la vue. À `d769e14`, `SchoolCaptureLocationModels.swift:146` fournit ce message, repris par `SchoolCaptureLiveView.placeholderMessage` et `DrivyMapPlaceholder`. | Employer « l’appareil », déjà présent dans la source `ed56802`. Contrôler les nouveaux PNG iPad pour fermer le point visuel. | Texte de l’état sans position sur iPad, deux images. | Élevée : texte lu dans les PNG, origine retrouvée. |
| 2 | **MEDIUM — historique** : le rail restant de la chronologie du replay est très atténué, particulièrement en sombre. | Visible dans les quatre `*-replay-*-synthetic.png`. `DrivyReplayScrubber.track` à `d769e14`, `UI/DrivyComponents+Seance.swift:515`, applique `controlBorder.opacity(0.45)` sur le panneau `surface`. La [mesure déclarée](proofs/ui-shared-contrast-20260929.json) donne 1,6747:1 clair et 1,8963:1 sombre, sous le seuil graphique 3:1 ; ces nombres proviennent des tokens, pas d’une estimation des pixels. La référence de composants réserve `controlBorder` à l’identification des contrôles. | Utiliser `controlBorder` opaque, correction déjà présente dans `ed56802` ; la paire déclarée devient 3,7003:1 clair et 4,1918:1 sombre. Refaire la vérification visuelle sur ce commit. | Chronologie replay, iPhone et iPad, deux thèmes. | Élevée pour la déclaration et sa présence dans le rendu ; aucune certification globale de contraste. |

## Priorité

Revoir d’abord le rail corrigé du replay sur les nouvelles captures : ce contrôle permet de retrouver le passage d’une observation et le défaut touche les quatre variantes. Les deux constats ci-dessus ont déjà une correction de source ; ils ne justifient pas de réappliquer une modification sur le code courant.

## Inventaire des images réellement examinées

Chaque nom de la table est relatif au répertoire de l’artefact indiqué plus haut. « Examiné » signifie que le PNG a été ouvert, pas seulement compté sur disque.

| Surface / état de fixture | iPhone clair | iPhone sombre | iPad clair | iPad sombre |
| --- | --- | --- | --- | --- |
| Accord GPS inconnu | `iPhone-gps-choice-light-synthetic.png` — examiné | `iPhone-gps-choice-dark-synthetic.png` — examiné | `iPad-gps-choice-light-synthetic.png` — examiné | `iPad-gps-choice-dark-synthetic.png` — examiné |
| Signalement, choix du thème | `iPhone-signal-light-synthetic.png` — examiné | `iPhone-signal-dark-synthetic.png` — examiné | `iPad-signal-light-synthetic.png` — examiné | `iPad-signal-dark-synthetic.png` — examiné |
| Préparation bloquée sur l’accord | `iPhone-capture-preparation-light-synthetic.png` — examiné | `iPhone-capture-preparation-dark-synthetic.png` — examiné | `iPad-capture-preparation-light-synthetic.png` — examiné | `iPad-capture-preparation-dark-synthetic.png` — examiné |
| Trajet actif, trois positions fictives | `iPhone-live-light-synthetic.png` — examiné | `iPhone-live-dark-synthetic.png` — examiné | `iPad-live-light-synthetic.png` — examiné | `iPad-live-dark-synthetic.png` — examiné |
| Trajet sans position | `iPhone-live-waiting-light-synthetic.png` — examiné | `iPhone-live-waiting-dark-synthetic.png` — examiné | `iPad-live-waiting-light-synthetic.png` — examiné | `iPad-live-waiting-dark-synthetic.png` — examiné |
| Observations, liste vide | `iPhone-observations-light-synthetic.png` — examiné | `iPhone-observations-dark-synthetic.png` — examiné | `iPad-observations-light-synthetic.png` — examiné | `iPad-observations-dark-synthetic.png` — examiné |
| Replay avec interruption et trois repères | `iPhone-replay-light-synthetic.png` — examiné | `iPhone-replay-dark-synthetic.png` — examiné | `iPad-replay-light-synthetic.png` — examiné | `iPad-replay-dark-synthetic.png` — examiné |

Total : **7 surfaces × 2 appareils × 2 thèmes = 28 images distinctes examinées**.

## Ce que montrent les rendus

L’identité de l’élève et les commandes principales ne sont pas tronquées dans les états capturés. Les choix Avec GPS/Sans GPS sont distincts ; les liens de notice restent sous ces choix. La grille montre notamment Priorité à droite, Signalisation, Vitesse et Anticipation. Sur iPhone, Terminer la leçon passe sur deux lignes et reste entièrement visible ; sur iPad, le panneau latéral laisse la carte disponible. Sans position, aucune carte ou trace n’est substituée au message d’attente. Dans le replay, la lacune est visible entre les deux fragments ainsi que sur la chronologie pointillée ; la liste iPad distingue les trois observations.

Les anciens raccourcis du replay iPhone affichent le statut et l’heure. Cette capture ne prouve ni ne réfute le rendu de l’ajout ultérieur du libellé de thème ; la référence DS18 prévoit aussi le détail du repère sélectionné, état absent ici. Aucun débordement du transport replay n’est visible à la largeur effectivement capturée : le risque des petites largeurs relevé dans la revue de source ne doit pas être présenté comme reproduit par ces PNG.

## Limites explicites

- Chaque surface ne présente qu’un état fixe : aucun tap, glisser, enregistrement durable, fermeture automatique ou transition n’a été exercé par l’ouverture des PNG.
- Le choix du statut après un thème, les erreurs d’enregistrement, la liste d’observations remplie, la sélection d’un repère et les reprises réseau ne sont pas couverts par ces images.
- Tailles Dynamic Type extrêmes, paysage, Split View étroit, plus petit iPhone, clavier matériel, VoiceOver, mouvement réduit et transparence réduite : **non vérifiés** par cette campagne.
- Les opacités pendant l’appui, l’ajustement VoiceOver du replay et la variante `ViewThatFits` récemment ajoutés ne sont pas vérifiables sur ces images statiques antérieures.
- Les fixtures restent isolées du homelab ; ces captures ne qualifient ni droits réels ni GPS, précision, autonomie ou transfert en conditions physiques.
- Les images du commit `ed56802` et des suivants devront porter leur propre inventaire. La réussite du run `d769e14` ne leur est pas attribuée.

## Contrôle suivant : fb809bc, 14 images claires

**14 PNG sur 14 ont été ouverts individuellement.** Provenance : [run 36581808488](https://github.com/tomyrms/Drivy/actions/runs/36581808488), **success**, commit exact `fb809bc009c6f8b5dfd366916e57955d883d58b0`, artefact `Drivy-native-results-fb809bc009c6f8b5dfd366916e57955d883d58b0` (`11041133636`). Originaux dans `artifacts/review-20260929/field-visual-fb809bc/` ; [inventaire avec dimensions et SHA256](proofs/ui-field-renders-fb809bc-20260929.json). iPhone 1206 × 2622, iPad 2064 × 2752, tous en portrait et apparence claire. Cette campagne visuelle ne lance pas les tests natifs.

| Surface | iPhone clair | iPad clair |
| --- | --- | --- |
| Accord GPS | `iPhone-gps-choice-light-synthetic.png` — examiné | `iPad-gps-choice-light-synthetic.png` — examiné |
| Signalement, ancienne grille | `iPhone-signal-light-synthetic.png` — examiné | `iPad-signal-light-synthetic.png` — examiné |
| Préparation | `iPhone-capture-preparation-light-synthetic.png` — examiné | `iPad-capture-preparation-light-synthetic.png` — examiné |
| Trajet actif | `iPhone-live-light-synthetic.png` — examiné | `iPad-live-light-synthetic.png` — examiné |
| Attente de position | `iPhone-live-waiting-light-synthetic.png` — examiné | `iPad-live-waiting-light-synthetic.png` — examiné |
| Observations vides | `iPhone-observations-light-synthetic.png` — examiné | `iPad-observations-light-synthetic.png` — examiné |
| Replay | `iPhone-replay-light-synthetic.png` — examiné | `iPad-replay-light-synthetic.png` — examiné |

Les trois changements ciblés sont **visibles** :

- L’attente GPS emploie « l’appareil » sur iPad comme sur iPhone. Le premier constat historique est fermé pour ces deux rendus clairs.
- Le rail restant du replay est maintenant nettement visible et continu hors de la lacune pointillée, sur les deux appareils. Le second constat historique est fermé pour le thème clair ; aucune nouvelle mesure de pixels n’est annoncée et le sombre n’appartient pas à ce lot.
- Le premier raccourci du replay iPhone porte son heure **et son libellé de thème**, « Contrôle latéral · exemple ». Le raccourci suivant déborde partiellement dans le défilement horizontal, montrant qu’il existe une suite ; aucun libellé n’est ellipsé dans le premier. Sur iPad, la liste nomme les trois repères et le contrôle de vitesse se place sur une seconde ligne du panneau de lecture, sans chevauchement visible.

Aucun nouveau défaut de disposition étayé dans ces 14 états. Le signalement reste ici l’ancienne grille, antérieure à l’emblème et au panneau compact de `e720c45` : ce lot ne peut pas valider leur rendu. Il ne comporte pas non plus l’état d’appréciation après le choix d’un thème. Les tailles de texte sont ordinaires ; aucune conclusion AX3, paysage, iPad 11 pouces ou qualification physique ne lui est attribuée.

## Contrôle orienté : e720c45, 16 images iPad claires

**16 PNG sur 16 ont été ouverts individuellement**, huit surfaces en portrait et paysage. Provenance : [run 36584370257](https://github.com/tomyrms/Drivy/actions/runs/36584370257), commit exact `e720c4579d8e12c6d0aedb7d0ada6f2f529f30a0`, artefact `Drivy-native-results-e720c4579d8e12c6d0aedb7d0ada6f2f529f30a0` (`11041862887`). Le résumé XCTest déclare **1 test réussi, 0 échec, 0 ignoré** ; `VisualOrientationTests/testRequestedScreensAtRealOrientations` a exécuté les prises de vues pendant 444,461 secondes. Le run global est cependant **failure** : après l’export des 16 attachments, l’ancien contrôle d’orientation comparait seulement les dimensions stockées et a rejeté le premier paysage.

Le simulateur déclaré est **iPad Pro 13-inch (M5), iOS 26.4.1 (23E254a), arm64**. Tous les fichiers stockent 2064 × 2752 pixels. Les portraits ont une orientation EXIF 1 ; les paysages ont une orientation EXIF 8 et s’affichent donc en **2752 × 2064**. `view_image` présente bien ces derniers en paysage, avec le texte horizontal. Les copies aux noms stables dans `artifacts/review-20260929/field-visual-e720/originals-named/` sont identiques aux attachments octet par octet : aucune rotation ni réencodage n’a été effectué. L’[inventaire](proofs/ui-field-renders-e720-20260929.json) distingue dimensions stockées, dimensions affichées et orientation EXIF, et conserve chemins et SHA256.

| Surface / état réel capturé | Portrait | Paysage |
| --- | --- | --- |
| Accord GPS | `iPad-gps-choice-light-portrait-synthetic` — examiné | `iPad-gps-choice-light-landscape-synthetic` — examiné |
| Préparation | `iPad-capture-preparation-light-portrait-synthetic` — examiné | `iPad-capture-preparation-light-landscape-synthetic` — examiné |
| Trajet actif | `iPad-live-light-portrait-synthetic` — examiné | `iPad-live-light-landscape-synthetic` — examiné |
| Attente de position | `iPad-live-waiting-light-portrait-synthetic` — examiné | `iPad-live-waiting-light-landscape-synthetic` — examiné |
| Signalement depuis le bouton de la carte | `iPad-live-signal-light-portrait-synthetic` — examiné | `iPad-live-signal-light-landscape-synthetic` — examiné |
| Appréciation après « Priorité à droite » | `iPad-signal-status-light-portrait-synthetic` — examiné | `iPad-signal-status-light-landscape-synthetic` — examiné |
| Observations vides | `iPad-observations-light-portrait-synthetic` — examiné | `iPad-observations-light-landscape-synthetic` — examiné |
| Replay | `iPad-replay-light-portrait-synthetic` — examiné | `iPad-replay-light-landscape-synthetic` — examiné |

Le panneau de signalement est maintenant **le vrai popover ancré au bouton Signaler**, au-dessus de la carte, dans les deux orientations. Ses sept emblèmes se distinguent, les libellés restent complets et le bouton « Marquer un moment » demeure visible. Après le choix « Priorité à droite », l’emblème sélectionné, le retour, la fermeture et les trois appréciations « À retravailler », « Attention », « Point positif » tiennent dans le panneau, sans chevauchement visible. Le test a réellement touché le déclencheur puis le thème ; il n’a pas enregistré d’appréciation et ces images ne prouvent pas la persistance ni le retour après enregistrement.

Les commandes du trajet restent à gauche de la carte dans les deux orientations. L’attente emploie « l’appareil » et ne présente aucune trace inventée. Le replay conserve un rail opaque, la lacune pointillée, les trois libellés d’observation et le contrôle de vitesse sur une seconde ligne. L’accord GPS et la préparation restent lisibles, sans coupe visible des commandes. La liste d’observations testée demeure vide. **Aucun nouveau défaut de disposition étayé dans ces 16 états.**

Ce lot utilise la taille de texte ordinaire et l’apparence claire, sur Pro 13 uniquement. Il ne valide ni l’Air 11, ni son seuil de navigation compact, ni AX3, ni le sombre du nouveau panneau. La barre système affiche encore une date anglaise sur ce commit antérieur à l’ajustement des localisations ; le contenu de l’application capturé est français. Une image fixe ne qualifie pas l’animation, VoiceOver, le GPS physique ou l’autonomie. La correction ultérieure de l’export EXIF est vérifiée séparément ; elle ne transforme pas rétroactivement ce run en succès.
