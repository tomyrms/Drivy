# Agenda et filtres d'historique — 29 octobre 2026

Issues #208, #209, #210 et #214. Base `2d9a5f64`, suite des 25 corrections de l'IPA 446. Aucun changement web, serveur, contrat, migration ou déploiement.

## Décisions

- #208 : l'administration choisit ses rendez-vous (si elle enseigne), toute l'école ou un moniteur du catalogue autorisé. La clé reste l'adhésion, le nom distingue les homonymes. Un moniteur retiré n'est jamais remplacé sous son ancien libellé. Le filtre serveur porte sur les leçons ; celui des cours porte sur le responsable de l'occurrence, pas sur le créateur de la série. Les lignes, repères, compteurs et états vides partagent cette projection. Le moniteur ordinaire garde exclusivement sa portée.
- #209 : le prochain engagement confirmé se cherche après le jour affiché, dans trois fenêtres de 30 jours, en dates civiles de l'école. Leçons planifiées et cours publiés sont mélangés, brouillons et annulations exclus. Une source en panne ou une réponse cours à la borne de 200 interdit de conclure. Annulation et changement de portée neutralisent les réponses tardives ; aucun parcours sans borne. La pagination des leçons possède aussi une limite de 100 curseurs, en plus des 10 000 lignes et du contrôle de cycles.
- #210 : recherche locale par mots, insensible aux accents/casse, sur la semaine ou grille mensuelle affichée. Période et moniteur visibles ; l'état partiel reste explicite jusqu'à réussite des deux sources. Rien n'est envoyé dans une URL ni écrit dans les journaux. Chaque résultat ouvre l'identifiant exact de la leçon ou de l'occurrence ; fermer la fiche conserve saisie et période. La recherche ne prétend pas couvrir tout l'historique.
- #214 : statut, période et tri passent de clés SceneStorage communes à une mémoire limitée à 20 dossiers. Elle est isolée par API, personne, école, adhésion, époque, rôles et droits ; changer de contexte purge les entrées. Retour dans un dossier de ce contexte retrouve les choix pendant la vie du processus. Aucun identifiant ni critère personnel sur disque. Les filtres actifs et le tri sont lisibles, avec remise à zéro immédiate ; le menu permet aussi de réinitialiser le permis.

Références relues : COMMENCER_ICI, F04/F05, R08–R10, J04/J05, contrat canonique AP39 (instructorMembershipId et pagination), projection cours et décisions de partage automatique déjà appliquées.

## Recette sur l'IPA

| Issue | Essai | Résultat attendu |
|---|---|---|
| #208 | ADMIN, Agenda : choisir deux moniteurs puis toute l'école ; passer semaine/mois, ouvrir/fermer une leçon et un cours ; essayer deux homonymes. | Dates conservées ; mêmes portées dans lignes/compteurs/repères ; référence pour homonymes ; un compte moniteur seul ne reçoit pas le sélecteur administratif. |
| #209 | Jour vide : Prochain rendez-vous ; placer une leçon et un cours à des dates différentes. Refaire avec réseau coupé, annuler, changer de filtre en cours de lecture. | Jour du premier engagement confirmé ; recherche de 90 jours affichée ; panne/annulation ne deviennent pas « aucun rendez-vous » et une ancienne réponse ne déplace pas le calendrier. |
| #210 | Rechercher un élève avec/sans accents, puis un cours ; changer semaine/mois et moniteur ; ouvrir un résultat et revenir. | Période et couverture explicites ; bonne leçon/occurrence ; saisie conservée au retour ; pas de résultats d'une autre école. |
| #214 | Dossier A : filtrer un mois ancien et un statut, changer le tri ; aller à B puis revenir à A. Réinitialiser, puis changer d'école/compte. | B commence sans les filtres de A ; A les retrouve pendant la session ; bouton rend toutes les leçons autorisées et le tri normal ; autre contexte repart sans critères hérités. |

## Vérification

`git diff --check` exécuté. Trois contrôles ciblés ajoutés à SchoolAgendaCoursesTests : filtrage par occurrence/annulations, borne 90 jours/réponse tronquée, annulation avec réponse tardive. Leur exécution Apple et la compilation sont à relever dans la livraison du lot ; aucun résultat physique ni succès de tests n'est présumé ici. Les grandes suites restent reportées après l'essai du porteur.
