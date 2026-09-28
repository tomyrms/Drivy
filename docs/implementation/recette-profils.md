# Recette locale G1D1 : profils scolaires

`scripts/dev/check-profile-entry.ts` traverse réellement Edge, le formulaire Keycloak, le BFF et l’API avec PostgreSQL. Aucun fournisseur d’identité, jeton, endpoint métier ou succès d’écriture n’est simulé. Les identifiants sont générés pour chaque exécution.

## Préparation et isolation

- Windows avec Node 24, Docker et Microsoft Edge ; dépendances racine, `apps/web` et `infra/dev` installées depuis leurs lockfiles.
- Le conteneur local `drivy-g1d-postgres` expose PostgreSQL sur `127.0.0.1:55434`. La recette lit ses identifiants avec `docker inspect` en mémoire, sans les écrire dans les preuves ni les journaux.
- Keycloak doit déjà être provisionné sur `127.0.0.1:8081`, realm `drivy-dev`. Le fichier de laboratoire primaire `C:/Users/jtoma/Documents/Projects/Drivy/infra/dev/.state/runtime.json` est lu, jamais modifié.
- Les ports `127.0.0.1:3005` (API) et `127.0.0.1:3006` (BFF) doivent être libres. La recette n’arrête aucun service existant.
- Base exclusive `drivy_profiles_entry_test`, créée si absente. Aucun paramètre ne permet de substituer une base distante. Les migrations API et BFF sont réelles ; une migration déjà appliquée dont le hash a changé fait échouer la recette.
- Un client OIDC confidentiel temporaire avec callback 3006 et trois comptes sonde temporaires sont créés, puis supprimés par leurs UUID. Aucun compte, client ou réglage du realm existant n’est modifié.

Depuis le worktree, après gel du serveur et du stockage BFF :

```powershell
npm ci --prefix infra/dev --ignore-scripts --no-audit --no-fund
npm run build --prefix apps/web
node node_modules/tsx/dist/cli.mjs scripts/dev/check-profile-entry.ts
```

Les services sont lancés dans le processus de recette et arrêtés dans son `finally`. Les données sont effacées uniquement par les UUID de cette exécution, dans la base dédiée, sans `TRUNCATE`, suppression de schéma ou purge du realm. Les commandes chiffrées des sondes sont aussi retirées ; leur clé temporaire ne quitte pas la mémoire du processus. Un nettoyage incomplet produit un échec.

## Parcours contrôlés

1. Provisionnement de prérequis synthétiques dans la seule base dédiée : école active, trois appartenances, dossier élève minimal, formation et affectation permettant au moniteur de consulter ce dossier. Cette étape n’est pas présentée comme une création de formation dans le produit. Les noms administratifs restent `null`.
2. Connexion ADMIN dans Edge par le vrai formulaire Keycloak. Adoption d’une notice et d’une conservation explicitement synthétiques par la vraie commande API, avec le jeton réellement obtenu. Ce prérequis ne prétend pas tester une vue web d’adoption de notice.
3. Dans l’interface, ADMIN renseigne les champs, finalités et explications ; crée un brouillon puis publie après deux confirmations distinctes, jamais précochées. Relecture SQL de l’état et de la référence à la notice exacte.
4. L’élève se connecte séparément. Les noms administratifs sont vides malgré les noms du compte OIDC. Il saisit explicitement prénom, nom, contacts et données facultatives synthétiques, confirme puis relit les mêmes valeurs via l’API.
5. Le moniteur affecté se connecte. Naissance et adresse sont absentes de sa projection API et de sa vue ; les noms ne sont pas modifiables. Une demande forgée de naissance est refusée par le BFF et les écritures directes naissance/adresse sont refusées par l’API, sans changer les données.
6. Le moniteur prépare une correction de téléphone. Le BFF est arrêté puis recréé avec un nouveau magasin, le même PostgreSQL et le même trousseau en mémoire. Après reconnexion, la même intention et le même identifiant d’opération reviennent ; la confirmation reste explicite. La preuve AP72 doit désigner `AdministrativeProfile.id`, distinct de `Learner.id`.
7. L’élève reconnecté relit le contact corrigé et ses données protégées inchangées. La provenance est `STAFF_ASSISTED` après correction par le moniteur.

## Preuves et limites

Chaque exécution écrit `artifacts/web/profile-entry/<run UUID>/result.json` et trois captures des écrans de politique publiée, profil élève et contact moniteur. Les comptes, mots de passe, cookies, jetons OIDC et clés de chiffrement ne sont jamais enregistrés dans ces preuves. Les captures contiennent uniquement les informations synthétiques saisies dans cette recette.

Un résultat n’est réussi que si `completed` et `cleanupOK` valent tous deux `true`. L’existence du script et sa vérification TypeScript ne prouvent pas le passage du parcours. À la rédaction initiale de cette recette, l’exécution reste à effectuer après gel du stockage BFF.

La recette valide une reprise de demande préparée après redémarrage, pas toutes les fenêtres de panne après commit. Les tests transactionnels du magasin couvrent séparément les commandes incertaines et la concurrence. Elle ne qualifie ni iOS, ni le GPS physique, ni l’envoi d’e-mail, ni les formations/plannings. Les comptes sonde sont provisionnés avec e-mail vérifié : la vérification réelle par messagerie relève de la recette d’entrée F02.
