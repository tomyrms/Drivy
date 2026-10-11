# Audit des parcours moniteur et élève — cinquième passe (11 octobre 2026)

Suite du [parcours de l’élève](parcours-eleve-profil-20261011.md). Deux audits en lecture seule menés par des agents dédiés (parcours du moniteur ; parcours de l’élève, cohérence et architecture), vérification de chaque constat dans le code, puis corrections. Le thème sombre est hors de cette passe (autre session, branche `claude/dark-soft-charcoal-20261011`, fusion vérifiée sans conflit).

Déjà en place et vérifié, donc non retouché : trois onglets pour l’élève (Leçons, Progression, Profil) ; attente de la première position sous le rideau, sept secondes au plus, puis la carte montre sa recherche ; une leçon planifiée ne démarre jamais seule (une heure passée la fait lire « En attente »).

## Démarrage d’une leçon

- **Bug corrigé** : « Commencer la leçon » était proposé pour toute leçon planifiée, même la semaine suivante, depuis l’agenda. Un appui la commençait aujourd’hui ; elle ne pouvait plus être déplacée et sa fin enregistrait les heures du jour. Une leçon se commence maintenant **le jour de son rendez-vous (dans son fuseau), jusqu’à 30 minutes après sa fin** (`SchoolLessonHubRules.mayBegin`). Ce contrôle est fait par l’app ; l’API ne vérifie pas l’horaire (voir points ouverts).
- **Rendez-vous manqué** (30 minutes après la fin, sans départ) : la fiche propose « Élève absent » en bouton, au lieu de « Commencer » ; Aujourd’hui ne le met plus en tête toute la journée, il reste dans la liste du jour, noté « En attente ».
- « Élève absent » attend une relecture en cours au lieu d’échouer sans message.
- Confirmation de fin : « Poursuivre la leçon » au lieu de « Continuer », qui se lisait comme une validation.
- Trajet dont la sauvegarde a échoué : « Terminer la leçon » est proposé à côté de « Réessayer la sauvegarde » ; la fiche reprend l’arrêt durable et dit son erreur.

## Parcours de l’élève

- L’accord GPS affiché dans Profil suit une réponse donnée dans la fiche de la prochaine leçon, et inversement.
- Profil dit qu’une relecture a échoué au lieu de montrer d’anciens chiffres comme à jour.
- « À venir » et « Passées » suivent la même règle que la carte « Prochaine leçon » (créneau pas encore fini).
- Une école archivée se lit « École archivée », comme chez le moniteur.
- Accueil guidé : permis nommés comme ailleurs (année quand deux permis ont la même catégorie), état en mots au lieu d’une pastille ; l’étape GPS dit que le choix se fait dans Profil.

## Accessibilité

- Les observations placées sur la carte sont annoncées comme boutons, et la sélectionnée comme telle.
- Une ligne de Progression dit « détail affiché » quand elle est dépliée, même sans les indications de VoiceOver.
- Sous Réduire les animations, la flèche de ces lignes change de sens en fondu au lieu de tourner.

## Fluidité et réseau

- Fiche de leçon : le compte et la leçon se lisent ensemble, les offres et les référentiels aussi ; une leçon passée ne lit plus le souhait de l’élève (il ne s’y montre pas).
- Ajouter une observation montre son attente dans le bouton ; Modifier et Retirer sont inactifs pendant ce temps.
- Fiches passées ouvertes depuis l’agenda, l’historique ou Aujourd’hui : le squelette a d’emblée le fond du récapitulatif (plus de saut).
- Calendrier de l’agenda gardé par fuseau ; formateurs mis en cache pour les heures d’observation, les créneaux du planning, le replay (10 rendus par seconde en lecture), l’horodatage des observations, les noms de mois et les durées de trajet.
- L’agenda met à jour l’état de ses leçons chaque minute.

## Trajets et données de l’élève

- L’app accepte un trajet sans `deviceId` ni `deviceAssessmentId`. Première étape de l’ordre proposé à la passe précédente : une fois cette version installée, l’API pourra cesser d’envoyer ces identifiants du moniteur à l’élève. L’enregistrement exige toujours leur présence et leur égalité avec ceux de l’appareil.

## Code retiré

État de sélection d’une formation dans `SchoolWorkspace` (jamais appelé) et trois DTO de commandes de configuration inutilisés.

