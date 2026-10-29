# EPIC #311 — livraison pour essai personnel

## Reprise du 29 octobre 2026

Branche `codex/epic-311-rebuild`, base retrouvée `33232416`. Aucun travail du dépôt principal sale n’a été déplacé ou écrasé. Comparaison des commits et patches avec les branches `backup/311-*-20261029-2050` avant récupération :

| Sauvegarde | Reprise |
| --- | --- |
| entry `0fdfb2de` | Entrée, écoles, invitation, récupération ; contrôleurs et présentation intégrés, aperçu isolé |
| setup `8b2d7fd9` | Ouverture et guide ; contrat et propositions du catalogue conservés |
| planning `eaa49d7c` | Quatre commits manquants, participants, appel, règlements et reprise des reçus |
| catalogue `dd37e256` | Deux commits manquants ; relecture obligatoire des textes et confirmation après conflit |
| team `9f903ea6` | Déjà intégré par patch équivalent ; aucun doublon rejoué |

Les trois agents ont terminé dans des worktrees distincts, puis leurs commits ont été repris par le coordinateur. Notes : [catalogue et participants](epic-311-catalogue-participants-reprise.md), [retrait](epic-311-retirement.md), [audit de parité](epic-311-retirement-audit.md). Les anciens paragraphes de `reprise-epic-311.md` sont historiques ; ils ne décrivent plus le routage actif.

## Résultat intégré

Le portail Cal.com / Untitled UI / shadcn avec la DA Drivy est le seul frontend de production. Les liens existants restent utilisables ; le paramètre historique de présentation est retiré. Entrée et pages secondaires utilisent le même socle. Les fragments d’invitation sont consommés avant les appels réseau. La recherche de réglages navigue et place le focus après fermeture du dialogue. Les textes de confidentialité ne peuvent pas être adoptés après une relecture échouée. Les blocages serveur du premier rendez-vous restent visibles.

60 fichiers historiques supprimés (dont 40 TSX et 15 CSS). Les modules métier sans rendu restent partagés. Contrôle AST des imports transitifs et garde Vite : aucune ancienne présentation ou donnée fictive dans le bundle réel. [Inventaire des 110 vues](epic-311-inventory.json) avec qualification exhaustive explicitement en attente.

## Contrôles avant essai

- Typage client, serveur et contrôles TypeScript ; compilation production exécutés.
- 91 tests ciblés de routage, frontières, recherche, BFF et réauthentification réussis lors de l’intégration. Les agents ont aussi exécuté leurs contrôles ciblés ; les décomptes se recouvrent et ne sont pas additionnés.
- Recette finale synthétique : **34 contrôles réussis**, 16 destinations à 390 px sombre et 1440 px clair, erreurs JavaScript, débordement et focus de la recherche. Préparation revérifiée avec son formulaire visible et captures relues après correction du contrat partagé. 13 tests ciblés supplémentaires (frontières de production, préparation, guidage agenda) et typages client/contrôles réussis après les derniers commits.
- Aucun résultat utilisateur authentifié, GPS/batterie/VoiceOver physique ou qualification exhaustive revendiqué. Campagnes complètes après essai du porteur.

## Déploiement et retour arrière

`scripts/homelab/deploy-web-311.py` produit un plan en lecture seule par défaut. Activation explicite `--execute`, accès SSH avec clé d’hôte connue. Sauvegarde `pg_dump` du seul `drivy_refonte` dans CT113, mode 0600 ; table des matières et tous les blocs relus par `pg_restore`. La sauvegarde reste sur le homelab. La vérification d’archive ne constitue pas une répétition de restauration.

Déploiement dans une nouvelle release web immuable sur CT114. Configuration privée sauvegardée et empreintes inchangées contrôlées, BFF compilée et dépendances verrouillées repris à l’identique depuis la release active. Pas de migration ; API, worker, identité et ingress restent sur leurs processus. Un override systemd modifie seulement le répertoire de la web app. Vérification HTML, SHA et processus après bascule. Les anciens assets hachés restent disponibles pour les onglets déjà ouverts, sans être importés par le nouveau portail.

Un reçu privé conserve l’état précédent. En cas d’échec d’activation, retour automatique au rendu précédent sous garde de concurrence. Retour manuel disponible via `--rollback <id>` (plan) puis `--execute` (nouvelle sauvegarde préalable). Les contrôles refusent un déploiement concurrent ou un état différent de celui relu.

## Déploiement effectif — 29 octobre, 22:25 Europe/Zurich

- URL : <https://drivy.shulker.ch/app/>.
- Commit source déployé : `4af4b0e6748081f90201169132cccd5c9fd6cfdb` ; les commits suivants de cette note ne changent pas le code servi.
- Sauvegarde CT113 : `/root/drivy_refonte-before-web311-20261029T212517Z.dump`, 1 921 190 octets, catalogue et tous les blocs relus avec succès ; aucune restauration réelle effectuée.
- Reçu de déploiement et rollback : `20261029T212518Z-4af4b0e67480`. Plan de retour vers `be8a02457ef2c8877117e9a13557b288738fc4bf` vérifié après activation ; pas de rollback exécuté.
- Web actif, zéro redémarrage automatique ; API, worker, identité et ingress inchangés. Configuration privée et BFF compilée inchangées. Ingress est un service oneshot actif, sans processus permanent : le contrôle tient compte de ce type d’unité.
- HTTPS public : six routes d’entrée/préférences servent le HTML exact ; **104 fichiers statiques vérifiés par empreinte**. Réponse sans cache, CSP stricte sans `unsafe-eval`, session anonyme vérifiée sans exposer son jeton.
- Navigateur : nouvelle connexion rendue et capture relue, préférences/version, invitation, récupération, ouverture et opérateur chargés. Aucun plantage JavaScript constaté sur ces pages ; l’appel des préférences sans connexion est refusé avec 401 et propose de se reconnecter, comme prévu. Contrôle Atrium : nouveau portail et SHA exact.

Limites connues de cet essai : récupération par e-mail toujours désactivée dans la configuration existante, avec message explicite ; une URL arbitraire hors des routes `/app` connues (ex. `/app/inconnue`) garde la réponse JSON 404 de la BFF. Le composant de page introuvable est disponible sur les routes de console servies ; étendre le fallback BFF devra préserver les 404 des API/assets et être qualifié après le retour du porteur. Aucun parcours authentifié avec données réelles n’a été effectué à sa place.

À essayer personnellement : connexion et choix d’école ; agenda/leçons/cours ; dossier élève ; équipe/invitations/accès ; formations, tarifs et textes ; participants/appel/règlements ; réglages, recherche, thème et mobile. `master` et les issues attendent le retour du porteur puis les campagnes complètes.
