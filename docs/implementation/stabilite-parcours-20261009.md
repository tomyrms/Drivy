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

Lorsqu’un rendez-vous attend son départ, Aujourd’hui distingue maintenant « Commencer la leçon » (ce rendez-vous) et « Leçon sans rendez-vous » (création manuelle). Le comportement de ces actions reste identique ; ce changement de libellé suit la revue des captures de la version fusionnée.

## Qualification

À la demande du porteur pendant cette passe, la branche `claude/marque-la-trace-20261006` à `b710303c40b8f4462e8a4b39817544ecb53bde65` est fusionnée dans la branche de stabilité. Ses ajustements visuels existants sont conservés ; Aujourd’hui garde le résumé compact tout en distinguant attente et démarrage réel. Les anciennes preuves de marque restent historiques ; les résultats de la version réunie sont consignés séparément dans le suivi.

Les résultats exécutés et les liens de CI sont consignés dans [STATUS](STATUS.md). Aucun trajet physique, mesure de batterie ni résultat VoiceOver sur appareil n’est déduit du simulateur. Une revue de code, même étendue, ne prouve pas que chaque écran est exempt de défaut. Les parcours non exécutés et les limites visuelles doivent rester explicites.

La première campagne native sur `083fbc0` a exécuté 399 tests Swift (un échec d’assertion : une fixture non démarrée attendait encore « À terminer »), les trois tests de présentation et les douze parcours d’interface iPhone réussis. L’assertion attend maintenant « En attente ». La campagne a ensuite été remplacée par celle de la fusion, avant qualification iPad ; la campagne visuelle initiale a également été interrompue après les douze vues iPhone. Ces campagnes interrompues ne qualifient pas la version finale.

La compilation de la campagne fusionnée `6443d02` a révélé deux arguments manquants dans une nouvelle fixture de test de capture ; `6026104` les renseigne et sort la lecture de l’espacement d’une closure SwiftUI isolée pour supprimer un avertissement de concurrence. La campagne complète relancée a utilisé cette source.

Les **24 captures** de `6443d02` ont toutes été ouvertes : Aujourd’hui en attente et déjà démarré, agenda, dossier, fiche et historique, sur iPhone 17 Pro et iPad Pro 13 pouces M5, en clair et sombre. Aucun contenu coupé ni superposition dans les viewports inspectés. [Preuve et limites](proofs/stabilite-native-visual-20261009.json), [aperçus conservés](assets/stabilite-ios-20261009). Le réglage `large` est la taille usuelle du simulateur, pas du grand texte d’accessibilité. La barre système est fixée à 9:41, sans modifier l’horloge métier. La fixture nommée `lesson-finish` montre une leçon encore en attente ; les captures ne prouvent donc pas le rendu du formulaire final. L’historique synthétique ne fournit pas les noms des élèves, d’où le repli « Élève » : ce rendu ne qualifie pas les noms servis par l’API réelle.

Le libellé final « Leçon sans rendez-vous » est compilé et vérifié dans deux captures iPhone clair/sombre de `45691db` : une ligne, commandes distinctes, aucune coupe. La preuve visuelle recense donc 26 images de ces deux campagnes, dont huit aperçus conservés.

La campagne complète `6026104` a exécuté **413 tests Swift : 410 réussis, trois échecs**, ainsi que **3 tests de présentation et 12 parcours UI réussis sur chaque appareil** (iPhone 17 Pro et iPad Air 11 pouces M4, iOS 26.4.1). Les trois nouveaux tests de transfert GPS s’arrêtaient avant l’adoption : la fixture omettait des champs nullables que le client exige explicitement, et renvoyait aussi 200 aux créations qui exigent 201. Le correctif HTTP de `843f7f7` seul laissait donc les trois échecs ; `bc0bfa7` fournit les nulls conformes au serveur. Les scénarios et assertions métier sont conservés ; le diagnostic d’attente est renforcé. La [requalification `unit_only` sur `bc0bfa7`](https://github.com/tomyrms/Drivy/actions/runs/37939864868) réussit **413/413 tests Swift et 3/3 tests de présentation**, sans échec ni test ignoré. Elle ne répète pas les parcours UI déjà réussis.

Huit captures supplémentaires issues des tests UI ont été inspectées : attente avant départ, dernière étape du bilan et saisie conservée après rotation, sur les deux appareils. La lecture des images, distincte des assertions réussies, a révélé un champ du bilan masqué par le clavier et la barre d’action en paysage sur iPhone. La correction finale libère cet espace et replace le champ actif après changement de taille. La [recette ciblée sur `f8f5c63`](https://github.com/tomyrms/Drivy/actions/runs/37940876364) réussit **1/1 test sur chaque appareil**, avec cinq captures supplémentaires inspectées. La saisie, la fermeture du clavier, le retour du bouton d’enregistrement et la conservation du texte sont confirmés sur ce parcours ; les autres parcours UI n’ont pas été répétés après ce correctif. [Preuve d’interaction et limites](proofs/stabilite-native-interactions-20261009.json).

Au total, **39 captures natives ont été inspectées** dans ces campagnes (26 de présentation, huit des parcours initiaux et cinq de rotation corrigée). Les textes longs, la frappe dans les deux autres champs et les grandes tailles de texte restent hors de cette recette ciblée. Le [relevé des vérifications](proofs/stabilite-verifications-20261009.json) associe chaque résultat à son commit et à sa campagne.

Aucun déploiement public ni modification des données de l’école dans cette passe. La migration exige une sauvegarde préalable lors du déploiement autorisé ; l’IPA reste non signée jusqu’à son installation par le porteur.

## Recette intégrée restante

Après mise à jour de l’API et installation, avec des dossiers de recette :

- Démarrer une leçon manuellement, poursuivre sans GPS, modifier ses objectifs, revenir à la fiche, terminer puis enregistrer le bilan ; contrôler la relecture et la visibilité côté élève. Le départ et la fin sont couverts séparément par les tests API/modèle, mais toute cette chaîne de feuilles n’a pas été parcourue de bout en bout dans la recette native automatisée.
- Laisser dépasser un rendez-vous sans action : vérifier « En attente » après reconnexion, puis tester séparément départ, annulation et fermeture sans modification.
- Démarrer depuis l’agenda, fermer puis rouvrir l’app, continuer la même leçon et la terminer ; vérifier les heures réelles après relecture depuis le bureau web.
- Qualifier sur appareil le démarrage GPS, le passage en arrière-plan, la batterie, VoiceOver et les grandes tailles de texte. La source synthétique des tests ne remplace pas ces mesures.

Les sessions OIDC réelles et la nouvelle recette navigateur après fusion restent également à vérifier. Les contrôles synthétiques ne sont pas présentés comme des écritures effectuées sur l’école hébergée.