Signalés, laissés en place parce qu’ils sont dans les fichiers du design system que la session du thème sombre modifie : `DrivyGuidedStepHeader`, `DrivyGuidedFact` (doublons privés dans l’accueil guidé), `DrivyMapStopButton`, `JourneyMapRegion`, `SchoolProfileWorkspace.loadMorePolicies`.

## Décisions du porteur (11 octobre 2026) et suite côté API

Le porteur a validé les trois points ouverts ci-dessous (« oui corrige »).

- **Départ jamais avant le jour du rendez-vous, aussi au serveur** : `POST /lessons/:id/start` refuse un départ avant le jour civil du rendez-vous dans le fuseau de la leçon (`409 LESSON_NOT_TODAY`). Un départ tardif reste accepté : une commande mise en file hors ligne peut arriver après le créneau. Cela remplace le comportement d’origine, où un départ anticipé était voulu (ancien test « un départ réel anticipé se termine »). La limite de 30 minutes après la fin reste propre à l’app.
- **Élève en avance** : on ne commence pas la veille ; on déplace la leçon.
- **Identifiants d’appareil** : `GET /captures`, `GET /captures/:id` et `GET /lessons/:id/captures` ne renvoient plus `deviceId` ni `deviceAssessmentId` à un lecteur qui n’est ni moniteur ni administrateur. Les réponses au moniteur qui enregistre (départ, arrêt, finalisation) et au personnel sont inchangées : l’app déjà installée chez lui continue de les décoder. Écart assumé avec `CaptureSession` du contrat canonique (livraison de conception non modifiée), consigné ici. **Ordre de déploiement** : l’app de l’élève doit être la version qui accepte ces champs absents (cette PR) avant que l’API soit déployée, sinon la liste de ses trajets ne se lit plus.

## Points ouverts (au porteur)

- **Horaire de départ côté serveur** : `POST /lessons/:id/start` ne contrôle pas l’horaire. Le même contrôle que l’app (jour du rendez-vous) y serait cohérent avec la règle « droits relus au serveur » ; c’est un changement d’API, à décider et déployer.
- **Commencer très en avance** : un élève arrivé la veille ne peut plus être pris sur un rendez-vous du lendemain ; il faut déplacer la leçon. Arbitrage à confirmer.
- **API sans identifiants d’appareil pour l’élève** : possible dès que cette version de l’app est installée.

## Laissés

Dossier élève relu à chaque réapparition (effet à mesurer selon `TabView`) ; barre du haut du trajet reconstruite chaque seconde avec son menu (à vérifier sur appareil avant d’y toucher) ; chargement d’une formation en série (`checkScope` puis formation puis leçons) ; relecture de tout l’historique à la fermeture d’une fiche, même sans écriture.

## Vérification

- IPA d’essai compilée sur chaque lot, sans avertissement Swift.
- Tests ajoutés : règle « commencer / manqué » (`SchoolLessonHubTests`), trajet sans identifiants d’appareil (`SchoolTripsTests`). Parcours UI `lesson-finish` adapté (horaire de la leçon d’essai recalé sur l’heure du runner, libellé « Poursuivre la leçon »).
- Campagne « Refonte · iOS » : 455 tests métier passent (dont les deux nouveaux). Parcours UI : tous passent sur iPhone et iPad sauf `NativeNavigationTests.testOpeningALearnerShowsItsProfileThenLessonsAndProgressionInPlace`, qui cherchait « Avec accompagnement » alors que la Progression de la passe précédente l’écrit en minuscule dans « Où j’en suis » (dérive jamais rejouée depuis `941ea06`). Assertion corrigée puis suite relancée seule : il passe sur iPhone et iPad. Dans cette relance, `testObservationListShowsEachStatusWithoutGPS` a échoué sur un appareil au lancement de l’app (« Failed to get background assertion », incident du simulateur) ; il passe sur l’autre, et sur les deux dans la campagne complète.
- Une première exécution n’avait pas compilé la cible de tests : quatre lignes de fixtures lisaient `deviceId` comme non optionnel. Corrigé.
- Rien n’a été vu tourner sur iPhone : ni les nouveaux boutons, ni VoiceOver, ni Réduire les animations.
- Aucune modification d’API, aucun déploiement.
