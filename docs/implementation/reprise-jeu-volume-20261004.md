# Reprise — jeu de volume fictif (4 octobre 2026)

## Demande du porteur

« Remplir la base de données avec un maximum d'infos, que ce soit pour le moniteur ou l'élève », pour tester l'application avec beaucoup d'entrées. Demande faite à Codex le 4 octobre à 22 h 40 ; Codex a atteint sa limite d'usage à 22 h 48 sans rien écrire en base. Le porteur a confié la suite à Claude (« oui termine, ça me va comme ça »).

## Décisions

- Cible : 80 élèves, 5 moniteurs sans compte de connexion, 102 formations, environ 1 200 leçons sur 180 jours passés et 45 jours à venir.
- Catégorie B : l'offre, le référentiel et la prestation existants de l'école sont repris. Seules les offres A et BE sont nouvelles (le porteur avait accepté trois offres ; deux suffisent et le sélecteur de tarif B reste inchangé).
- Aucune capture GPS ni position, aucun compte de connexion, aucun e-mail.
- À partir du jour d'exécution, `luc` n'a que deux leçons planifiées par jour ouvré et Alex trois, pour que « Démarrer une leçon » reste possible pendant les essais.
- Les formations 61 à 80 ne sont pas confiées à Alex : le compte `moniteur` ne doit pas les voir.
- Seule ligne préexistante modifiée : les champs vides du dossier de « Léa Morel · exemple » (compte `eleve`).

## Fichiers

- `infra/deploy/provision-volume-data.sql` : le script, une transaction, contrôles avant validation, refuse une seconde exécution. `-v dry_run=1` annule la transaction.
- `.local/volume-run.py <base> <fichier.sql> [--dry-run]` : exécution sur CT113 (bases admises : `drivy_refonte`, `drivy_volume_rehearsal`).
- `.local/volume-rehearsal.py create <dump> | drop` : copie de répétition restaurée depuis une sauvegarde.
- `.local/backup-volume.py` : sauvegarde vérifiée, reçu dans `.local/seed-volume-backup.json`.
- `.local/volume-verify.sql` : ce que voient `luc`, `moniteur` et `eleve` sous le rôle `drivy_app` (compteurs seulement).
- Brouillons de Codex, non utilisés tels quels : `.local/seed-volume-profile.sql`, `.local/seed-volume-lessons-plan.md`.

## État

Terminé le 4 octobre 2026 à 23 h 21.

1. Script écrit : fait.
2. Répétition sur une copie restaurée (`drivy_volume_rehearsal`) : faite deux fois, tous les contrôles passent.
3. Sauvegarde `/root/drivy_refonte-before-volume-20261004-20261004T212104Z-aa8aba17.dump` (CT113) puis application sur `drivy_refonte` : fait, 1 236 leçons.
4. `.local/volume-verify.sql` sur la production : fait, identique à la répétition.
5. Copie de répétition supprimée : fait.
6. `STATUS.md` et preuve `proofs/volume-seed-20261004.json` : faits.

Reste au porteur : parcourir l'app et le web avec ce volume. Rien n'a été vu à l'écran.

## Retirer le jeu

Aucun script de retrait n'existe. Deux voies : restaurer la sauvegarde ci-dessus (perd tout ce qui a été saisi depuis), ou écrire un retrait ciblé à partir des identifiants du lot, tous dérivés de `md5('volume-20261004/…')` par `pg_temp.seed_uuid` dans le script.

## Pour reprendre

Lire ce fichier et `AGENTS.md`. Si l'opération `PROVISION_EXAMPLE_DATA` du lot `volume-20261004` existe déjà dans `drivy.operation`, le script a été appliqué : ne pas le relancer, passer à l'étape 4. Le script a été appliqué : ne pas le relancer (il refuse de toute façon une seconde exécution).
