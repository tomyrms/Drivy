# Actions à effectuer : du point bleu jusqu’à la résolution — 13 octobre 2026

Demande du porteur : un point bleu sur « Élèves », des élèves marqués « Profil à compléter » dans la liste, mais rien dans leur dossier ; ni quoi compléter, ni où. Le système né avec `b95a633` (12 octobre, « required actions ») détectait sans accompagner. Il est complété, pas remplacé : même store (`SchoolRequiredActionStore`), mêmes règles (`SchoolRequiredActionRules`), même point (`DrivyTabIcon`, `DrivyActionDot`).

## Architecture existante

| Action | Qui | Onglet | Source | Où elle se résout |
|---|---|---|---|---|
| `completeLearnerProfile` | administration | Élèves | `learner.profileReadiness` | dossier de l’élève → formulaire de profil |
| `finishLesson` | moniteur | Aujourd’hui | leçons du jour et rappel des jours passés | fiche de la leçon → « Terminer » |
| `giveRecordingConsent` | élève | Profil | accord GPS général | Profil → ligne « Accord GPS » → Paramètres |
| `resumeOnboarding` | moniteur (non élève) | Profil | `my-onboarding` | Profil → « Reprendre l’accueil » |

Une action n’existe que si la donnée la dit en attente et que le compte peut la résoudre. Le store est en mémoire ; chaque source remplace son type d’action ; rien n’est stocké.

## Où le guidage s’interrompait

1. **Faux « Profil à compléter » (cause du constat).** La liste lisait `learner_profile.profile_readiness`, un état stocké qui ne suivait pas la politique : `MINIMAL` à la création par invitation ou import, recalculé seulement à l’enregistrement d’un profil, et sur la seule étape JOIN. Le dossier, lui, demandait la readiness `PLAN_LESSON`, calculée sur la politique applicable. Sur le homelab : 11 élèves marqués à compléter alors que la politique de Luc auto école n’exige que prénom et nom, que tous ont. Le dossier ne trouvait rien, n’affichait rien, et éteignait le point de l’onglet en gardant la ligne de la liste (devenue grise).
2. **Le dossier nommait les champs sur une ligne**, sans accès direct : un seul bouton « Compléter » ouvrait le formulaire en haut, sans rien marquer.
3. **Le point Élèves dépendait de la page affichée** : seuls les élèves de la recherche et des pages chargées comptaient. Une recherche pouvait éteindre le point.
4. **« Leçon à terminer »** ne s’allumait qu’à la relecture de la journée, pas à la fin prévue d’une leçon en cours ; une leçon terminée ne l’éteignait qu’après une relecture réussie.
5. **« Accord GPS à donner »** n’était calculé qu’à l’ouverture de l’onglet Profil de l’élève : le point ne guidait vers rien qu’on n’ait déjà vu.
6. **« Reprendre l’accueil »** disparaissait sur une simple panne réseau.

## Ce qui change

### Une règle de complétude, côté serveur (`apps/api/src/profile-completeness.ts`)

Un dossier est complet quand chaque champ **requis** par la politique applicable aux étapes **JOIN et BEFORE_LESSON** est renseigné : ce qui manque pour planifier une leçon (R81). Un champ facultatif ou d’une étape à venir (BEFORE_COURSE) ne rend jamais un dossier incomplet ; sans politique publiée, rien n’est exigé.

- Les listes et la lecture d’un élève calculent `profileReadiness` à la lecture : `MINIMAL` si l’identité manque, `ACTION_REQUIRED` s’il manque autre chose, sinon `READY`. Le filtre `requiresAction=true` porte sur le même calcul.
- La readiness `PLAN_LESSON` du dossier et le contrôle de planification (`lessons.ts`) appliquent la même fonction TypeScript. La règle SQL et la règle TypeScript sont vérifiées l’une contre l’autre sur PostgreSQL (`profile-completeness.integration.test.ts` : sans politique, champ facultatif, incomplet, partiellement complété, complet, champ vidé).
- La colonne `profile_readiness` reste écrite à l’enregistrement, avec la même règle, mais n’est plus lue. Contrat OpenAPI inchangé : `Learner` n’a pas de propriété en plus.
- Un moniteur affecté lit le même état que l’administration ; la readiness ne lui nomme que les champs qu’il voit (noms, coordonnées), comme avant.

