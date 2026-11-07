# Check-up des issues — 7 novembre 2026

Mandat : examiner les issues restantes et réaliser leurs correctifs de bout en bout
avec le skill orchestre-go. Branche de travail :
`tomyrms/issues-manquantes-orchestre-go`. Base locale et master distant vérifiés :
`2a801eaf6930976760b79372c75b3fa04efd1796`.

## Inventaire initial

GitHub renvoie **39 issues ouvertes**, dont 30 anomalies d’audit #421–#450
et neuf sujets antérieurs. Aucune PR ouverte. Une issue ouverte n’est pas
assimilée à une absence totale d’implémentation : les correctifs intégrés et
preuves des 4–5 novembre sont conservés. La modification préexistante de
`package-lock.json` (30 lignes retirées) est laissée intacte et hors commits.

Le dossier de conception est une référence conservée. Il ne justifie pas
d’étendre ce mandat à Android ou aux options explicitement différées.
Aucun nouveau défaut vérifié hors backlog n’est encore établi.

## Lots et ordre de réalisation

| Lot | Issues | Résultat attendu | État |
|---|---|---|---|
| A · Planning API | #423, #424, #439, #444, #446 | Congés/réservations cohérents, conditions conservées, replanification atomique, examens traitables et rangs exacts | 2878e141 + b0215d88 relus, non intégrés ; retour 1/2 #423/#424 en cours, ctx_ec6c6bd171dc |
| B · Confidentialité iOS | #425, #426 | Annotations revalidées, données et actions purgées sur refus d’accès | Intégré ; compilation Apple et 264 tests ciblés réussis sur 3d213e7c ; limites UI conservées |
| C · Identité et portraits | #421, #450 | Versions cohérentes inter-écoles et générations de photos monotones ; API puis lecteurs clients coordonnés | Serveur en cours avec Sonnet, contrat client à coordonner |
| D · Reprise web et finances | #422, #430, #432, #433, #434, #437, #442, #443 | Saisies conservées, conflits explicites, historique financier accessible, créations rapprochées sans doublon | b283b4bd relu ; retour correctif 1/2 et trois issues web complémentaires, ctx_302dba84258e |
| E · Intentions natives | #427, #431, #438 | Reprise atomique sans verrou fantôme ni écrasement concurrent | 7a4d70b4 relu, non compilé/non intégré ; retour 1/2 #431/#438, ctx_b8241b8cfecb |
| F · Messagerie et clés | #428, #435, #436, #440 | File récupérable, sauvegarde restaurable, clés à usage unique non redistribuées | À réaliser ; coordonner avec les travaux existants |
| G · Notifications serveur et appareil | #429, #441, #445, #448 | Identités distinctes, reprises par appareil, révocation et réception active cohérentes | À réaliser |
| H · Boîtes natives | #447, #449 | Listes complètes et actualisation cohérente | À réaliser |
| I · Restes antérieurs | #37, #50, #65, #68, #78, #97, #105, #106, #131 | Réutiliser les lots existants, compléter code et preuves manquantes, distinguer contraintes externes | À rapprocher des critères et commentaires actuels |

Les lots A et B sont indépendants : deux workers isolés suffisent pour commencer.
Le routage initial était OpenCode Go pour A et Codex GPT-6-Astra pour B.
Après l’erreur `Go usage limit exceeded`, le porteur a demandé explicitement
Claude Sonnet 5.5 pour les tâches restantes. Le routage est donc remplacé par
`--agent claude --model claude-sonnet-5-5 --effort medium`, pour le backend
comme pour l’UI. Cette instruction utilisateur prime sur le routage du skill.
Les mêmes tâches, branches et worktrees sont réutilisés ; aucun fichier produit
n’avait encore été modifié. Le budget de reprises par problème reste inchangé ;
l’échec de quota n’est pas un échec de correction produit.

Run de cette session : `run_c89bc7c0cfbd`. Lot A : `task_c79eb56f8380`,
premier dispatch `ctx_2805e5e51a0e` arrêté après quota. Lot B :
`task_9be193226778`, premier dispatch `ctx_67dee16934c1` arrêté pour le
changement de modèle demandé. Les deux arrêts sont confirmés par Orca
(`state: stopped`, `processAction: closed_agent_terminal`).

## Travaux préexistants à réutiliser

Le worktree `integration-issues-20261105` à `6c1f8957` comporte des compléments
de signalement média et de qualification absents de la base actuelle. Trois
dispatchs de l’ancien run `run_3634d37dc612` sont encore inscrits ready :
`ctx_c430fa0c16e6`, `ctx_7aad80e17c5e`, `ctx_2af50fda2427`.
La liste indique une liveness non vérifiable ; cela ne prouve pas leur arrêt.
Aucune reprise, suppression ou modification de ces espaces n’a été faite.
Leur état, leurs sources et leurs preuves seront rapprochés avant d’attribuer
les lots I/F qui pourraient les recouvrir.

