# Leçon terminée en trois onglets, « Mon souhait » et Formation d’un permis — 12 octobre 2026

Demande du porteur : réorganiser la fiche d’une leçon terminée, corriger deux défauts de la prochaine leçon côté
élève, remonter et resserrer la formation d’un permis dans le profil de l’élève.

## 1. Leçon terminée : Bilan, Compétences, Trajet & notes

`SchoolLessonSummaryTabs` (nouveau) remplace la page unique du récapitulatif quand la leçon est `COMPLETED`.
Une leçon annulée ou manquée garde sa page (il n’y reste que les objectifs prévus et le prix).

- **En-tête** : la carte de l’élève (`SchoolLessonHeaderView`) et les messages restent en haut.
- **Sélecteur** : segmenté système (même contrôle que les sections du dossier), teinte `drivyControlTint()`,
  épinglé sous la barre de navigation pendant la lecture. Au-delà de la taille de texte `xLarge`, un menu qui
  nomme l’onglet ouvert (les trois intitulés ne tiennent plus). VoiceOver lit « Trajet et observations ».
- **Transition** : fondu entre onglets, les deux pages superposées (`ZStack`) pour que la page ne s’allonge jamais
  de leur somme ; la zone d’onglet garde au moins la hauteur de l’écran, donc un onglet court ne fait pas
  redescendre le sélecteur. Lu plus bas que le sélecteur, changer d’onglet ramène au début de l’onglet, sélecteur
  en place.
- **Intitulé du troisième onglet** : « Trajet & notes ». « Observations » cachait le trajet ; « Trajet &
  observations » ne tient pas à trois segments sur un iPhone de 375 pt.

### Bilan
Rangée de chiffres sans carte (`DrivyFigureStrip`, nouveau composant partagé) : permis (icône + code), durée
(réelle si l’école connaît départ et fin, sinon « Durée prévue »), nombre de compétences évaluées et
d’observations — ces deux chiffres ouvrent leur onglet. Puis le bilan (Prochaine étape, Travail réalisé,
À retenir), la mention « Non enregistré » / « Pour moi » au besoin, les objectifs prévus ouverts (la note privée
du moniteur, cadenas, n’est rendue qu’à lui), et le prix sous un filet quand le rôle y a droit.

### Compétences
Une phrase de répartition (« 2 en autonomie · 1 avec accompagnement »), puis toutes les compétences évaluées
(plus de repli à cinq dans un onglet qui leur est dédié) : nom, niveau en mots, situation notée, parcours en
trois étapes commun à la Progression. **Pas de note sur 10** : l’école évalue en trois niveaux
(`DISCOVERING`/`GUIDED`/`INDEPENDENT`) ; aucune note n’est inventée. Sans compétence évaluée : état vide ;
bilan pas encore écrit : la même phrase que dans Bilan.

### Trajet & notes
La carte existante (`SchoolLessonTripMap`, replay sur la carte, liens de replay sans tracé, états du trajet,
« Pour moi ») puis les observations par appréciation : Points positifs, Points d’attention (Attention et
À retravailler), Autres observations (repères, notes). Chaque groupe garde l’ordre du trajet, l’heure et
« Sur le trajet ». Toucher une observation placée grossit son épingle (comportement existant) et, si la carte
est sortie de l’écran, y ramène. Rien n’a changé dans le GPS, le tracé ou les données. Ni trajet ni observation :
état vide.

### Rôles
Une seule vue : ce que chacun lit vient de `SchoolLessonSummaryContent`, inchangé (le moniteur relit son
brouillon, l’élève la révision publiée ; la note privée et « Pour moi » ne sont qu’au moniteur ; l’équipe ne lit
pas les observations d’un collègue). Les actions (Rédiger / Reprendre / Modifier le bilan, Déplacer, Annuler,
Élève absent) restent dans la barre et le menu de la fiche, sous les mêmes règles.

## 2. Prochaine leçon de l’élève

### Clavier impossible à fermer
Cause : « Mon souhait » est un champ multiligne (Retour va à la ligne), dans un formulaire sans
`scrollDismissesKeyboard`, souvent trop court pour défiler, et sans geste de fermeture. Correction : `@FocusState`
sur le souhait, les objectifs et la note du moniteur ; bouton « Terminé » au-dessus du clavier ; défilement
interactif ; toucher hors d’un champ (`drivyDismissesKeyboardOnOutsideTap`, geste de fenêtre qui n’annule aucun
autre toucher et ignore ceux qui tombent dans un champ). La saisie reste, rien n’est envoyé à la fermeture ;
« Enregistrer le souhait » ferme le clavier puis envoie. Quitter la fiche avec un souhait modifié demande
toujours confirmation (règle existante).

### Squelette sans fin sous « Mon souhait »
Le squelette est l’**accord GPS de l’élève** pour cette leçon (`SchoolOwnRecordingChoice`), utile : sans lui,
l’élève ne peut pas accepter ou refuser l’enregistrement de son trajet avant la leçon. Ni l’API
(`GET …/recording-notice`, `GET …/learners/:id/recording-choice`, accessibles à l’élève via `learnerAccess`),
ni le décodage ne sont en cause : une panne aboutit déjà à « L’accord GPS n’a pas pu être lu » avec « Réessayer ».

