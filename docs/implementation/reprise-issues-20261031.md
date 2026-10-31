# Reprise des issues du 31 octobre 2026

Document de reprise : ce qu'il faut savoir pour continuer si la session est coupée. Écrit le 31 octobre 2026 sur `claude/tests-83-78`. `master` est à `2a376c39` ; **rien n'est déployé, aucune IPA n'a été livrée, aucune nouvelle issue n'a été créée.** Le tri détaillé de départ est dans `.local/triage-20261031/` du clone principal (non versionné).

## Consignes qui s'appliquent

- Aucun déploiement homelab, aucune « IPA d'essai · iLoader ». Pour vérifier du Swift, passer par « Refonte · iOS » en mode ciblé (`unit_only` avec `unit_test_scope`, ou `ui_test_suite`), **jamais** la campagne sans paramètre : elle se termine par `Construire l'IPA pour iLoader`.
- Commits additifs seulement : pas de force-push, pas de `reset --soft` suivi de `add -A`, pas de `--no-verify`. Aucune clé GPG sur la machine.
- Un test n'est vert que si le run est conclu et lu. Aucune preuve physique (GPS, APNs reçu, VoiceOver, batterie) n'est affirmée.
- Fusionner uniquement #337, #338, #339, dans cet ordre, et seulement quand les tests métier ET les parcours UI sont verts sur la même tête de #339. Les autres PR sont ouvertes, jamais fusionnées par cette reprise.

## Les branches

| Branche | Contenu | État au moment de l'écriture |
| --- | --- | --- |
| `codex/ios-batch-15-20261029` (PR #339, empilée sur #338 puis #337) | Candidat iOS : agenda, brouillons protégés, 15 tickets | Tête `80efe4d1`. Tests métier verts (run 41223726701). Parcours UI ciblé relancé (run 41229249440), voir « Décision de fusion » |
| `claude/pilotage-373` (PR #385) | #374 dictionnaire, #375 agrégations API/BFF et export CSV | Terminé et vert (« Refonte · vérifications » run 41224457783 sur `36cc69ef`) |
| `claude/messagerie-74` | #74 alertes de messages, préférences, ouverture depuis une alerte | Terminé, vert (runs 41200814594 et 41200806812 sur `051a2d37`) |
| `claude/messagerie-77` | #77 signalements chiffrés, boîte des administrateurs | API verte (run 41225134866), tests métier iPhone `all` verts sur `27b34483` (run 41227477381). Qualification bout en bout jamais faite |
| `claude/tests-83-78` (cette branche) | #83 tests de cours, #78 test MSG-17, #73 test UI du sondage, matrices de suivi | Voir ci-dessous |
| `claude/lot-web-20261031` (PR #386) | #251 libellé du motif d'absence | Terminé et vert (run 41203027890) |

Les branches #74, #77 et tests sont empilées sur le candidat #339 (elles partent de `1bc67ae1`, avant ses deux derniers commits).

PR ouvertes à 19 h UTC, aucune fusionnée : #385 (pilotage, base `master`), #386 (motif d'absence #251, base `master`), #387 (#74, base `codex/ios-batch-15-20261029`), #388 (#77, base `claude/messagerie-74`). Pas encore de PR pour `claude/tests-83-78` : elle attend le correctif de sélecteur du candidat (`a1a3529a`) pour être verte ; une fois le candidat fusionné, fusionner `master` dans la branche (commit additif), relancer `ui_test_suite=MessagingFeatureCheckUITests`, puis ouvrir la PR vers `master`. Quand #337 à #339 sont fusionnées, changer la base de #387 en `master` (et celle de #388 quand #387 l'est).

## Ce qui a été fait sur `claude/tests-83-78`

- **#83** : cinq fichiers de tests API de cours (concurrence, fuseau et changement d'heure, push en échec, effets d'une validation, absence de paiement en ligne) et un fichier de tests web. Verts dans « Refonte · vérifications » sur `c71fbd06` (run 41201921118). Matrice `docs/qa/cours-collectifs-tracabilite.md` mise à jour : 59 critères, 19 PASS, 34 PARTIAL, 6 NOT_COVERED, complément daté en fin de fichier.
- **#78** : `MessagingLessonIndependenceTests` (MSG-17, panne ou file pleine de la messagerie, départ, arrêt et « Signaler » continuent), vert dans les tests métier iPhone `all` sur `c71fbd06` (run 41201923959). Matrice `docs/qa/messaging-78-20261023.md` : les 18 états relevés sur ce qui a réellement tourné, relevé daté en fin de fichier.
- **#73** : test UI du sondage (vote, changement de choix, clôture). L'échec du run 41202131542 avait deux causes : un cadre `{inf, inf}` interrogé pour sa « hittability » avant que la ligne soit posée, et un contrôle de `isEnabled` que ces lignes n'exposent pas sur le simulateur. Corrigé (`e63868aa`) : `waitFor` n'interroge la hittability qu'une fois le cadre posé, et le test vérifie le comportement après la clôture (un appui ne crée aucun vote en attente, totaux et choix inchangés). **Le test passe** dans le run 41224876858, sur iPhone et iPad.
- Ce même run reste rouge sur un seul test, `testReactionFromLongPressClosesMenuAndUpdatesCapsule`, sur iPhone et iPad. Ce n'est pas le test du sondage : c'est le sélecteur de la palette de réactions, corrigé sur le candidat par `a1a3529a` (« Réagir : Cœur »), que cette branche n'a pas encore. Elle l'aura dès que le candidat est fusionné dans `master` puis `master` dans cette branche.

## Décision de fusion #337 → #338 → #339

- Premier échec du candidat (run 41202251576, tête `a1a3529a`) : un seul test, `SchoolAgendaUITests.testRefreshFailureRetainsCoursesAndSelectionUntilRetry`, sur iPhone seulement (iPad vert). La hiérarchie finale du run montre l'agenda chargé, sans erreur de cours ni message de dernière lecture : le geste de tirer pour actualiser n'a jamais déclenché la relecture. Cause : sur iPhone la barre de navigation (titre large et champ de recherche) couvre les ordonnées 62 à 228 sur 874 ; le geste partait de 221, donc de la barre. Ce n'était pas un test instable : même échec sur trois têtes successives. Correctif de test seul, `80efe4d1` (le geste part 10 pt sous la barre), aucun code produit modifié.
- Tests métier sur `80efe4d1` : verts (run 41223726701).
- Parcours UI sur `80efe4d1` : run ciblé 41229249440, sept suites (les six du contrôle précédent plus `MessagingLatencyUITests`, modifiée par `a1a3529a`), sans IPA. Une première campagne sans paramètre (run 41223734873) a été annulée parce qu'elle construit une IPA.
- Tant que ce dernier run n'est pas vert, **ne rien fusionner**. S'il est vert : fusionner #337, #338 puis #339 (merge commit, comme pour #384), en vérifiant avant chaque fusion que la base de la PR est bien la branche précédente ou `master`. Puis fusionner `master` dans chaque branche empilée (#74, #77, tests) par un commit additif, et relancer seulement les contrôles ciblés qui vérifient leur propre travail.

## Ce qui reste, par nature

- **#77** : le partage de clé to-device vers un administrateur et le déchiffrement chez lui n'ont jamais été exercés de bout en bout ; aucun parcours d'interface (le signalant confirme, l'administrateur ouvre la boîte) n'est automatisé, la fixture de qualification n'a ni compte administrateur ni signalement. La conservation des preuves attend #68.
- **#74** : aucune alerte APNs réelle reçue sur appareil ; pas de regroupement anti-rafale côté serveur.
- **#375** : le contrat OpenAPI 3.11.0 n'est pas modifié ; le détail des séances de cours et des règlements calcule encore ses libellés par ligne ; aucun objectif de performance n'est déclaré atteint (une école, une machine locale). La migration n'est appliquée sur aucune base de production.
- **#83** : alertes « prochaines sessions » (fonction non livrée), plusieurs places libérées pendant une offre, horloge client fausse, parcours navigateur de bout en bout « série créée sur le web puis inscription » : sans test. Les tests Swift et UI de cours n'ont pas été rejoués dans ce lot.
- **#78** : tout ce qui demande un appareil (VoiceOver, grandes tailles, deux appareils, APNs réel), l'hébergement et la restauration en Suisse (#68), la revue de sécurité indépendante, la campagne finale #84 (après le retour du porteur sur l'IPA 447).
- Hors périmètre et non touchés : reste de l'optimistic UI, pilotage T03 à T09, #52, #54, #50, #43, #44, #99, décisions de #68, #97 et #109, campagnes #55, #84 et #131.

## Pièges rencontrés

- Un heredoc bash a mangé des échappements (`\r\n` écrit comme un vrai saut de ligne) dans un fichier de tests : écrire les fichiers contenant des échappements avec l'outil Write ou Edit, relire avec `cat -A`.
- Les tests de capture n'appliquent que les migrations numérotées : une migration datée n'y change pas le compte de tables à RLS (resté à 67).
- Un test d'export refusé au-delà de 10 000 lignes peut dépasser le délai de 15 s sur le serveur d'intégration si les noms sont calculés ligne par ligne ; le refus se fait maintenant d'après le seul compte.