## Validation et limites initiales

- Node système 26 hors cible ; Node 24.22.2 portable déjà présent sera utilisé.
- Docker Desktop installé mais moteur indisponible au premier contrôle ; démarrage
  demandé pour les tests PostgreSQL synthétiques isolés. Disponibilité à confirmer.
- Aucun outil Apple local. Compilation et tests Swift/UI ciblés sur GitHub Actions,
  conformément au mandat ; aucune substitution par une seule lecture statique.
- Codebase Memory disponible, sans index correspondant au nouveau worktree ;
  recherche dans les sources et tests pour ce préflight.
- Qualification ciblée par lot, puis candidat intégré stable. Aucun succès
  physique GPS/batterie/VoiceOver/APNs ni résidence suisse déduit des simulateurs.
- Les critères qui exigent un appareil, une décision de conservation ou une preuve
  d’exploitation restent ouverts jusqu’à preuve. Aucun déploiement public implicite ;
  toute bascule homelab autorisée reste précédée d’une sauvegarde.
- Aucun correctif, test, clôture d’issue ou déploiement revendiqué à ce stade.

Le coordinateur est l’unique auteur de STATUS.md et de ce suivi transversal.
Les workers livrent leurs preuves dans leur rapport de lot.

## Première revue du lot B

Sonnet A : `ctx_c87ad04aa597`. Sonnet B : `ctx_73ee36443ecc`.
Le lot B livre `9dc90566` et rapporte 25 tests du sélecteur Python réussis,
mais Swift non compilé/non exécuté. Revue groupée : deux chemins résiduels
retournés au même worker, dispatch `ctx_939b65ae1a39` :
lecture tardive de loadCandidates après révocation (#426), et feuille
reading du texte intégral non réconciliée après retrait/correction (#425).
Premier retour correctif sur chacun, aucun succès produit revendiqué.
Les chemins des skills UI existants ont été fournis ; le rapport initial les
disait à tort absents. Validation Apple prévue sur le delta stable.

Le lot D peut démarrer en parallèle : son périmètre web est indépendant
des fichiers API de A et Swift de B, ce qui justifie un troisième worker.

## Intégration B et validation Apple

Le delta `8d6c00fc` ferme les deux chemins retournés ; diff relu,
`git diff --check` réussi. Fusion sans conflit en `3d213e7c46500e46a35abd4a49ec2125fe9d7cad`,
identité de tous les blobs apps/scripts avec le worker vérifiée.
Branche de travail poussée ; master et exploitation inchangés.

- GPS/replay : [run 42395051487](https://github.com/tomyrms/Drivy/actions/runs/42395051487).
- Agenda/cours : [run 42395055092](https://github.com/tomyrms/Drivy/actions/runs/42395055092).

Les deux runs ont terminé avec succès au SHA intégré : compilation et
**146 tests dans 11 suites** pour GPS/replay, **118 tests dans 7 suites** pour
agenda/cours. Résultats collectés par le worker et succès des jobs vérifiés
par le coordinateur via GitHub. Les trois nouvelles régressions de replay et
les onze de révocation sont réussies, sans test ignoré. Rapport `f1eb696a`
intégré en `82e1d651` ; pas de relance. La réconciliation du texte intégral
conserve sa limite : pas de test UI de `@State reading`, preuve par sa fonction
et son raccord. Aucune recette physique, GPS ou VoiceOver déduite de ces tests.

Un quatrième lot peut avancer sans conflit pendant cette qualification :
C ne touche que les profils/portraits API, A possède le planning, D le web
et B le client Swift. Les migrations nouvelles restent propres à chaque lot.

## Première revue du lot D

Livraison `b283b4bd`, non intégrée. Typages et build réussis selon le rapport ;
43 tests ciblés réussis. La suite web complète termine en **échec** : 903 tests
réussis, deux tests pending-recovery-106 bloqués au lancement du navigateur.
Le contrôle Chromium synthétique de #432/#433 passe ; le contrôle sur les
sources d'origine s'arrête à #433 et ne prouve donc pas le RED de #432.

Deux chemins d'écrasement résiduels relevés dans la revue de #422 : résolution
d'un conflit d'horaires à partir d'une saisie devenue périmée pendant l'alerte,
et reprise d'une intention refusée sans sa base d'origine (#430 également).
Retour groupé 1/2 au même worker Sonnet, `ctx_302dba84258e` : correction,
preuves sur les vrais composants/hooks et contrôles navigateur manquants
de #422/#430/#434. Réutilisation d'Edge et adaptation minimale du harnais
autorisées pour exécuter les deux tests bloqués ; aucune nouvelle campagne
complète demandée. Aucun succès global ni clôture d'issue déduit de la livraison.

## Périmètres corrigés et suite après B

La lecture des chemins sources corrige le classement initial : #437/#442/#443
sont web et rejoignent D ; #446 est API et rejoint A, propriétaire de exams.ts.
#445 rejoint les notifications G pour garder un seul auteur de SchoolPushCenter.
Il reste bien trente anomalies réparties, sans doublon. Ces ajouts ne sont pas
des retours correctifs et ne remettent aucun compteur existant à zéro.

Le même worker Sonnet de B reprend E dans son checkout conservé, sur les trois
problèmes iOS #427/#431/#438 : barrière après refus, rejeu exact après relance,
remplacement atomique du coffre réel. Il possède temporairement les sources
Swift et la sélection des tests ; les trois autres workers possèdent planning
API, identité API et web. Les nouvelles preuves Apple seront demandées sur
le candidat stable, sans rejouer les campagnes B pour de simples documents.

## Première revue du lot A et raccords clients

Livraison serveur `2878e141` : typage/build réussis, seize tests ciblés
PostgreSQL réussis après reproduction des quatre défauts. Suite API complète
en **échec** : 1 073 réussis, un ignoré, deux échecs g1c avec Mailpit absent.
Rejeu ciblé des deux échecs demandé avec un Mailpit synthétique isolé, image
déjà verrouillée ; aucune campagne complète supplémentaire demandée.

Revue groupée retournée au même worker (`ctx_ec6c6bd171dc`), premier retour
correctif pour #423 et #424 : la lecture directe des congés sous RLS peut
ignorer ceux d'un collègue pour un moniteur pourtant autorisé à gérer le
cours ou l'examen ; l'égalité par JSON.stringify des règles d'annulation
dépend de l'ordre des clés JSONB/Zod. Régressions demandées avec vraies
identités non admin, véritable aller-retour sans changement et conservation
de l'échéance lors d'une nouvelle inscription au programme révisé.

Pour #444, l'option de l'issue qui garde les examens existants corrigeables
après transition est retenue ; aucune réactivation administrative exigée,
création de nouvel examen toujours soumise à une formation active.
Les raccords web sont confiés au propriétaire D : règles structurées,
actions d'examen actuellement masquées par le statut ACTIVE, engagements
restants visibles et messages de refus. Le propriétaire E vérifie les
consommateurs Swift existants et leurs messages, sans créer d'administration
dans l'app. Le contrat et la couverture des issues A restent transversaux ;
la livraison API seule ne termine pas ces parcours.

Complément #446 livré en `b0215d88` et delta relu : rang groupé par formation
et type d'épreuve, reports sans numéro, ordre date/création/id conservé.
Régression PostgreSQL rouge puis verte rapportée : seize tests examens
réussis, seize tests planning encore réussis et typage réussi. Pas de
campagne globale répétée. Ce delta attend l'intégration du lot A corrigé ;
il n'annule ni le retour #423/#424 ni les deux échecs SMTP à requalifier.

## Première revue du lot E

Livraison `7a4d70b4`, Swift **NON COMPILÉ / NON EXÉCUTÉ**. Les 25 tests
Python de sélection passent. Les suites préparées sont agenda (exactitude
et coffre), reports (barrière de leçon) et reactivity (outbox commune).
La correction principale de #427 existait déjà en `8271c206` ; ce lot ajoute
deux relectures de barrière et sélectionne les régressions déjà présentes.

Retour groupé 1/2 #431/#438 au même worker, `ctx_b8241b8cfecb` : substitution
d'une ancienne intention absente actuellement acceptée malgré le test qui
l'interdit ; absence de parcours conservant une saisie bloquée pour une
réconciliation explicite ; abandon annoncé malgré un éventuel échec de
suppression du coffre. L'oracle du serveur simulé doit vérifier l'identité
canonique réelle incluant la version, sans dépendre de l'ordre d'encodage JSON.
Raccord Swift A également rappelé. Aucun run Apple lancé sur ce candidat
connu incomplet ; compilation et contrôles ciblés prévus dès le delta stable.

Le coordinateur a vérifié dans les sources API que schoolCommand traite
le reçu/hash après autorisation mais avant work/checkVersion, et que
PUT course-series et publish suivent ce chemin. Le test API existant couvre
le rejeu publish ; ceci n'est pas présenté comme une nouvelle exécution.
