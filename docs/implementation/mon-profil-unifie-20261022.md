# Page unique « Mon profil » (#94), 22 octobre 2026

## Avant

- Paramètres / Compte montrait deux lignes : « Mon profil » (`SchoolRenameSelfRow` → `SchoolSelfProfileSheet`, compte Drivy via `/v1/me/profile`) et « Mes informations » (`openProfile` → `SchoolProfileView`, dossier d’élève via `SchoolProfileWorkspace`, réservé au rôle LEARNER avec dossier).
- Le Profil de l’élève ajoutait un volet « Mes informations » (`SchoolLearnerProfileSummary` en lecture, bouton « Modifier mes informations ») relu à chaque lecture du dossier (`learnerReadCount`).
- Champs communs aux deux pages : prénom, nom, e-mail, téléphone, date de naissance, adresse. Propres au compte : photo, nom affiché. Propres au dossier : politique de l’école et explications, notice de confidentialité, prochaine étape (readiness), accueil à reprendre, photo associée au dossier, demande en attente, conflit de version, droits relus au serveur.

## Après

- Une seule ligne « Mon profil » (identifiant `open-my-profile`, `profile-open-my-profile` dans l’onglet Profil de l’élève) pour tout compte connecté : élève, moniteur, administration, rôles cumulés, compte sans école. Elle ouvre `SchoolMyProfileView`. Paramètres de l’élève ne répète pas la ligne déjà en tête de son Profil.
- `SchoolMyProfileView` : photo, identité (prénom, nom, nom affiché), contact, date de naissance, adresse du compte Drivy ; puis, seulement si l’élève a un dossier dans l’école ouverte (`ownProfileLearner`, rôle LEARNER, école active), la section « Dossier scolaire » avec le nom de l’école, l’état de la demande, les champs autorisés par le serveur, la prochaine étape, l’accueil, les explications et la notice. Sans dossier, aucun dossier n’est créé ni lu.
- Doublons : un champ du dossier dont la valeur enregistrée est identique à celle du compte n’est pas répété. Il reste visible s’il est vide, modifié, invalide, demandé par l’école, ciblé par un chemin guidé, ou après « Afficher les champs identiques au compte ». Les deux valeurs gardent leur source : rien n’est recopié d’une source à l’autre.
- Enregistrement : un seul bouton, deux requêtes distinctes et dans cet ordre, compte (`PATCH /v1/me/profile`, If-Match) puis dossier (file chiffrée, `saveProfileAfterConfirmation`). `SchoolMyProfileOutcome` dit le résultat de chacune ; un échec partiel est écrit dans la barre d’action et annoncé à VoiceOver, jamais un succès global. Chaque saisie échouée reste en place. Conflits : compte relu comme référence ; dossier conservé avec « Recharger les informations ».
- Dossier d’un autre élève (moniteur affecté, administration) : `SchoolProfileView`, inchangé dans ses droits. Le dossier de l’administration qui est aussi élève, ouvert depuis Élèves, s’ouvre dans « Mon profil » avec le champ ciblé.
- Accueil guidé : `SchoolOnboardingView` inchangé ; « Reprendre l’accueil » reste dans le compte et dans la section dossier.

## Code

- Nouveaux : `SchoolProfileUI/SchoolMyProfileView.swift`, `SchoolProfileUI/SchoolSelfProfileEditor.swift` (validation et sauvegarde du compte, reprises de l’ancienne feuille), `SchoolProfileUI/SchoolProfileFormSections.swift` (champs et contexte du dossier partagés avec `SchoolProfileView`, adresse et pays partagés avec le compte).
- Supprimés : `SchoolRenameSelfRow`, `SchoolSelfProfileSheet`, la ligne « Mes informations », le volet « Mes informations » du Profil de l’élève et son modèle, `makeLearnerProfile` de `SchoolLearnerProfileTab`, `SchoolWorkspace.learnerReadCount`, `renameSelf` (workspace, protocole, client : aucun appelant), le doublon du sélecteur de pays.
- Conservés car partagés : `SchoolProfileView`, `SchoolProfileWorkspace`, `SchoolLearnerProfileSummary` (dossier vu par le moniteur), `SchoolProfileStatusSections`, `SchoolProfileConflictNotice`, `SchoolProfileBlockers`, `SchoolProfilePhotoEncoder`.
- Aucun changement serveur, base ou homelab.

## Vérification

- Exécuté : relecture des références, compilation Release de l’IPA par le workflow `ipa-essai.yml` (résultat consigné dans STATUS).
- Non exécuté : tests unitaires et UI Apple (dont le test ajouté `myProfileNeverAnnouncesAGlobalSuccessWhenOneSourceFailed` et `SchoolEntryTests` mis à jour), captures iPhone et iPad, VoiceOver, Dynamic Type, appareil physique.
