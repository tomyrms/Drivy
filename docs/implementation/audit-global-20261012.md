# Audit global et corrections — 12 octobre 2026

Branche `claude/audit-global-20261012`, partie de `master` (`668deaa`). Demande du porteur : audit technique et fonctionnel de toute l’application, puis corrections, tests et bilan par priorité. Suite des passes du [10 octobre](audit-global-20261010.md) et du [11 octobre](audit-parcours-20261011.md), dont les constats ouverts n’ont pas été redécouverts.

Méthode : cinq audits en lecture seule (écrans iOS, API et base, UI/UX, architecture et code mort, fiabilité terrain et sécurité), puis des lots de correction à fichiers disjoints, chacun relu et vérifié avant son commit. L’audit UI/UX sur captures n’a pas abouti : son agent a été arrêté par la limite d’usage hebdomadaire (voir « Non fait »).

## Constats

65 constats distincts après fusion des doublons (68 bruts : le trajet révoqué était vu des deux côtés, le verrou Face ID par deux audits, la règle « à venir » aussi).

| Priorité | Trouvés | Corrigés | Laissés |
| --- | --- | --- | --- |
| P0 | 1 | 1 | 0 |
| P1 | 8 | 7 | 1 |
| P2 | 30 | 18 | 12 |
| P3 | 26 | 15 | 11 |

Le P1 laissé est la règle « à venir » écrite cinq fois : le filtre du dossier est aligné, les autres copies restent à factoriser.

## Décisions du porteur (12 octobre 2026)

- Trajet coupé par un changement de droits : correction complète (serveur et app).
- Règles de terrain : laissées à l’appréciation de la session ; les quatre corrections proposées ont été faites (reprise sans réseau, ancre à l’arrêt, heure réelle du départ, purge des positions envoyées).
- Confidentialité côté élève : les quatre fermetures acceptées (anciennes versions du bilan, notes des repères, motif d’une correction, annulation d’une leçon commencée).
- Bureau : l’administrateur lit les bilans partagés.

## P0

- **Trajet arrêté et bloqué par une affectation faite au bureau.** Créer ou terminer une affectation du moniteur avançait son époque d’accès. Le serveur révoquait son trajet en cours ; l’app arrêtait le GPS, gardait les positions sous l’ancienne portée sans jamais les envoyer, et refusait tout nouveau départ (seule issue : désinstaller). Serveur : migration 025, le déclencheur ne révoque plus que sur une vraie perte de droit (adhésion close, rôle retiré) ; la fin de l’affectation à la formation de la leçon révoque toujours. App : les faits de collecte ne bloquent plus un départ ; un trajet scellé adopte la nouvelle époque après relecture de `/me` (même adhésion active, rôle moniteur) ; un trajet en cours garde sa portée jusqu’à sa fermeture. L’école reste juge à chaque envoi.

## P1 corrigés

- **Verrou Face ID et masque de confidentialité sous les feuilles** : une fiche ouverte restait visible dans le sélecteur d’apps et utilisable après annulation de Face ID. Ils vivent dans leur propre fenêtre, au-dessus des feuilles et du rideau ; le masque se pose dès que l’app devient inactive.
- **Bilans illisibles au bureau** : la console les affichait « indisponibles » pour un administrateur non affecté. Migration 026 : l’administrateur et l’élève lisent la révision courante ; un bilan privé ou retiré reste invisible ; le moniteur affecté garde l’historique.
- **Heure de départ fausse après un départ hors ligne** : l’app envoie l’instant du geste (`startedAt`, facultatif). Le serveur le garde s’il est passé, du jour du rendez-vous et de moins de 12 heures, sinon il prend son heure de réception : une commande en file n’est jamais bloquée par son horodatage.
- **Un seul signalement hors réseau** : la demande repart seule (5 s, 15 s, 60 s, et au retour du réseau). L’invariant « une demande par école » est conservé : un second signalement attend toujours le premier.
- **« Reprendre » impossible sans réseau** : la reprise rouvre un segment si le bail local est valide et que l’école est seulement injoignable ; un refus (401, 403, 404) reste un refus.
- **Positions jamais effacées** : chaque position restait trois fois sur l’iPhone. Le coffre purge points et lots d’un trajet dont la finalisation est acquittée, ou retiré par l’école, jamais si un lot n’a pas de reçu.
- **Copie de la réauthentification qui avait perdu une garde** : la correction d’issue utilise la fonction commune (refus d’un `auth_time` dans le futur).

## P2 et P3 corrigés

API et web :
- Replay : chaque page déchiffrait tout le trajet (coût quadratique) ; seuls les lots utiles sont lus.
- Index sur les reçus d’opération, les occupations d’une leçon et les trajets d’une leçon (migration 025).
- Limite de connexions du bureau commune à tous les visiteurs derrière Caddy : adresse du visiteur posée par le proxy (`WEB_TRUST_PROXY`), effective au prochain déploiement.
- L’élève ne reçoit plus les anciennes versions d’un bilan, ni les notes des repères préparés, ni le motif d’une correction faite par l’école.
- Une leçon commencée ne peut plus être annulée (`409 LESSON_STARTED`) ; l’app ne le propose plus, ni dans la fiche ni dans le menu du trajet.

