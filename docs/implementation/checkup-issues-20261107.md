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
| A · Planning API | #423, #424, #439, #444 | Congés/réservations cohérents, conditions conservées, replanification atomique, examens traitables | En cours, Sonnet |
| B · Confidentialité iOS | #425, #426 | Annotations revalidées, données et actions purgées sur refus d’accès | 8d6c00fc relu et intégré en 3d213e7c ; CI Apple en cours |
| C · Identité et portraits | #421, #450 | Versions cohérentes inter-écoles et générations de photos monotones ; API puis lecteurs clients coordonnés | Serveur préparé pour Sonnet, contrat client à coordonner |
| D · Reprise web et finances | #422, #430, #432, #433, #434 | Saisies conservées, conflits explicites, historique financier accessible | En cours avec Sonnet, ctx_fd98c5c7c86d |
| E · Intentions natives | #427, #431, #437, #438, #442, #443 | Reprise atomique sans verrou fantôme, doublon ni écrasement concurrent | À réaliser |
| F · Messagerie et clés | #428, #435, #436, #440 | File récupérable, sauvegarde restaurable, clés à usage unique non redistribuées | À réaliser ; coordonner avec les travaux existants |
| G · Notifications serveur | #429, #441, #448 | Identités distinctes et reprises par appareil, révocation cohérente | À réaliser |
| H · Boîtes natives | #445, #446, #447, #449 | Nouveau message chargé, comptes exacts, listes complètes et actualisation cohérente | À réaliser |
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

Les deux runs sont observés en cours au SHA intégré ; aucun résultat Apple
n’est encore acquis. La réconciliation du texte intégral n’a pas encore
de preuve UI ; la régression actuelle vérifie sa fonction et son raccord.
Le worker B reprend la collecte de ses preuves sur ces runs, sans les dupliquer.

Un quatrième lot peut avancer sans conflit pendant cette qualification :
C ne touche que les profils/portraits API, A possède le planning, D le web
et B le client Swift. Les migrations nouvelles restent propres à chaque lot.
