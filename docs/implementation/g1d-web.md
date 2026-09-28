# G1D1 web — politique de champs et profil scolaire

Implémentation isolée sur `codex/g1d-profils`, base `6ffc103`, le 24 septembre 2026. Elle complète le web G1C sans modifier son déploiement. Référence de périmètre : [préparation G1D](g1d-formation-ready.md). **G1D n’est pas qualifié complet**, notamment pour la reprise durable après perte de session/BFF et la recette intégrée avec PostgreSQL réel.

## Parcours disponible dans le code

- Depuis les écoles de `/me`, ouverture d’une école puis pagination des seuls dossiers autorisés. Les URL contiennent les UUID scolaires et du dossier ; une école absente des appartenances relues ne reste pas sélectionnée.
- AP169 affiche les politiques visibles selon les droits. Un ADMIN peut préparer AP170 depuis la notice de données approuvée, puis publier le brouillon par AP171 avec une confirmation distincte. Noms imposés pour l’identification ; autres champs bornés ; photo toujours facultative. Aucun précochage d’approbation d’impact ou de publication.
- AP175 présente le profil de cette école et sa politique applicable, AP177 les besoins de l’action `ENTER`. Le PATCH AP176 ne transmet que les champs modifiés, avec la version commune et `policyVersionId`. Le nom d’affichage n’est jamais découpé pour inventer prénom/nom. Un moniteur autorisé modifie seulement les contacts ; les champs omis par la projection serveur ne sont pas présentés comme valeurs vides à remplacer.
- La saisie est un brouillon en mémoire. Un avertissement précède les changements de rubrique/école et la déconnexion ; `beforeunload` avertit avant fermeture si le navigateur le permet. Les frappes ne sont ni synchronisées ni enregistrées dans `localStorage`, `sessionStorage` ou IndexedDB.
- Après préparation, l’interface relit le contenu à confirmer. Elle affiche un résultat confirmé seulement après réponse de commande ou preuve AP72, puis relit les projections actuelles. Les retours tardifs d’un ancien écran sont ignorés ; perte de droits `401/403` ou changement d’époque efface les dossiers et brouillons affichés.

Les contacts passent ici par AP176. AP16, l’assistant AP172–174, la formation et son affectation ne sont pas de nouveaux écrans web livrés par ce fichier. La photo est expliquée comme facultative ; aucun dépôt ou document fictif n’est ajouté.

## Frontière BFF et commandes

[upstream.ts](../../apps/web/server/upstream.ts) autorise explicitement les routes et méthodes utiles, les UUID, paramètres de pagination et corps. Il n’existe pas de proxy HTTP arbitraire. Toutes les mutations navigateur exigent `Origin` exact, JSON et `X-CSRF-Token`. OAuth reste côté serveur.

[profiles.ts](../../apps/web/server/profiles.ts) propose les lectures scolaires nommées et quatre routes de commande : lecture de la demande courante, préparation, confirmation et annulation avant émission. L’UUID, le corps validé et la version attendue sont fixés au serveur avant l’envoi. La demande est liée à la Person, à l’école, à l’appartenance et à son `accessEpoch`. Un identifiant de confirmation opaque empêche un autre onglet de modifier silencieusement la demande déjà présentée.

Avant chaque émission, le BFF relit les droits. Avant la première émission, il relit également la version/politique concernée ; l’API conserve la validation transactionnelle finale. Après une réponse incertaine, AP72 est interrogé avant de réémettre exactement la même commande. Une réponse `4xx` obtenue après une émission incertaine ne supprime pas cette intention. L’annulation recontrôle son état après l’attente réseau pour ne pas effacer une émission concurrente.

Les tests du BFF injectent des réponses API synthétiques ; ils ne remplacent pas les contraintes, RLS et verrous PostgreSQL du serveur métier.

## Preuves exécutées

Dans ce worktree :

```powershell
npm ci --prefix apps/web --ignore-scripts
npm run typecheck --prefix apps/web
npm test --prefix apps/web
npm run build --prefix apps/web
```

Résultats : installation sans vulnérabilité connue signalée, typecheck strict réussi, **34 tests réussis** (19 existants G1C, 15 ajoutés), build réussi. Les tests ajoutés couvrent préparation sans effet, corps/UUID/version conservés, preuve après commit dont la réponse est perdue, rejet après résultat incertain, révocation/epoch, confirmation interonglets, annulation concurrente, droits par champ, photo non obligatoire et transport HTTP PATCH/If-Match/Idempotency-Key avec refus des routes/paramètres non prévus.

