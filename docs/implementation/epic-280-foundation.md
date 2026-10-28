# EPIC #280 — fondation web, composants et contrôles ciblés

Décision et exécution du 28 octobre 2026. Périmètre : W02 #282, W03 #283, compositions partagées W05 #285, W06 #286, W07 #287 ; contribution aux protections de retour W28 #306 et à la revue W29 #307. Cette note qualifie le socle et les contrôles décrits, pas l’acceptation intégrale de l’EPIC ni la recette physique mobile. Les parcours métier, captures et déploiement ont leur suivi séparé.

## Direction et provenance

La section web de `DESIGN.md` remplace la prescription Studio antérieure par la hiérarchie Untitled UI adaptée à Drivy : navigation nommée, titres affirmés, surfaces unies, boutons rectangulaires arrondis, listes et fiches lisibles. Cobalt `#245BD6`, fond `#F7F8FA`, mode sombre Soft Charcoal conservé. Untitled UI sert de référence de composition ; aucun composant, fichier ou actif payant du kit n’est copié. La partie Apple de `DESIGN.md` reste distincte et inchangée.

Le code des primitives provient du registre officiel [shadcn/ui](https://ui.shadcn.com/docs), style `base-nova`, CLI 4.23.0. Installation sélective : Button, Input, Textarea, Field, Badge, Skeleton, Empty, Alert, Dialog, ToggleGroup et leurs dépendances Label/Separator/Toggle. La licence MIT officielle est conservée dans `apps/web/client/components/ui/LICENSE.md`. Adaptations : tokens Drivy, français, tailles tactiles, surfaces sémantiques, dialogues, désactivation lisible. Les directives RSC inutiles sont retirées dans ce client Vite.

Base UI 1.9.0, déjà présent, reste l’unique moteur des dialogues et sélecteurs. Aucun Radix, routeur, moteur de tableaux, magasin optimiste ou second cache métier n’est ajouté. Les radios et cases natives restent natives. Manrope locale et sa licence existante sont conservées ; aucun CDN, appel de police ou ressource décorative tiers.

## Intégration et contrats conservés

- `components.json`, alias `@/` TypeScript/Vite et Tailwind 4.3.3. Import des tokens et utilitaires sans preflight ; `data-theme` est l’unique sélecteur de thème. `cn` est local (`clsx` + `tailwind-merge`).
- Dépendances exactes ajoutées : `class-variance-authority` 0.7.1, `clsx` 2.1.1, `tailwind-merge` 3.7.0, `lucide-react` 1.63.0. Tailwind et son plugin Vite : 4.3.3. `cn` et `tw-animate-css`, non nécessaires au résultat, sont retirés. Manifestes et verrou mis à jour ensemble.
- Les correctifs de sécurité des outils Vite 8.3.5 et Vitest 5.0.5 remplacent respectivement 8.3.1 et 5.0.1. Aucun scanner, contrôle de sécurité ou assertion existante n’est désactivé.
- `ui.tsx` et `console/layout.tsx` restent les compositions Drivy : TextField, TextArea, CheckField, ConfirmDialog, Notice, EmptyState, Loading, RecordSearch, FilterTabs, ListPagination, SplitView et DetailPanel. Les signatures, valeurs, identifiants accessibles, contrôleurs, versions et résultats métier sont conservés. FilterTabs utilise des boutons pressés, pas de faux panneaux d’onglets.
- `SelectField` conserve Select/Combobox Base UI, recherche et observation du fieldset désactivé. Les menus d’un dialogue utilisent son conteneur de portail. Aucun second formulaire responsive, arbre de liste ou chargement privé caché n’est créé par le socle.
- Première lecture sans données : squelette décoratif et annonce ; une actualisation conserve les données existantes. Refus, attente, réponse absente et confirmation durable continuent de venir du moteur de commandes existant. Les erreurs restent près de la tâche.
- ConfirmDialog utilise le dialogue Base UI ; cible, conséquence et acquittement proviennent toujours du domaine. Focus initial sur le titre, focus contenu puis restitué à l’élément d’ouverture valide. Retour, confirmation et Échap sont bloqués durant l’envoi. Le contenu défile en petite hauteur sans remonter le formulaire au changement de largeur.
- SettingsSearch utilise le même Dialog avec recherche et résultats existants ; le focus de destination n’est pas volé lors d’une navigation.
- `UiSuspendedContext` suspend uniquement les portails durant la relecture d’accès de Console. Les états des formulaires restent chez leurs contrôleurs. Les overlays sont cachés immédiatement, sans animation de sortie exposant des données anciennes. La propriété `hidden` n’est imposée que pendant la suspension, pour préserver le masquage natif Base UI à la fermeture normale.

Les tokens historiques `--surface`, `--surface-inset`, `--border`, `--text`, `--muted`, `--accent`, `--accent-fill`, `--accent-soft`, `--radius-panel`, `--radius-field`, `--font` restent disponibles aux domaines. Les rôles shadcn pointent vers ces variables. Couches : dialogues 100, choix 110 ; les menus restent au-dessus du tiroir de navigation.

Les anciennes règles shell/navigation, double carte d’entrée, largeur 720 px de l’ancien en-tête d’accès, signalements globaux et tableau mobile people sont retirées après transfert aux feuilles de composition correspondantes. Les règles structurelles d’ancrage du menu de compte sont conservées, son apparence appartient à `access.css`. Les tables génériques restent utilisables par les autres domaines.

## Vérifications indispensables exécutées

Environnement : Node **24.22.1**, Windows, builds Vite de production, Edge Chromium sans interface. Commandes depuis `apps/web` : `tsc --noEmit`, `tsc -p tsconfig.check.json`, `tsc -p tsconfig.server.json`, `vite build`. Tous passent. Le message Vite préexistant concernant `theme-init.js` sans `type="module"` reste attendu : le script local doit s’exécuter avant React ; son comportement CSP n’est pas modifié.

Contrôles ciblés exécutés, sans suite complète :

| Contrôle | Résultat |
|---|---:|
| Thème (`theme.test`) | 2 réussis |
| BFF, cookies `__Host` et refus Origin | 7 réussis, autres cas filtrés |
| BFF réauthentification, preuve/session, même compte, autre compte, CSRF | 4 réussis, autres cas filtrés |
| Protocole de session | 5 réussis |
| BFF fichiers statiques, CSP et cache | 1 réussi, autres cas filtrés |
| TypeScript client, checks et serveur | réussite |
| Build de production et `git diff --check` du socle | réussite |
| Audit npm du workspace web, dépendances de développement incluses | **0** vulnérabilité signalée |

Le script `scripts/dev/check-web-280-access.mjs` ajoute six vérifications essentielles exécutées avec les vrais composants React, uniquement sur la fixture locale `test/visual.html` :

1. Brouillon de coordonnées et recherche de réglages conservés après retour avec les mêmes droits ; console `hidden` + `inert`, aucun dialogue ou menu exposé durant la relecture.
2. Relecture indisponible : ancienne école toujours masquée, brouillon gardé en mémoire, action Réessayer disponible.
3. Retrait du rôle Administration : sortie explicite, ancien formulaire et ancienne navigation retirés.
4. Changement de personne : ancien brouillon purgé, nouvelle ouverture depuis la projection autorisée.
5. Retrait d’accès en cours : dialogue suspendu puis restauré, actions toujours bloquées, Échap refusé, une seule mutation, résultat seulement après réponse.
6. Sélection au clavier dans le dialogue, option désactivée évitée, tabulation contenue, fermeture et restitution du focus.

Résultat final : **6/6, aucune exception React**. La fixture modélise les réponses BFF et l’identité confirmée ; l’événement `pageshow.persisted` est synthétique. Ce contrôle ne prouve pas un vrai cycle bfcache de navigateur, une session OIDC réelle ou une écriture PostgreSQL. Le script refuse un hôte non loopback et attend le marqueur de fixture avant toute action. Exécution :

```powershell
$env:DRIVY_REVIEW_ORIGIN = 'http://127.0.0.1:5187'
# Facultatif : URL file:// du module playwright-core si infra/dev/node_modules est absent.
$env:DRIVY_PLAYWRIGHT_MODULE = 'file:///chemin/vers/playwright-core/index.mjs'
node scripts/dev/check-web-280-access.mjs
```

## Revue sécurité et confidentialité

La fondation ne modifie aucun serveur BFF, schéma d’autorisation, protection Origin/CSRF, cookie, protocole de réauthentification, clé d’idempotence, version If-Match ni reçu. Les changements Console de W28 revalident identité, école, adhésion et époque d’accès avant de rendre les données ; le contexte n’est conservé que si cette portée est identique.

Pas de nouveau stockage de données scolaires, jetons, positions ou corps de commande. Le thème neutre conserve son stockage existant. Les métadonnées de commandes déjà permises par le magasin existant ne deviennent pas un brouillon privé persistant. Aucun service worker, IndexedDB, télémétrie ou API décorative n’est ajouté. Les imports paresseux du client restent en place ; aucun préchargement de tous les dossiers n’est ajouté au socle.

CSP BFF conservée : `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; manifest-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'`. Le test BFF vérifie l’en-tête et la politique de cache. Les ressources du build sont locales et sans source map. La fixture Vite n’applique pas l’en-tête BFF de production : ce smoke ne certifie donc pas à lui seul tous les popups sous la CSP déployée. Vérifier ce point à la recette du candidat sans assouplir la politique.

## Taille des ressources, avant et après

Mesure du 28 octobre 2026. Base figée **e5166404**, extraite séparément ; candidat : **52fe0320 + modifications #280** présentes au moment du build final du socle, après nettoyage du tableau mobile. Node 24.22.1 dans les deux cas ; Vite 8.3.1 pour la base, 8.3.5 pour le candidat. La base utilise ses dépendances initiales via une jonction non modifiée. Les builds temporaires n’écrivent pas dans la source d’origine.

Tailles en **octets**, gzip calculé par `node:zlib.gzipSync` avec les mêmes options par défaut sur chaque fichier, puis additionné. Il ne s’agit pas de tailles HTTP observées. Le graphe statique inclut le chargeur et les imports statiques récursifs de la page ; les imports dynamiques non demandés ne sont pas inclus.

| Ressource | Base brut | Candidat brut | Base gzip | Candidat gzip |
|---|---:|---:|---:|---:|
| Chargeur initial JS | 327 046 | 329 513 | 99 154 | 100 014 |
| CSS initial | 79 601 | 101 773 | 14 129 | 18 174 |
| Graphe statique page compte | 526 687 | 586 144 | 165 766 | 184 152 |
| Graphe statique console | 966 331 | 1 067 440 | 288 596 | 319 038 |
| Tous les chunks JS | 991 277 | 1 092 754 | 296 962 | 327 549 |
| Tous les CSS | 116 134 | 166 299 | 21 375 | 30 225 |
| Manrope WOFF2 | 53 876 | 53 876 | 53 887 | 53 887 |

Le chargeur initial augmente de **860 octets gzip** ; le graphe de console augmente de **30 442 octets gzip**. La croissance totale comprend la refonte complète des domaines et l’intégration des fonctions #253, pas seulement shadcn. Aucun gain de chargement, CLS ou réactivité n’est revendiqué à partir de ces tailles. Une fonte WOFF2 étant déjà compressée, sa taille brute est la métrique utile.

Budgets de revue adoptés pour ce candidat à partir de la base : chargeur gzip ≤ base +5 % (104 111 octets), CSS initial ≤ base +30 % (18 367), graphe console ≤ base +12 % (323 227), CSS total ≤ base +50 % (32 062). Cet instantané tient ces plafonds. Ce sont des limites d’artefact, pas une garantie de temps de réponse. Recalculer sur l’artefact effectivement déployé si le code change.

Reproduction : construire les deux révisions isolées avec leurs verrous (`vite build --outDir <dossier-temporaire>`), relever chaque fichier sous `assets`, additionner sa longueur et celle de `gzipSync(contenu)`. Pour les graphes compte/console, partir de `index-*.js` + `App-*.js` ou `Console-*.js`, puis parcourir les imports `from "./…js"`/`import "./…js"` en dédupliquant. Les builds ne contiennent aucune source map. Les temps de compilation chauds locaux ne sont pas une mesure d’affichage utile.

## Contrastes mesurés et limites

Calcul WCAG de luminance sur les paires sRGB opaques utilisées par les tokens :

| Paire | Clair | Sombre |
|---|---:|---:|
| Texte sur surface | 16,03:1 | 14,00:1 |
| Secondaire sur surface | 6,48:1 | 7,72:1 |
| Lien/focus sur surface | 5,93:1 | 7,59:1 |
| Texte blanc sur primaire | 5,93:1 | 5,25:1 |
| Texte accent sur sélection | 5,19:1 | 5,41:1 |
| Bordure de contrôle sur surface | 3,39:1 | 4,59:1 |

Ces rapports ne constituent pas une certification de toutes les compositions, états désactivés ou captures. Le fonctionnement physique Safari iOS/Chrome Android, clavier mobile, lecteur d’écran, affichage utile/CLS/latence réseau et scénarios exhaustifs restent à qualifier. Conformément au mandat utilisateur, l’essai visuel sur le homelab précède la campagne complète #309/#84. La préparation/sauvegarde/rollback et la confirmation finale avant production relèvent du suivi de livraison ; aucun déploiement n’est effectué par cette fondation.
