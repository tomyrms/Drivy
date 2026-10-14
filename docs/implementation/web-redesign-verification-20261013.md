# Refonte web — vérifications du 13 octobre 2026

## Périmètre exécuté

Les contrôles utilisent Microsoft Edge **155.0.4283.45**, Playwright **1.63.0**, Vite local et les composants React réellement livrés. Le harnais `apps/web/test/visual.tsx` remplace uniquement les réponses BFF par des données fictives. Les écoles, noms, adresses, profils et formations présentés sont synthétiques.

Le test conserve un instantané de ses fixtures **dans son processus**, puis intercepte le document HTML lors du rechargement d’une URL du portail. Le routeur et les formulaires de production restent utilisés. Cette technique vérifie le comportement du client après relecture ; elle ne constitue pas une preuve de transaction PostgreSQL ou d’autorisation API.

## Résultats

| Contrôle | Résultat exécuté |
| --- | --- |
| Parcours navigateur | **18 scénarios réussis**, aucun échec |
| Campagne initiale | **23 pages × 1440, 1024 et 390 px × clair/sombre = 138 captures** |
| États complémentaires | **48 captures ciblées** : trajets, invitations équipe et six étapes du guide DRAFT, mêmes largeurs et thèmes ; **186 configurations distinctes** au total |
| Erreurs JavaScript et débordement du document | **Aucun** dans ces 186 configurations |
| Axe-core 4.14.0 | **92 audits initiaux + 32 audits complémentaires**, aux largeurs 1440/390, règles WCAG 2 A/AA et 2.1/2.2 AA : **0 violation, 0 vérification indéterminée** ; audits ciblés réexécutés après retouches |
| Reflow et mouvement réduit | Vue 720 CSS px, facteur de pixels 2 et `prefers-reduced-motion: reduce` ; absence de débordement |
| Typage et build web | Exécutés avec succès pendant cette passe |
| Tests web finaux | **233 tests réussis dans 21 fichiers**, exécutés après les corrections finales ; typage, build et diff-check également réussis |

Les pages parcourues : élèves, école, agenda, confidentialité, préférences personnelles, équipe, disponibilités, absences, signalements, formations, référentiels, procédures, offres, prestations, conditions commerciales, préparation, informations des élèves, invitations, connexion, compte/écoles, acceptation d’invitation, ouverture d’école, opérateur.

La campagne complémentaire ajoute les trajets, les invitations de personnel et les étapes **IDENTITY, PRIVACY, PROFILE, FORMATIONS, PRICING, REVIEW** d’une école en préparation. La relecture a aussi été recapturée après « Vérifier la préparation », avec le récapitulatif réellement affiché ; ses six dernières captures et quatre audits axe intègrent la date au format français. Les listes élèves/équipe et les deux dossiers détaillés ont été régénérés après leurs dernières corrections de densité et de doublons.

Les dix-huit scénarios automatisés couvrent :

1. Clair/sombre/système, conservation après rechargement, priorité du choix manuel, changement système et thème appliqué avant React.
2. Recherche de paramètres, résultat profond, clavier, Échap, restitution du focus, ouverture directe de « Conservation », puis retour au même champ par une nouvelle recherche.
3. Recherche d’élève, fiche, trajets, retour navigateur et filtre conservé.
4. Recherche sans résultat puis réinitialisation des filtres.
5. Menu du compte au clavier, changement du thème et restitution du focus après Échap.
6. Profil incomplet corrigé, confirmation d’écriture, disparition du signal et rechargement.
7. Coordonnées modifiées puis rechargées depuis leur URL.
8. Refus d’enregistrement, conservation de la saisie et absence de faux succès.
9. E-mail invalide, erreur au champ, focus et absence d’envoi.
10. Conflit de version 412, relecture, conservation de la saisie et nouvel envoi confirmé.
11. Départ avec saisie non enregistrée : navigation annulée, arrière annulé puis accepté, avant conservé.
12. Accès direct à la console refusé pour un élève.
13. Accès direct à la console refusé pour un moniteur sans rôle d’administration.
14. Liste vide.
15. Erreur de lecture avec possibilité de reprise.
16. Chargement lent sans erreur JavaScript.
17. Valeur B confirmée avec relecture d’école bloquée : retaper l’ancienne valeur A reste une modification enregistrable ; saisir C puis Annuler restaure B ; la relecture libérée conserve B et l’état « À jour ».
18. Signalements : inverser puis rétablir un réglage permet de partir sans confirmation ; une vraie modification déclenche la protection et reste conservée après annulation du départ ; une sauvegarde confirmée permet ensuite de partir sans dialogue.

