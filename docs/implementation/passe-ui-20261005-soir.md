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

## Suite du 6 octobre : dossier, récapitulatif, Leçons du moniteur

Conception détaillée : [conception-dossier-lecon-20261006.md](conception-dossier-lecon-20261006.md).

- **Dossier** : contrôle segmenté « Leçons | Progression » sous l’identité, contenu en place, un seul filtre par permis (toujours un menu). Le segmenté de permis à deux permis est abandonné pour ne pas empiler deux contrôles segmentés.
- **Ligne de leçon partagée** : « Bilan · Trajet » en mots ; un bilan gardé « pour moi » n’est pas marqué ; le lieu quitte la ligne.
- **Progression** : pas d’évolution ni de tendance, le serveur ne garde que le dernier niveau par compétence.
- **Leçon** : lecture par défaut à toute largeur ; quatre portes vers la rédaction (fin de leçon, Reprendre, Rédiger, Modifier dans le menu), règle pure testée. Le trajet s’affiche dès qu’il existe, quel que soit le statut.
- **Profil → Leçons** remplace Trajets ; les trajets à envoyer restent en tête de cette page. `SchoolTripsWorkspace` conservé pour ses règles.
- **API** : `order=asc|desc` sur `GET /v1/schools/:id/lessons`, curseur lié au sens. Extension hors contrat canonique.
- **Nom affiché recomposé** (`4daae5f`) : accepté par le porteur le 6 octobre, déployé avec la release `ef0ea21`.

Bugs trouvés par les tests à leur première exécution : `lessonHistory` refusait une première page sans suite (l’historique d’un moniteur de moins de cent leçons ne se serait jamais affiché) ; isolation d’acteur de `tripNotes`.

Restes ajoutés : étapes de rédaction jamais capturées ; fixtures de capture sans « Bilan · Trajet » ni nom d’élève dans l’historique ; administrateur non moniteur toujours sans bilan ni observations ; recherche de l’historique côté client.