### Le dossier dit ce qui manque et y mène

Dans la carte de l’élève, sous son identité, visible sans rien déplier :

- « Profil à compléter » et, à droite, « 3 informations manquantes », avec le point d’action si ce compte peut en compléter au moins une ;
- une ligne par champ manquant, dans l’ordre de la politique. Un champ modifiable par ce compte est un bouton (chevron) qui ouvre le formulaire **défilé jusqu’au champ, clavier ouvert** (une adresse à renseigner s’ouvre d’elle-même) ;
- un champ que ce compte ne peut pas modifier est nommé sans geste, avec qui le renseigne (« Administration », ou « Élève ou administration » pour les noms vus par un moniteur) ;
- un moniteur dont l’élève manque seulement de champs protégés lit « Profil à compléter · Par l’administration », sans que ces champs soient révélés.

Le bloc n’apparaît qu’après une lecture réussie : une panne n’affirme ni un manque ni un dossier complet.

### Le formulaire marque les champs requis vides

Chaque champ qui manquait garde le point d’action devant son libellé (ou l’en-tête de sa section pour la date de naissance et l’adresse) tant qu’il est vide ; le point part dès la première saisie. VoiceOver lit « À renseigner ». Plusieurs informations manquantes restent visibles ensemble : on les complète dans l’ordre voulu, un seul enregistrement suffit.

### Synchronisation sans relance

- Le point Élèves lit la liste des dossiers à compléter de **toute l’école** (`GET …/learners?requiresAction=true&status=ACTIVE`, toutes pages), administration seulement, à l’ouverture de l’école et à chaque retour dans l’app.
- Chaque élève relu (dossier, liste, recherche, page suivante) corrige aussitôt cet ensemble : à la fermeture du formulaire, le dossier est relu, sa ligne de la liste et le point de l’onglet suivent dans la même seconde.
- Une panne garde ce qui a été lu ; un refus d’accès ferme la portée comme ailleurs.

### Les autres actions

- **Leçon à terminer** : le point s’allume à la fin prévue d’une leçon commencée (la vue attend cette heure, sans relecture) et s’éteint dès que l’école confirme la fin ou l’absence, depuis n’importe quel écran (`SchoolLessonChange.kind`).
- **Accord GPS** : lu avec les onglets de l’élève, le point de Profil s’allume avant toute visite ; la page relit le même modèle, et une réponse donnée l’éteint aussitôt. Relu au retour dans l’app.
- **Reprendre l’accueil** : une lecture en panne ne retire plus la ligne ni le point (`SchoolOnboardingPrompt.pendingState`).
- Le bouton « Profil » de la vue formation suit le même signe et le même mot (point d’action, « Profil à compléter »).

## Ce qui n’a pas été fait, volontairement

- Pas de nouvelle obligation ni de nouvelle notification. Le moniteur n’a toujours pas de point pour un profil incomplet (décision de `b95a633` : il ne peut compléter que les coordonnées).
- Pas d’accueil à reprendre pour l’élève dans l’app : rien ne l’y oblige aujourd’hui, l’accueil est reproposé après sept jours. À décider.
- Le web montre le badge « Profil à compléter » désormais juste, sans mener champ par champ (le bureau a son propre formulaire).
- Pendant un trajet, l’onglet Aujourd’hui montre la conduite, pas les leçons à terminer d’avant.

## Déploiement

API avant l’app. Sans l’API, l’app nouvelle lit encore l’ancien état stocké : les faux « Profil à compléter » restent, mais le dossier ne les confirme pas. Aucune migration.

## Captures

Simulateur iPhone, données fictives (`dossier-incomplete`, [run 38322661217](https://github.com/tomyrms/Drivy/actions/runs/38322661217)) : [clair](assets/guidage-actions-20261013/dossier-incomplet-clair.jpg) · [sombre](assets/guidage-actions-20261013/dossier-incomplet-sombre.jpg).
