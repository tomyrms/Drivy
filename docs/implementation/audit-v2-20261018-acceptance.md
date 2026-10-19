# Audit V2 : matrice de clôture et observations d’acceptation

Complément au [rapport V2](audit-v2-20261018.md). Rejeu demandé après livraison, sur le lot complet committé `a6c2043397ac5cf2d01fe640eff0479e41fcab70`, base V1 `7c117cd`. Aucun changement produit pendant ce complément. Une réussite de test n’est pas assimilée à une qualification Apple ou à un déploiement.

**État : rejeu intégral réussi, observations vérifiées le 18 octobre 2026 à 17:23:47 UTC (19:23:47 +02:00).** Les sorties sont conservées sous `artifacts/audit-v2-20261018/closure/`. `evidence-index.json` relie 27 groupes aux noms exacts des assertions et scénarios réellement réussis. Les deux autres groupes, compilation et intégrité, sont établis par les journaux de commandes terminées avec exit 0. Les limites de qualification restent distinctes des réussites.

## 1. Sorties publiques modifiées et bénéfice observable

| ID | Exigence / sortie | Contrôle concret | Avant | Observation de clôture |
|---|---|---|---|---|
| AUTH-1 | Le step-up ne change pas le compte | `bff.test.ts`, « une réauthentification refuse un autre compte sans remplacer la session initiale » | Test rouge : `/app` reçu au lieu de `/app?auth=failed` | Réussi : redirection `/app?auth=failed` dans le BFF et avec Keycloak réel |
| AUTH-2 | Refuser sans déconnecter le compte initial | Même test : aucun Set-Cookie, même session et sujet, transaction consommée. Recette Keycloak : autre compte valide, `me.personId` et cookie inchangés | Le callback tournait la session vers le nouveau compte | Réussi : cookie inchangé, même personne métier, session initiale conservée |
| AUTH-3 | Le même compte peut toujours confirmer | Test paramétré `reauthentification=true`, puis Keycloak avec le compte initial | Parcours déjà autorisé, invariant à préserver | Réussi : nouveau cookie et même `personId`, contrôles BFF et Keycloak |
| AUTH-4 | La connexion ordinaire peut changer de compte | Test paramétré `reauthentification=false` | Parcours volontairement autorisé | Réussi : autre sujet accepté et session tournée, JSON web |
| AUTH-5 | La reconnexion après logout reste possible | « l’invite de mot de passe n’est demandée que pour se réauthentifier ou après une déconnexion » | Marqueur relogin existant | Réussi : marqueur pris en compte puis effacé au callback |
| AUTH-6 | Ne pas exposer sujet/jetons au navigateur | « cookie __Host Secure HttpOnly SameSite, aucun jeton ni sujet OIDC au navigateur » | Invariant existant | Réussi : aucun sujet/jeton exposé, protections cookie conservées |
| GPS-1 | Une panne est visible et réessayable | `gps-read-error-retry-1440` et `gps-read-error-retry-390` | Rouge : titre d’erreur absent | Réussi aux deux largeurs : alerte visible, bouton actif, deux lectures puis statut confirmé |
| GPS-2 | La reprise retourne au vrai serveur | Recette officielle : première lecture 503 injectée, seconde non interceptée | Ancien composant sans bouton de reprise | Réussi : HTTP 200 du vrai BFF/API/PostgreSQL, alerte retirée et statut visible après reprise |
| GPS-3 | Une session perdue propose reconnexion | `gps-session-expired` | Rouge : erreur et action absentes | Réussi : « Se reconnecter » présent, aucun consentement fabriqué |
| GPS-4 | Un refus 403 reste masqué | `gps-permission-refusal-stays-hidden` | Déjà vert, invariant conservé | Réussi : aucun texte Accord GPS après le refus 403 |
| GPS-5 | Le chargement ne ressemble pas à un consentement | `gps-loading-is-not-a-consent` | Rouge : indicateur absent | Réussi : indicateur pendant attente, statut seulement après libération de la réponse |
| GPS-6 | L’action est utilisable au clavier et sur mobile | Deux scénarios GPS-1 : focus puis Entrée, viewport 390/1440, largeur et erreurs JS contrôlées | Pas d’action de reprise | Réussi : Entrée déclenche la reprise, aucun débordement ni erreur JS |
| RUN-1 | L’extension de recette reste explicite | Invocation `--audit-v2 --skip-account-recovery`, lecture `result.json` | Pas de contrôles V2 | Réussi : trois assertions V2 présentes, `account-recovery` explicitement exclue |
| RUN-2 | Utiliser Edge disponible sans changer le défaut du runner | `DRIVY_BROWSER_CHANNEL=msedge`, launch Chromium, version dans résultat | Chromium par défaut conservé | Réussi sous Edge 155.0.4283.62, autres canaux non revendiqués |

