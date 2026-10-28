# Accueil GPS, bilan et aide native — S16, S20–S22

Réalisation du 28 octobre 2026 sur `codex/simplification-253`, après intégration des parcours #111/#114. Références : #268, #272, #273, #274, `AGENTS.md`, `DESIGN.md`, `docs/implementation/DESIGN.md`, F21/R76/R81, R46, T175–T191 et décisions du 28 septembre. Les références de conception livrées restent intactes. La décision récente de #253 gouverne le départ GPS ; sa mise en service réelle reste soumise à #266/#267 et aux contrôles de départ S17–S19.

## Ce qui change

**S16.** L’étape GPS de `SchoolOnboardingView` utilise `SchoolOwnRecordingChoice` et son `SchoolRecordingChoiceWorkspace` : mêmes API, portée personne/école et notice versionnée, même journal chiffré et mêmes reprises que Profil. Un choix applicable déjà enregistré se lit sans poser à nouveau la question. Le résumé distingue réponse confirmée, absence de décision, lecture en cours, écriture en cours et demande incertaine. « Décider plus tard »/Continuer n’écrit aucun choix GPS ; un refus et une absence de choix ne bloquent pas l’accueil. Aucune permission de position n’est demandée à l’élève. Les textes promettant une nouvelle leçon sans trajet ont été retirés de cet accueil. `SchoolRootView` injecte le client existant ; Mon profil le propage lors de la reprise.

**S21.** Le bilan en trois étapes, la proposition de travail réalisé issue des objectifs, les observations déjà conservées, la visibilité élève, la note privée, les commandes versionnées et le brouillon protégé existaient déjà. Seul manque traité ici : les compétences explicitement reliées à une évaluation, une observation ou un objectif de cette leçon apparaissent d’abord ; les autres restent disponibles dans un groupe natif dépliable. L’ordre et les objets du programme historique autorisé restent inchangés dans chaque groupe. Les groupes restent stables durant la saisie pour qu’une ligne ne se déplace pas à la sélection. Une observation qualifiée par thème sans identifiant de compétence ne crée aucun rapprochement automatique. Aucun niveau n’est déduit, aucun texte n’est obligatoire.

**S22.** Paramètres ouvre une page Aide native commune, avec des explications dépliables adaptées aux rôles. Le contact ouvre seulement une adresse e-mail utilisable réellement configurée dans l’école courante. L’absence de contact et l’échec d’ouverture de la messagerie sont nommés ; aucun ticket/message/délai n’est annoncé. Le diagnostic affiché contient seulement version publique de Drivy, build et nom/version du système. Copier exige un geste explicite ; aucun compte, nom d’appareil, école, identifiant, conversation, jeton, clé ou position n’est lu ou ajouté à ce diagnostic.

**Revue du départ et du replay.** Le démarrage immédiat lit aussi la politique de départ sans module GPS ni contrôleur disponible. Une lecture échouée ou une valeur inconnue bloque le nouveau départ avec reprise ; la réponse valide d’un ancien serveur sans `practicalStartPolicy` conserve explicitement `LEGACY`, pour que l’IPA reste compatible avec le homelab non redéployé. `GPS_REQUIRED` exige le contrôleur disponible et le choix personnel applicable. Les demandes déjà journalisées gardent leur résolution sans nouveau départ automatique. Le détail du replay indique « Position de l’appareil du moniteur » seulement après lecture de la capture scolaire : la création serveur lie cette capture à l’affectation du moniteur et au diagnostic de son appareil. Le message hors créneau renvoie à la modification du rendez-vous dans l’agenda ; la fenêtre serveur n’est pas modifiée ici.

## Réutilisation S20 et direction native

`SchoolCaptureLiveView` fournit déjà la carte réelle, l’état issu du contrôleur, les signalements locaux, Pause/Terminer, les présentations compactes/larges/grand texte et les mentions de carte. Il n’est pas réécrit dans cette tranche. Les protections du contrôleur et de la synchronisation ne changent pas ici.

Choix de composants : composants Drivy existants (`SchoolOwnRecordingChoice`, `DrivyFormMessage`, rangées et squelettes), puis `NavigationLink`, `List`, `DisclosureGroup` et `LabeledContent` Apple. Couleurs `DrivyTheme`, marges `DrivySpacing`, colonne `DrivyLayout.formColumn`, titres système et texte dynamique suivent les paramètres et le bilan existants. La hiérarchie reste Cartographie native/La trace et Soft Charcoal ; aucun package ou token ajouté. Le skill `swift-native-components` a servi à cette sélection, sans bibliothèque externe.

## Vérifications réalisées et préparées

Lecture des règles/scénarios, des composants, des points d’entrée et revue du diff ; `git diff --check` ciblé sans erreur. Aucun test Swift/UI exécuté, aucune compilation Apple, capture comparative ou mesure physique réalisée dans cette sous-tâche Windows. L’agent principal prépare ensuite l’IPA sur GitHub Actions.

Tests préparés, non exécutés :

- `SchoolOnboardingRecordingSummaryTests` : aucun accord/refus anticipé pendant lecture, envoi ou incertitude ; absence de choix distincte.
- `SchoolReportCompetencyGroupsTests` : couverture exacte du programme autorisé, ordre et version historiques, absence de compétence inventée, liens explicites seulement.
- `SchoolHelpTests` : contact absent/mal formé/plusieurs destinataires/paramètres de message refusés ; copie limitée aux métadonnées de l’aperçu.
- `SchoolStartNowLaunchTests` : lecture `GPS_REQUIRED` sans contrôleur, valeur inconnue bloquante, panne de relecture supprimant la permission précédente et reprise réussie, compatibilité de l’ancienne notice sans champ de politique.

Recette à exécuter après compilation et essai utilisateur :

1. Élève sans choix : notice de son école, deux choix de même poids, pas de permission OS, accueil terminable sans décision.
2. Accord/refus confirmé : retour/reprise sans nouvelle sollicitation ; passage à une autre école sans reprendre le choix précédent ; modification de notice demandant seulement une nouvelle lecture/choix applicable.
3. Réponse GPS perdue, journal indisponible, reprise, retrait : aucune acceptation/refus inventé, demande à vérifier conservée, autres accès disponibles ; aucun départ pratique admis hors des préconditions serveur qualifiées.
4. Bilan avec/sans observation liée, objectifs liés ou libres, ancien programme, trace partielle, aucune nouvelle note : retrouver les données, choisir une autre compétence depuis le groupe, terminer sans ressaisie et lire uniquement les éléments autorisés côté élève.
5. Paramètres élève/moniteur/administration : Aide avec bon vocabulaire de navigation ; contact configuré/absent/invalide ; ouverture sans messagerie ; diagnostic exact après action Copier et aucune copie à l’ouverture.
6. iPhone/iPad, rotation, clavier, grands textes, clair/sombre et VoiceOver sur appareil : commandes atteignables, groupes dépliables et ordre de lecture. Comparaison avant/après de la séance sur mêmes données synthétiques. Les résultats GPS/batterie/VoiceOver physiques restent **non qualifiés**.