Cause : la tâche de lecture était posée sur un `Group`. Dans une ligne de formulaire, le modificateur suit chaque
branche du `Group` : quand l’attente cédait la place au choix, la tâche de l’attente était annulée — lecture en
cours comprise — et la nouvelle tâche ne relançait rien parce que `isLoading` était encore vrai. La lecture
annulée se terminait sans notice, sans erreur, sans chargement : l’état « en attente » sans fin.
Correction : conteneur stable (`VStack`) ; et toute lecture interrompue (`interruptedRead`) est relancée aussitôt,
donc l’attente ne dure que le temps d’une lecture et se termine en choix, en panne avec « Réessayer », ou en accès
retiré.

## 3. Profil de l’élève → un permis

`SchoolLearnerPermitDetail` : la **Formation** passe au-dessus de Leçons et Progression, en un seul bloc dense.

Données réellement disponibles : état et dates de la formation (`SchoolTraining`), leçons de la formation (toutes
pages lues), progression (dernier niveau publié par compétence + compétences jamais évaluées), affectations des
moniteurs. Il n’existe **aucune donnée d’exigences ou d’étapes obligatoires** par formation dans l’API actuelle :
rien de tel n’est affiché.

- En-tête : icône du permis, « Formation en cours / en pause / terminée / annulée », « Depuis le … » ou
  « Jusqu’au … ». Le nom du permis est déjà le titre de la page.
- Compétences : barre fine en trois tons et légende — acquises (en autonomie), en cours (découverte ou
  accompagnement), à voir (jamais évaluées ; un niveau inconnu n’est pas compté acquis). Des décomptes du dernier
  niveau publié, ni score ni pourcentage. Absente tant que la progression n’est pas lue.
- Chiffres (`DrivyFigureStrip`) : leçons terminées, temps de conduite réel (absent sans horaire réel), dernière
  leçon, prochaine leçon planifiée. Squelette tant que toutes les leçons ne sont pas lues.
- Moniteur(s) affecté(s).
- Leçons et Progression en dessous, sans répéter les chiffres de la formation. Le filtre par permis est
  inchangé : la page reste construite sur la formation choisie.

## Fichiers

- `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonSummaryTabs.swift` (nouveau)
- `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonSummaryView.swift`
- `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportView.swift`
- `apps/ios/Drivy/SchoolCaptureUI/SchoolOwnRecordingChoice.swift`
- `apps/ios/Drivy/SchoolUI/SchoolLearnerPermitDetail.swift`
- `apps/ios/Drivy/UI/DrivyFigureStrip.swift`, `apps/ios/Drivy/UI/DrivyKeyboardDismissal.swift` (nouveaux)
- Tests : `DrivyTests/SchoolLessonSummaryTabsTests.swift` (nouveau), `DrivyTests/SchoolLearnerProfileTests.swift`
- Captures : écrans `lesson-competencies`, `lesson-route`, `learner-lesson`, `learner-lesson-planned`,
  `learner-permit` dans le banc de rendu et `scripts/ios/capture-screens.sh`.

Aucun changement d’API, de base ou de règle métier.

## Vérification

**Exécuté** sur `6acfc0f` : IPA d’essai compilée ([run 38239548637](https://github.com/tomyrms/Drivy/actions/runs/38239548637)) ;
**497 tests Swift réussis** (43 suites), dont les 7 nouveaux ([run 38239551963](https://github.com/tomyrms/Drivy/actions/runs/38239551963)).
Captures iPhone clair et sombre sur `79d694a` ([run 38239694126](https://github.com/tomyrms/Drivy/actions/runs/38239694126)) :
leçon terminée (Bilan, Compétences, Trajet & notes), leçon terminée vue par l’élève, prochaine leçon de l’élève
(l’accord GPS s’affiche sous « Mon souhait », sans squelette), Formation d’un permis. Extraits dans
`assets/lecon-onglets-20261012/`. Corrigé après relecture : dates longues de la rangée de chiffres du permis
(« 21 septembre 2026 » faisait passer la rangée sur deux colonnes) → « 21 sept. ».

**Non exécuté / reste à qualifier** : clavier (fermeture au toucher, « Terminé ») et passage animé entre onglets —
aucune capture ne montre une interaction ; appareil réel, VoiceOver, grand texte (menu à la place du segmenté),
iPad. Le rendu élève du banc affiche « Les observations de la leçon n’ont pas pu être chargées » : limite du banc
synthétique (la lecture des observations n’y est pas servie pour le rôle élève), sans lien avec ce changement.

## 4. Icône de l’onglet Progression (élève)

Demande : une icône personnalisée « dans le style d’Apple », trois propositions, garder la meilleure. Atelier avec
le skill de conception de logo (rendus réels à chaque passe, audit SVG, essai à 64/32/16 px) :

- **A · Paliers** — trois marqueurs du parcours de compétence en escalier, l’autonomie pleine au sommet. Lu comme
  un circuit ou une molécule ; jonctions délicates à petite taille.
- **B · Toile** — la toile de la Progression en hexagone. Lu comme un écrou ou une pierre taillée.
- **C · Route parcourue** — **retenue**. Une route en perspective : le chemin fait est plein, le point est où l’élève
  en est, la suite en pointillé. Seule à rester nette à 16 px, propre à la conduite, et reprend le point de la
  marque. Première version écartée : le point au-dessus de la route se lisait comme une tête.

Construction : grille 64, traits de 4,5 (≈ poids medium des symboles du système à 26 pt), extrémités rondes,
tracés convertis en formes pleines (`icone-progression-build.py`), image vectorielle en gabarit
(`Tab-progress.imageset`) teintée par la barre d’onglets. Planches : `icone-progression-passe1.png`,
`icone-progression-passe3.png`. Pas vue sur appareil.
