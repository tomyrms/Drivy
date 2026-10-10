# Reprise — passe UI/UX « dossier par permis, fiche de leçon, agenda sobre » (5 octobre 2026, soir)

Document de passation. La section « État des lots » fait foi.

Phrase à donner à Codex : « Lis docs/implementation/reprise-passe-ui-20261005-soir.md et continue le chantier là où il s'est arrêté, en respectant AGENTS.md et les skills indiqués (Codex n'a pas l'outil Skill : lire `.claude/skills/<nom>/SKILL.md`). »

## Demande du porteur

Passe de corrections UI/UX, sans refonte, sans aspect « généré » (badges, couleurs inutiles, cartes partout, textes explicatifs, emojis), avec des agents et les skills pertinents.

1. Liste des élèves et données de démonstration : données crédibles, photos de profil si possible, aucune mention « exemple ».
2. Dossier de l'élève : deux sections, Leçons et Progression, avec un filtre par permis à l'intérieur de chacune ; plus de structure dupliquée par permis.
3. Détail d'une leçon : informations manquantes (objectifs, bilan) ; trouver la cause, adapter le contenu au statut.
4. Agenda : plus de tags colorés pour les états (« Annulée »), un rendu intégré à la ligne.
5. Audit emojis / SF Symbols : une icône seulement si elle a une fonction.
6. Leçon terminée : retirer l'élément vert « Leçon terminée » et les libellés de statut redondants.
7. « Revoir le trajet » : bouton lecture en bas à droite de la carte du trajet.
8. Vérification globale des écrans touchés, puis résumé (fichiers, changements, bugs, restes, recommandations).

## État des lots

Chemins relatifs à `apps/ios/Drivy/`. Les agents ne committent pas ; l'intégrateur relit et committe lot par lot.

| Lot | Sujet | Modèle | Fichiers possédés | État |
|---|---|---|---|---|
| Données | Libellés réalistes dans la base du homelab | intégrateur | `infra/deploy/provision-realistic-labels.sql` | **appliqué en production** après sauvegarde et répétition |
| L | Fiche de leçon : diagnostic des informations manquantes, statut redondant, lecture du trajet sur la carte | opus | `SchoolLessonReportUI/*`, `SchoolLessonReportAPI/*`, `SchoolObservationUI/*`, `SchoolCaptureUI/SchoolCaptureReplay*`, `SchoolCaptureHistory*`, éventuellement `apps/api` | lancé |
| D | Dossier : Leçons et Progression avec filtre par permis | opus | `SchoolUI/SchoolLearnerDossierView.swift`, `SchoolTrainingUI/*`, `SchoolTrainingAPI/*`, parties utiles de `SchoolWorkspace`, `SchoolRootView`, `SchoolHomeView` | lancé |
| G | États de leçon sans badge coloré, audit des symboles | sonnet | `UI/DrivyComponents+Agenda.swift`, `UI/DrivyComponents+Accueil.swift`, `SchoolAgendaUI/SchoolAgendaView.swift`, `SchoolPlanningView.swift`, `SchoolUI/SchoolTodayView.swift`, `SchoolBrowserView.swift`, `SchoolTripsUI/*`, `SchoolAccountComponents.swift`, `SchoolProfileTabView.swift` | lancé |
| Intégration | Migration des appels à `DrivyLessonRow(badge:)` restés chez L et D, fixtures `UI/*VisualReview.swift` sans « exemple », galerie, tests, documents | intégrateur | fichiers partagés | à faire après les lots |

Fichiers partagés réservés à l'intégration : `UI/DrivyComponents.swift`, `UI/DrivyTheme.swift`, `UI/DrivyLearnerIdentity.swift`, `UI/*VisualReview.swift`, `UI/DrivyDesignSystemGallery.swift`.

Le lot G ajoute à `DrivyLessonRow` un paramètre d'état et garde `badge:` le temps que L et D finissent ; l'intégrateur migre ensuite les appels restants et retire l'ancien paramètre s'il n'a plus d'appelant.

