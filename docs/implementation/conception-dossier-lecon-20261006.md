# Conception du 6 octobre 2026 : dossier, fiche de leçon, Profil → Leçons

Décisions du porteur prises par défaut par l'intégrateur : 1. mots « Bilan · Trajet » ; 2. bilan « Pour moi » non marqué dans les listes ; 3. lecture de l'administrateur non moniteur inchangée ; 4. « Rédiger le bilan » en barre basse.

Pose des contrats : le lot 1 écrit `DrivyLessonContents`, `DrivyLessonRow.contents`, `SchoolLesson.drivyContents` et `UI/SchoolLessonHistoryRow.swift` ; le lot 3 écrit `SchoolLessonCaptureSummary`, `SchoolLesson.captureSummary`, `lessonHistory(...)` et le paramètre `order` de l'API. Chaque lot code contre ces signatures exactes sans attendre l'autre.

Audit en lecture seule sur `d038571`. Le skill `apple-hig` ne contient que son `SKILL.md` dans ce dépôt (aucun fichier `distilled/`) : les choix de pattern ci-dessous ne s'appuient sur aucune citation HIG vérifiée.

## 1. Faits établis

| Sujet | Constat | Source |
|---|---|---|
| Onglets équipe | Aujourd'hui, Agenda, Élèves, Profil | `SchoolUI/SchoolHomeView.swift:86-113` |
| Onglets élève | Leçons, Progression (grand titre), compte derrière l'avatar ; aucune entrée Trajets | `SchoolHomeView.swift:167-199`, `:255` |
| Dossier | Deux `DrivyNavigationRow` poussant `SchoolTrainingScreen(section:)` ; barre « Démarrer / Planifier » | `SchoolUI/SchoolLearnerDossierView.swift:270-278`, `:56-66`, `:282-304` |
| Sélecteur en place | `SchoolTrainingContent` sait déjà afficher un segmenté Leçons/Progression quand `fixedSection == nil`, mais seul l'écran de revue l'emploie | `SchoolTrainingUI/SchoolTrainingView.swift:302`, `:426-441` ; `UI/SchoolVisualReview.swift:81` |
| « Trajets » | Exposé uniquement dans Profil, pour l'équipe | `SchoolUI/SchoolProfileTabView.swift:63-71` |
| Trajet sans leçon | Impossible : `capture_session.lesson_id NOT NULL` | `apps/api/migrations/008_capture.sql:24` |
| Fiche de leçon | Cinq appelants applicatifs (Agenda, Démarrer, Dossier, Accueil après trajet, Aujourd'hui), tous en feuille, plus trois écrans de revue | `SchoolAgendaView.swift:98`, `SchoolStartNowView.swift:421`, `SchoolTrainingView.swift:133`, `SchoolHomeView.swift:51`, `SchoolTodayView.swift:99` |
| Liste de leçons | Filtres `from`, `to`, `trainingId`, `instructorMembershipId`, `limit` ≤ 100, curseur ; tri croissant uniquement ; aucune recherche | `apps/api/src/lessons.ts:222-232` |
| Indicateurs par ligne | Déjà dans la projection : `currentPublishedRevisionId`, `captureSummary{hasCapture,syncState,publicationState}`, `instructorDisplayName`, `learnerDisplayName` | `lessons.ts:26-30`, `:36-39` ; test `lessons.integration.test.ts:79` |
| Modèle Swift | `SchoolLesson` ne décode pas `captureSummary` | `SchoolAgendaAPI/SchoolAgendaClient.swift:3-27` |
| Progression | Une ligne par compétence : dernier niveau publié, contexte, `observedAt`, `sourceLessonId`, plus les compétences jamais vues. Aucun historique | `migrations/007_lesson_reports.sql:122-129`, `lesson-reports.ts:225-230`, `SchoolLessonReportModels.swift:114-133` |

**Ce que la page Trajets offre et que les leçons n'offrent pas**

- États inhabituels par trajet : En cours, Partiel, Pas encore envoyé, Envoi refusé, Interrompu, Retiré, Supprimé (`SchoolTripsUI/SchoolTripsWorkspace.swift:177-194`).
- Section « À envoyer » des trajets arrêtés sur l'appareil (`SchoolTripsView.swift:212-215`).
- Filtre par moniteur pour l'administration, sur les pages chargées (`:180-199`).
- Replay direct, y compris quand la leçon n'est pas terminée : la fiche ne montre le trajet que si `isCompleted` (`SchoolLessonReportView.swift:384-387`). Les trajets de leçons « À terminer », annulées ou en absence deviendraient inaccessibles sans la correction du lot 2.

**Fiche d'une leçon terminée : où elle ressemble encore à un formulaire**

1. Dès 900 pt de large, hors grand texte, l'auteur reçoit l'éditeur (champs, menus de niveau, « Enregistrer ») à l'ouverture de toute leçon terminée (`SchoolLessonReportView.swift:259`, `:293`, `:283-285`). C'est le seul cas où la consultation passe par la rédaction. Non vérifié : quels iPad atteignent 900 pt dans une feuille `.page`.
2. Sur iPhone, le parcours en étapes ne s'ouvre seul qu'après « Terminer la leçon » (`:262-266`, `:467`). C'est conforme.
3. La lecture est un `Form` groupé avec des commandes d'édition :
   - bascule « Visible par l'élève » dans Trajet (`SchoolReportSections.swift:149-153`) ;
   - menu « … » sur chaque observation (`:262-281`) ;
   - bouton « Ajouter une observation » (`:212-219`) ;
   - texte « Aucune observation. », donc une section vide (`:205-207`) ;
   - barre basse permanente « Modifier le bilan » (`SchoolLessonReportView.swift:339-353`).
4. Les compétences sont à plat sous le bilan, sans jauge (`SchoolReportSections.swift:466-469`). L'en-tête peut atteindre sept lignes, prix compris (`SchoolLessonReportView.swift:509-530`).
5. Un administrateur non moniteur ne reçoit ni bilan ni observations (`SchoolLessonReportWorkspace.swift:82`, `SchoolLessonReportView.swift:388`). C'est une règle serveur, non modifiée ici.

**Incohérence de modèle mental** : Trajets est une liste parallèle d'objets qui appartiennent tous à une leçon, et les deux pages poussées du dossier dupliquent un sélecteur qui existe déjà.

## 2. Décisions

### Dossier
- **Pattern** : un contrôle segmenté « Leçons | Progression » sous l'identité, contenu en place dans le même `ScrollView` que la fiche, sans push. Écartés : deux lignes (état actuel), onglets imbriqués, pages balayées (conflit avec le retour par balayage du split view).
- En taille d'accessibilité, le segmenté devient un `Picker` en menu (comme `sectionPicker`, `SchoolTrainingView.swift:426-434`).
- **Filtre par permis** : un seul, partagé, toujours un menu (plus de second segmenté empilé). Il occupe une rangée sous le segmenté, permis à gauche et menu « Filtrer et trier » à droite (ce dernier en Leçons seulement). Avec un seul permis, pas de menu.
- **Barre « Démarrer / Planifier »** : inchangée, visible sur les deux segments.
- **iPad** : même composition dans la colonne de détail, largeur de lecture existante.
- **Élève** : garde ses deux onglets. Il gagne la nouvelle ligne de leçon et la nouvelle Progression.
- **Identifiants** :
  - conservés : `learner-dossier`, `training-dossier`, `training-permit-filter`, `training-lessons-menu`, `training-lesson-<uuid>`, `training-month-*` ;
  - supprimés : `learner-lessons-<uuid>`, `learner-progress-<uuid>` ;
  - ajouté : `dossier-section` sur le `Picker`, les segments se touchent par leur libellé ;
  - `training-tab-*` : abandonné, peu fiable sur un segment.

### Ligne de leçon partagée
- Colonne d'heure : début et fin.
- Titre : la date dans le dossier, le nom de l'élève dans l'historique du moniteur.
- Ligne de détail 1 : état inhabituel, puis date (historique du moniteur), permis (si la liste en mêle plusieurs), moniteur (s'il n'est pas le lecteur).
- Ligne de détail 2 : « Bilan · Trajet », absente si la leçon n'a ni l'un ni l'autre.
- Le lieu quitte la ligne du dossier, il reste dans la fiche.
- **Des mots, pas de glyphe** : DESIGN.md impose le statut en mots, et aucun symbole SF ne signifie « bilan » sans légende. VoiceOver lit la ligne telle quelle.
- **Limite** : « Bilan » signifie bilan partagé. Un bilan gardé « Pour moi » n'est pas marqué, même pour son auteur.

### Progression
Par permis (« Tous » empile une section par permis, comme aujourd'hui) :
1. **Dernière leçon évaluée · date** : « Prochaine étape » du dernier bilan publié et « Travaillé : Giratoire, Vitesse » (compétences dont `sourceLessonId` est cette leçon). Le bloc ouvre la leçon. Coût : une lecture `report-revisions/:id` par permis, via le `currentPublishedRevisionId` de la leçon la plus récente déjà chargée. Bloc omis si la lecture est refusée.
2. Une ligne de décompte en mots : « 4 en autonomie · 3 avec accompagnement · 2 en découverte · 5 pas encore vues ». Pas de barre, pas de pourcentage.
3. **À travailler** : niveaux En découverte puis Avec accompagnement, la plus ancienne observation d'abord. Chaque ligne porte libellé, niveau, jauge, date, et ouvre la leçon source.
4. **En autonomie** : mêmes lignes.
5. **Pas encore vues (n)** : `DisclosureGroup` replié.

« Évolution » n'est pas affichable : la vue SQL ne garde que le dernier niveau. Aucune flèche de tendance.

### Fiche de leçon
- **Lecture par défaut à toute largeur.** L'éditeur deux colonnes de l'iPad n'apparaît qu'après une entrée explicite (`isEditingReport`) ou après « Terminer la leçon ».
- **Entrée dans la rédaction** : « Modifier le bilan » passe dans le menu « … » de la barre d'outils, en premier. La barre basse ne subsiste que pour « Reprendre le bilan » (saisie non envoyée, primaire) et « Rédiger le bilan » (bilan vide, secondaire). Identifiant `lesson-report-edit` conservé sur les trois.
- **Garantie** : `openReport()` n'a que ces quatre origines. Elle est portée par une règle pure testée.
- **iPhone**, `ScrollView` sans cartes, titres `DrivySectionHeader` et filets :
  1. En-tête : identité, état, date et horaire, horaire réel, moniteur, lieu.
  2. Bilan : Prochaine étape, Travail réalisé, À retenir, mention « Pour moi ».
  3. Compétences évaluées : jauge par ligne, repli au-delà de cinq.
  4. Trajet : carte et bouton lecture. Un état inhabituel s'écrit en une ligne de texte.
  5. Observations : un appui met l'épingle en avant, repli au-delà de quatre.
  6. Objectifs prévus et note privée : repliés.
  7. Détails (prix) : repliés.
- Toute section vide disparaît. Une leçon terminée sans rien affiche une seule ligne (`missingReportText`).
- **Lecture sans commandes** : `SchoolReportTripSection` et `SchoolReportObservationsSection` reçoivent `editable: Bool`. Bascules de partage, menus de ligne et « Ajouter une observation » ne vivent que dans les étapes.
- **Trajet affiché dès qu'une capture existe**, quel que soit le statut de la leçon : c'est ce qui compense le retrait de Trajets.
- **iPad ≥ 900 pt** : en-tête pleine largeur ; à gauche Bilan, Compétences, Objectifs ; à droite carte plus haute et Observations. Sans trajet ni observation, une seule colonne.

### Profil → Leçons
- La ligne « Leçons » (`profile-open-lessons`) remplace « Trajets ». L'en-tête de section « Leçons » est retiré.
- **Moniteur** : ses leçons passées et à terminer (`to = maintenant`, `instructorMembershipId = lui`), les plus récentes d'abord, groupées par mois dans le fuseau de la leçon. Pas de compteur par mois tant que tout n'est pas lu.
- **Admin et moniteur** : même page, plus un choix « Mes leçons / Toute l'école ».
- **Admin seul** : toute l'école, moniteur nommé sur chaque ligne, pas de filtre par moniteur.
- **Élève** : rien de nouveau, son onglet Leçons est son historique.
- **Un seul menu** en barre d'outils : Afficher (Toutes, Avec bilan, À terminer, Annulées et absences), Trier (récentes ou anciennes d'abord), portée.
- **Recherche** : `.searchable` sur le nom d'élève, côté client. Activer la recherche ou un filtre charge tout l'historique (même précédent que `loadHistory` du dossier). « Aucun résultat » ne s'affiche qu'une fois tout lu.
- **Pagination** : 100 par page, chargement à l'approche de la fin, `List` paresseuse.
- **Ouverture** : même feuille que l'Agenda, `SchoolLessonReportView`. Une seule implémentation du détail.
- **Trajets à envoyer** : `SchoolCaptureUploadsSection` en tête, seulement s'il y en a ou en cas d'erreur d'envoi.
- **Fichiers** : `SchoolTripsView.swift` est supprimé. `SchoolTripsWorkspace.swift` reste intact (ses règles statiques servent à la fiche, `SchoolTripsTests` reste vert). `SchoolTripReplayRoute` y est déplacé.

## 3. Contrats partagés

```swift
// SchoolAgendaAPI/SchoolAgendaClient.swift
struct SchoolLessonCaptureSummary: Codable, Sendable, Equatable {
    let hasCapture: Bool
    let syncState: String?
    let publicationState: String
}
// dans SchoolLesson, après commercialSelection :
var captureSummary: SchoolLessonCaptureSummary? = nil

// Historique : `to = before`, tri serveur.
func lessonHistory(schoolID: UUID, before: Date, instructorMembershipID: UUID?,
                   newestFirst: Bool = true, cursor: String?) async throws -> SchoolPage<SchoolLesson>
```

```swift
// UI/DrivyComponents+Agenda.swift
struct DrivyLessonContents: OptionSet, Sendable, Equatable {
    let rawValue: Int
    static let report = DrivyLessonContents(rawValue: 1 << 0)
    static let trip = DrivyLessonContents(rawValue: 1 << 1)
}
// DrivyLessonRow, après `note` ; rendu en dernière ligne de détail « Bilan · Trajet » :
var contents: DrivyLessonContents = []

extension SchoolLesson {
    /// Bilan partagé ; trajet reconstruit (mêmes critères que SchoolTripsWorkspace.isReplayable).
    var drivyContents: DrivyLessonContents { /* COMPLETED && currentPublishedRevisionId != nil ;
        hasCapture && publicationState == "PRIVATE" && syncState synchronisé ou partiel */ }
}

// UI/SchoolLessonHistoryRow.swift (nouveau)
struct SchoolLessonHistoryRow: View {
    enum Title { case day, learner }
    let lesson: SchoolLesson
    var title: Title = .day
    var permit: String? = nil
    var instructor: String? = nil
    var showsState = true
}
```

Les valeurs brutes de l'état de synchronisation n'ont pas été lues pendant l'audit : les prendre dans l'enum de `SchoolCaptureAPI/SchoolCaptureModels.swift`.

```ts
// apps/api/src/lessons.ts:222 — schéma
order:z.enum(['asc','desc']).default('asc')
// :230-231
const desc=query.order==='desc';
if(position)where.push(`(planned_start,id)${desc?'<':'>'}(${bind(position.createdAt)}::timestamptz,${bind(position.id)}::uuid)`);
// … ORDER BY planned_start ${desc?'DESC':'ASC'},id ${desc?'DESC':'ASC'} LIMIT …
```

Le curseur est déjà lié à la requête (`scope`, `:226`), donc à `order`. Pas de SQL ni de migration.

## 4. Lots

| | Lot 1 : Dossier, Progression | Lot 2 : Fiche de leçon | Lot 3 : Profil → Leçons, API |
|---|---|---|---|
| Fichiers | `SchoolUI/SchoolLearnerDossierView.swift`, `SchoolTrainingUI/*`, `SchoolTrainingAPI/*`, `UI/DrivyComponents+Agenda.swift`, `UI/SchoolLessonHistoryRow.swift` | `SchoolLessonReportUI/*`, `SchoolObservationUI/*` | `SchoolUI/SchoolProfileTabView.swift`, nouveau `SchoolLessonHistoryUI/*`, `SchoolTripsUI/*`, `SchoolAgendaAPI/*`, `apps/api/src/lessons.ts`, `apps/api/test/lessons.integration.test.ts`, ligne 54 de `UI/SchoolVisualReview.swift` |
| Dépend de | `SchoolLesson.captureSummary` (lot 3) | `SchoolTripsWorkspace` statique et `SchoolTripReplayRoute`, noms inchangés | Ligne partagée (lot 1), signature inchangée de `SchoolLessonReportView` |
| Signatures à ne pas changer | `SchoolTrainingScreen` (deux `init`), `SchoolLearnerDossierView` | `SchoolLessonReportView` | `SchoolTripsWorkspace` |
| Tests unitaires | `SchoolDossierTests`, `SchoolTrainingRefreshTests` ; nouveaux : groupes de progression, « dernière leçon évaluée », décompte ; `DrivyLessonRowStateTests` pour `contents` | `SchoolReportFlowTests` (origines de la rédaction, lecture par défaut en large), `SchoolLessonHubTests` (trajet hors statut terminé, sections vides) | Nouveau `SchoolLessonHistoryTests` (mois par fuseau, pagination décroissante, recherche sur historique complet, boucle de curseur) ; `SchoolAPIClientTests` (requête) ; intégration API : deux pages en `desc`, curseur `asc` refusé en `desc`, élève avec trajet masqué |
| Identifiants | `dossier-section`, retrait de `learner-lessons-*` et `learner-progress-*` | `lesson-report-edit` dans le menu, `lesson-more-actions` | `profile-open-lessons`, `lessons-history`, `lessons-history-filter`, `history-lesson-<uuid>` |

`SchoolHomeView.swift` n'a besoin d'aucun changement et reste hors lots.

## 5. Captures et tests d'interface à adapter ensuite

- `NativeNavigationTests.swift:7-10` (Trajets) et `:53-65` (deux pages du dossier).
- `VisualOrientationTests.swift:77-112`.
- `LayoutContinuityTests.swift:16` (ouvrir le menu avant « Modifier »).
- `UI/SchoolVisualReview.swift` (écrans `trips`, `lesson`), `UI/SchoolPermitsVisualReview.swift`, `UI/SchoolOfficeVisualReview.swift`.
- `scripts/ios/capture-screens.sh:9` et `:19` : remplacer `trips` par `lessons-history` ; ajouter `lesson-read-ipad`, `lesson-read-empty`, `dossier-progression`.

## 6. Risques et exclusions

- **Ordre de déploiement** : le schéma de requête est strict, un serveur non mis à jour refuse `order`. Déployer l'API sur le homelab (sauvegarde préalable) avant de distribuer l'IPA.
- **Trajet masqué à l'élève** : non vérifié que `captureSummary` renvoie `hasCapture:false` dans ce cas. Le test d'intégration du lot 3 doit l'établir avant d'afficher « Trajet » côté élève.
- **Rien n'a été vu tourner** : pas de toolchain Swift sur la machine de conception. Le segmenté dans le `ScrollView` du dossier et la composition iPad sont à valider sur captures CI.
- **Volume** : une recherche charge tout l'historique, soit une dizaine de requêtes ou plus pour un moniteur chargé.
- **À ne pas faire dans cette passe** :
  - historique des niveaux ou flèche de tendance ;
  - score ou pourcentage ;
  - recherche serveur ;
  - filtre par moniteur pour l'administration ;
  - permis sur les lignes de l'historique du moniteur (il faudrait lire chaque formation) ;
  - deux colonnes Leçons/Progression dans le dossier ;
  - renommer ou vider `SchoolTripsWorkspace` ;
  - toucher aux droits de lecture.

## 7. Décisions du porteur

Tranchées par défaut par l'intégrateur (voir en tête), à confirmer à l'œil :

1. « Bilan · Trajet » en mots sur une seconde ligne de détail ; l'alternative est deux glyphes en fin de ligne.
2. Un bilan gardé « Pour moi » n'est pas marqué dans les listes. Le marquer demande un booléen de plus dans la projection.
3. Un administrateur non moniteur ne lit ni bilan ni observations sur la fiche : ouvrir ou non cette lecture.
4. « Rédiger le bilan » reste en barre basse sur toute leçon terminée sans bilan, même ancienne ; l'alternative est de le mettre aussi dans le menu.
