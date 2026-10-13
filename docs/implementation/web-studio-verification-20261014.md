# Portail Studio — vérification du 14 octobre 2026

La campagne locale couvre **240 configurations distinctes**, **160 audits axe** et **41 scénarios fonctionnels distincts réussis**. Les **140 audits de pages produit et les 8 audits de composants fermés ne relèvent aucune violation ni règle indéterminée**. Les 12 audits de menus ouverts conservent leurs signalements bruts et leur diagnostic complémentaire, décrits ci-dessous. La CI finale réussit **439 tests API et 233 tests web**, les types, builds et contrôles documentaires. La recette intégrée réussit séparément **80 contrôles avec Keycloak, SMTP, BFF, API et PostgreSQL réels, isolés et alimentés uniquement en données synthétiques**.

La source produit finale est `2b4ca811a777d6f7283fd6910bd179451acc0cba`. Le pilote navigateur et la fixture sont ceux de `3f898d487a5827adbf6f4f92dbeeee1e8aea6d7c` ; le dernier commit produit corrige seulement la spécificité d’une règle d’espacement de l’agenda. Les mesures d’agenda ont été reprises après cette correction. Les heures des preuves JSON sont en UTC ; la date de ce rapport est celle de Zurich.

Ce document qualifie les essais exécutés, pas une conformité WCAG globale, un lecteur d’écran, un appareil physique ou un déploiement. Les périmètres fonctionnels et les choix de composition sont décrits dans l’[inventaire](web-studio-inventory-20261014.md) et la [direction Studio](web-studio-20261014.md).

## Sources et méthode

L’[agrégat final](proofs/web-studio-20261014/reports/coverage-summary.json) fusionne les résultats par `target|theme|width`. Une reprise remplace la même configuration du rapport initial ; elle n’augmente pas artificiellement les totaux. Edge `155.0.4283.45` exécute les vrais composants React avec le BFF synthétique de `apps/web/test/visual.tsx`, pilotés par `scripts/dev/check-web-redesign.mjs`.

| Périmètre | Configurations | Audits axe | Violations brutes | Règles indéterminées |
|---|---:|---:|---:|---:|
| 35 états produit | 210 | 140 | 0 | 0 |
| Deux fixtures de composants fermés | 12 | 8 | 0 | 0 |
| Trois fixtures de menus ouverts | 18 | 12 | 4 | 24 |
| **Total dédupliqué** | **240** | **160** | **4** | **24** |

Les captures couvrent 1440, 1024 et 390 pixels CSS, dans les thèmes clair et sombre. Axe est exécuté à 1440 et 390 pixels CSS. **Aucun débordement horizontal ni erreur JavaScript n’est relevé dans les configurations finales.** Les 35 états produit comprennent les annuaires et fiches élèves/équipe, les invitations, l’agenda, disponibilités et absences, trajets, formations et catalogue, coordonnées, confidentialité et profil, signalements, préférences et compte, ouverture/guide d’école, connexion et espace opérateur. Cette couverture par états n’implique pas l’essai de toutes les combinaisons possibles de données et de droits.

Le [rapport principal brut](proofs/web-studio-20261014/reports/review-results.json) reste conservé avec ses signalements. Les reprises finales sont également disponibles : [catalogue et formations](proofs/web-studio-20261014/reports/targeted-curricula-procedures-offerings-products-terms-formations-results.json), [équipe et fiche](proofs/web-studio-20261014/reports/targeted-team-team-detail-results.json), [trajets](proofs/web-studio-20261014/reports/targeted-trips-results.json) et [agenda](proofs/web-studio-20261014/reports/targeted-agenda-results.json). Les chemins de captures cités dans ces JSON désignent les artefacts locaux de la campagne ; la sélection publiée est la galerie ci-dessous.

## Parcours et interactions

Les **41 scénarios uniques réussis** portent notamment sur :

- Recherche, tri accessible, filtres, pagination, homonymes, liens natifs et conservation du contexte après fiche, trajet ou changement de sous-page ; dossier direct, y compris absent de l’annuaire ou inexistant, et panne d’une lecture secondaire sans disparition des dossiers.
- Agenda : changement de semaine, moniteur recherché, recherche élève, ouverture/retour du dossier, puis Disponibilités → Planning avec conservation de `week`, `instructor` et de la recherche.
- Formulaires : modification explicite, envoi par Entrée, erreur associée et focus du premier champ invalide, refus et conflit avec saisie conservée, garde de départ et historique arrière/avant, retour à la dernière valeur durable avant relecture tardive. La sauvegarde et le retour à la valeur initiale libèrent la garde des signalements.
- Menus : clavier, Échap, Tab et restitution du focus, options désactivées, valeur métier vide et option retirée, recherche sans émission de valeur, aucun résultat, fermeture lorsque le fieldset parent devient désactivé. Les menus simple et recherché restent dans le dialogue à 1440 et 390 pixels ; Échap ferme une couche à la fois.
- Thème manuel/système et rechargement, recherche profonde des réglages, accès console refusé aux rôles élève/moniteur, états vide/erreur/chargement, cases et radios natives, cibles tactiles et barre d’actions ne masquant pas les champs au clavier.

