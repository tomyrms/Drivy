# « Planifier une leçon » : prochain créneau libre présélectionné

12 octobre 2026, branche `claude/prochain-creneau-20261012`.

## Comportement

À l’ouverture de « Planifier une leçon » (Agenda, dossier de l’élève, conflit de « Commencer maintenant »), dès que l’élève, la formation, le moniteur et la durée sont connus, l’app demande à l’école le prochain créneau libre et le présélectionne. Exemple : il est 19 h 30, la journée du moniteur est finie, la feuille s’ouvre sur demain 9 h 00. Depuis l’Agenda, la recherche part du jour affiché (ou de maintenant s’il est passé).

- Pendant la recherche, la date et l’heure sont remplacées par un squelette de deux lignes (`DrivySkeletonRows`) : aucune date provisoire n’apparaît puis ne saute. Le sélecteur s’ouvre directement sur le créneau trouvé.
- Le moniteur reste libre : un choix manuel de la date ou de l’heure arrête toute proposition, même en cours de recherche.
- Changer de moniteur, de durée ou de tampon relance la recherche tant que l’horaire n’a pas été choisi à la main.
- Aucun créneau dans la période (14 jours) : « Aucun créneau libre jusqu’au jeudi 22 octobre. » et « Chercher plus loin », qui reprend au jour suivant. La date reste modifiable.
- Panne réseau : notice d’erreur avec « Réessayer », date modifiable à la main.
- Service sans la route (app plus récente que l’API, réponse 404) : aucun message, le formulaire reste celui d’avant (horaire initial, saisie manuelle).
- Un déplacement de leçon ne cherche jamais : il garde l’horaire de la leçon.
- La proposition reste indicative : la prévalidation existante (`…/lessons/availability`) vérifie le créneau, puis la création le recontrôle sous verrou.

## Architecture retenue : calcul au serveur

Les occupations de l’élève avec d’autres moniteurs, et celles du moniteur sur des formations qui ne lui sont plus visibles, sont masquées par la RLS : le client ne peut pas les voir, la prévalidation existante ne renvoie qu’un booléen. Un calcul côté client proposerait donc des créneaux occupés. La recherche se fait au serveur :

- `apps/api/src/next-slot.ts`, module pur (sans base ni horloge implicite) : pour chaque jour civil dans le fuseau de l’école, les débuts alignés sur un pas de 15 minutes depuis le début de chaque ouverture, qui respectent exactement ce que l’écriture contrôle (`ensureOpen` et l’affectation de `trainingContext`) : leçon entière dans une seule ouverture le même jour local, aucune fermeture croisée (bornes semi-ouvertes), affectation couvrant tout le rendez-vous, début futur. Heures murales relues après conversion : une heure sautée au passage à l’heure d’été n’est jamais proposée, une heure répétée ne crée pas de doublon.
- Les occupations sont testées par un prédicat injecté. La route l’implémente avec la fonction SQL existante `drivy.lesson_slot_conflict` (moniteur tampon compris, élève dans toute l’école), appelée en une requête par jour pour tous les candidats du jour. Aucune réservation n’est lue ni renvoyée : seule leur absence est déduite. Aucune migration.
- Route `GET /v1/schools/{schoolId}/lessons/next-slot`, extension hors contrat canonique 3.11.0, documentée dans `apps/api/contracts/lesson-next-slot.json`. Mêmes droits et mêmes refus que la prévalidation (ADMIN ou moniteur affecté ; profil, formation, offre, affectation). Paramètres : `trainingId`, `instructorMembershipId`, `durationMinutes`, `bufferMinutes`, `timeZone` (celui de l’école), `from` (facultatif), `days` (1 à 31, 14 par défaut), `stepMinutes` (5 à 60, 15 par défaut). Réponse : `slot` (`plannedStart`, `plannedEnd`) ou `null`, `searchedThrough` (dernier jour examiné), `timeZone`. Le premier début proposé est au moins cinq minutes après maintenant.

Ce qui compte dans la recherche : ouvertures du moniteur (« horaires de travail », `availability_rule` : jours, heures, validité), pauses (trou entre deux ouvertures d’un même jour), indisponibilités (`closure`), leçons déjà planifiées du moniteur et de l’élève (réservations actives), durée prévue, tampon entre leçons, jours non travaillés, affectation du moniteur à la formation. Le modèle ne contient aucune autre contrainte liée à l’élève ou au type de permis pour l’horaire ; aucune n’a été inventée.

iOS : `SchoolPlanningClient.nextSlot`, état `SchoolSuggestedSlotState` dans `SchoolPlanningWorkspace` (activé par `suggestingNextSlotFrom:`), `.task(id: nextSlotRequest)` dans `SchoolPlanningView`.

## Limites

- La validité d’un tarif à la date du créneau n’entre pas dans la recherche : en fin de validité d’une prestation, le créneau proposé peut demander un autre tarif (message existant « Aucun tarif ne correspond… »).
- Les ouvertures se saisissent sur le web ; `SchoolPlanningSettingsView` ne règle que la formation et le tarif par défaut.
- Grille fixe de 15 minutes alignée sur l’ouverture : un créneau libre à 9 h 05 n’est pas proposé.
- Au plus 14 jours par recherche (31 par appel) ; « Chercher plus loin » avance par périodes de 14 jours.