Preuves rouges originales : `step-up-red.log` et `gps-red-corrected/results.json`. Elles établissent des différences observées sur le même défaut, pas seulement une lecture favorable du nouveau code. La recette réelle complète les tests contrôlés, elle ne remplace pas ces contre-exemples avant correction.

## 2. Risques, régressions et frontières autour des changements

| ID | Risque / exigence | Contrôle qui exerce la frontière | Observation vérifiée dans le rejeu final |
|---|---|---|---|
| REG-1 | Préserver le correctif V1 de brouillon équipe | Cinq scénarios `closure/v1/results.json` : conflit desktop/mobile, abandon explicite, retry réussi, succès direct | Texte conservé pendant conflit, résolution explicite, nettoyage après succès |
| REG-2 | Préserver le correctif V1 OIDC | Tests API d’authentification, sujets non textuels et sujet opaque | Refus des types invalides, sujet opaque valide accepté |
| ERR-1 | Ne pas casser CSRF/origine ni réutiliser un callback | Tests BFF nommés : login/logout/invitation refusant origine/CSRF, callback cookie/state/délai/consommation unique | Refus attendus, aucun appel amont indu |
| ERR-2 | Concurrence et expiration de session | Tests BFF : refresh unique concurrent, session détruite pendant refresh, panne fournisseur vs refus, durée de session | Pas de résurrection de session, panne temporaire distinguée d’un refus |
| ERR-3 | Résultat inconnu après panne réseau | Tests command-store : réponse perdue, 5xx, session perdue pendant réponse. Recette réelle : réponse perdue après commit, reprise AP72 | Même opération, une seule version/écriture, saisie récupérée |
| ERR-4 | Refus d’écriture avant transmission | Tests de gestion : CSRF absent/étranger, origine étrangère, corps non JSON, REAUTH_REQUIRED | Refus avant amont, session préservée seulement pour REAUTH_REQUIRED |
| API-1 | Maintenir les contrats HTTP | Test « échange HTTP réel : méthode, Bearer, Idempotency-Key, If-Match et ETag, sans cookie ni redirection » | Méthodes/en-têtes attendus et absence de propagation indue |
| API-2 | Préserver permissions et isolation des écoles | Suite API PostgreSQL et recette : rôle drivy_app sans BYPASSRLS, ADMIN scolaire non opérateur, invitation sans rôle ajouté | Règles réellement exercées en DB et par API |
| FLOW-1 | Préserver élèves, formations, disponibilités et leçons | Recette officielle depuis invitation élève jusqu’à réservation et agenda | Bonne personne, prérequis réels, leçon et deux occupations durables |
| FLOW-2 | Préserver navigation, filtres et actions web | 41 scénarios nommés dans `closure/interactions/interaction-results.json` | Tous réussis, pas de redirection ni erreur JS inattendue |
| UI-1 | Respecter le design system, sans cosmétique gratuite | Diff produit limité à trois fichiers, composants Loading/Notice/ReadRetry existants, captures GPS et essais clavier | Aucun CSS, token, police ou dépendance ajouté |
| PKG-1 | Vérifier le code réellement empaqueté | Build web neuf, puis recette officielle servant `dist/client` depuis le BFF réel | Les parcours utilisent le bundle construit, pas seulement Vite |
| PKG-2 | Préserver distribution/cache des assets | Test BFF « les fichiers construits sont immuables, jamais une page ni un fichier absent » | Asset immuable, page sans cache, asset absent 404, manifest et CSP conservés |
| PKG-3 | Types, compilation et lint disponible | Types API/web/infra, builds API/web, `git diff --check` | Commandes réussies. Pas de script lint dédié à inventer |
| DOC-1 | Ne pas altérer le référentiel canonique | `npm run check:docs` | 556 fichiers présents et inchangés |