Le [rapport fonctionnel initial](proofs/web-studio-20261014/reports/interaction-results.json) contient 40 réussites et une mesure tactile en échec. Cette mesure incluait des contrôles présents dans le DOM d’un dialogue fermé, donc de dimensions nulles. Le pilote a été corrigé pour mesurer les contrôles rendus ; la [reprise tactile](proofs/web-studio-20261014/reports/touch-controls/interaction-filtered-results.json) réussit, sans correctif produit associé. Les reprises [Planning](proofs/web-studio-20261014/reports/planning-return/interaction-filtered-results.json) et [identité équipe](proofs/web-studio-20261014/reports/team-identity/interaction-filtered-results.json) remplacent des scénarios déjà comptés. On ne présente donc pas le rapport initial comme une exécution entièrement verte et on n’additionne pas ses reprises comme de nouveaux scénarios.

Pour le Ctrl-clic, le nouvel onglet et son URL sont vérifiés, puis cette même URL est rechargée pour y installer la fixture BFF. Ce montage qualifie le lien et le contexte de navigation ; il ne remplace pas une session OIDC réelle dans plusieurs onglets.

## Accessibilité : résultats et signalements conservés

Les quatre violations brutes `aria-hidden-focus` concernent uniquement les quatre sentinelles internes de focus du menu simple Base UI ouvert, dans les deux thèmes à 1440 et 390 pixels. Les **24 règles indéterminées** des trois variantes ouvertes se répartissent en `aria-hidden-focus` (8), `aria-valid-attr-value` (12) et `target-size` (4). Aucune règle axe ni aucun nœud n’a été exclu pour rendre les résultats verts.

Le [diagnostic de focus autonome](proofs/web-studio-20261014/reports/focus-guard-results.json) focalise directement les 12 sentinelles des trois variantes : menu simple, choix recherché et menu dans un dialogue. **Toutes redirigent immédiatement vers un vrai bouton**, puis conservent ce comportement après deux frames. Les menus restent ouverts pendant le scan : `aria-expanded` vaut toujours `true`, et toutes les références `aria-controls` existent avant et après axe. L’indétermination n’est donc pas attribuée à une fermeture du menu. Les actions du dialogue recouvertes temporairement par le panneau sont de nouveau atteignables et sans recouvrement après sa fermeture ; le diagnostic conserve leurs mesures et tests de pointage.

