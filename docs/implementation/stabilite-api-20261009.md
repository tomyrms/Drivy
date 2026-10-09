# Stabilité de l’API — 9 octobre 2026

Cette passe corrige les parcours existants de leçon. Références relues : R13–R15, F05/F07, AP49 et T025/T026 du dossier de conception, plus les décisions de partage du 28 septembre. Le dossier conservé et l’OpenAPI canonique 3.11.0 restent inchangés ; le contrat complémentaire est `apps/api/contracts/lesson-field-flow.json`.

## Cause et état persistant

`start-now` créait une leçon `PLANNED` avec un horaire prévu à l’instant de l’appel, sans enregistrer son début réel. Aucun départ distinct n’existait pour une leçon de l’agenda. Les projections ne pouvaient donc distinguer « horaire dépassé » et « réellement commencée ». La complétion et le déplacement contenaient aussi des conditions fondées sur le début prévu.

L’erreur précise rapportée sur une ancienne leçon manuelle n’est pas reproduite avec ses données historiques. Le code actuel de `start-now` fixe déjà `plannedStart` à l’instant serveur : sa seule garde de complétion à −15 minutes ne suffit donc pas à expliquer cet incident. Le défaut confirmé est l’absence de départ durable commun aux parcours ; les tests ajoutés prouvent les nouveaux comportements, sans attribuer rétrospectivement une cause non observée.

Le résultat métier reste `PLANNED` pendant la séance, pour conserver le contrat existant. `actualStart` renseigne maintenant le début réel durable ; `actualEnd` reste nul jusqu’à la fin. Un rendez-vous dont `actualStart` est nul n’est pas démarré, quelle que soit son heure prévue. Le temps seul n’entraîne aucun démarrage, réalisation, annulation, bilan ou charge.

- `POST /lessons/start-now` enregistre le départ dans la transaction de création, avec le même instant serveur que `plannedStart` ; version initiale 1.
- `POST /lessons/{lessonId}/start` prend uniquement `{operationId}`, `If-Match` et `Idempotency-Key`. La commande `START_LESSON` renvoie un `LessonEnvelope` en 200, avec la version incrémentée et `actualStart` serveur. Elle est réservée au moniteur désigné et actuellement affecté ; l’école, la formation et l’appartenance de l’élève doivent être actives, le dossier non archivé. Le retard n’interdit pas le départ. Un second départ reçoit `LESSON_STARTED`, sauf rejeu de la même opération.
- Le démarrage GPS explicite AP161 établit aussi le début réel s’il manque, dans la même transaction que l’autorisation. Un refus GPS n’enregistre aucun faux départ. Cette compatibilité avec les anciens clients incrémente la version de la leçon : elle doit être relue avant une autre commande utilisant `If-Match`. Si le départ est déjà enregistré, l’ancien créneau n’interdit plus d’activer le GPS ; les choix de l’élève, diagnostics, droits, bornes d’autorisation et unicités de capture continuent à s’appliquer.
- AP161 revérifie également l’appartenance active de l’élève et son dossier non archivé : après révocation ou archivage, une ancienne préférence GPS favorable ne permet plus de créer une nouvelle autorisation de capture.
- La fin conserve le début réel déjà enregistré, même si l’horloge cliente ou les dates du créneau diffèrent. Elle valide `actualEnd` contre ce début et conserve l’atomicité leçon/bilan/compte/charge/partage. Le GPS absent ou encore en transfert n’empêche pas la fin.
- L’avertissement de permis est calculé à la date locale du début réel dès qu’il existe. La complétion le revérifie à cette date, y compris pour un constat rétrospectif. Un permis valide au créneau prévu mais expiré le jour du départ ne passe donc plus inaperçu.
- La déclaration rétrospective AP49 reste compatible : lorsqu’aucun départ n’a été enregistré, elle exige toujours les heures réelles explicitement déclarées et refuse une leçon future à plus de 15 minutes. Cela ne constitue jamais un démarrage automatique ou un état affichable déduit de l’horloge.
- Une leçon démarrée ne peut pas être marquée absente ou déplacée. Un rendez-vous dépassé sans départ reste annulable, en attente, ou déplaçable explicitement vers un créneau futur. La prévalidation et la commande de déplacement utilisent la même règle.
- La clôture d’une formation exige que toutes ses leçons aient un résultat, y compris celles dont le créneau est dépassé. Les comptes rendus de retrait d’affectation ou d’accès incluent également ces leçons encore ouvertes ; elles ne disparaissent plus du nombre à traiter lorsque l’heure passe.

## Migration et conservation des données

La migration `023_explicit_lesson_start.sql` formalise l’intervalle avec début sans fin et ouvre les politiques de commande/audit requises. Elle répare uniquement les leçons encore `PLANNED` dont un départ explicite existe déjà : reçu `START_LESSON_NOW` ou autorisation de capture. Le premier instant prouvé est conservé et la version est incrémentée. Une date prévue dépassée sans preuve ne produit aucun début. Les leçons closes et reçus historiques restent inchangés.

L’écriture de réparation est exécutée par le propriétaire de migration, sous transaction, avec `FORCE ROW LEVEL SECURITY` rétabli avant commit. Aucun privilège applicatif supplémentaire de lecture n’est ajouté. Cette migration nécessite le déploiement habituel précédé d’une sauvegarde ; aucun déploiement n’est effectué par cette passe d’audit.

## Nettoyage et vérification

La condition commerciale redondante qui assimilait heure prévue passée à départ a été retirée du déplacement. Aucun écran ou endpoint n’est supprimé côté serveur sans preuve d’inutilisation.

Une nouvelle suite PostgreSQL `lesson-start.integration.test.ts` couvre départ manuel, reprise, départ agenda tardif ou anticipé, absence de transition temporelle, annulation, déplacement, droits, version, concurrence, complétion idempotente, partage et réparation historique. Les suites capture conservent leurs scénarios existants avec la nouvelle version durable de leçon et ajoutent les vérifications « refus GPS sans départ », « départ GPS persistant » et « reprise GPS après le créneau ».

Validation locale : compilation TypeScript vérifiée ; 31 tests unitaires passent (authentification, curseurs, invitations, ancrage). Sur `84f2cce`, la campagne [37931070865](https://github.com/tomyrms/Drivy/actions/runs/37931070865) réussit les **248 tests API, 21 fichiers**, avec une vraie PostgreSQL, ainsi que les types, builds et contrôles documentaires. Le moteur Docker de ce poste est arrêté : aucune exécution PostgreSQL locale n’est revendiquée. Aucun résultat terrain GPS/batterie/VoiceOver n’est déduit de ces tests serveur.
