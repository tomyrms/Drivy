# Passe UI/UX du 5 octobre 2026 (soir) — dossier par permis, fiche de leçon, agenda sobre, bilan en étapes

À la demande du porteur. Reprise : [reprise-passe-ui-20261005-soir.md](reprise-passe-ui-20261005-soir.md).

## Décisions

1. **Données fictives sans mention d’exemple.** Lot `infra/deploy/provision-realistic-labels.sql`, appliqué sur le homelab après sauvegarde vérifiée et répétition sur une copie : suffixe « · exemple » retiré de 92 noms, 2 fermetures et du libellé des conditions générales ; 75 adresses passées sur des rues de la région. E-mails (`@example.invalid`) et téléphones (`+41 000…`) laissés non attribués : l’app propose d’appeler et d’écrire. Les données synthétiques des captures portent aussi des noms crédibles.
2. **Photos de profil : non faites.** `learner_profile.profile_photo_document_id` porte `CHECK (… IS NULL)` et aucun dépôt de documents n’existe. L’avatar reste les initiales.
3. **Dossier** : deux lignes, Leçons et Progression ; filtre par permis dans chaque page (aucun avec un permis, segmenté avec deux, menu à partir de trois ou en très grand texte). Le serveur ne sait lister les leçons que par formation : l’app fusionne les lectures et ne montre rien au-delà de la dernière page lue de chaque formation.
4. **État d’une leçon dans une ligne** : un mot de texte en tête de la ligne de détail, plus de pastille. « Annulée » et « Absence » passent de l’alerte au neutre.
5. **Fiche de leçon** : objectifs lisibles après la leçon, horaire réel s’il s’écarte de cinq minutes, moniteur nommé pour l’équipe, confirmation verte « Leçon terminée » retirée, bouton lecture sur la carte.
6. **Bilan** : lecture et rédaction séparées ; rédaction en étapes Trajet → Compétences → Bilan sur iPhone, deux colonnes sur iPad large ; un seul envoi final ; brouillon local chiffré ; le constat de fin de leçon ne publie plus les objectifs comme bilan.

## Pourquoi cette organisation du bilan

La leçon est déjà terminée quand le bilan s’ouvre et rien n’y est obligatoire : le parcours doit être court, sans validation bloquante, avec un seul geste qui engage, l’enregistrement, parce qu’il partage avec l’élève. L’ordre Trajet → Compétences → Bilan fait revoir avant de noter et de rédiger ; la dernière étape est toujours la même, donc l’action finale aussi. Écartés : pages balayées (conflit avec la carte, points de page), feuille dédiée (une couche modale de plus), envoi à chaque étape (l’élève lirait un bilan à moitié écrit).

## Causes établies des « informations manquantes » de la fiche

- Objectifs rendus seulement sur une leçon planifiée, alors qu’ils étaient reçus pour tout statut : corrigé.
- Objectifs et observations d’un collègue refusés par le serveur (`preparation_read`, test `lesson-reports.integration.test.ts`) : règle voulue, non modifiée. Un administrateur-moniteur voit donc peu de chose sur les leçons des autres.
- Motifs d’annulation, d’absence et d’anomalie écrits en base, absents de la projection de leçon : non corrigé.
- Horaire réel et souhait de l’élève reçus sans être rendus : corrigé.

## Restes et propositions

- Décision du porteur : ouvrir les objectifs aux moniteurs affectés (une politique de lecture, un test à adapter).
- Exposer les motifs d’annulation et d’absence.
- Route de leçons par élève avec sens de tri : la prochaine leçon d’une formation de plus de 100 leçons se cache derrière « Afficher d’autres leçons ».
- Photos de profil : dépôt de documents, consentement, service des images.
- Tracé de chaque trajet quand une leçon en a plusieurs.
- Liste des élèves : « À vérifier » et « Archivé » sont encore des pastilles (`DrivyEntityRow`).
- Symboles décoratifs restants hors périmètre : accueil guidé, invitations, rejoindre une école, profil.
- 16 révisions de bilan du jeu de volume répètent deux fois la même phrase.
- `DrivyDestructiveRow` exige un symbole ; `SchoolTripBadge.symbol` n’a plus d’usage ; `DrivyGuidedStepHeader` et `DrivyGuidedFact` sont sans appelant.
