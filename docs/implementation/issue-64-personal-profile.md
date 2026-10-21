# Issue #64 — édition du compte personnel (premier lot)

## Portée réalisée

- Source de vérité : `drivy.person.display_name`, commune à toutes les écoles et aux sessions de ce compte. La fiche scolaire `learner_profile` reste séparée et son formulaire élève reste accessible.
- `PATCH /v1/me` : identité déterminée **exclusivement** par le jeton OIDC vérifié et la correspondance `identity_link`. Les champs `personId`, rôles, autorisations, dossiers et identifiants d'authentification ne sont pas modifiables.
- Corps strict : `{ operationId: UUID, displayName: string }` (nom NFC, 1 à 200 points de code, sans caractères de contrôle). `If-Match: "<version>"` et `Idempotency-Key: <operationId>` obligatoires. Réponse `{ data: { personId, version, displayName, locale }, requestId, serverTime }` et ETag.
- Écriture PostgreSQL sous `drivy_app`, RLS `person_id`, verrou du compte et reçu d'idempotence durable dans la même transaction. En cas de rejeu identique, l'ancienne réponse est retrouvée sans double écriture ; même clé/autre contenu = 409 ; version périmée = 412.
- iOS : action « Modifier mon profil » pour le compte connecté, pour les rôles INSTRUCTOR/ADMIN/LEARNER et leurs cumuls, sans dossier élève artificiel. Écran SwiftUI avec nom affiché, contrôle des caractères, annulation confirmée, saisie conservée et erreur visible en cas d'échec. La relecture du compte met à jour le nom visible dans l'app.
- Ce changement n'écrit **pas** l'e-mail Keycloak et ne copie pas les noms administratifs d'une école vers les autres écoles.

## À ne pas confondre avec une livraison complète

Ce lot ne couvre **pas** : photo d'avatar choisie, cadrée, téléversée, protégée et supprimable ; coordonnées de contact personnelles distinctes de la connexion OIDC et du dossier scolaire ; invalidation multimachine garantie en temps réel ; validation sur appareils iPhone/iPad. Le document `profile_photo_document_id` du profil scolaire n'est pas un système d'images opérationnel et ne doit pas être traité comme tel.

L'issue #64 reste **ouverte** jusqu'à la livraison des photos et des autres critères d'acceptation. Un contrat API canonique pour la nouvelle mutation, une qualification PostgreSQL/iOS et la recette d'appareil doivent encore être terminés.

## Livraison et déploiement

- Branche : `feat/64-personal-profile-edit` (non intégrée à `master` lors de cette note).
- Nouvelle migration : `037_personal_profile_edit.sql`. **Ne pas** activer le formulaire iOS avec une ancienne API qui ignore `PATCH /v1/me`.
- Déploiement homelab : sauvegarder PostgreSQL et vérifier la restauration, exécuter les migrations via le mécanisme habituel, déployer la même version d'API que l'application, puis compiler l'IPA et l'installer sur un appareil test. Aucun déploiement distant n'a été effectué dans ce lot.
- Tests d'intégration ciblés ajoutés (sans les déclarer exécutés) : moniteur sans dossier, admin, élève, idempotence et conflits.

## Notes sur la concurrence

La requête est conditionnelle à la version du compte : un autre appareil doit relire `GET /v1/me` après 412 avant de changer l'état. En cas de réponse perdue, le formulaire conserve `operationId` et sa saisie pour rendre la répétition sûre. Une nouvelle saisie crée une nouvelle clé. Après un succès serveur, la relecture peut échouer indépendamment ; dans ce cas le changement reste durable mais la projection locale ne se remet à jour qu'à la prochaine lecture réussie.
