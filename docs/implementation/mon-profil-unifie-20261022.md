# Une seule identité et une seule page « Mon profil » (#94), 22 octobre 2026

## Décision du porteur (22 octobre 2026)

- Une seule donnée par information : prénom, nom, nom affiché, e-mail, téléphone, date de naissance, adresse et photo vivent sur le compte Drivy de la personne (`drivy.person`). Le dossier d'élève (`drivy.learner_profile`) ne garde que ce qui appartient à l'école : politique acceptée, auteur et source de la saisie, archivage.
- Un élève inscrit dans plusieurs écoles a les mêmes valeurs partout : une personne n'a qu'un prénom, qu'un nom, qu'une adresse.
- L'administration peut modifier ces informations pour un élève, après une confirmation qui dit que le compte de l'élève change partout.
- Les données en base sont des données d'essai : aucune reprise exigée. La migration complète seulement un compte vide avec ce que portait le dossier, sans rien écraser.

## Première version abandonnée

La première livraison (7cf25a3, 42d4374) mettait les deux formulaires sur une même page : compte, puis « Dossier scolaire » avec ses propres champs. Le porteur a constaté les informations en double. La cause était dans la base : deux jeux de colonnes pour les mêmes informations (#64 avait ajouté celles du compte). Remplacée par ce qui suit.

## Serveur

- Migration `041_single_person_identity.sql` : `lesson_learner_name` et `capture_trip_names` lisent le compte ; `profile_fields_writable` disparaît ; reprise sur le compte des valeurs que seul le dossier portait (sans écraser) ; suppression des colonnes `display_name`, `contact_email`, `contact_phone`, `first_name`, `last_name`, `birth_date`, `postal_address`, `profile_photo_document_id`, `profile_readiness` de `learner_profile`.
- RLS de `drivy.person` : lecture par l'école de la personne derrière un dossier lisible (`school_reads_person`), écriture seulement par la route du dossier, qui pose `app.school_profile` (`school_writes_person`), et par la personne elle-même à l'acceptation d'une invitation (`school_person_self_update`).
- `profiles.ts` : la route `administrative-profile` lit et écrit le compte ; les droits ne changent pas (accès complet pour l'administration et l'élève lui-même, coordonnées de contact pour le moniteur affecté, champs protégés absents de sa réponse). Le compte est verrouillé avant l'école : deux écritures concurrentes donnent 200 et 412, sans interblocage.
- `queries.ts`, `profile-completeness.ts`, `lessons.ts`, `school-onboarding.ts` : listes, recherche, complétude et planification lisent le compte.
- `invitations.ts` : l'acceptation crée le dossier et complète seulement les champs vides du compte (noms signés, e-mail vérifié) ; une valeur déjà saisie n'est jamais réécrite.
- Formes des réponses inchangées (contrat OpenAPI), `profilePhotoDocumentId` vaut toujours `null`.

## Web

- `profile-completion.tsx` : avant d'enregistrer, une confirmation dit que ces informations sont celles du compte de l'élève, qu'il retrouvera dans Mon profil et que toute autre école lira les mêmes.

## App

- Une seule ligne « Mon profil » pour tout compte connecté (élève, moniteur, administration, rôles cumulés, sans école), qui ouvre `SchoolMyProfileView`.
- Un seul formulaire et un seul enregistrement (`PATCH /v1/me/profile`) : photo, prénom, nom, nom affiché, e-mail, téléphone, date de naissance, adresse. Pour un élève, l'école ajoute en dessous ce qui lui appartient : prochaine étape, accueil à reprendre, « Pourquoi ces informations ? » et la notice. Aucun second jeu de champs.
- Champ manquant demandé par l'école : la page s'ouvre sur ce champ, avec son point.
- Dossier d'un élève vu par l'école (`SchoolProfileView`) : mêmes champs, mêmes droits ; l'administration confirme avant d'enregistrer.
- Supprimés : `SchoolRenameSelfRow`, `SchoolSelfProfileSheet`, la ligne et le volet « Mes informations », `learnerReadCount`, `renameSelf`, le masquage des doublons et l'enregistrement en deux requêtes de la première version, la ligne « photo associée au dossier ».

## Vérification

- Exécuté localement (PostgreSQL 17 en conteneur, même image que la CI) : suite API complète, 569 tests passés, dont le nouveau test « une seule identité » (l'élève saisit, l'administration et le moniteur lisent les mêmes valeurs, l'administration corrige l'adresse et l'élève la retrouve, le moniteur ne peut pas écrire un nom). Web : typage et 320 tests passés.
- CI : `refonte-checks.yml` (PostgreSQL, web) et `ipa-essai.yml` (compilation Release et IPA) ; résultats consignés dans l'issue #94.
- Non exécuté : tests unitaires et UI Apple, captures iPhone/iPad, VoiceOver, Dynamic Type, appareil physique. Déploiement homelab non fait : il attend l'accord du porteur, avec sauvegarde préalable de la base.
