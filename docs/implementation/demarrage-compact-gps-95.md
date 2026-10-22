# Démarrage compact et choix GPS réutilisé (#95), 22 octobre 2026

## Constat (lecture du code, avant correction)

- Quand un choix GPS valide existait, `SchoolRecordingChoiceInline` n'affichait pas la question : il passait en `.answered` (ligne « Accord GPS / Avec ou Sans GPS / Modifier »). La question ne revient que si `validAnswer == nil` (absence de choix, statut `UNKNOWN`, notice changée). `SchoolStartNowGPS.commit()` n'écrit que si la sélection locale diffère du choix enregistré : aucune écriture à la simple ouverture.
- La lecture du choix général de l'élève (`GET /learners/{id}/recording-choice` sans `lessonId`) passe par `capture_effective_choice` : un choix saisi par l'élève sur son compte ou par le moniteur est retrouvé de la même façon, sur n'importe quel appareil, les refus `SELF` restant prioritaires. Aucun défaut de lecture n'a été trouvé : pas de correction de lecture, pas de changement d'API, d'OpenAPI ni de base.
- Ce qui pesait : `gpsSection` était toujours rendu dans une carte (donc un bloc « Accord GPS » à chaque départ) et la feuille imposait `.presentationDetents([.large])`.

## Décisions

### Modèle d'affichage du choix (`SchoolStartNowGPS.Display`)

Un état pur et testé, `reading / unavailable / needsReview / question / known(statut)`. Seul `known` allège la présentation.

- Chargement ou panne de lecture : `reading` / `unavailable`, jamais `question` ni `known`. Le départ attend (`isReading`) tant que la lecture est en cours ou doit être refaite (`needsReload`).
- `consentIsClear` exige désormais `!needsReload` : une relecture échouée ne laisse plus un ancien choix valoir pour démarrer un trajet.
- Retour d'arrière-plan : `refreshConsent()` relit le choix (choix modifié ailleurs, retrait). Aucune écriture, aucune collecte. Une lecture interrompue reprend (`readWasInterrupted`).
- Changement rapide d'élève : `prepareGPS` ferme le modèle précédent (`invalidate`, génération incrémentée, donc réponse tardive ignorée). Le bouton de départ exige en plus `gps.learnerID == form.learnerID` (`gpsMatchesLearner`).
- Pas de second stockage : mêmes `SchoolRecordingChoiceWorkspace`, file chiffrée, notice versionnée, refus protégé, exceptions par leçon. Le choix lu ici est le choix général, jamais recopié vers une autre école ni converti depuis un accord de leçon.

### Présentation du choix connu

- Avec GPS ou Sans GPS valide : ni cartes, ni panneau. Le bouton annonce « Démarrer avec GPS » ou « Démarrer sans GPS ». Reste un bouton texte discret « Modifier le choix GPS » (`start-now-gps-change`), désactivé pendant une commande.
- « Modifier » rouvre la question (`isChanging`), sans écrire. La réponse reste locale jusqu'à « Démarrer » (sémantique inchangée). Rechoisir la même réponse referme la question.
- Permission iOS refusée ou position approximative : message et « Ouvrir Réglages » conservés pour un accord Avec GPS. Module indisponible : `SchoolGPSUnavailableNotice` inchangée.
- Question complète (absence, notice changée, demande à vérifier) : `SchoolRecordingChoiceInline` inchangé, dans un bloc, sans présélection.
- Panne de lecture : message et « Réessayer ». Le départ sans GPS reste proposé par le bouton.

### Carte flottante (`DrivyFloatingCard`)

- `SchoolStartNowSheets` présente le parcours en `fullScreenCover` à fond transparent (`presentationBackground(.clear)`). Le récapitulatif est une carte centrée, fond flouté à la demande du porteur (22 octobre 2026 : matériau `.ultraThinMaterial` et voile noir 15 %), largeur au plus `compactColumn`, hauteur au contenu (`DrivyFittingScrollLayout`), plafonnée à la zone sûre moins des marges, avec défilement au-delà.
- En-tête (titre, « Fermer ») et bouton de départ restent hors du défilement. Aux tailles d'accessibilité, le bouton rejoint le défilement pour ne jamais être coupé. Le fond ne ferme pas la carte (aucune saisie perdue par un geste de travers).
- Recherche d'élève et fiche leçon restent en plein écran (`NavigationStack` à fond opaque dans la même présentation). Ouverture depuis un dossier élève : récapitulatif direct (`presetLearnerID`, inchangé).
- Une seule présentation pour tout le parcours : lieu et formation (état de `SchoolStartNowWorkspace`) sont conservés entre recherche et récapitulatif, sans rechargement ni second `load()` (optimisations #86 intactes). Transitions en fondu sous Réduire les animations.
- #87 : `isBusy` désactive « Fermer » et le choix GPS, les protections de `launch()`/`run()`/`DrivyPendingRequest` sont inchangées. Le retrait de `interactiveDismissDisabled` de la feuille s'explique par le passage en `fullScreenCover` (pas de geste de fermeture) ; la fiche leçon garde sa propre protection (bilan modifié).
- Planification d'une leçon : fichier et feuille inchangés.

### Écran de contrôle

`start-now-gps-known` (DEBUG, simulateur) : choix général `ALLOWED` valide dans le transport synthétique. Ajouté à `capture-screens.sh`.

## Tests (rattachés à #84)

- `SchoolStartNowConsentTests` (Swift Testing, transport synthétique, journal chiffré temporaire) : accord réutilisé sans écriture, refus mémorisé, absence, `UNKNOWN`, notice changée, lecture lente, panne, relecture échouée, choix modifié ailleurs, changement d'avis sans écriture avant le départ, refus protégé, permission refusée/approximative, réponse tardive d'un élève précédent.
- UI : `FieldFlowTests.testAKnownGPSChoiceIsReusedInACompactCardWithoutTheQuestion`. Les tests UI existants du démarrage (`start-now-gps-permission`, `start-now-gps-disabled`) restent la référence pour la première demande et le GPS indisponible.

## Reste à qualifier

- Exécution Apple des tests unitaires et UI (runner), captures iPhone/iPad/paysage/grands textes de la carte.
- Sur appareil : rendu de la carte flottante, clavier, VoiceOver (ordre de lecture, focus à l'ouverture de la carte), Réduire les animations, iPad redimensionné, GPS réel. Rien de cela n'est déduit du simulateur.
- Critères inter-appareils (« autre appareil ») : vérifiés par le contrat serveur existant (choix effectif lu par école et élève), pas par un essai sur deux appareils.
