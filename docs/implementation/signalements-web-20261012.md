# Signalements configurables : panneau web (12 octobre 2026)

Livraison du volet web du contrat `signalements-configurables-20261012.md`. Rien n'est commité ni poussé.

## Fichiers

Créés (`apps/web`) : `client/console/observation-themes.tsx` (section), `observation-themes-model.ts` (règles pures), `theme-icons.tsx` (pictogrammes), `test/observation-themes-model.test.ts`.

Modifiés : `server/school-routes.ts` (liste blanche), `client/command-core.ts` (commande `saveObservationThemes`), `client/school-api.ts` (schéma zod et lecture), `client/console/{sections,navigation,Console,context,people}.ts(x)`, `client/ui.tsx` (symboles `grip` et `chevron-up`), `client/styles.css`, `test/{school-bff,console-route,visual}`.

## Décisions

- BFF : `GET` et `PUT observation-themes` seulement, `PUT` avec `If-Match` et corps limité à 4 096 octets. `POST`, `PATCH`, `DELETE` et tout sous-chemin restent refusés.
- Navigation : rubrique `signalements` dans l'espace Réglages (École, Informations élèves, Signalements, Préparation). La console n'est ouverte qu'au rôle ADMIN : `canManage` sert de repli (lecture seule si faux ou si le serveur répond 403).
- Schéma : le client exige une liste cohérente (clés uniques, positions d'origine uniques, 1 à 40 thèmes) sans fixer les clés ni leur nombre ; le catalogue appartient au serveur.
- Commande : `PUT`, `If-Match` = version lue, `Idempotency-Key` = `operationId`, reprise par le magasin de commandes existant (reçu AP72). Le reçu est attendu avec `commandType SAVE_OBSERVATION_THEMES` et `resourceType ObservationThemeSettings` sur l'identifiant de l'école. Le `resourceType` du reçu a été corrigé par le coordinateur en `ObservationThemeSettings` (commit `85e6e35`).
- Glisser-déposer : événements pointeur écrits sur la poignée (souris, toucher, stylet ; `touch-action: none`), écouteurs sur `window` pour survivre au déplacement des nœuds, la rangée tenue suit le pointeur, réordonnancement en direct, Échap ou annulation du pointeur rétablit l'ordre de départ.
- Clavier : poignée focalisable (flèches haut et bas, Début et Fin), boutons « Monter » et « Descendre » sur chaque ligne, le focus est rendu à la commande utilisée après le déplacement, région `role="status"` pour la position (« Vitesse : position 3 sur 15. ») et pour l'affichage.
- Interrupteur : case native `role="switch"`, nom accessible = titre du thème, texte « Affiché » ou « Masqué » (masqué sur écran étroit). Le dernier thème affiché est désactivé, avec une phrase qui le dit.
- Enregistrement : un seul état lisible (« Aucune modification », « Modifications non enregistrées », « Enregistrement en cours… », « Résultat à vérifier », « Enregistré »). « Enregistré » n'apparaît qu'après la confirmation (réponse ou reçu). Brouillon gardé en mémoire de session (`useSectionDraft`), rattaché à la version lue : un brouillon d'une version plus ancienne n'est jamais rejoué.
- Erreurs : 412 recharge la configuration, abandonne le brouillon et le dit en une phrase ; 403 passe la section en lecture seule ; réseau ou 5xx laissent la commande en attente (panneau existant « Demande à vérifier », « Renvoyer la même demande ») et le brouillon intact.
- Permission : `MANAGE_OBSERVATION_THEMES`, « Gérer les signalements », ajoutée à la liste des autorisations de `people.tsx`. Elle part dans `grants` du `PATCH` existant et le résumé de confirmation utilise la même table de libellés (« Autorisations ajoutées / retirées »).
- Pictogrammes : `import.meta.glob` sur `client/assets/observation-themes/*.svg` (`?raw`, `currentColor`), repli neutre si un fichier manque. Aucune dépendance ajoutée.

Skills appliqués : `frontend-design` (cohérence avec l'identité existante plutôt qu'une nouvelle), `fixing-accessibility` (noms accessibles, clavier, focus rendu, annonces, états désactivés expliqués), `baseline-ui` (pas d'animation hors petits retours locaux, cibles de 44 px, pas de dégradé ; sa pile Tailwind ne s'applique pas, le panneau est en CSS maison).

## Commandes exécutées (dans `apps/web`)

- `npm ci` : réussi.
- `npm run typecheck` : sans erreur (`tsc --noEmit` puis `tsc -p tsconfig.check.json`).
- `npm test` : 13 fichiers, 186 tests passés, 0 échec, 0 ignoré. Aucun test du paquet web ne demande PostgreSQL. Les tests ajoutés sont 36 dans `observation-themes-model.test.ts`, plus 3 assertions ajoutées dans `school-bff.test.ts` et `console-route.test.ts`.
- `npm run build` : réussi (pictogrammes présents).

## Vérifié et non vérifié

Vérifié dans Chromium (Playwright, page `test/visual.html?page=themes`, API simulée) : glisser à la souris de 3 rangs, flèches au clavier avec focus conservé et annonce, interrupteur et compteur, enregistrement avec `If-Match`, états 412, 403 et lecture seule, rendu clair et sombre, 390 px de large.

Non vérifié : glisser au toucher sur un vrai écran tactile (le code repose sur les événements pointeur), lecteur d'écran (NVDA, VoiceOver), défilement automatique en bordure pendant un glissement (non écrit, la liste tient en un écran), contrastes mesurés, connexion réelle à l'API (la section n'a été vue que contre la maquette de `visual.tsx`), mode contraste élevé.

## Mise à jour : catalogue de 18 thèmes

Trois thèmes s'ajoutent à la fin, masqués à l'origine : `moving-off` « Démarrage », `bends` « Virages », `eco-driving` « Éco-conduite » (douze affichés sur dix-huit, inchangé).

- Aucun total n'est codé en dur dans le code de l'interface : le compteur (« 12 affichés sur 18 »), l'aperçu, les annonces et le corps de la commande sont calculés sur la liste reçue. Seuls les tests et les données de `test/visual.tsx` ont été mis au catalogue de 18 (un test vérifie aussi « 5 affichés sur 5 » sur une liste de cinq).
- Les SVG des trois nouveaux thèmes n'existaient pas encore : le repère neutre (carré arrondi) s'affiche à leur place, sans erreur. Ils s'afficheront à la compilation suivante dès que les fichiers seront présents.
- Résultats (dans `apps/web`) : `npm test` 13 fichiers, 186 tests passés, 0 échec ; `npm run typecheck` sans erreur ; `npm run build` réussi.
- Vu dans Chromium (page de revue, API simulée) : 18 lignes, 12 tuiles d'aperçu, aucun défilement horizontal (largeur du document 1280 et 390), liste d'environ 955 px de haut qui défile avec la page, aperçu collant à droite en bureau et sous la liste à 390 px, affichage du 17e thème qui passe le compteur à 13 sur 18 et ajoute une tuile.
- Non vérifié : les trois pictogrammes définitifs (absents), mêmes limites que plus haut (toucher réel, lecteur d'écran).
