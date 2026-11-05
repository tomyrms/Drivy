# U106-L2 — retrait avant transport, planification native

## Préflight du 5 novembre 2026

État initial du préflight : attente du checkpoint N106, sans raccord ni stub.
Le raccord livré après réception est décrit en fin de rapport.
Base vérifiée : `bc2c53cbaae6fa719e6203ea77119a753d6780d7`, branche
`tomyrms/issues-annulation-planification-ui-106`, arbre initial propre.
Le runtime `orca orchestration worker-show --dispatch ctx_03e2318e5896 --json --full`
rend `startOptions.launch.effective` = Codex, `gpt-6-astra`, effort `high`.
Le contrat commun de bristleworm `docs/implementation/L2-interface-annulation-native-20261105.md`
a été lu intégralement. Checkpoint ensuite consommé : **8edb13c0b80fa4e932aa5cdd92483490d1e5f144**, via la livraison finale
**d5c9dee086d5868ac3f8effd4531ff08a63879cf** fusionnée localement sur le préflight `f5a1e76b`.

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


## Livraison après réception N106

Le coordinateur a autorisé l'extension de `apps/ios/Drivy/UI/SchoolOfficeVisualReview.swift`
(message de réponse Orca `msg_8df9e7997a55`) : constructeur et helpers de fixture uniquement.
Aucun fichier N106 n'a été édité ; les cinq fichiers de sa livraison proviennent de la fusion autorisée.

Fichiers U106 modifiés :

- `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningWorkspace.swift` : admission seulement après sauvegarde réussie d'un nouveau create/move ; comparaison de la commande complète pour utiliser la preuve et afficher son erreur ; aucune reconstruction au chargement.
- `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningView.swift` : action « Annuler l’envoi » dans la section de la demande, erreur locale et annonce accessible ; style texte natif existant, sans nouveau panneau ni changement de palette/typo. « Fermer » et « Annuler la leçon » gardent leur sens.
- `apps/ios/DrivyTests/SchoolPlanningCancellation106Tests.swift` : 9 tests, dont une matrice de 4 cas create/move × token/me, écrits avec vrais workspace/client/admission/coffre temporaire et frontières synthétiques.
- `apps/ios/Drivy/UI/SchoolOfficeVisualReview.swift` : source privée de jeton et barrière bornée, scène planning uniquement, sous le garde DEBUG simulateur existant.
- `apps/ios/DrivyUITests/SchoolPlanningCancellationUITests.swift` : 3 scénarios UI (token, /me, retrait refusé puis réessayé en taille maximale), captures seulement lors de leur future exécution.
- Le présent rapport.

Retrait réussi : pending et bloqueur relus après suppression durable, brouillon conservé, aucune ressource,
confirmation ni notification serveur. Retrait refusé : émission fermée, record inchangé, message local,
« Annuler l’envoi » retente le retrait et `canRetry` interdit le renvoi. Admission handed : aucun retrait,
suivi inchangé. Le même objet admission survit à une panne avant transport dans cette instance ; un
workspace restauré n'en reçoit jamais. Les méthodes de reprise existantes restent disponibles selon
leurs règles ; les retours de `verify` sont aussi protégés contre un retrait intervenu pendant leur attente.

Chaque envoi porte une identité de tentative ; retrait et nouveau geste invalident la précédente.
Le callback et le defer anciens ne réécrivent donc pas l'état nouveau. La génération de chargement et
les règles existantes de sortie volontaire/révocation restent distinctes. La fermeture pendant envoi
continue à permettre une notification sur preuve tardive, et ne retire pas l'intention.

Le harnais est activé seulement par `-planning-l2-cancellation-token` ou
`-planning-l2-cancellation-me`, avec l'option `-planning-l2-cancellation-storage-failure`.
Il s'arme dans `outbox.save` au geste, jamais pendant le chargement. La suppression réussie libère
la retenue ; après 25 secondes, la frontière échoue et le retrait ne peut plus passer comme succès.
Lectures /me et mutations sont comptées séparément ; un retrait exige zéro mutation et le nombre
attendu de lectures d'identité. Ce contrôle ne prétend pas mesurer de vrais paquets réseau.
Les tests workspace ont des barrières de 5 secondes et une attente de rendez-vous de 3 secondes,
avec `Issue.record` et erreur explicites à l'échéance ; aucune continuation indéfinie ni assertion async
placée dans une autoclosure.

### Vérifications réellement disponibles

- `git diff --check` puis inspection du diff : exit 0 ; avertissements de normalisation CRLF/LF seulement.
- Impeccable `detect --json` sur workspace/vue : exit 0, `[]`. Détecteur statique, aucune preuve de rendu SwiftUI.
- Nouvelle indexation Codebase Memory de la même racine après raccord : 53 341 nœuds, 204 264 arêtes ; mêmes 88 parsings partiels et 4 inutilisables globaux. Ce n'est pas un compilateur Swift.
- Recherche des assertions await et continuations dans le nouveau test : aucune ; quatre boucles d'attente ont des échéances explicites.
- `Get-Command swift,xcodebuild -ErrorAction SilentlyContinue` : aucun outil trouvé. Tests Swift/UI, compilation, RED/GREEN, rendu et captures : **NON EXÉCUTÉS**. La préparation test-first ne revendique pas un cycle RED/GREEN observé.
- Le `project.yml` inclut déjà les dossiers DrivyTests/DrivyUITests ; aucun changement du projet requis.

### Campagne Apple restante

Exécuter la suite `SchoolPlanningCancellation106Tests`, les suites N106 et les régressions
`SchoolPlanningLeaveWhileSendingTests`, `SchoolPlanningRecovery106Tests`, `SchoolPlanningBookingTests`
et `SchoolPlanningDefaultsTests`, puis la suite UI ajoutée. Faire ensuite la suite native complète
sur le candidat intégré, sans considérer ces seuls scénarios comme une qualification produit.

Préparer iPhone compact et iPad 11 pouces, portrait/paysage, clair/sombre, taille standard et accessibilité
maximale : bouton atteignable dans la section de la demande, aucune troncature, saisie intacte après retrait,
barre Planifier disponible après revalidation du créneau. Avec clavier ouvert, vérifier fermeture protégée
et réédition du lieu. Sur appareil, vérifier l'ordre VoiceOver, les deux libellés français distincts,
l'annonce de l'erreur et le focus après disparition de l'action. Aucune de ces vérifications physiques
n'est annoncée faite. GPS, autres familles de commandes, serveur/PostgreSQL et notification distante
restent hors qualification de ce pilote.

Pas de push, CI, installation, activation, changement de dépendance, de modèle ni de sous-agent.

Commit de raccord : `57179b42885cff02d9595e495ddd61163a7b3832` ; fusion locale N106 : `ac6e0080` ; préflight : `f5a1e76ba9615aa66d61bce128624ead9248c476`. Arbre propre vérifié après le commit de raccord.