## Lot Données — fait

- Inventaire en lecture seule de la base `drivy_refonte` : 92 personnes et 86 dossiers suffixés « · exemple », 75 adresses sur des rues inventées, deux fermetures et le libellé des conditions générales suffixés.
- `infra/deploy/provision-realistic-labels.sql` : une transaction, ne modifie que des libellés, vérifie avant validation que les noms de dossier et de personne restent identiques et égaux à prénom + nom, que les nombres de lignes n'ont pas changé ; refuse une seconde exécution.
- Sauvegarde vérifiée `/root/drivy_refonte-before-labels-20261005-20261005T205714Z-8cf7171d.dump` (CT113), répétition sur une copie restaurée (résultat identique, seconde exécution refusée), application en production, copie supprimée, `/health/ready` de l'API à 200.
- Laissés tels quels, volontairement : e-mails (`…@example.invalid`) et téléphones (`+41 000…`), parce que l'app propose d'appeler et d'écrire et qu'une valeur vraisemblable pourrait appartenir à quelqu'un ; clés internes (`example-category-b`), motifs d'approbation et journaux d'audit, qui ne sont pas des libellés d'écran.
- Photos de profil : impossibles dans cette passe. La colonne `profile_photo_document_id` porte une contrainte `CHECK (… IS NULL)` (migration 004) et aucun dépôt ni service de documents n'existe ; l'avatar reste les initiales.
- Relevé, non corrigé : 16 révisions de bilan du jeu de volume répètent deux fois la même phrase dans « À retenir ».

## Skills

`impeccable` (références iOS, distill, quieter, layout), `swiftui-ui-patterns`, `write-swift`, `apple-hig`, `no-ai-slop` / `anti-slop`, `balise-ux-writing`, `better-typography`, `superpowers:systematic-debugging` pour le lot L.

## Contraintes

Aucune compilation Swift locale : l'IPA se compile par le workflow « IPA d'essai · iLoader » à chaque push sur `codex/**` touchant `apps/ios/Drivy/**` ; tests et captures par `gh workflow run "Refonte · iOS" --ref <branche>` (voir `reprise-ux-sobre-20261005.md`). Jamais de force-push ni de signature GPG forcée, documents écrits par script, deux ou trois agents à la fois.

## Ce qu'il reste à faire

1. Attendre les lots L, D, G ; relire chaque fichier modifié ; committer lot par lot.
2. Intégration : appels à `DrivyLessonRow`, fixtures et galerie sans « exemple », tests.
3. Pousser, compiler l'IPA, lancer la campagne native et les captures (dossier, leçon, agenda, aujourd'hui).
4. Écrire la décision (`passe-ui-20261005-soir.md`) et l'entrée de `STATUS.md`.

## Suite de la demande (soir et nuit)

- Points 9 à 12 (bilan et fin de leçon) : **faits**, commit `b960478`. Fiche de lecture pour une leçon terminée ; rédaction en étapes Trajet → Compétences → Bilan sur iPhone, deux colonnes sur iPad large ; brouillon local chiffré ; constat sans texte. Décision : `passe-ui-20261005-soir.md`.
- Lots L, D, G : **committés** (`afee877`, `f296e27`, `117950c`). Fixtures multi-permis : `8e9b685`. Retouches issues des captures : `d038571`.
- Points 13 à 17 : **faits et committés** (`1203579`, `86a43fc`, `454bb7f`, `2345bb9`, correctifs `ef0ea21`, `0d42721`, `5054914`). Campagne native verte sur `0d42721`, API déployée (`ef0ea21`). Conception : `conception-dossier-lecon-20261006.md`.
- **Il reste** : capturer les étapes de rédaction du bilan (écran de revue à ajouter), enrichir les fixtures de capture (« Bilan · Trajet », nom d’élève dans l’historique), essai sur appareil par le porteur, puis les restes listés dans `passe-ui-20261005-soir.md`.

## Journal

- 5 octobre, 22 h 45 : lots L, D, G lancés. Lot Données appliqué en production.
