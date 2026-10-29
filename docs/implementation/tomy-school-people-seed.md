# Peuplement synthétique de Tomy School — personnes

Fragment préparé le 29 octobre 2026 pour la demande du porteur : donner du contenu plausible à son école de recette, sans libellé « test » dans les écrans. `scripts/dev/tomy-school-people.sql` n’est pas une migration. Son intégration et son exécution ultérieures sur le homelab sont consignées dans [le reçu de population](tomy-school-content-20261029.md).

Il apporte 24 élèves et 3 moniteurs fictifs. Chaque élève a une formation active : 16 B, 4 A, 2 A1, 2 BE. Prénom, nom, date de naissance et adresse sont synthétiques ; les adresses de contact utilisent exclusivement `example.com`. Aucun téléphone, document, photo, compte OIDC, invitation, appareil push, consentement ou vérification physique de permis n'est créé. Un souhait pédagogique bref accompagne seulement chaque nouvelle formation. Les préférences de notifications des 27 nouvelles personnes sont toutes désactivées.

## Contrat d'intégration

Le coordinateur réalise la sauvegarde, vérifie sa restauration possible, choisit une connexion de maintenance autorisée et conserve toute l'opération dans une seule transaction. Le fragment ne touche ni aux rôles, ni à RLS, ni aux déclencheurs. Il n'ouvre et ne valide aucune transaction. Il nécessite :

- `seed_context(school_id uuid, actor_id uuid)`, exactement une ligne ; `actor_id` désigne le membre ADMIN actif de cette école.
- `seed_catalogue(formation_id uuid, kind text, offering_id uuid, ordinal int)` avec une offre activée et approuvée par catégorie B/A/A1/BE ; `kind` est le code de catégorie.
- `pg_temp.seed_uuid(text)`, générateur stable d'UUID version 4 / variante RFC. Tous les identifiants explicites passent par ce générateur, afin de rester acceptés par `z.uuid()`.

La sortie temporaire `seed_people(person_id, membership_id, learner_id, training_id, role, ordinal)` contient des ordinals 1–24 pour LEARNER et 1–3 pour INSTRUCTOR. Les moniteurs ont `learner_id` et `training_id` nuls. Les affectations et le planning appartiennent à un autre fragment. Le coordinateur doit sérialiser l'opération avec les écritures de l'école pour que les vérifications préalables restent valables.

## Schéma et conservation

La migration 041 place l'identité sur `person` ; `learner_profile` conserve le contexte scolaire, la politique administrative et l'auteur de saisie. Il faut insérer dans l'ordre personne → membre → dossier → formation. Les rôles des nouveaux membres sont exclusivement LEARNER ou INSTRUCTOR, sans grants supplémentaires. Aucune mise à jour de rôle existant n'est faite.

Les clés uniques interdisent deux dossiers pour une même personne dans l'école et deux formations actives/en pause pour une même offre. Les clés étrangères composées assurent la même école pour le dossier, l'offre et la formation. Le fragment exige une politique de profil publiée déjà applicable et des offres avec référentiel et politique approuvés.

L'insertion d'un membre déclenche `initialize_profile_context`, qui parcourt toute l'école. Le fragment refuse donc de commencer s'il existe un ancien dossier sans politique administrative ou un ancien membre actif sans onboarding attendu ; cela évite une modification indirecte de données existantes. Le déclencheur du dossier remplace l'auteur par le membre élève : une correction remet l'ADMIN uniquement sur les dossiers effectivement ajoutés par le fragment.

Une relance conserve les lignes existantes (`ON CONFLICT(id) DO NOTHING`) et ne remplit pas leurs champs. Elle refuse les collisions, les comptes déjà reliés à OIDC ou au push, les préférences devenues actives et les formations qui ont changé de catégorie ou de statut. Ces situations exigent une revue ; elles ne sont jamais corrigées par écrasement automatique.

## Effets automatiques et vérification

La migration 007 crée un souhait vide après insertion d'une formation ; seuls les souhaits des formations nouvellement insérées sont complétés. Les nouveaux membres obtiennent un onboarding initial par le déclencheur de profil ; aucun parcours n'est marqué accepté ou terminé. Les insertions utilisées ici ne créent pas d'événement de cours ni de message. Les workers de cours peuvent toutefois parcourir les membres d'une école : les préférences désactivées et l'absence d'appareil/identité évitent d'ajouter des destinataires synthétiques aux notifications automatiques.

Revue locale effectuée sur `apps/api/scripts/seed.ts`, `fixtures.ts`, les migrations 001/002/004/005/007/016/038/039/041/045 et la migration de messagerie, ainsi que les contraintes utilisées par les API. Les seeds de développement existants ne conviennent pas directement : ils supposent une base de développement et créent des liens d'identité. Contrôle local du diff effectué. Aucun accès homelab, aucune instruction SQL exécutée sur une base et aucune validation de transaction PostgreSQL ne sont revendiqués ici ; l'exécution transactionnelle et les contrôles d'intégrité restent à réaliser par le coordinateur. Les campagnes produit restent après le retour utilisateur.