iOS, écrans :
- Liste des élèves relue sans geste (premier plan, onglet, code créé), sans perdre les pages chargées ni la sélection ; l’élève sans dossier peut tirer pour actualiser.
- « Mes informations » suit une modification ; le filtre « À venir » du dossier suit la règle commune.
- Planifier, Déplacer et Annuler lisent en parallèle après `/me` ; l’annulation ne lit que la leçon. Même chose pour les préférences de leçon.
- Une lecture annulée par un changement d’onglet n’est plus présentée comme une panne ; un 404 de profil garde la feuille ouverte avec son message.
- Présentations coordonnées à la connexion (offre Face ID et feuille du code) ; feuille « Leçon sans rendez-vous » ancrée sur une vue stable ; rideau levé à toute issue d’un départ.
- Pas de changement d’école pendant un trajet par « Rejoindre une école » ; plus de double relecture après une planification ; « Fermer » disponible pendant la lecture initiale de « Rejoindre une école » ; « Reprendre l’accueil » ne clignote plus.
- Recherche dans l’historique : 300 ms de pause et deux caractères avant de lire tout l’historique.

iOS, terrain :
- « Terminer » juste après « Signaler » attend le transfert en cours au lieu d’échouer.
- La notification de changement d’heure n’arrête plus le trajet ; un vrai saut d’horloge ouvre un nouveau segment.
- À un feu rouge, l’observation prend la position tenue, confirmée par la dernière mesure.
- Replay : chronologie reconstruite au plus une fois par seconde pendant le chargement. Barre du haut du trajet : seule la durée se redessine chaque seconde. Plus de comptage de toutes les positions à chaque écriture.
- Premier 401 : un renouvellement forcé du jeton et un seul nouvel essai avant de conclure à une session expirée.

Nettoyage : quatre déclarations sans aucune référence retirées (`DrivyGuidedStepHeader`, `DrivyGuidedFact`, `JourneyMapRegion`, `DrivyLessonState.isUnusual`), commentaire de CI qui citait un fichier disparu.

## Changements d’API et de données

- Migration 025 : déclencheur de révocation des trajets, trois index. Migration 026 : lecture des révisions de bilan. Aucune donnée supprimée ni réécrite.
- `POST /lessons/:id/start` : champ facultatif `startedAt` (contrat `lesson-field-flow.json`), rétrocompatible.
- `POST /lessons/:id/cancel` : `409 LESSON_STARTED` sur une leçon commencée.
- Lecteurs non auteurs : `plannedWaypoints[].note` à `null`, `charges[].reason` neutre pour une correction.
- **Conséquence à connaître** : un départ immédiat lancé par erreur ne s’annule plus ; il se termine, puis l’école corrige l’issue.
- **Déploiement** : non fait. L’API peut partir avant l’app ; une app déjà installée qui propose encore « Annuler » sur une leçon commencée reçoit un refus définitif.

## Exécuté

- API : 26 fichiers, **322/322 tests** sur PostgreSQL 17 locale jetable (ligne de base 311) ; typage sans erreur.
- Web : **149/149 tests**, typage sans erreur.
- CI : voir STATUS pour l’IPA et les tests Swift.

## Non fait

- **Audit UI/UX sur captures** : 112 captures iPhone clair et sombre prises sur `master` (`artifacts/audit-20261012/`, non suivies), mais l’agent chargé de les lire a été arrêté par la limite d’usage. Aucune amélioration visuelle n’a été faite dans cette passe.
- Laissés, à décider ou à mesurer : liste vidée à chaque frappe dans Élèves (choix délibéré, au porteur) ; fin de trajet rognée si l’horloge de l’iPhone retarde (la borne sert la confidentialité ; deux voies proposées dans le rapport) ; prédicat de rôle dans les listes (coût à mesurer) ; violations de contrainte SQL rendues en 503 ; récepteur GPS recréé après un trou de signal (à essayer sur route) ; file des commandes synchrone sur le fil principal ; chemins « fermés par défaut » sans sortie ; révocation du jeton à la déconnexion ; constat rétrospectif sans borne.
- Architecture : sept autres déclarations mortes, machinerie d’annulation devenue inutile dans l’écran du trajet, onze clients HTTP iOS qui répètent le même traitement, cinq boucles de pagination divergentes, formats de dates dupliqués, dépendances de l’API en `^` (le lockfile fixe les versions), deux fichiers de plus de 840 lignes.

## Non vérifié

- Rien n’a été vu tourner sur iPhone : fenêtre du verrou au-dessus d’une feuille, défilement de l’élève sans dossier, adoption d’époque, purge, reprise hors réseau, renvoi automatique des signalements.
- Les migrations 025 et 026 n’ont tourné que sur une base de test, jamais sur une copie de la base hébergée. Le Caddyfile modifié n’a pas été validé par `caddy validate`.
- Aucune mesure de performance.
