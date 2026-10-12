# Reprise d’une leçon après une fermeture, un crash ou un redémarrage (12 octobre 2026)

## Constat

Scénario du porteur : leçon commencée, GPS lancé, 15 minutes de route, signalements ajoutés, puis l’app se ferme. À la relance, « Continuer la leçon » proposait « Démarrer le trajet », le chronomètre repartait de zéro et le tracé précédent n’apparaissait plus.

Cause : rien n’était perdu, mais rien n’était repris. À l’ouverture du coffre, `recoverInterrupted` scelle tout trajet resté ouvert (positions conservées, arrêt mis en file pour l’école) : c’est voulu, l’autorisation de collecte (`SchoolCaptureLease`) vit sur l’horloge monotone et ne survit pas à une relance, par sécurité. Le contrôleur repartait ensuite à vide : la fiche voyait « aucun trajet », le chronomètre lisait l’horloge monotone du nouveau trajet, et la carte ne montrait que lui.

## Ce qui est durable, et où

| Donnée | Stockage | Après relance |
| --- | --- | --- |
| Départ de la leçon (`actualStart`) | école (PostgreSQL), écrit une fois | inchangé ; jamais réécrit par un trajet |
| Positions GPS | coffre SQLCipher, écrites point par point avant affichage | scellées au dernier fait durable + 1 ms, puis envoyées (lots idempotents, UUID d’opération) |
| Signalements | école ; celui en cours d’envoi dans la file chiffrée | confirmés : chez l’école ; en attente : restaurés et renvoyés |
| Objectifs, bilan, compétences | école + brouillon local chiffré (`SchoolReportLocalDraft`) | relus, saisie locale non envoyée restaurée |
| Leçon | école | jamais terminée ni recommencée par une fermeture de l’app |

## Décision

On ne rouvre pas le trajet interrompu : sa capacité de collecte ne doit pas renaître d’un fichier. « Continuer le trajet » ouvre un nouveau trajet pour la même leçon (l’école autorise plusieurs trajets par leçon, un seul ouvert à la fois), et l’app les présente comme un seul parcours :

- **Libellé** : la fiche affiche « Continuer le trajet » dès que la leçon a déjà un trajet chez l’école (`SchoolLessonHubRules.continuesTrip`), même titre dans la préparation.
- **Pas de doublon ni de refus** : avant le départ, la préparation attend (20 s au plus) que l’arrêt scellé du trajet interrompu et ses lots partent (`settleInterruptedCaptures`) ; sans cela l’école répondrait « trajet déjà ouvert ». Rien n’est réécrit : mêmes opérations, mêmes UUID.
- **Chronomètre** : il affiche la durée de la leçon depuis son départ durable, lu par la fiche (`noteLessonStart`), et calculée sur l’heure de l’école reçue avec l’autorisation puis l’horloge monotone (`lessonElapsedSeconds`). La durée GPS du trajet (`elapsedSeconds`) reste distincte. Sans départ lu, la leçon commence avec ce trajet, à l’heure de l’autorisation (règle du serveur).
- **Tracé** : après le départ, les trajets précédents de la leçon sont lus chez l’école (replay privé) et dessinés avant le trajet courant, avec un pointillé sur la lacune. Leurs signalements sont placés sur la position mesurée qu’ils désignent ; un signalement sans position affichée garde son heure, sans lieu inventé. La position courante (flèche) ne vient jamais d’un trajet précédent.
- **Fiche de la leçon** : l’aperçu du trajet assemble tous les trajets rejouables de la leçon, dans l’ordre.

## Tests

- `SchoolCaptureLifecycleTests.aRelaunchKeepsEveryDurablePointAndSealsAtTheLastDurableFact` : crash simulé sur le vrai coffre SQLCipher (réouverture du fichier), positions conservées, fin au dernier point + 1 ms, un seul arrêt même après une seconde récupération.
- `theLessonClockFollowsTheDurableLessonStartNotTheGPSStart` : durée de leçon ≠ durée GPS, insensible au départ d’une autre leçon, remise à zéro seulement à la fermeture du trajet.
- `SchoolLessonRecoveryTests` : libellé, durée, tracé antérieur (points gardés, signalements ancrés seulement), position courante jamais issue d’un trajet précédent.

## Limites

- Hors réseau, on ne peut pas continuer le trajet : un nouveau départ demande l’autorisation de l’école (inchangé). La leçon, ses signalements et sa fin restent possibles.
- Le replay détaillé reste par trajet ; seul l’aperçu de la fiche et la carte en direct assemblent les trajets.
- Un trajet précédent pas encore finalisé chez l’école n’est pas dessiné sur la carte en direct (il le sera dans la fiche une fois envoyé).
- Rien n’a été vu tourner : fermeture forcée, crash, redémarrage du téléphone et reprise après plusieurs minutes restent à qualifier sur iPhone.