Cette classification rejoint l’[explication du mainteneur Base UI](https://github.com/mui/base-ui/issues/4668#issuecomment-4306200868) et la [limite de l’heuristique axe-core](https://github.com/dequelabs/axe-core/issues/4832). Elle ne transforme pas les quatre signalements bruts en « zéro violation absolu » et ne remplace pas un essai avec lecteur d’écran. Aucun `tabindex`, attribut `aria-hidden` ou garde interne de la bibliothèque n’a été modifié pour contourner l’analyse.

Les [mesures de contraste des tokens résolus](proofs/web-studio-20261014/reports/token-contrast-results.json) donnent **40 paires de texte sur 40 au-dessus de 4,5:1**, avec un minimum de **4,707:1**, et **9 paires de bordure sur 10 au-dessus de 3:1**. La combinaison potentielle claire `control-border` / `surface-muted` mesure **2,889:1**. Aucun contrôle requis défaillant utilisant cette combinaison n’a été démontré dans les pages auditées ; cette réserve reste ouverte pour les usages futurs. Les 50 paires ne sont pas présentées comme toutes conformes. Les séparateurs décoratifs et les états désactivés sont exclus du calcul des paires requises, comme indiqué dans la preuve.

Le reflow a été contrôlé à 720 pixels CSS avec un facteur de pixel de 2 et les animations réduites : c’est un **équivalent géométrique**, pas une commande de zoom natif du navigateur à 200 %. Les couleurs forcées sont une émulation navigateur ; l’apparence native des cases/radios et le masquage de leurs SVG sont vérifiés. Quatre [vues tactiles élèves/équipe](proofs/web-studio-20261014/reports/touch-viewport-results.json), à 390 × 844 pixels CSS et dans les deux thèmes, ne relèvent ni débordement ni erreur. Le scénario tactile vérifie une cible de 44 pixels et la sélection dans le vrai menu ; il ne qualifie pas un téléphone physique.

## CI intégrée réelle

Le workflow [Refonte · ouverture école navigateur — 38481209552](https://github.com/tomyrms/Drivy/actions/runs/38481209552) réussit sur `2b4ca811a777d6f7283fd6910bd179451acc0cba`. Son [résultat conservé](proofs/web-studio-20261014/ci-2b4ca81/result.json) comporte **80 contrôles réussis**, dans Chromium `153.0.8010.12`, avec Keycloak, vérification d’adresse et récupération de compte par SMTP, BFF, API et PostgreSQL isolés. Il vérifie notamment :

- Base initialement vide, rôle PostgreSQL `drivy_app` sans `BYPASSRLS`, secret du lien retiré avant OIDC avec PKCE, vérification réelle de l’adresse et absence de création d’école ou d’identité métier avant confirmation.
- Sauvegarde durable du guide puis réponse perdue, reprise AP72 sans double commande/version, reprise par un navigateur indépendant et après reconnexion, sans corps de commande ou données personnelles conservés dans le stockage navigateur.
- Validation et focus dans le guide, garde d’une demande au résultat incertain, adoption explicite des textes et activation après commit, tarif explicitement saisi, ajout de catalogue durable et reprise idempotente.
- Invitation équipe avec rôle explicite, confirmation distincte, courrier conservé chiffré puis effacé après acceptation SMTP, consentement au rattachement et vérification d’adresse. Un administrateur scolaire ne devient pas opérateur Drivy.
- Prérequis du premier élève, dossier, formation, affectation du bon moniteur et disponibilité réelle ; réservation d’un créneau futur via l’API, leçon, deux occupations et reçu durables. L’agenda relit cette leçon et ouvre le bon dossier, sans trajet ou position GPS inventés.

La [capture 08 finale](proofs/web-studio-20261014/ci-2b4ca81/08-premiere-lecon-planifiee-synthetic.png) a été relue. Elle a aussi permis de détecter une collision CSS entre `.row-meta` et les métadonnées de l’agenda, visible dans le build CI malgré l’espacement attendu en développement. Le sélecteur `.agenda-studio .agenda-lesson-meta` rend maintenant la priorité explicite, sans dépendre de l’ordre d’émission des feuilles. Les [six mesures finales](proofs/web-studio-20261014/reports/agenda-spacing-results.json) donnent 16 pixels entre moniteur et lieu lorsqu’ils partagent la ligne, puis 4 pixels verticalement à 390 pixels CSS. Les six captures et quatre audits axe de l’agenda ont été repris ; le nouveau build intégré et sa capture confirment la correction.

Le workflow [Refonte · vérifications — 38481209557](https://github.com/tomyrms/Drivy/actions/runs/38481209557) réussit sur la même source finale. Il passe **439 tests API dans 37 fichiers** avec PostgreSQL, **233 tests web dans 21 fichiers**, les contrôles TypeScript et builds API/web, ainsi que l’intégrité du manifeste et les contrats documentaires. Les [métadonnées CI et lignes de totaux filtrées](proofs/web-studio-20261014/reports/ci-checks-result.json) sont conservées, sans journal complet. Ces résultats sont lus dans cette exécution finale ; ils ne sont pas déduits de la fixture navigateur locale ni repris d’un ancien commit.

## Relecture visuelle et pièces conservées

**39 captures produit distinctes ont été examinées visuellement** pendant la passe, dont les deux nouvelles captures Agenda après la correction finale. Ce nombre désigne des fichiers image, pas des fichiers source ni 39 parcours métier indépendants. La [galerie de 21 images comparatives — 20 PNG et un JPEG](proofs/web-studio-20261014/index.html) montre une sélection avant/après, dans les deux thèmes et sur mobile, ainsi qu’un menu ouvert. Son [manifeste](proofs/web-studio-20261014/manifest.json) contient provenance, dimensions et empreintes ; les reprises finales portent leur propre source. Le [contrôle de la galerie](proofs/web-studio-20261014/reports/gallery-check.json) vérifie les 21 décodages et empreintes, ses filtres, l’absence de débordement à 1440/390 pixels et l’absence d’erreur JavaScript. Il qualifie la galerie, pas les parcours du produit.

Les JSON bruts, agrégats, diagnostics et résultat intégré copiés ici contiennent uniquement des données synthétiques Drivy. Le [manifeste des rapports](proofs/web-studio-20261014/report-manifest.json) donne leur origine et leur empreinte. Aucune capture de la démo Mercury, donnée externe, session authentifiée personnelle ou journal CI complet n’est publié dans ce dossier. La référence esthétique externe reste distincte des preuves du produit. L’exécution du déploiement et ses vérifications sont consignées dans une [attestation séparée](web-studio-deployment-20261014.md).

## Limites restantes

- Pas de certification WCAG, d’essai VoiceOver/NVDA physique, de validation de tous les navigateurs ou de tous les contenus possibles. Les menus ouverts gardent leurs signalements bruts classifiés et la paire de bordure potentielle conserve sa réserve.
- Pas d’essai Apple, GPS, batterie ou téléphone physique. Les essais locaux ne prouvent pas OIDC ou PostgreSQL ; seules les preuves CI intégrées ci-dessus qualifient leur périmètre isolé.
- La recette valide les parcours annoncés et les règles exercées ; elle ne prouve pas à elle seule l’acceptation esthétique du porteur, l’exhaustivité de la sécurité ou l’état d’un service déployé.
- L’audit de dépendances web effectué pendant cette passe rapporte zéro vulnérabilité avec `--omit=dev` et une vulnérabilité élevée de développement déjà présente pour `source-map-js@1.2.1` via Vite/PostCSS. Le détail et la version corrigée sont consignés dans l’[inventaire](web-studio-inventory-20261014.md#relecture-des-primitives-et-dépendances) ; aucune mise à niveau automatique n’est revendiquée ici.
