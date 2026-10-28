# Déploiement et remise à zéro autorisés — 28 octobre 2026

Le porteur a demandé de déployer le web puis d’effacer les données pour refaire le premier usage. La clarification « données et comptes Drivy » a été confirmée. Cette autorisation remplace, pour cette opération, l’attente de déploiement mentionnée dans le [plan du lot](simplification-253-20261028.md). Aucun compte utilisateur n’a été créé à sa place. Aucun merge vers `master` ni clôture d’issue.

## Versions livrées

- Web, API et worker : `a41cf64d153252dc133a60f29755f0685516be8f`, sur [Drivy](https://drivy.shulker.ch/app/). Version précédente `7a7031dd2e8c2da8cd5dde8c05b1f06319028bfd`, vérifiée ancêtre de la branche livrée.
- IPA : `77306e9882216688b3250c77f72047619c42ad04`, build 441, [compilation et empreintes vérifiées](preuve-ipa-253-uxb-20261028.md). Aucun changement natif entre ce commit et la version web/API ; le correctif ultérieur préserve la validité des conditions communes côté serveur.
- Les 15 corrections UX B sont incluses dans l’IPA, ainsi que les changements natifs de #253. La [PR #279](https://github.com/tomyrms/Drivy/pull/279) reste en brouillon.

## Inventaire et sauvegardes

CT114 : API, web et worker suivaient le lien `current`, sans override ; identité Keycloak distincte. CT113 : seules les bases actives `drivy_refonte` et `drivy_identity` sont concernées. `drivy_web` est absente et n’a pas été créée ; les bases de l’ancien projet et autres bases du serveur sont hors périmètre.

Les quatre services écrivains ont été arrêtés avant sauvegarde. Copies privées conservées dans `/root/drivy-reset-20261028-a41cf64d/` : dumps sur CT113 et configuration Drivy sur CT114, permissions privées. La sauvegarde métier mesure 2 582 766 octets ; la sauvegarde identité 463 543 octets. Catalogues et blocs relus, **restauration réelle des deux dumps dans deux bases temporaires réussie**, comptages de contrôle concordants. Les bases temporaires ont ensuite été supprimées. Aucune donnée, clé, identité personnelle ou empreinte de sauvegarde n’est publiée ici.

## Opérations réalisées

1. Archive Git du commit de livraison transférée avec empreinte vérifiée, compilation Linux API et web réussie dans un nouveau répertoire de release, sans toucher au service actif.
2. Les 55 empreintes de migration existantes ont été comparées au dépôt. La seule migration en attente, `20261028_individual_cancellation_rules.sql`, a d’abord été appliquée avec succès à la copie restaurée. Elle a ensuite été exécutée sur la base active ; le registre compte 56 migrations.
3. Remise à zéro transactionnelle des 91 tables métier du schéma `drivy`, avec garde sur le nom de base, l’inventaire et les références. Pas de `CASCADE` vers des objets inconnus. Les deux types de cours globaux de la migration 042 sont conservés ; schéma, fonctions, RLS, rôles et registre de migrations sont conservés.
4. Suppression des cinq comptes humains du seul realm `drivy` par l’API d’administration Keycloak, en excluant explicitement le compte de service. Le compte de service d’inscription, les clients/secrets/rôles et l’administrateur du realm `master` sont conservés. Aucun autre realm modifié.
5. Création d’un seul code d’ouverture, utilisable jusqu’au 4 novembre 2026. Il réserve l’identifiant de la future école sans créer de personne, de compte ni d’école. Le code reste dans un fichier privé d’exploitation et est transmis directement au porteur, jamais au dépôt.
6. Le périmètre de qualification Messages pointe désormais seulement vers cette future école réservée. Aucun changement du mode de messagerie, de ses clés ou de ses protections. `GPS_ONLY_QUALIFICATION_SCHOOL_IDS` reste vide : **GPS obligatoire non activé**, blocage #266 conservé.
7. Préflight des privilèges du rôle runtime et des 91 tables RLS réussi ; dépendances runtime réduites ; bascule atomique de `current`, redémarrage API, web et worker. L’identité a été redémarrée pour la suppression ciblée des comptes. OSRM et les autres services restent hors périmètre.

## Vérification effectuée

Contrôle final à **17:33:00 UTC** : quatre services actifs, aucun redémarrage automatique, aucun avertissement ni erreur dans leurs journaux depuis leur démarrage. Répertoires réels API/web/worker conformes à la release ; readiness interne `ready` ; contrôle de privilèges et RLS réussi.

Contrôles HTTPS avec curl : HTML identique au build, les 21 fichiers publics identiques par empreinte, session anonyme disponible, API protégée par 401 sans authentification, découverte OIDC disponible et code d’ouverture reconnu sans création de compte. Les requêtes Python faites depuis CT114 ont été refusées par la protection Cloudflare 1010 ; les contrôles curl ont réussi, sans modification de cette protection.

Comptage final : **0 personne, 0 école, 0 appartenance, 0 leçon** ; un code d’ouverture disponible et deux références techniques de cours. Identité : **0 compte humain Drivy**, un compte de service Drivy et un administrateur `master` conservés. Le redémarrage du web vide les anciennes sessions BFF en mémoire. Les données locales d’un ancien compte sur un appareil ne sont pas effacées par une remise à zéro serveur : se déconnecter avant de recréer son compte.

Ce sont des vérifications de compilation, restauration et déploiement. Les tests métier PostgreSQL/Swift, les tests UI, l’essai du porteur et la qualification physique restent **NOT_EXECUTED** pour cette tranche. Aucune réussite du parcours utilisateur complet n’est déduite des réponses HTTP.

## Retour arrière

Pour un retour logiciel seul : arrêter API/web/worker, remettre `current` sur la release précédente puis rétablir la configuration sauvegardée avant redémarrage. La colonne nullable ajoutée peut rester ; l’ancienne API l’ignore. Vérifier le périmètre de qualification Messages : l’ancien identifiant scolaire supprimé ne correspond pas à la nouvelle école.

Pour annuler aussi la remise à zéro : arrêter les quatre services et restaurer **ensemble** les deux bases et la configuration sauvegardées, puis reprendre l’ancienne release. Les restaurations de contrôle ont réussi. Cela réintroduirait les anciennes données/comptes et remplacerait les créations postérieures au reset ; inventorier ces créations et obtenir une décision explicite avant une telle restauration. Le nouveau code d’ouverture ne doit alors plus être utilisé. Aucune restauration sur les bases actives n’a été effectuée.

Après l’essai du porteur : corriger les problèmes observés, exécuter les tests ciblés pertinents et respecter les contrôles requis du dépôt avant fusion. L’épic et les 15 issues UX restent ouvertes.
