# Audit global et corrections — 10 octobre 2026

Branche `claude/audit-global-20261010`, partie de `claude/deblocage-demandes-20261010` (`0926c48`). Demande du porteur : audit technique et UI/UX de toute l’application, avec corrections directes. Cinq lots à fichiers disjoints (API, web, trois lots iOS), puis une revue croisée indépendante du diff complet. Aucune fonctionnalité retirée, contrat 3.11.0 et migrations inchangés (toujours 001–023).

## Règle commune des codes HTTP

Les lots ont été alignés sur une seule lecture, côté API, iOS et web :

| Réponse | Sens | Effet sur une demande en file |
| --- | --- | --- |
| 503 | Panne, y compris du fournisseur d’identité | Conservée, à réessayer ; jamais une déconnexion |
| 408 | Résultat inconnu | Conservée, à réessayer |
| 400 `INVALID_REQUEST` | Refus définitif | Retirée au premier envoi |
| 404 sur le reçu d’une écriture confirmée | Incertitude | Conservée, à vérifier |

## API

- Une panne du fournisseur d’identité pendant la relecture des clés répondait 401 et pouvait fermer les sessions ; elle répond 503. Signature, clé inconnue et jeton expiré restent des 401.
- Un caractère NUL ou une valeur que PostgreSQL refuse (classe 22) répondait 503 et était rejoué sans fin par les apps ; c’est un 400 définitif, le NUL étant refusé avant toute requête SQL.
- Le pool PostgreSQL reçoit un écouteur d’erreur : une connexion inactive coupée (redémarrage, sauvegarde) n’arrête plus le service.
- Un `ROLLBACK` qui échoue ne masque plus l’erreur d’origine et la connexion cassée est détruite.
- Les 5xx journalisent le nom et le code technique de l’erreur, jamais le message ni la pile.
- Une leçon déjà commencée ne bloque plus la modification des ouvertures du moniteur (`EXISTING_BOOKINGS`).

## Web

- Lecture refusée pour session expirée : « Se reconnecter » au lieu d’un « Réessayer » sans issue.
- Un refus d’écriture reste affiché dans son dialogue, avec la saisie (réglages, champs du profil, équipe, catalogue, conditions et prestations) ; un dialogue rouvert ne montre plus un ancien refus.
- La page de compte ne bascule plus sur la vue de connexion à chaque actualisation ; « Se reconnecter » ne peut plus rester sans effet dans la console.
- Le serveur web garde la session quand le fournisseur d’identité est injoignable pendant un rafraîchissement de jeton (503) ; un refus du jeton déconnecte toujours.
- Dates par défaut dans le fuseau de l’école ; semaine lisible quand minuit n’existe pas ; sélecteur des disponibilités cohérent quand le moniteur est devenu inactif ; agenda relu au retour sur l’onglet.
- Notes explicatives retirées (pied de page, compte, connexion, réglages, champs du profil).

## iOS — terrain

- Un signalement refusé par l’école quitte la file, disparaît de la carte et le bandeau dit « Non enregistré » avec le motif ; il bloquait toute autre écriture, dont la fin de leçon.
- Un départ GPS dont l’adoption échoue ne rend plus « Autorise la localisation » au nouvel essai ; plus d’attente d’une minute quand la demande d’autorisation n’a pas pu être présentée.
- Observations : une demande inconnue de l’école peut être abandonnée, avec confirmation.
- « Réessayer l’envoi » ne réécrit plus une demande retirée ailleurs ; l’enregistreur relit sa demande à la fermeture d’une fiche de leçon.

## iOS — leçons et agenda

- Une écriture confirmée dont le reçu est introuvable reste en file au lieu d’être annoncée « non enregistrée ».
- Le bouton d’école de la barre d’outils est masqué pendant un trajet, comme la ligne du compte.
- Pas de second envoi d’un bilan déjà confirmé ; « Terminer la leçon » dit pourquoi il ne peut pas aboutir.
- Session expirée ou accès retiré : l’agenda, Aujourd’hui et l’historique relisent le compte et mènent à la reconnexion.
- Dossier qui restait en chargement après un nouvel essai de l’école ; préférences de leçon dont le 404 restait en file ; agenda relu au retour au premier plan ; leçon créée depuis le dossier visible dans sa liste.
- Aujourd’hui montre les leçons commencées un jour précédent et jamais terminées (« À terminer »).
- Le refus de l’école est ramené à l’écran dans Planifier, Déplacer et Annuler ; retour haptique après confirmation de l’école.

