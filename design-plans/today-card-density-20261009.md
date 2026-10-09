# Alléger la carte principale d’Aujourd’hui

Written against: `89891641244f0de64174f3d79d5c0438291f53ec`.

## Evidence chain

- Surface: application Apple, onglet Aujourd’hui du personnel, `SchoolHomeView.sessionTab` → `SchoolTodayView.card`. Le trajet actif remplace cette vue par `SchoolCaptureLiveView` ; ce dernier est exclu.
- Problem: le porteur a explicitement confirmé le 9 octobre que la carte principale d’Aujourd’hui contient trop de texte et d’informations. En présence d’une prochaine leçon non démarrable, la source empile la date complète, le délai relatif, les deux heures, l’avatar, le nom, le lieu, une disponibilité de démarrage, une action et l’entrée des leçons suivantes.
- Design evidence: `AGENTS.md`, Construction, « Peu de texte à l’écran » ; `docs/implementation/decisions-2026-09-28.md`, décision Écriture ; `DESIGN.md`, principes natifs « Une zone de décision dominante » et « Le texte utile, pas le texte accumulé ». `docs/implementation/today-signal-finish-20261004.md` exige de conserver la priorité À terminer et la liste des seules leçons à venir.
- Owner: `apps/ios/Drivy/SchoolUI/SchoolTodayView.swift`, `card` lignes 184–235, `lessonSummary` lignes 241–278. Le panneau est `DrivyMapDock` dans `UI/DrivyComponents+Seance.swift:303` ; son espacement est `DrivySpacing.s` et son padding `DrivySpacing.m`.
- Scope and affected surfaces: panneau bas compact, panneau latéral à partir de 960 pt, et flux de grand texte de cette seule vue. Les trois chemins rendent le même `card`.
- Uncertainty: audit de source et retour utilisateur, sans inspection de nouveaux rendus. La réduction effective de hauteur et la lisibilité des noms/lieux longs doivent être vérifiées après implémentation.

## Design decision

Réduire le résumé dominant à l’horaire, l’élève et le lieu, en réutilisant la rangée de leçon existante. Conserver l’état À terminer lorsqu’il existe et l’action contextuelle, sans changer le choix de leçon ni ses droits. Retirer de ce résumé la date de la journée, déjà située par l’onglet Aujourd’hui, le délai relatif et l’avatar. La disponibilité réelle « Démarrer dès… » reste visible lorsque l’action est fermée ; elle se lit comme une métadonnée, sans réserver la hauteur d’un bouton. Le reste de la journée demeure replié initialement sur toutes les largeurs, avec son intitulé et son compte visibles. Cette décision de simplification remplace explicitement le choix antérieur d’ouvrir le groupe pour occuper la grande colonne iPad ; elle ne masque pas la prochaine leçon affichée sous À terminer.

## Reuse

- `DrivyMapDock`, sans modification globale.
- `DrivyLessonRow(start:end:title:details:note:)` dans `UI/DrivyComponents+Agenda.swift:123` : heures tabulaires, élève en `.headline`, lieu en `.subheadline`, état inhabituel en texte, chevron et adaptation verticale aux grandes tailles.
- `DrivyRowButtonStyle`, les styles primaire/secondaire `.field`, `DrivyTheme.muted`, `DrivySpacing` existants.
- Exemplar: la prochaine leçon secondaire emploie déjà `DrivyLessonRow` dans `SchoolTodayView.upcomingLesson:287`. Aucune nouvelle primitive nécessaire.

## Changes

1. `apps/ios/Drivy/SchoolUI/SchoolTodayView.swift`, `lessonSummary` et ses deux appels.
   - Change: remplacer le contenu construit localement par `DrivyLessonRow(start: startTime(lesson), end: endTime(lesson), title: name(lesson), details: [lesson.meetingPoint], note: note)`. Retirer le paramètre `moment` de ce résumé et ses appels. Retirer la date du début du `card`.
   - Preserve: le `Button` existant, son ouverture de la fiche en lecture, `DrivyRowButtonStyle`, son indice d’ouverture ; les deux heures, le nom résolu sans invention, le lieu et la note À terminer. Ne pas transmettre un état normal supplémentaire qui ajouterait un nouveau texte.
   - Verify: le résumé affiche seulement les informations nécessaires à l’identification du rendez-vous. Le lieu vide ne produit aucune ligne. À terminer reste écrit avec son ton d’alerte existant.