L’inspection visuelle manuelle a porté notamment sur la liste dense sombre à 1440 et 390 px, le dossier et les coordonnées à 390 px. Le défaut confirmé pendant la recette — Échap intercepté par la navigation latérale alors que la recherche était ouverte — a été corrigé puis retesté. La barre d’enregistrement des signalements a également été replacée dans le flux après constat de recouvrement ; ses six captures et quatre audits axe ont été réexécutés sans échec.

## Captures et reproduction

Les artefacts locaux sont ignorés par Git :

- `artifacts/web-redesign-20261013/before/` : **10 captures antérieures à la refonte**, listes/dossier, coordonnées affichées, agenda et confidentialité, clair/sombre.
- `artifacts/web-redesign-20261013/after/` : campagne initiale, états complémentaires, captures supplémentaires dossier/formulaire/reflow et rapports `interaction-results.json`, `review-results.json`, `targeted-*-results.json`.

Depuis la racine, avec le Vite local sur `127.0.0.1:5173` :

```powershell
node scripts/dev/check-web-redesign.mjs --checks-only
node scripts/dev/check-web-redesign.mjs --captures-only
```

Pour reproduire les audits axe sans modifier les dépendances du produit :

```powershell
npm install --prefix .local/a11y --no-save --package-lock=false --ignore-scripts axe-core@4.14.0
node scripts/dev/check-web-redesign.mjs --captures-only --axe
```

`DRIVY_CAPTURE_TARGETS=learners,config` limite la campagne aux vues représentatives. `DRIVY_REVIEW_ORIGIN` accepte une origine loopback ; `DRIVY_BROWSER_CHANNEL` permet de sélectionner le navigateur installé. Aucun jeton OIDC, mot de passe, export de session ou trace réseau n’est enregistré.

## Complément intégré avant déploiement

La [recette GitHub Actions à `93c85d1`](https://github.com/tomyrms/Drivy/actions/runs/38468486729) réussit **80 contrôles** avec OIDC/Keycloak, SMTP, BFF/API et PostgreSQL réels sur données synthétiques, jusqu’à la première leçon réservée et la récupération du compte. [Rapport brut](proofs/web-redesign-20261013/reports/integrated-browser.json). Les [439 tests API et 233 tests web](https://github.com/tomyrms/Drivy/actions/runs/38468486548), types et builds sont également verts. Les sources produit sont identiques à `bad540b`, release [déployée et vérifiée](web-redesign-deployment-20261013.md) ensuite.

## Limites explicites

- **La recette intégrée locale reste indisponible.** Le démarrage de Docker Desktop échoue avant le moteur, sur son socket local `sailor-ingest.sock`. La campagne CI ci-dessus fournit désormais la preuve intégrée. Aucun volume ni état de compte local n’a été réinitialisé.
- Les refus de rôles du harnais vérifient l’interface ; les tests BFF/métier existants restent les preuves des permissions serveur et du cloisonnement scolaire.
- Le reflow 720 CSS px à échelle 2 est l’équivalent géométrique d’un écran desktop de 1440 px à 200 %. Il ne prouve pas une manipulation du contrôle de zoom natif du navigateur.
- Axe et les parcours clavier automatisés ne qualifient pas une conformité WCAG complète ni un lecteur d’écran physique. Les décisions sémantiques et les parcours longs demandent également une recette humaine.
- Les pages ont toutes été rendues et auditées ; chaque commande métier disponible n’a pas fait l’objet d’un nouveau test navigateur individuel. La confirmation tardive AP72 des disponibilités n’a notamment pas été simulée dans ce harnais.
- Le build conserve l’avertissement du script initial de thème classique et celui du bundle JavaScript principal supérieur à 500 Ko ; aucun objectif de performance n’est revendiqué.

Aucun déploiement, changement natif Apple ou traitement de données réelles n’a été effectué par cette recette.
