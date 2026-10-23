# Cours collectifs : inscription (#39), liste d'attente prioritaire (#40), annulations (#41)

23 octobre 2026. Branche `vague/cours-collectifs`. Migration 043, `apps/api/src/course-enrollments.ts`. Socle : [cours-collectifs-socle-80.md](cours-collectifs-socle-80.md). Règles : [cadrage #79](cours-collectifs-cadrage-79.md).

## Principe

Toutes les mutations passent par des fonctions SQL `SECURITY DEFINER` qui relisent les droits, verrouillent la série (`FOR UPDATE`), utilisent le seul compteur `course_seats_taken` (inscriptions actives + propositions actives) et écrivent les occupations élèves dans `drivy.reservation`. L'exclusion partagée avec les leçons refuse tout chevauchement et annule toute la commande : jamais de réservation partielle. L'API traduit les refus (`P0001` = code métier, `23P01` = `COURSE_SCHEDULE_CONFLICT`).

## #39 Inscription

- `POST course-series/{id}/enroll` (élève pour lui-même) et `POST course-series/{id}/enrollments` (personnel habilité, à la demande de l'élève, origine `STAFF`). Mêmes contrôles.
- Contrôles : appartenance élève active, série publiée et non commencée, type non validé (`COURSE_ALREADY_COMPLETED`, lié à l'identifiant du type, pas au titre), pas déjà inscrit, pas d'autre session à venir du même type (`COURSE_EQUIVALENT_ENROLLED`, proposition #79), place libre (`COURSE_FULL`), toutes les séances sans conflit.
- Une place pour toute la série ; conditions copiées (`policyVersion`, `selfCancelHours`, échéance). Brouillon : 404 pour l'élève.
- `GET course-series/{id}/me` : état personnel (`AVAILABLE`, `FULL`, `ENROLLED`, `WAITING`, `OFFERED`, `COMPLETED`, `CANCELLED`, `CLOSED`), sans liste nominative ni paiement. `GET course-enrollments/me` : inscriptions et propositions actives.
- `GET course-series/{id}/enrollments` : liste nominative et file, réservée à la gestion des cours.

## #40 Liste d'attente prioritaire

- Désactivée tant que `offerResponseMinutes` est vide (`COURSE_WAITLIST_DISABLED`). Entrée seulement si la série est complète (`COURSE_SEATS_AVAILABLE` sinon). Retrait libre.
- `drivy.course_queue_advance` (idempotent, sous verrou) : expire les propositions échues, puis tant qu'une place est libre propose au premier `WAITING` admissible (ordre d'entrée). Non admissible : retiré, la file avance. Appelé par chaque commande et par la lecture `me` : une proposition due est visible sans push.
- Proposition exclusive : retenue comptée dans la capacité, aucune occupation d'agenda. Événement `CourseSeatOffered:{entrée}` avec cible unique et `valid_until` pour #43.
- `POST course-offers/{id}/accept` : conversion atomique via la même règle d'inscription (origine `OFFER`). Réponse après échéance ou proposition révoquée : `COURSE_OFFER_EXPIRED`. `POST course-offers/{id}/decline` : passage au suivant. Refus ou expiration : la personne quitte la file (peut s'y réinscrire en fin).
- **Valeurs provisoires, non approuvées par le porteur** : échéance = min(proposition + délai de l'école, première séance - 2 h) ; si moins de 30 min restent, aucune proposition et la place reste libre. Le délai par défaut proposé (12 h) n'est pas appliqué automatiquement : l'école doit le saisir.

## #41 Annulations et changements de dates

- `POST course-enrollments/{id}/cancel` (élève, If-Match) : accepté jusqu'à l'échéance acceptée incluse, heure serveur ; après : `COURSE_SELF_CANCEL_CLOSED`. L'état `me` donne `canSelfCancel` et `contactEmail` (contact de l'école) : ouvrir un e-mail n'annule rien et ne libère aucune place.
- `POST course-enrollments/{id}/staff-cancel` (personnel habilité, motif obligatoire, If-Match) : à tout moment, auteur et motif conservés, place et occupations futures libérées une fois, file avancée.
- `PUT course-policy` (déjà livré, #80) : délai modifiable (ex. 48 h) ; s'applique aux séries enregistrées ensuite et à leurs inscriptions, jamais rétroactivement.
- `POST course-series/{id}/cancel` (motif) : inscriptions `SERIES_CANCELLED`, file et propositions fermées, occupations futures libérées, historique gardé.
- `POST course-series/{id}/reschedule` : même nombre de séances, par position. Occupations formateurs et inscrits recréées ; un conflit annule tout (aucune désinscription silencieuse). Échéances : gardées, sauf si la nouvelle est plus tardive. Propositions actives révoquées puis réémises sur les nouvelles dates.

## Vérification

- 29 tests ciblés (`courses.integration.test.ts`, `course-enrollments.integration.test.ts`) passés localement sur PostgreSQL 17 jetable, migrations 001 à 043. Ce n'est pas la campagne #84.
- Non couverts automatiquement : changement d'heure saisonnier, horloge client fausse (la règle ne lit que l'heure serveur), workers concurrents prolongés.

## Limites

- Pas de worker d'expiration autonome : la file avance à chaque commande et à chaque lecture de la série. Une proposition échue sans aucune activité reste non convertie mais ne bloque rien (comptée seulement tant que non échue).
- Abonnement « prochaines sessions de ce type » (#40) non livré : lié aux préférences #44.
- Pas de notification push effective : événements en outbox pour #43.
