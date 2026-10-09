# Stabilité des parcours — 9 octobre 2026

Demande du porteur : vérifier et corriger l’existant, sans nouvelle fonctionnalité ni refonte visuelle. Branche `codex/stabilite-parcours-20261009`. La conception 3.17 et son contrat canonique 3.11.0 sont conservés. Références : R07, R08, R14–R16, R46, AP49 et T023/T025–T027 ; partage automatique selon la décision du 28 septembre.

## Leçons : décision d’implémentation

`PLANNED` est conservé tant qu’aucun résultat final n’est enregistré. Le champ existant `actualStart`, jusqu’ici renseigné à la clôture seulement, porte désormais le départ confirmé par le serveur. L’horaire prévu ne prouve jamais ce départ.

| État enregistré | Affichage et actions |
| --- | --- |
| PLANNED, sans actualStart, horaire futur | Planifiée ; commencer, déplacer ou annuler |
| PLANNED, sans actualStart, début prévu dépassé | En attente ; commencer, annuler, déplacer vers un créneau futur, ou fermer sans modifier |
| PLANNED avec actualStart | En cours ; continuer et terminer. Après la fin prévue : À terminer. Aucune fin automatique |
| COMPLETED | Récapitulatif et bilan ; aucune relance implicite |
| CANCELLED / NO_SHOW | Résultat explicite conservé ; aucune relance implicite |

Le départ agenda utilise `POST /lessons/{id}/start` avec version et idempotence ; le départ manuel crée directement le début réel. Le GPS reste facultatif. Arrêter un trajet ne termine pas la leçon, et commencer le GPS plus tard ne raccourcit pas sa durée : la clôture utilise le départ de la leçon et l’instant de l’action de fin. Avant tout succès, la demande est conservée dans la file chiffrée et sa confirmation relue. La rédaction du bilan suit le constat durable.

Les anciennes leçons manuelles et captures sont reprises seulement quand une preuve de départ existe. Aucun horaire dépassé n’est transformé en départ ou annulation. AP49 conserve le constat rétrospectif documenté pour les anciens clients ; la nouvelle app exige un départ confirmé avant de proposer ou envoyer la fin. L’API doit être mise à jour avant de distribuer cette app.

L’incident historique signalé n’a pas été reproduit sur les données de l’élève : les causes structurelles sont confirmées par le code et les tests synthétiques. Autre ambiguïté supprimée : un 404 au départ manuel ouvrait automatiquement un formulaire de planification ; le refus reste maintenant visible dans le parcours demandé.

## Étendue de la revue

| Domaine | Vérification / correction |
| --- | --- |
| Leçon manuelle et agenda | Départ durable, reprise après réponse perdue, heures réelles, fin, annulation concurrente, absence, déplacement d’une attente, GPS optionnel |
| Aujourd’hui / agenda / dossier / historique | État commun fondé sur actualStart, leçons en attente accessibles, pas de Continuer ou À terminer dérivé seulement de l’heure |
| Dossier, profil, droits et invitations iOS | [Revue dédiée](stabilite-ios-parcours-20261009.md) |
| Bureau web | [Revue dédiée](stabilite-web-20261009.md) |
| Serveur et migration | [Revue dédiée](stabilite-api-20261009.md) |

Le démarrage sans GPS retourne à la fiche de la leçon manuelle pour continuer le travail. Les objectifs et la note saisis sont enregistrés avant le départ de la leçon ou du GPS ; un refus conserve la saisie et bloque cette transition. Les relectures d’Aujourd’hui attendent la fermeture de la chaîne de feuilles du démarrage manuel, pour éviter de détruire leur vue porteuse. La branche devenue inaccessible de la barre « objectifs / trajet dès… » et ses calculs horaires ont été retirés après vérification des appels ; les autres retraits vérifiés sont listés dans les revues dédiées.

## Qualification

Les résultats exécutés et les liens de CI sont consignés dans [STATUS](STATUS.md). Aucun trajet physique, mesure de batterie ni résultat VoiceOver sur appareil n’est déduit du simulateur. Une revue de code, même étendue, ne prouve pas que chaque écran est exempt de défaut. Les parcours non exécutés et les limites visuelles doivent rester explicites.

Aucun déploiement public ni modification des données de l’école dans cette passe. La migration exige une sauvegarde préalable lors du déploiement autorisé ; l’IPA reste non signée jusqu’à son installation par le porteur.