2. Même fichier, texte `today-start-later`.
   - Change: retirer la hauteur minimale de 44 pt du texte de disponibilité ; garder son retour à la ligne et l’aligner avec le résumé. Il reste une information sans apparence de commande.
   - Preserve: calcul `startOpening`, texte « Démarrer dès… », identifiant de test et fuseau de la leçon.
   - Verify: une leçon future explique toujours quand son trajet devient démarrable ; aucun bouton désactivé ou nouvelle explication n’est ajouté.
3. Même fichier, contenu secondaire et actions.
   - Change: conserver leur structure actuelle pour cette passe ; la réduction vient du résumé, pas de la disparition de commandes ou de rendez-vous.
   - Preserve: priorité de `toFinish.first`, prochaine leçon visible après une leçon À terminer, liste repliable des autres leçons futures, erreurs et reprises, squelette de chargement, garde de rôle et d’auteur, `mayStart`, `startOpening`, préparation GPS et retour de fiche.
   - Verify: « Démarrer une leçon » reste disponible dans sa branche actuelle. Il crée une autre leçon et n’est donc pas un doublon de « Démarrer le trajet ».
4. Même fichier, branche de panneau latéral dans `body`.
   - Change: retirer le `.onAppear { showsDay = true }`. Conserver la valeur initiale `false` et laisser ensuite le `DisclosureGroup` refléter le choix de l’utilisateur.
   - Preserve: intitulé singulier/pluriel, compte, filtrage et toutes les lignes. Ne pas ajouter de remise à `false` à chaque rotation ou retour de fiche.
   - Verify: à la première ouverture sur iPad large, le panneau présente le même degré de détail que sur iPhone ; après ouverture volontaire, un changement de largeur ne replie pas arbitrairement le groupe.

## Scope

- Inherit: les trois dispositions d’Aujourd’hui qui appellent `card`.
- Verify: leçons À terminer seule et suivie d’une prochaine ; prochaine démarrable ou plus lointaine ; aucune leçon ; erreur avec données conservées ; noms/lieux longs ; liste secondaire ouverte et fermée.
- Exclude: carte GPS, écran de capture actif, agenda, fiches de leçon, styles globaux, tokens, API et règles métier.

## Validation

- Product: ouvrir la fiche depuis le résumé ; terminer une leçon passée depuis le bouton conservé ; démarrer le trajet autorisé ; retrouver la prochaine leçon malgré une leçon À terminer ; démarrer une autre leçon lorsque la branche l’autorise.
- Interface: comparer Aujourd’hui sur iPhone et iPad, clair/sombre, colonne large/fenêtre étroite, texte standard et grand texte. La nouvelle carte doit être moins haute dans l’état standard ; ne pas réduire les tailles de texte ni tronquer le nom pour obtenir cet effet.
- System: aucune modification de `DrivyLessonRow` ou `DrivyMapDock` partagés ; aucune nouvelle couleur, police ou dimension arbitraire.
- Repository: `git diff --check` → aucun défaut d’espacement. Exécuter sur runner Apple la compilation prévue par `.github/workflows/refonte-ios.yml` ; `bash scripts/ios/test-simulator.sh` après la compilation `build-for-testing` → tests existants conservés, notamment `SchoolStartNowClientTests`. La capture ciblée est `home-tabs` dans `scripts/ios/capture-screens.sh`. Une compilation/test Swift n’est pas revendiquée depuis Windows.

## Stop conditions

- Stop if le contrat des leçons impose une autre information à rendre immédiatement visible ; ne pas la masquer pour réduire la hauteur.
- Stop if le rendu du composant partagé doit être changé dans toutes les vues pour résoudre cette seule carte ; garder la correction locale et réévaluer la composition.
- Stop if le périmètre nécessite de changer droits, sélection des leçons, conditions de démarrage ou données de localisation.

## Design documentation

- After acceptance and validation: consigner dans `docs/implementation/` le résumé compact d’Aujourd’hui et ses états préservés ; mettre `STATUS.md` à jour avec les essais réellement exécutés et leurs limites. Ne pas modifier le dossier de conception livré.

## Implementation follow-up

Implémenté sur `86ef790`. Le résumé emploie la rangée partagée sans modifier cette primitive ni le panneau commun. La relecture indépendante ne relève pas de changement des actions, droits ou choix de leçon. Le contrôle Apple retenu pour cette passe est la compilation et les tests d’interface de captures ciblées ; la suite native métier complète proposée plus haut n’est pas répétée. Les résultats effectifs et leurs limites sont consignés dans [le suivi de réalisation](../docs/implementation/today-privacy-20261009.md).
