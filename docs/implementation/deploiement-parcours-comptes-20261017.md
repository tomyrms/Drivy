# Livraison des parcours et de la confirmation GPS — 17 octobre 2026

## Service d’identité

Déployé sur le homelab, terminé à **16:45 Europe/Zurich**, depuis `9d6731ec2f710d612d78b9faa77457b6ea5e1e50`. La [recette intégrée](https://github.com/tomyrms/Drivy/actions/runs/39041852389) avait réussi ses **149 contrôles**, dont les signatures d’`auth_time`, son maintien au renouvellement, la confirmation du même compte et le réglage GPS durable. Les [vérifications API/web](https://github.com/tomyrms/Drivy/actions/runs/39041850002) avaient également réussi : 470 tests API/PostgreSQL et 282 tests web, types et builds.

Avant mutation, deux sauvegardes de CT113 sont créées en propriétaire root, mode 0600, synchronisées puis vérifiées par `pg_restore --list` :

- `/root/drivy_identity-before-identity-9d6731ec2f710d612d78b9faa77457b6ea5e1e50-20261017T144445Z-a4d5122b9d3f.dump`
- `/root/drivy_refonte-before-identity-9d6731ec2f710d612d78b9faa77457b6ea5e1e50-20261017T144445Z-a4d5122b9d3f.dump`

Le fournisseur est compilé depuis l’archive Git de ce commit contre la distribution Keycloak et le JDK verrouillés déjà installés. Les quatre gardes Java passent. Le JAR installé, propriétaire root et mode 0644, porte le SHA256 `d7cb34188254e5a715857e38bb61d2730775c1c841806b10520dfc81d9e9dbce`, égal aux deux compilations locales. Seul le service d’identité est arrêté, reconstruit avec le fournisseur puis redémarré. L’API et le web conservent leurs PID, chemins, empreintes d’environnement et configurations.

Le flow standard `direct grant` est copié vers `drivy-direct-grant`. L’identifiant, le mot de passe et le sous-flow OTP gardent leurs exigences, niveaux et priorités ; le fournisseur Drivy est ajouté en dernier, obligatoire. La liaison du realm est ensuite modifiée vers ce flow. La disponibilité interne, la découverte OIDC et la liaison exacte sont relues. La découverte HTTPS publique répond avec l’issuer et le point de jeton attendus. Aucun compte utilisateur, rôle ni réglage GPS d’une école réelle n’est modifié par le déploiement.

État privé de reprise sur CT114 : `/root/drivy-identity-auth-time-9d6731ec2f710d612d78b9faa77457b6ea5e1e50-20261017T144445Z-a4d5122b9d3f.json` (root, 0600). Les secrets administrateur restent dans la mémoire du processus distant et la session d’administration est fermée. Aucun jeton ni fichier d’environnement n’est exporté.

[Reçu filtré du déploiement de l’identité](assets/deploiement-parcours-comptes-20261017/identity-deployment.json).

## API et portail

Publiés à **16:59 Europe/Zurich**, depuis `d97dfa96cad63990aa661671b125d0ebb25d3307`, après les [470 tests API/PostgreSQL et 289 tests web, types et builds](https://github.com/tomyrms/Drivy/actions/runs/39042838403) et les [150 contrôles intégrés](https://github.com/tomyrms/Drivy/actions/runs/39042840471). Cette version inclut les dernières corrections de focus des tarifs et coordonnées, de destination des codes et de contexte après confirmation d’identité.

Nouvelle sauvegarde CT113 avant bascule : `/root/drivy_refonte-before-d97dfa96cad63990aa661671b125d0ebb25d3307-20261017T145924Z-d418e846ae15.dump`, root, 0600, synchronisée et vérifiée par `pg_restore --list`. Les **33 noms et empreintes de migration** correspondent exactement avant et après à la release ; aucune migration n’est ajoutée. Archive Git transférée de SHA256 `9182acf1e6f6bb34f4fded4d4762e894572747adfb93fe8601fc80eaa1735988`.

`/opt/drivy-refonte/current` pointe vers `/opt/drivy-refonte/releases/d97dfa96cad63990aa661671b125d0ebb25d3307`. Le répertoire réel de chaque processus confirme l’API et le web dans cette release. Le drop-in `90-web-release.conf`, qui fixait le web sur le correctif GPS `e8d7b75`, est retiré ; sa copie privée reste dans `/root/90-web-release.conf.before-d97dfa96cad63990aa661671b125d0ebb25d3307-20261017T145924Z-d418e846ae15`. Les environnements API/web, le profil d’essai iPad du porteur et le PID du service d’identité sont préservés. L’API et le web sont disponibles après redémarrage. Les sessions web en mémoire expirent lors de ce redémarrage.

**19 contrôles HTTPS réussis** : 12 fichiers correspondent aux empreintes de la release, cinq adresses d’entrée servent la page attendue, la session anonyme est anonyme et `/refonte/v1/me` refuse sans jeton (401). La disponibilité interne de l’API est également vérifiée. [Reçu API/web](assets/deploiement-parcours-comptes-20261017/api-web-deployment.json) · [Contrôles publics](assets/deploiement-parcours-comptes-20261017/https-checks.json). Le premier correctif web GPS de 15:39 reste décrit dans [sa preuve historique](deploiement-gps-web-20261017.md).

Retour arrière API/web : rétablir le lien `current` vers `releases/a68bb381af3936cc923f631c7ce21360459d2fbb`, remettre le drop-in depuis sa copie privée après contrôle de son empreinte, recharger systemd et redémarrer seulement l’API/web. Vérifier leurs répertoires réels, disponibilité et empreintes d’environnement, ainsi que le PID inchangé de l’identité. Refuser toute release ou configuration tierce inconnue. Aucun retour arrière de base automatique. Le fournisseur d’identité corrigé peut rester en place pendant ce retour du code.

## Retour arrière du fournisseur

Le retour arrière doit d’abord rétablir la liaison vers `direct grant`, tant que le fournisseur existe. Ne retirer le JAR qu’après relecture de cette liaison. Supprimer uniquement le flow dont l’identifiant exact appartient à cette tentative et dont les exécutions sont celles attendues ; toute modification tierce impose un arrêt de la procédure. Arrêter ensuite l’identité, retirer uniquement le JAR à l’empreinte vérifiée, reconstruire Keycloak, redémarrer et vérifier santé, découverte et ancien flow. Ne pas restaurer automatiquement la base, pour préserver les écritures intervenues depuis la sauvegarde.

La procédure a dix tests avec mocks, incluant l’échec avant arrêt, l’échec de reconstruction, le refus de redémarrage, une liaison écrite avec réponse perdue, les modifications tierces et l’ordre liaison → retrait du fournisseur. Aucun de ces tests simulés ne vaut un exercice de restauration physique. La livraison a réussi sans retour arrière.

## Limites

La recette utilise des comptes et écoles synthétiques isolés. Le déploiement vérifie les services et configurations ; aucun compte réel n’est utilisé comme compte de test. GPS physique, batterie, permissions réelles, VoiceOver et fluidité sur appareil restent à qualifier. L’IPA du lot est **0.7.0, build 277**, décrite dans [l’audit des parcours](audit-parcours-comptes-20261017.md).