Le harness [check-profile-ui.mjs](../../apps/web/scripts/check-profile-ui.mjs) a également réussi dans Edge avec le vrai React/BFF et **des réponses métier synthétiques** : noms initialement vides, préparation sans effet, confirmation du profil, publication distincte et absence de débordement horizontal à 390 px. Les captures desktop clair et profil mobile sombre ont été relues ; aucun texte ou contrôle coupé n’a été constaté. Ce n’est pas une mesure WCAG ni une recette assistée au lecteur d’écran.

Le harness utilise le module Playwright déjà verrouillé dans `infra/dev` et exige le port loopback `3004` libre. Après installation des dépendances de ce laboratoire, exécuter :

```powershell
node apps/web/node_modules/tsx/dist/cli.mjs apps/web/scripts/check-profile-ui.mjs
```

`DRIVY_BROWSER_MODULE` peut pointer vers ce même module déjà installé dans un autre checkout local ; cela sert uniquement au harness. Il ne contacte aucun fournisseur OIDC ni service distant et ne charge aucun compte réel. Les captures synthétiques sont dans `apps/web/node_modules/.cache/` et restent ignorées par Git. Il démarre et ferme son serveur et son profil Edge éphémères.

## Écart de durabilité à fermer avant qualification

La demande préparée est actuellement dans `SessionStore`, **en mémoire du processus BFF**. Un timeout HTTP, une fermeture d’onglet suivie d’un retour dans la même session et les retries couverts par les tests peuvent retrouver cette intention. Un redémarrage du BFF, la déconnexion, la rotation de session ou son expiration suppriment cet état. Les sessions expirent après 30 minutes d’inactivité authentifiée ou deux heures absolues.

L’effet déjà validé dans l’API reste durable et l’utilisateur peut relire le dossier après reconnexion. En revanche, le BFF a perdu l’UUID et le corps de la demande incertaine : il ne peut plus prouver sa reprise exacte avec AP72. **La présente tranche ne satisfait donc pas la promesse complète de persistance des commandes avant émission et de continuité R02/R11/R12.** Une nouvelle saisie ne constitue pas une reprise démontrée. Aucun stockage navigateur ne compense cet écart.

Le stockage minimal à ajouter est une petite table d’intentions BFF dans PostgreSQL, avec un rôle dédié : UUID d’opération unique, type/ressource, propriétaire authentifié, école/appartenance/epoch, version attendue, empreinte de revue, corps chiffré authentifié, état et dates. Aucun access token ou refresh token n’a besoin d’y figurer. Une nouvelle session du même compte peut retrouver les intentions via le serveur, après relecture des droits et nouvelle confirmation explicite ; les changements de compte/école/epoch ne permettent jamais un renvoi implicite.

Invariants à tester pour ce raccord : écriture durable avant tout HTTP métier ; aucun envoi si stockage/ciphertext/clé échoue ; verrou ou lease empêchant deux confirmations concurrentes ; reprise AP72 après arrêt entre commit API et réception BFF ; conservation de l’UUID/corps/version ; aucune lecture du contenu avec droits retirés ; réponse connue relue depuis les ressources actuellement autorisées. Chiffrement sans repli en clair, rotation de clé, rétention/purge et effacement des données doivent être définis avant activation. Les sessions OAuth peuvent rester éphémères : la reprise des intentions ne doit pas dépendre de leur ancien cookie.

Restent aussi à exécuter la recette G1D1 intégrée avec les véritables nouvelles routes API/PostgreSQL, les accès ADMIN/INSTRUCTOR/élève sur des dossiers réels de laboratoire, les conflits de politique, les parcours natifs et la recette assistée. Aucun scénario T/MOB n’est déclaré passé par analogie avec ces tests.


## Journal durable — état de travail, non qualifié

Le code du journal PostgreSQL chiffré a été raccordé au BFF : configuration par `WEB_COMMAND_DATABASE_URL` et `WEB_COMMAND_KEYRING_FILE`, rôle `drivy_web_commands`, schéma `drivy_web`, migration `apps/web/migrations/001_profile_commands.sql`. La configuration absente ferme les mutations de profils. Les sessions OAuth restent uniquement en mémoire. Le journal conserve UUID, corps et version ; la reprise relit les droits et exige une nouvelle confirmation liée à la session. La publication affiche la notice exacte du brouillon.

Les 34 tests unitaires existants ont passé après raccordement avec injection mémoire explicite. La recette PostgreSQL dédiée, la reprise réelle après redémarrage, la rotation et la purge n’ont **pas** été exécutées : travail arrêté pour donner priorité à l’accueil natif visible. Les scripts `command-migrate.ts`, `command-maintain.ts` et `prepare-command-roles.sql` sont du code préparé, non une preuve de déploiement. Ne pas qualifier ni déployer le journal sur cette seule base. Les descriptions antérieures de reprise uniquement en session décrivent l’ancienne implémentation ; cet ajout remplace ce constat de code sans fermer l’écart de qualification.
