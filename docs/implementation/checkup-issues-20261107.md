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
| A · Planning API | #423, #424, #439, #444 | Congés/réservations cohérents, conditions conservées, replanification atomique, examens traitables | Préparé |
| B · Confidentialité iOS | #425, #426 | Annotations revalidées, données et actions purgées sur refus d’accès | Préparé |
| C · Identité et portraits | #421, #450 | Versions cohérentes inter-écoles et générations de photos monotones ; API puis lecteurs clients coordonnés | À réaliser |
| D · Reprise web et finances | #422, #430, #432, #433, #434 | Saisies conservées, conflits explicites, historique financier accessible | À réaliser, vérifier la part native de #434 |
| E · Intentions natives | #427, #431, #437, #438, #442, #443 | Reprise atomique sans verrou fantôme, doublon ni écrasement concurrent | À réaliser |
| F · Messagerie et clés | #428, #435, #436, #440 | File récupérable, sauvegarde restaurable, clés à usage unique non redistribuées | À réaliser ; coordonner avec les travaux existants |
| G · Notifications serveur | #429, #441, #448 | Identités distinctes et reprises par appareil, révocation cohérente | À réaliser |
| H · Boîtes natives | #445, #446, #447, #449 | Nouveau message chargé, comptes exacts, listes complètes et actualisation cohérente | À réaliser |
| I · Restes antérieurs | #37, #50, #65, #68, #78, #97, #105, #106, #131 | Réutiliser les lots existants, compléter code et preuves manquantes, distinguer contraintes externes | À rapprocher des critères et commentaires actuels |

Les lots A et B sont indépendants : deux workers isolés suffisent pour commencer.
Logique/backend/tests autonomes : OpenCode sans surcharge de modèle, configuration
hôte `opencode-go/deepseek-v4.1-flash` vérifiée (champ model seul).
UI : Codex `gpt-6-astra`, effort high. Chaque worker conserve son modèle,
son propriétaire et le budget de deux reprises par problème.

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
