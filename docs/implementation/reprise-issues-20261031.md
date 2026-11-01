# Reprise des issues du 31 octobre 2026

Document de reprise : ce qu'il faut savoir pour continuer si la session est coupée. Mis à jour le 1er novembre 2026, `master` à `6c4f37c3`. **Toutes les PR de ce lot sont fusionnées.** Aucune IPA n'a été livrée et aucune nouvelle issue n'a été créée par ce lot ; le déploiement sur le homelab n'est pas décrit ici. Le tri détaillé de départ est dans `.local/triage-20261031/` du clone principal (non versionné).

## PR fusionnées dans `master`

| PR | Contenu | Fusion |
| --- | --- | --- |
| #337 | iOS : retours de connexion et états de Messages | `d77acb71` |
| #338 | iOS : 19 issues indépendantes | `3199e6a5` |
| #339 | iOS : agenda, brouillons protégés, 15 tickets | `f2664a8a` |
| #385 | Pilotage #373 : dictionnaire (#374) et agrégations API/BFF avec export CSV (#375) | `a35176f8` |
| #386 | Disponibilités : qui voit le motif d'une absence (#251) | `4e4e4944` |
| #387 | Messagerie #74 : alertes de messages, préférences, ouverture depuis une alerte | `5c079a86` |
| #388 | Messagerie #77 : signalements chiffrés pour les administrateurs, boîte de traitement | `30168a65` |
| #389 | Tests de recette #83, #78, #73 et matrices de suivi | `3e0b4283` |
| #390 | CI allégée : mode explicite, iPad sur demande, API et web selon les fichiers | `0974e6f1` |
| #391 | Tests UI instables : agenda et réaction retirée | `6c4f37c3` |

Les fusions sont des merge commits ; les branches sont conservées.

## Consignes qui s'appliquent

- Aucun déploiement homelab sans demande, aucune « IPA d'essai · iLoader » pour vérifier du Swift : passer par « Refonte · iOS » en mode ciblé (`unit_only` avec `unit_test_scope`, ou `ui_test_suite`). Depuis #390, un lancement sans mode choisi est refusé.
- Tester uniquement le nécessaire : jamais de campagne complète, jamais de relance de ce qui est vert. Ne pas modifier `.github/workflows/` quand un autre agent y travaille.
- Commits additifs seulement : pas de force-push, pas de `reset --soft` suivi de `add -A`, pas de `--no-verify`. Aucune clé GPG sur la machine.
- Un test n'est vert que si le run est conclu et lu. Aucune preuve physique (GPS, APNs reçu, VoiceOver, batterie) n'est affirmée.

## Ce qui a été fait

- **#83** : cinq fichiers de tests API de cours (concurrence, fuseau et changement d'heure, push en échec, effets d'une validation, absence de paiement en ligne) et un fichier de tests web. Verts dans « Refonte · vérifications » sur `c71fbd06` (run 41201921118). Matrice `docs/qa/cours-collectifs-tracabilite.md` : 59 critères, 19 PASS, 34 PARTIAL, 6 NOT_COVERED.
- **#78** : `MessagingLessonIndependenceTests` (MSG-17 : panne ou file pleine de la messagerie, départ, arrêt et « Signaler » continuent), vert dans les tests métier iPhone `all` (run 41201923959). Matrice `docs/qa/messaging-78-20261023.md` relevée sur ce qui a réellement tourné.
- **#73** : test UI du sondage (vote, changement de choix, clôture), corrigé puis vert sur iPhone et iPad (run 41224876858) : `waitFor` n'interroge la « hittability » qu'une fois le cadre posé, et le test vérifie le comportement après la clôture plutôt que le trait `isEnabled`, que ces lignes n'exposent pas sur le simulateur. Le test de la réaction (`testReactionFromLongPressClosesMenuAndUpdatesCapsule`) est vert après fusion de `master` (run 41242976214).
- **Fusion #337 à #339** : le premier échec (run 41202251576) était `SchoolAgendaUITests.testRefreshFailureRetainsCoursesAndSelectionUntilRetry` sur iPhone : la barre de navigation (y 62 à 228 sur 874) interceptait le geste parti de y 221 (correctif de test `80efe4d1`). Le test échouait ensuite sur un compte de boutons (la bannière d'erreur repousse la seconde séance sous la barre d'onglets, la liste n'expose pas ce qu'elle n'affiche pas ; `b24f2def`), puis a été repris par #391 (`702865be`). Tests métier verts sur `b24f2def` (run 41234900088) ; deux tests iPad avaient échoué au lancement de l'app (`Timed out while launching application via Xcode`, infrastructure) et sont verts rejoués seuls (run 41240538959). L'iPad des autres suites n'a pas été rejoué sur `b24f2def`.
- **#375** : mesure sur 10 064 leçons réalisées, un index manquant sur les écritures de débit corrigé (carte finance 4,7 s à 86 ms) ; export de plus de 10 000 lignes refusé d'après le seul compte. Détail en section 11 de `docs/implementation/pilotage-373-indicateurs.md`.

## Ce qui reste, par nature

- **#77** : voir `docs/implementation/messaging-reports-77.md`, section « Qualification du 1er novembre ». La conservation des preuves attend #68. Rien ne vaut preuve physique.
- **#74** : aucune alerte APNs réelle reçue sur appareil ; pas de regroupement anti-rafale côté serveur.
- **#375** : le contrat OpenAPI 3.11.0 n'est pas modifié ; le détail des séances de cours et des règlements calcule encore ses libellés par ligne ; aucun objectif de performance n'est déclaré atteint (une école, une machine locale).
- **#83** : alertes « prochaines sessions » (fonction non livrée), plusieurs places libérées pendant une offre, horloge client fausse, parcours navigateur de bout en bout « série créée sur le web puis inscription » : sans test. Les tests Swift et UI de cours n'ont pas été rejoués dans ce lot.
- **#78** : tout ce qui demande un appareil (VoiceOver, grandes tailles, deux appareils, APNs réel), l'hébergement et la restauration en Suisse (#68), la revue de sécurité indépendante, la campagne finale #84.
- Hors périmètre et non touchés : reste de l'optimistic UI, pilotage T03 à T09, #52, #54, #50, #43, #44, #99, décisions de #68, #97 et #109, campagnes #55, #84 et #131.

## Pièges rencontrés

- Un heredoc bash a mangé des échappements (`\r\n` écrit comme un vrai saut de ligne, `\` de fin de ligne retiré) : écrire les fichiers contenant des échappements avec l'outil Write ou Edit, relire avec `cat -A`.
- Les tests de capture n'appliquent que les migrations numérotées : une migration datée n'y change pas le compte de tables à RLS (resté à 67).
- Un test d'export refusé au-delà de 10 000 lignes peut dépasser le délai de 15 s sur le serveur d'intégration si les noms sont calculés ligne par ligne ; le refus se fait maintenant d'après le seul compte.
- Un identifiant d'appareil de messagerie est propre à une personne : un autre compte qui le réutilise obtient sa propre file, jamais celle du premier.
