# #311 — reprise Catalogue et participants, 29 octobre 2026

Base `33232416`, branche de lot `codex/311-catalogue-courses-finish`. Les changements déjà intégrés sont conservés. Sauvegardes récupérées : Catalogue `1c532d71`, `dd37e256` ; Planning `4551b9f1`, `5b2f68de`, `8c77e829`, `eaa49d7c`. Aucun backend, contrat, migration, donnée réelle, rendu partagé ou dépendance verrouillée modifié par ce lot.

## Réalisation reprise

- #326/#327 : finitions mobiles de la fiche, pages d'édition, programme, tarifs et conditions récupérées. Notes historiques conservées avec attribution explicite. La mise à jour depuis la référence est maintenant interdite si sa lecture a échoué, y compris lorsqu'une ancienne réponse reste en mémoire. Un conflit des conditions communes conserve le texte saisi, relit les tarifs impactés, ferme la confirmation et exige une nouvelle relecture/acceptation ; une lecture échouée maintient l'adoption bloquée.
- #329 : inscrits, inscriptions annulées, attente avec échéance, inscription manuelle, annulation motivée, appel par séance, règlements/corrections et validation/retrait sont raccordés à la fiche de cours. Chacune de ces tâches a son onglet et ses confirmations. Les modèles, commandes, validations et droits retournés par le serveur sont conservés ; aucune présence, paiement ou validation n'est déduit d'un autre fait.
- Reprise après reçu : les lectures participants/inscrits suivent la révision des commandes, et une confirmation tardive libère l'identifiant de l'intention. Une nouvelle saisie identique après confirmation est donc une nouvelle commande, tandis qu'une commande encore incertaine reste bloquante et rejouable à la même clé. Une réponse ancienne ne remplace pas la feuille confirmée. Une erreur d'accès qui purge la lecture masque aussi sa copie confirmée locale ; les identifiants de cours et d'école de la réponse sont vérifiés.
- Le total des règlements inclut les paiements toujours actifs des inscriptions annulées : annuler l'inscription n'est pas rembourser. Une offre expirant exactement à l'instant courant est affichée expirée. Les styles de dialogue des participants sont limités à leur famille.

## Vérifications exécutées

Sous Node **24.22.1**, avec le verrou npm de `apps/web` :

- Typage client `tsc --noEmit` et typage serveur/contrats `tsc -p tsconfig.check.json` : PASS.
- Tests ciblés `formations.test.ts`, `pricing.test.ts`, `participants-model.test.ts`, `course-presentation.test.ts` et `portal-boundary.test.ts` : **37 tests, 5 fichiers, PASS**. Ils couvrent notamment indépendance paiement/inscription, absence non déduite, échéances, prix absent, historique/routage, et frontière sans rendu historique.
- Construction d'aperçu `vite build --config vite.preview-311.config.ts` : PASS, 3 138 modules, `legacyPresentationImports: 0`. L'avertissement sur le script classique `theme-init.js` est conservé, sans blocage du build.
- Navigateur Atrium, **données synthétiques** : ouverture de la fiche de cours et des quatre tâches ; saisie d'un règlement de 12,50 CHF en scénario « Réponse perdue » ; dialogue fermé pour laisser le panneau de vérification accessible ; reçu vérifié, attente disparue, total passé de 360,00 à 372,50 CHF. Nouvelle saisie de 12,50 CHF après confirmation : deux lignes distinctes et total 385,00 CHF. Aucune donnée réelle utilisée.
- DOM des participants mesuré à 390 et 1440 CSS px : pas de défilement horizontal global sur les vues consultées. Ce contrôle n'est pas une qualification visuelle : les captures Atrium sont noires et le viewport physique du volet invisible est de 1 px. Les actions DOM vérifiées ne qualifient ni les transitions/focus, ni le rendu mobile réel.

## À qualifier sur l'intégration

Raccord #320 « Préparer un permis » dans le guide unique ; vérification visuelle par le coordinateur puis essai du porteur sur le homelab. Les états refus/conflit/lecture impossible, l'ensemble des largeurs/thèmes, clavier, zoom et lecteur d'écran restent à vérifier sur le dernier SHA intégré. La recette navigateur du nouveau traitement de conflit des conditions n'a pas été exécutée ici (volet fermé avant cette étape) ; la logique est relue et typée. Les anciennes notes rapportent une recette antérieure, sans remplacer cette preuve.

Les règles contractuelles R28/R63/R106 et le contrat canonique restent des références ; ce lot conserve le protocole réellement déjà exposé par `course-facts.ts` et `course-model.ts` (présence autorisée après le début de la séance, `expectedVersion` dans le corps), sans prétendre qualifier une évolution serveur ou PostgreSQL. Les campagnes étendues, la sécurité et les performances attendent l'essai personnel demandé. Aucun ticket n'est clos sur ces seuls contrôles.
