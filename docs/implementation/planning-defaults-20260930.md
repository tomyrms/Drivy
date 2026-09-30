# Planifier avec moins de saisie — 30 septembre 2026

Décision du porteur : lieu de rendez-vous facultatif, moniteur courant par défaut quand il est éligible, formation et tarif préférés configurables, détails secondaires conservés, textes accessibles en bas du formulaire. La clarification limite la nouvelle direction artistique au web ; les composants et tokens natifs restent ceux de l’application.

Références relues : `COMMENCER_ICI.md`, F04/F05 dans `03-fonctionnel/planning-lecons.md`, R06/R08–R14, API de planification, scénarios T018/T059/T061/T067/T092. Le dossier de conception et le contrat OpenAPI canonique 3.11.0 sont conservés. Les différences ci-dessous sont des extensions d’implémentation demandées le 30 septembre.

## Comportement

- Planifier, déplacer ou démarrer immédiatement accepte un lieu vide, absent ou `null`. Le serveur conserve la chaîne vide ; il ne fabrique plus « À préciser ». Le champ reste disponible : directement au démarrage immédiat, dans « Détails du rendez-vous » pendant la planification. L’intervalle entre leçons y reste réglable ; ses règles de réservation ne changent pas.
- Dans `Profil → Préférences de leçon`, chaque membre ADMIN ou INSTRUCTOR règle sa catégorie de formation et son tarif. Ces préférences sont propres au membre et à l’école et sont relues sur un autre appareil.
- La catégorie sélectionne une formation ACTIVE **déjà existante et accessible** de l’élève, uniquement si la correspondance est unique. Une seule formation active est reprise même sans préférence. Plusieurs formations de même catégorie laissent le choix à la personne ; aucune formation ni affectation n’est créée.
- Le moniteur courant est présélectionné seulement s’il figure parmi les moniteurs actifs affectés à la formation, avec des dates couvrant le rendez-vous. Cela inclut un membre ADMIN + INSTRUCTOR. Le choix reste modifiable selon les droits existants.
- Le tarif préféré est identifié par `productKey`, pour suivre sa version courante. Seul un tarif individuel, actif, applicable à la date, de la bonne catégorie et avec conditions approuvées est proposé automatiquement. Sinon, une seule prestation admissible est reprise ; une ambiguïté garde le choix vide. Les conditions doivent toujours être explicitement acceptées lors de la planification.
- Le démarrage immédiat garde sa durée issue de l’offre. Il privilégie la clé préférée seulement si elle est compatible avec cette durée et les conditions applicables. Sinon, il emploie la sélection courante déjà prévue par ce parcours. La leçon conserve l’identifiant de version, la quantité et le prix durablement vérifiés par le serveur.
- Conditions tarifaires, procédure et annulation sont consultables par trois liens de bas de formulaire. La feuille conserve le texte intégral sélectionnable, avec nom et validité pour les conditions commerciales. L’accord commercial reste distinct de cette consultation.
- Un crochet facultatif `beforeCancellation` permet au panneau GPS d’arrêter et sauvegarder la capture avant d’annuler la leçon sans imposer de bilan. Le raccord et les tests de capture sont traités dans le chantier carte.

## Persistance et contrat d’extension

Migration `021_planning_defaults.sql` : une ligne minimale par `(school_id, membership_id)`, avec version, catégorie nullable et clé de prestation nullable. RLS forcée limite lecture et écriture au membre courant ; même un administrateur ne lit pas la préférence d’un autre membre.

`GET /v1/schools/{schoolId}/planning-defaults` renvoie dans l’enveloppe habituelle `{id: membershipId, schoolId, version, trainingCategoryCode, serviceProductKey}` et un ETag fort. Tout membre du personnel possède une représentation initiale vide, version 1. Aucune écriture n’a lieu lors de cette lecture.

`PUT` au même chemin exige `Idempotency-Key`, `If-Match` et `{operationId, trainingCategoryCode: string|null, serviceProductKey: string|null}`. Le serveur vérifie la catégorie disponible et le tarif actuel compatible, puis enregistre la préférence, l’opération et l’audit dans la même transaction. Première mutation : version 2. Une version périmée renvoie 412, une valeur indisponible 422 `PLANNING_DEFAULT_INVALID`. La commande `SAVE_PLANNING_DEFAULTS` possède un reçu AP72 de type `PlanningDefaults`, ciblant l’identifiant du membre.

Le client conserve la commande dans l’outbox chiffrée avant envoi et ne confirme l’enregistrement qu’après le reçu durable. Une réponse perdue conserve la même opération. Modifier une préférence ne modifie ni les leçons antérieures, ni leurs prix, ni leurs conditions photographiées.

## UI Skills appliqués

`ui-skills-root` (catégories et sélection CLI), `swiftui-ui-patterns` et sa référence `async-state` : composants natifs, état local observable, lectures asynchrones et feuille pilotée par document. `better-layout` : détails secondaires repliables, formulaire borné sur iPad et bas de formulaire adaptable. `better-writing` : labels permanents et « facultatif » explicite, aucun sous-titre ajouté. `better-ui` : réutilisation des surfaces existantes sans nouveau style global. `better-accessibility` et `interactive-hit-areas` : contrôles SwiftUI et liens avec cible d’au moins 44 points, texte adaptable et documents sélectionnables. `apple-design-hig` a été consulté ; ses fichiers de références ne sont pas présents dans l’installation, donc aucune citation de page HIG non lue n’est revendiquée. `mobile-native` a été consulté puis écarté de l’implémentation native : ses corrections CSS concernent le chantier web.

## Vérification

- API : `npm run typecheck` et `npm run build` exécutés avec succès.
- PostgreSQL 17 réelle dans un conteneur Docker jetable, port local éphémère, données en tmpfs, base `drivy_test` dédiée. Les migrations sont appliquées par le harness sous propriétaire NOSUPERUSER/NOBYPASSRLS ; les requêtes HTTP utilisent le rôle applicatif.
- `planning-defaults.integration.test.ts` : 6 tests passés (droits, RLS personnelle, absence de lieu, idempotence, concurrence, reçu, tarif préféré et repli admissible). `lessons.integration.test.ts` et `field-lesson-flow.integration.test.ts` : 11 tests existants passés.
- `SchoolPlanningDefaultsTests.swift` ajouté : formation univoque, moniteur courant avec double rôle, absence d’affectation, lieu vide, accord commercial et confirmation par reçu. Le mock de `SchoolLessonFinishTests` comprend la lecture des préférences utilisée par le démarrage immédiat.
- Compilation et exécution Swift : à réaliser sur le runner Apple après intégration. Rendu iPhone/iPad, grande taille de texte et VoiceOver : non qualifiés depuis ce poste Windows. Aucun résultat physique n’est revendiqué.