## 3. Exigences de mission et preuve correspondante

| Exigence explicite | Vérification / décision observable |
|---|---|
| Analyser V1 avant V2, éviter les répétitions | Plan basé sur `7c117cd`, comparaison des correctifs V1, REG-1 et REG-2. Aucun défaut V1 encore reproduit dans le périmètre testé. |
| Exécuter 20 spécialistes | 20 sessions Swarm ont produit `agents/01.md` à `20.md`. Le rapport principal associe chacun aux 20 périmètres demandés. Aucun résultat d’agent non exécuté. |
| Privilégier Luna et modèles exploratoires économiques | 16 Luna et 4 Sol utilisés. Le catalogue ne donnait pas les prix : coût minimal absolu non vérifiable, donc non affirmé. |
| Paralléliser sans dépasser les capacités | Deux vagues de dix explorateurs. Aucun changement simultané du produit par les agents. |
| Contexte réduit, recherches ciblées, rapports ≤300 mots | Brief local borné, périmètres disjoints, 20 rapports de 132 à 272 mots vérifiés. Aucun contexte complet envoyé aux explorateurs. |
| Réserver décisions, vérification et intégration au principal | Arbitrage et reproductions par le coordinateur. Agent 11 réutilisé pour revue statique, sans créer un 21e explorateur ni lui attribuer des tests non exécutés. |
| Fusionner, dédupliquer, comparer, évaluer impact/risque/effort | 26 signaux initiaux, deux bugs distincts. Rapport principal : preuve, fichier, impact, correction, confiance, effort et risque pour chacun. |
| Priorités P0/P1/P2/P3 et refus du travail artificiel | Confirmés : 0 P0, 1 P1, 1 P2, 0 P3. GPS reclassé P2. Propositions retirées et raisons dans le rapport, aucune refonte cosmétique. |
| Vérifier les 20 domaines sans faux positif | Rapports individuels et table de consolidation couvrent les vingt domaines. Native/performance : limites statiques explicites, pas de fausse qualification terrain. |
| Branche dédiée issue de V1, jamais main/master | `git merge-base` renvoie `7c117cdd6db44ff00311dba6b05b0de7e16e5cc2`, branche courante `audit/intelligent-v2-20261018`. Aucun diff produit par rapport à `a6c2043` pendant le rejeu. |
| Préserver fonctionnalités, architecture, design et API | REG/ERR/API/FLOW/PKG ci-dessus. Aucune dépendance, route API ou modèle DB ajouté, aucune modification Swift. |
| Ajouter des régressions utiles | Trois tests BFF supplémentaires, cinq scénarios GPS et trois contrôles réels dans le parcours existant. AUTH/GPS tracent chaque sortie modifiée. |
| Tests, lint et compilation disponibles | PKG-3, suites complètes API/web, interfaces réelles. Limites Node/Apple ci-dessous, aucun succès non exécuté. |
| Pas de migration destructive ou données de production | Bases neuves dans conteneurs d’audit loopback, migrations existantes seulement sur ces bases. Aucun accès production ni migration du produit modifiée. |
| Isoler les modifications et centraliser la revue | Worktree dédié, explorateurs en lecture seule sauf leur rapport, correctifs committés par le coordinateur. Worktrees V1 et principal non modifiés par l’audit. |
| Aucun déploiement ni fusion sans accord | Aucun push, merge ou déploiement exécuté. Les seuls services lancés sont des dépendances locales de test puis arrêtés. |
| Rapport avec comptes, décisions, fichiers, tests, limites, branche et commits | Rapport principal complet, présent complément ajoute la traçabilité et les noms de contrôles. Preuves locales conservées, scripts versionnés. |
| Rendre l’application réellement meilleure, pas seulement plus modifiée | AUTH-1/2 refusent maintenant un changement de compte auparavant accepté. GPS-1/2 rendent visible et récupérable une panne auparavant cachée. Aucun gain UX/performance non mesuré revendiqué. |

## 4. Limites reliées à une vérification, pas cachées par les totaux

