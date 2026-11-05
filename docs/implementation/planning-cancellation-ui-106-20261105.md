# U106-L2 — retrait avant transport, planification native

## Préflight du 5 novembre 2026

Travail en attente du checkpoint N106 : aucun raccord ni stub d'admission créé.
Base vérifiée : `bc2c53cbaae6fa719e6203ea77119a753d6780d7`, branche
`tomyrms/issues-annulation-planification-ui-106`, arbre initial propre.
Le runtime `orca orchestration worker-show --dispatch ctx_03e2318e5896 --json --full`
rend `startOptions.launch.effective` = Codex, `gpt-6-astra`, effort `high`.
Le contrat commun de bristleworm `docs/implementation/L2-interface-annulation-native-20261105.md`
a été lu intégralement. Checkpoint consommé : **aucun pour le moment**.

Skills effectivement lus sous `C:/Users/jtoma/.codex/skills/` :

- `systematic-debugging/SKILL.md` : source et cause avant correction.
- `test-driven-development/SKILL.md` et `writing-good-tests.md` : scénarios avant implémentation ; RED/GREEN Apple non exécutés sous Windows, conformément au contrat.
- `verification-before-completion/SKILL.md` : preuves fraîches et limites explicites.
- `impeccable/SKILL.md` (4.8.0), `reference/operate.md` ; contexte exécuté avec le binaire déjà présent `impeccable/scripts/bin/windows-x64/impeccable.exe context --target apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningView.swift` (aucune installation).
- `uncodixfy/SKILL.md` : composants sobres, sans décoration ni nouveau panneau explicatif.
- `ui-skills-root/SKILL.md` : route UI connue ; pas d'installation CLI additionnelle.
- `C:/Users/jtoma/.agents/skills/orchestration/SKILL.md` et `orca-cli/SKILL.md`, puis guides versionnés fournis par Orca.

Impeccable signale PRODUCT absent et autorise cette correction ciblée sur le contexte existant.
DESIGN.md et la source native servent de référence. Les prescriptions CSS/rem, dimensions web,
et interdictions génériques de bleu/rayons d'Uncodixfy ne remplacent pas les tokens Drivy ni
la géométrie système SwiftUI : la spec impose leur conservation. Mode Operate ; Form existante,
styles Dynamic Type, couleurs sémantiques et cible native, sans nouvelle hiérarchie.

Références parcourues : AGENTS, COMMENCER_ICI, DESIGN ; F04/F05, R09–R14,
J02/J04/J05, synchronisation (outbox, matrice de reprise, AP72), rapports de fermeture et
repères de planification du 3 novembre, sources du workspace/vue/client et tests de sortie/reprise.

## Codebase Memory et diagnostic

Index dédié créé avec le chemin absolu de **ce** worktree :
`C-Users-jtoma-orca-workspaces-Drivy-issues-annulation-planification-ui-106`.
Résultat : 53 125 nœuds, 202 936 arêtes ; 963 fichiers exclus, 88 parsings partiels,
4 inutilisables (signalements globaux, pas preuve de couverture exhaustive).
Recherches `SchoolPlanningWorkspace|SchoolPlanningClient|SchoolPlanningView`, puis
`transmit|SchoolCommandOutbox|SchoolPlanningFeedback` ; snippet de `transmit` et trace sortante.
La trace trouve les méthodes locales de confirmation/erreur/relecture ; elle attribue aussi
send/save/remove à des doubles sans rapport : résolution polymorphe non fiable ici, vérifiée
par lecture du source (`SchoolPlanningClient`, `SchoolCommandOutbox`, injection constructeur).

Cause observée statiquement : aucune preuve vivante ni action de retrait dans le workspace ;
`transmit` utilise la génération de chargement et un `defer { isSendingRequest = false }`
inconditionnel. Une annulation réussie permettant un nouveau geste exige de distinguer
les tentatives afin que la fin ancienne ne réécrive ni attente, erreur, brouillon ou confirmation.
`leaveWhileRequestIsSent` ferme volontairement, sans retirer le record ; conserver cette règle.
La section `SchoolPlanningFeedback` du record est le point d'insertion de l'action et de son erreur.

## Scénarios préparés avant raccord

Tests à écrire sur le vrai workspace/client/admission ; seuls token, transport et panne de retrait
sont des frontières contrôlées. Attentes bornées avec échec explicite, valeurs async extraites
avant assertions. Coffre temporaire réel avec clé exclusivement synthétique si utilisé.

| Scénario | Preuve attendue |
|---|---|
| Création et déplacement, token retenu | Retrait durable ; zéro mutation métier ; saisie inchangée ; aucune confirmation/notification |
| /me retenu après jeton | Même résultat ; compter les lectures séparément des mutations |
| Retrait refusé puis réessayé | Record conservé, erreur locale, aucun renvoi silencieux ; retrait suivant possible |
| Transport gagne avant clic | Aucun retrait, aucune annonce d'annulation ; suivi et AP72 maintenus |
| Premier essai échoue avant handOff | Admission vivante conservée ; retrait reste possible |
| Renvoi même opération | IDs, octets, version identiques ; une commande déjà handed ne redevient jamais annulable |
| Réponse perdue | Record et suivi conservés ; aucune confirmation inventée |
| Annulation puis nouveau geste, ancien retour tardif | Nouveau pending/busy/error/sending intacts ; ancien defer inoffensif |
| Reçu puis relecture | Une confirmation et une notification seulement |
| Réouverture d'un ancien record | Aucune admission neuve, donc aucune annulation avant transport prétendue |
| Sortie volontaire pendant envoi | Fermer ne retire rien ; preuve tardive annoncée selon règles existantes |
| Annulation de leçon | Action métier et préparation GPS existantes conservées, sans admission pilote |

## UI et qualification restant à faire

Libellés distincts : « Annuler l'envoi » pour le geste local ; « Annuler la leçon » pour
l'engagement existant. Le retrait échoué reste attaché au record et propose le même retrait,
sans toast global ni fausse annonce d'effacement. Vérifier iPhone/iPad, clair/sombre,
Dynamic Type maximal, clavier, ordre VoiceOver, fermeture, conservation de la saisie.

Le harnais actuel ne fournit pas de retenue déterministe du jeton ou de /me pour la planification.
Point d'injection précis à signaler avant extension : `apps/ios/Drivy/UI/SchoolOfficeVisualReview.swift`,
constructeur `SchoolOfficeVisualModels` (token `SchoolVisualToken`, transport
`SchoolOfficeVisualTransport`, outbox `SchoolOfficeVisualOutbox`, puis `SchoolAgendaClient`
et workspace), ainsi que `SchoolOfficeVisualTransport.send` pour /me.
Ces chemins sont hors périmètre : aucune extension ni fichier UITest prétendant observer
la course n'est créé à ce stade.

`Get-Command swift,xcodebuild -ErrorAction SilentlyContinue` ne trouve aucun exécutable.
Swift, XCTest/Testing, rendu Apple, VoiceOver physique : **NON EXÉCUTÉS** ; aucune capture produite.
Le pilote ne qualifie aucune autre famille de commandes, GPS ou backend.
STATUS reste à la charge de l'intégration : modification explicitement interdite à ce worker.
