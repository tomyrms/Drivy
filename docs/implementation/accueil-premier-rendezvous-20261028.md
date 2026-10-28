# Accueil quotidien et premier rendez-vous — 28 octobre 2026

Lot web/API de #247 et première portion de #258, après le cadrage #254. À essayer avant fusion. Base : `e5166404` (master, PR #277 comprise). Branche : `codex/accueil-premier-rendezvous`. Le checkout principal et les travaux des autres sont préservés.

## Parcours retenu

Une école DRAFT garde son guide et son brouillon existants. Une école ACTIVE ouvre le planning existant, ses rendez-vous, ses filtres et leurs erreurs de lecture ; l’ancienne adresse `/apercu` rejoint ce même planning. Réglages → Préparation et la recherche de réglages donnent un accès explicite à la préparation (`apercu?from=configuration`). Les entrées de préparation d’une formation sont conservées. Une école archivée affiche son état et des accès à la consultation.

Le responsable suit une prochaine action issue de `setup-draft/next-actions` : invitation, dossier, formation/affectation, disponibilités puis réservation. Le bandeau existant de readiness reste responsable des blocages de l’école. Aucun nouvel accueil ni modèle de préparation n’est créé. La navigation terrain du moniteur et les données élèves ne changent pas dans ce lot.

Une réservation PLANNED ou une leçon COMPLETED laisse place au planning. Une école avec uniquement des leçons CANCELLED/NO_SHOW garde l’action à résoudre. Cela signifie « premier rendez-vous confirmé », **pas** « départ autorisé » : les contrôles actuels de conduite/GPS restent séparés.

Le bouton Actualiser et la relecture périodique du planning relisent aussi la préparation. L’heure de lecture est affichée pour l’action proposée ; une panne reste une erreur, jamais une réussite. Réduire l’action est conservé en mémoire dans la portée de l’école et des droits ; une action de nature différente se réaffiche. Ni données personnelles ni préférence d’accueil ne sont ajoutées au stockage navigateur.

La DA Studio et les composants existants sont réutilisés. Aucune bibliothèque, migration, permission, politique de données ou modification native. Les dépendances S07/S14/S15 et S16–S19 restent nécessaires à la simplification complète et au futur départ GPS-only ; elles ne sont pas réalisées ici. #247/#258 ne sont pas annoncées terminées dans leur totalité.

## Examiner le vrai client modifié, avec données synthétiques

Depuis ce worktree, sous Node **24** :

```powershell
npm ci --prefix apps/web
npm run dev --prefix apps/web -- --host 127.0.0.1 --port 5184 --strictPort
```

Ouvrir les adresses ci-dessous. Cette entrée de revue existe déjà dans le dépôt et utilise les composants de l’application ; les réponses serveur et les personnes y sont fictives. Elle n’est pas incluse dans le build de production et ne qualifie pas la requête PostgreSQL modifiée.

- Accueil actif et invitation en attente : <http://127.0.0.1:5184/app/test/visual.html?page=overview&shell=1&agenda=mixed&first-lesson=pending>.
- Préparation accessible directement : <http://127.0.0.1:5184/app/test/visual.html?page=overview&shell=1&agenda=mixed&from=configuration>.
- École en préparation : <http://127.0.0.1:5184/app/test/visual.html?page=overview&shell=1&status=draft>.
- École archivée : <http://127.0.0.1:5184/app/test/visual.html?page=overview&shell=1&status=archived>.
- Lecture de la prochaine action en erreur : <http://127.0.0.1:5184/app/test/visual.html?page=overview&shell=1&agenda=mixed&first-lesson=error>.
- Planning vide, création avec élève sélectionné : <http://127.0.0.1:5184/app/test/visual.html?page=overview&shell=1&agenda=empty&first-lesson=plan>.

À essayer : retrouver le planning immédiatement ; ouvrir l’invitation ; revenir ; réduire l’action puis naviguer et revenir ; retrouver Préparation par Réglages et la recherche ; examiner l’erreur et le petit écran au clavier. Un rechargement de l’adresse réécrite `/app/gestion/…` quitte l’entrée synthétique : rouvrir le lien de revue ci-dessus.

Pour le cas annulé/absent, la recette métier sera effectuée avec vraie PostgreSQL après le retour du porteur : annuler le seul premier rendez-vous et relire `next-actions`, puis réserver réellement et vérifier que le guidage disparaît. Le test d’intégration existant a été adapté à cette régression.

## Vérification

Node 24.22.1. Compilation web (`npm run build --prefix apps/web`), contrôle TypeScript web (`npm run typecheck --prefix apps/web`) et compilation API (`npm run build --workspace @drivy/api`) exécutés avec succès. Aucun résultat de suite de tests, de recette PostgreSQL, de test physique ou de déploiement n’est revendiqué. Le build Vite conserve l’avertissement du script classique `theme-init.js` ; il produit les fichiers normalement.

Les contrôles ciblés et requis avant fusion attendent l’essai du porteur. Aucun workflow complet lancé ; commit de revue marqué `[skip ci]`. Pas d’IPA : aucune modification iOS. Pas de déploiement, ni de migration à appliquer.