| Limite | Observation / statut |
|---|---|
| Apple, iOS natif, VoiceOver, Dynamic Type, GPS terrain | Hôte Windows, pas de runner Apple exécuté. Audit statique réalisé, acceptation native **non qualifiée**. Aucun changement natif introduit. |
| Node 24 requis | Runtime local Node 26.8.1. Les commandes sont réellement passées sous cette version, **qualification Node 24 non exécutée**. Rejeu CI requis avant intégration. |
| Coût comparatif des modèles | Noms/routes observés, tarifs non exposés. Aucune économie chiffrée ni prétention de minimum absolu. |
| Performance à charge réelle | Pas de profil terrain ni de benchmark représentatif. N+1 et travail avant bail restent des opportunités à mesurer, pas des bugs prouvés. |
| Récupération de compte | Exclue par `--skip-account-recovery`. `skipped: ["account-recovery"]` présent dans le résultat lu, aucune réinitialisation de mot de passe. |
| Navigateurs | Edge exécuté, Safari et appareils non exécutés. Ne pas extrapoler les captures à une validation universelle. |
| Déploiement | Aucun environnement déployé testé ou modifié. Le bundle local et ses frontières sont qualifiés, pas une mise en production. |

## 5. Résultats du rejeu final

Toutes les observations des tableaux 1 et 2 ont été vérifiées sur le lot final. **Aucun test en échec ni ignoré dans les suites API et web** : `api-tests.json` contient 447 assertions réussies, `web-tests.json` 236. Ce ne sont pas seulement des totaux : l’index relie chaque identifiant AUTH/GPS/REG/ERR/API/FLOW/UI/PKG aux noms exacts et au fichier source de preuve.

- `v1/results.json` : cinq scénarios réussis, brouillon conservé sur conflit desktop/mobile et nettoyage après succès.
- `gps/results.json` : cinq scénarios réussis, y compris 401, 403, attente, panne puis reprise au clavier.
- `interactions/interaction-results.json` : 41 parcours réussis, dont empty/error/slow, dossier 404 vs panne, refus d’écriture sans faux succès, conflit avec saisie conservée, navigation annulée et historique, rôles interdits, menus au clavier, cibles tactiles de 44 px et dialogues à 390/1440 px. Les tableaux `accessibility` et `captures` y sont vides : aucun nouvel audit axe ni aucune campagne générale de captures n’est revendiqué.
- `acceptance.json` : 82 contrôles réels réussis sur le bundle fraîchement construit. Les assertions « Step-up réel : le compte différent est refusé et le compte initial reste connecté », « Step-up réel : le même compte est accepté avec rotation de session » et « Accord GPS : panne injectée visible puis reprise vers le vrai BFF/API/PostgreSQL » sont présentes.
- `api-build.log` et `web-build.log` : types/builds réussis, intégrité canonique 556 fichiers inchangés. Avertissements web existants conservés : script classique theme-init et chunk principal supérieur à 500 kB. Pas d’avertissement transformé artificiellement en succès de performance.

**Bénéfice réellement observé :** le compte différent, accepté avant correction dans le test rouge, est maintenant refusé sans perdre l’identité initiale dans une connexion Keycloak réelle. Une panne GPS, silencieuse avant correction, est maintenant expliquée et résolue par une action relisant le vrai serveur. La même action est aussi validée au clavier dans les scénarios à transport contrôlé. Les cas de refus 403, reconnexion et chargement ne sont pas confondus avec un accord.

La première commande de collecte web de ce complément n’avait fait que créer le dossier à cause d’une commande Windows multiligne. Elle n’a pas été comptée comme un test. La suite complète a ensuite réellement été exécutée, avec JSON nominatif, types et bundle. Aucun échec produit observé dans le rejeu de clôture. Aucun nouveau changement produit nécessaire.

Les résultats de la recette portent `checkedAt: 2026-10-18T17:23:47.614Z`. L’index a été vérifié avec `node artifacts/audit-v2-20261018/closure/collect-evidence.mjs` : il lit et contrôle les preuves existantes, ne simule pas de tests supplémentaires. Les documents seuls évoluent après le SHA testé. Les limites du tableau 4 empêchent toute affirmation de qualification universelle ou de préparation automatique au déploiement.