## iOS — compte et socle

- Lancement hors réseau ou pendant une panne d’identité : la session enregistrée et encore autorisée est conservée. Un refus du fournisseur ou un Trousseau illisible déconnectent toujours.
- 400 définitif pour rejoindre une école, renvoyer une invitation et modifier le profil ; 408 traité en panne dans tous les clients.
- Verrou de l’app : si le code de l’appareil a été retiré, l’écran verrouillé n’avait aucune sortie ; il s’ouvre (erreur `LAError.passcodeNotSet` seulement).
- Rideau de marque : garde-fou annulé à la fermeture, dessin et chorégraphie inchangés.
- Composants partagés : état pressé du bouton de danger et des tuiles sous « Réduire les animations », contour sous « Augmenter le contraste », colonnes de symboles qui suivent la taille du texte, titre destructif sur plusieurs lignes.

## Exécuté

Sur `071af98` :

- **436/436 tests Swift** (`unit_only`, [run 38048222267](https://github.com/tomyrms/Drivy/actions/runs/38048222267)), dont 16 nouveaux.
- IPA Release compilée ([run 38048222378](https://github.com/tomyrms/Drivy/actions/runs/38048222378)).
- Contrats, droits, PostgreSQL et web ([run 38048222436](https://github.com/tomyrms/Drivy/actions/runs/38048222436)) : 22 fichiers de tests API, 12 fichiers web.
- En local : typage API et 58/58 tests unitaires (27 nouveaux) ; typage, build et **148/148 tests web** (10 nouveaux). Docker ne démarrait pas sur le PC : les tests d’intégration PostgreSQL n’ont tourné que sur la CI.

## Déployé

Release `071af986417486ce3f758c85556e82d21cc86695` sur le homelab, à la demande du porteur, après sauvegarde vérifiée `/root/drivy_refonte-before-071af98…-20261010T113522Z-34a45d1c3991.dump` (CT113). 23 empreintes de migration conformes, environnement de l’API inchangé, quatre services actifs, `/health/ready` 200, page web publique 200. Aucune migration nouvelle. Aucun parcours réel n’a été rejoué sur l’école hébergée après ce déploiement.

## Laissé au porteur ou pour plus tard

Les constats GPS et d’adhésion de [la passe précédente](deblocage-demandes-20261010.md) restent ouverts. S’y ajoutent :

- **Verrou ouvert sans code d’appareil** : choix retenu ; l’alternative serait d’imposer une reconnexion.
- **Signalement à l’arrêt sans position** : à un feu rouge, l’ancre peut être nulle et l’observation part sans position. Intégrité des trajets, à décider.
- **Un 404 sur un ancien trajet arrête le trajet en cours** (règle fermée par défaut).
- **Rideau de départ sans sortie** pendant l’attente (jusqu’à 60 s pour l’autorisation).
- **Refus définitif sur un renvoi** : la demande reste en file, « Vérifier » puis « Abandonner ».
- **Bandeau de refus du signalement** : titre et texte redondants, et un message qui renvoie à un brouillon déjà retiré.
- **« À terminer » sous Aujourd’hui** : lit une seule page de 100 leçons passées.
- **Coûts non mesurés** : tracé recalculé en entier à chaque position, formateurs de dates recréés à chaque ligne, historique relu à chaque fermeture de fiche, Planifier qui lit tous les élèves avant d’afficher.
- **Fermer Planifier ou Annuler par glissement** perd un motif saisi.
- **API** : pas d’index sur `capture_session(school_id, lesson_id)` (demanderait une migration 024).
- **Web** : aucun test de rendu React ; agenda filtré par élève « Aucune leçon trouvée » si l’annuaire n’est pas chargé ; bundle de 516 kB.

## Non vérifié

- Aucun écran iOS de cette passe n’a été vu tourner : ni parcours UI ni capture. Compilation et tests de logique seulement.
- Web : quelques changements vus dans le navigateur sur le harnais synthétique (refus dans le dialogue, actualisation du compte, « Se reconnecter »), rien avec l’API et l’identité réelles.
- Aucun appareil physique : GPS, batterie, VoiceOver, Face ID et retrait du code.
