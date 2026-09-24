# G1B — Configurer puis activer l’école

Implémentation du 24 septembre 2026. Le dossier de conception reste immuable. G1B ajoute la configuration ADMIN à G1A ; aucun parcours d’invitation, envoi email, formation, planification ou capture scolaire n’est annoncé par cet incrément.

## Parcours et références

Une école DRAFT possède un état de configuration et une première révision de politique vide, sans approbation. L’ADMIN peut corriger son identité scolaire, lire/saisir la notice et la politique de données, adopter explicitement ces textes puis vérifier la préparation. L’activation est une commande distincte et confirmée, qui relit la version de configuration et les prérequis sous verrou. Cocher DATA ou REVIEW ne valide aucun texte.

Références canoniques : `03-fonctionnel/regles-etats.md` R01/R02/R11/R12/R73–R76 ; `03-fonctionnel/onboarding.md` F20 ; `04-technique/api.md` AP06/AP72/AP165–AP168 ; schémas correspondants de `04-technique/openapi.yaml` ; recettes T163–T174, T233 et T235. La readiness n’est jamais une autorisation de planifier, capturer ou publier.

## Contrats livrés

Toutes les routes ci-dessous sont sous `/v1/schools/{schoolId}`, authentifiées par Bearer. ADMIN actif courant est requis. Les lectures répondent `Cache-Control: no-store`. Les enveloppes restent `{data,requestId,serverTime}` et les erreurs `application/problem+json` conformes à Problem.

| Méthode / chemin | Corps | Réponse 200 |
|---|---|---|
| GET `/setup` | Aucun | SchoolSetup et ETag fort |
| PATCH `/setup` | `{operationId,currentStep,completedSteps}` | SchoolSetup et nouvelle version |
| GET `/readiness` | Aucun | SchoolReadiness, quatre capacités exactement |
| PATCH base scolaire (AP06) | `{operationId,name,timeZone,contactEmail,contactPhone?,impactConfirmed}` | School et nouvelle version |
| GET `/data-policy` (extension) | Aucun | SchoolDataPolicy et ETag fort |
| PUT `/data-policy` (extension) | Voir ci-dessous | Nouvelle révision SchoolDataPolicy et ETag fort |
| POST `/activate` | `{operationId,expectedConfigurationVersion,reviewAcknowledged:true}` | School ACTIVE et nouvelle version |
| GET `/operations/{operationId}` (AP72) | Aucun | OperationResult de cet auteur dans cette école |

Chaque mutation porte `Idempotency-Key` égal à `operationId` UUID. `If-Match` est une version forte, par exemple `"2"`. PATCH setup utilise la version du setup ; PUT data-policy celle de la politique ; AP06 et AP168 celle de School. AP168 exige en plus `expectedConfigurationVersion`. Une adoption de politique incrémente la version et configurationVersion de School : les recharger avant activation. Les commandes sont synchrones ; aucun 202 n’est émis par G1B.

AP166 transporte exclusivement la progression, conformément au canon. `currentStep` vaut IDENTITY/ORGANISATION/OFFERINGS/COLLECTIVE/DATA/REVIEW. `completedSteps` accepte au plus six valeurs distinctes de cette liste. Elles décrivent le parcours, sans preuve d’adoption. SchoolSetup.status est IN_PROGRESS, READY depuis les prérequis réels, ou COMPLETED après activation. Un GET ne crée aucun objet ni aucun accord.

AP06 accepte les champs du contrat : nom non blanc de 1–150 caractères, fuseau IANA valide, contact email valide, téléphone optionnel ou null. `impactConfirmed:true` est nécessaire à l’écriture. Les modules peuvent être retransmis identiques ; les modifier ou choisir un logo non null répond MODULE_NOT_READY dans cette tranche. Le changement de fuseau d’une école déjà ACTIVE reste soumis à une future analyse d’impact dédiée. Les autres corrections d’identité restent possibles avec versions et audit.

## Extension minimale : notice et politique réellement adoptées

Le canon ne contient aucune commande transportant les textes nécessaires à sa propre readiness ; AP166 ne contient que la progression. Cette extension de réalisation a donc été retenue explicitement pour éviter une approbation fictive ou une édition SQL préalable. Son schéma machine séparé est `apps/api/contracts/g1b-data-policy.json`, vérifié sur les réponses réelles. Elle ne prétend pas implémenter les politiques de champs F21, les référentiels de formation ou une politique GPS.

`SchoolDataPolicy` :

```json
{
  "id": "<schoolId>",
  "schoolId": "<schoolId>",
  "version": 1,
  "status": "DRAFT",
  "noticeText": "",
  "retentionText": "",
  "contactEmail": null,
  "approvedAt": null,
  "approvedByMembershipId": null
}
```

Le PUT reçoit strictement :

```json
{
  "operationId": "<UUID neuf>",
  "noticeText": "<texte réel présenté à l’ADMIN>",
  "retentionText": "<politique réelle de conservation et de traitement>",
  "contactEmail": "<contact réel ou contact d’essai explicitement assumé>",
  "reviewAcknowledged": true
}
```

Textes non blancs, chacun au plus 20 000 unités UTF-16, email valide au plus 320 caractères, JSON strict et corps au plus 200 000 octets. Aucun texte juridique n’est généré ou adopté par défaut. Le contact de demande de données est distinct du contact général scolaire. L’interface montre les deux textes et demande un geste d’adoption, jamais précoché. La saisie reste locale avant ce geste. Une adoption enregistre les octets logiques exacts reçus, une nouvelle version, l’auteur authentifié et l’instant serveur. Les anciennes révisions restent immuables ; modifier les textes exige une nouvelle adoption versionnée.

Cette preuve confirme le choix de l’ADMIN ; elle ne certifie ni conformité juridique ni exécution automatique de la conservation décrite. Aucun consentement d’élève, aucune autorisation GPS et aucune approbation de permis ne sont créés.

## Readiness et versions

`activationReady` ne dépend pas de DRAFT lui-même. Il exige nom scolaire non blanc, fuseau valide, contact valide, ADMIN actif et politique contenant notice/conservation adoptées. Une école archivée n’est pas activable. `activationBlockers` expose des ActionBlocker canoniques, notamment POLICY_REVIEW_REQUIRED. CAN_USE_WORKSPACE exige en plus School ACTIVE. Les trois autres capacités restent fausses, avec des motifs explicites de la tranche non livrée : LESSON_SETUP_REQUIRED, GPS_MODULE_DISABLED/DEVICE_REQUIRED, COURSE_SETUP_REQUIRED.

La configuration, les policies et les lectures liées d’une réponse utilisent une transaction à instant cohérent. Le paramètre canonique optionnel `deviceId` de AP167 est validé comme UUID ; aucun appareil n’est qualifié ou reconnu implicitement par sa présence, et CAN_CAPTURE reste faux en G1B. Les versions des réglages et de la politique sont persistées distinctement de la progression de setup. L’activation incrémente School.version et Setup.version ; elle ne change pas le contenu de la configuration confirmée ni ne crée une offre, formation ou inscription.

## Transactions, RLS et reprise

La migration 002 est distincte de 001. Elle ajoute cinq tables : school_setup, school_data_policy, school_settings_version, operation et audit_event. Les treize tables du schéma conservent ENABLE/FORCE RLS. Aucun NO FORCE n’est exécuté. Le propriétaire DDL obtient les politiques explicites nécessaires à l’initialisation/backfill ; ce rôle n’est pas le runtime. Le trigger d’initialisation s’exécute sous ce propriétaire, avec search_path fixe et sans EXECUTE PUBLIC. Il crée seulement l’état initial sans accord lorsqu’un premier ADMIN est provisionné. L’insertion runtime de setup n’est pas autorisée.

Le runtime reste `drivy_app`, non propriétaire et sans BYPASSRLS. Les INSERT/UPDATE sont accordés par table/colonne et filtrés ADMIN/école ; les preuves, audits et révisions ne sont ni modifiables ni supprimables par ce rôle. Les permissions UPDATE(version) sur Person/Membership servent exclusivement à FOR SHARE ; leurs politiques WITH CHECK false interdisent toute écriture réelle. L’auteur d’une preuve et l’approbateur d’une politique ne peuvent être choisis dans la charge HTTP.

Une commande verrouille d’abord l’accès Person, sérialise la clé par auteur, puis verrouille School et l’appartenance ADMIN. Les droits sont relus après attente des verrous et restent protégés jusqu’au commit. L’unicité `(actorPersonId,operationId)` vaut entre écoles. Type, école, charge canonique et If-Match entrent dans la comparaison de preuve ; une clé incohérente retourne IDEMPOTENCY_MISMATCH. Le résultat, la preuve et l’audit sont écrits dans le même commit. Une erreur annule tout. Aucun appel fournisseur ni événement asynchrone ne justifie une outbox serveur dans cette tranche.

L’audit contient acteur, école, action, ressource, operationId, instant et noms des champs modifiés. Il ne contient ni textes de politique ni coordonnées. La preuve conserve la réponse métier nécessaire au rejeu, sous autorisation. Les journaux applicatifs ne restituent ni SQL, ni corps reçu, ni secret.

AP72 retourne uniquement `{operationId,commandType,resourceType,resourceId,committedAt,resourceVersion}`, pour l’auteur et l’école encore autorisés. Types : SAVE_SCHOOL_SETUP, UPDATE_SCHOOL, ADOPT_SCHOOL_DATA_POLICY, ACTIVATE_SCHOOL ; ressources SchoolSetup, SchoolDataPolicy ou School, id scolaire. Aucun texte/coordonnée ne figure dans cette preuve publique. Un 200 établit le commit. Un 404 ou 403 ne permet jamais de conclure qu’une commande incertaine n’avait pas été appliquée.

Le client journalise la commande chiffrée avant son premier envoi. Toute reprise conserve compte, école, UUID, corps et If-Match exacts ; un rejeu de succès retourne l’ancienne réponse, puis l’interface recharge l’état actuel. Aucun 4xx générique ne supprime une commande incertaine ou reprise après fermeture. IDEMPOTENCY_MISMATCH reste non résolu. Pour un premier envoi UUID neuf, sans historique incertain, un refus métier explicite peut rendre le formulaire modifiable selon le protocole client ; une nouvelle intention utilise une nouvelle clé.

| Erreur | Signification |
|---|---|
| 400 INVALID_REQUEST | JSON/champ/clé invalide ; contrôle de forme avant recherche de preuve |
| 428 PRECONDITION_REQUIRED | If-Match absent, avant recherche de preuve |
| 403 SETUP_ACCESS_REQUIRED | ADMIN courant requis ; ne prouve pas l’absence d’un ancien commit |
| 412 VERSION_CONFLICT | Version objet ou configuration différente, après comparaison de preuve |
| 409 IDEMPOTENCY_MISMATCH | Clé déjà employée avec autre contenu, version, type ou école |
| 409 POLICY_REVIEW_REQUIRED / SETUP_INCOMPLETE | Prérequis d’activation non satisfaits |
| 409 SCHOOL_ALREADY_ACTIVE / SCHOOL_ARCHIVED | Transition non admissible |
| 409 MODULE_NOT_READY / CONFIG_IMPACT_REVIEW_REQUIRED | Modification hors tranche ou confirmation/analyse manquante |
| 409 SETUP_NOT_INITIALIZED | Provisionnement à compléter ; aucun GET réparateur implicite |
| 422 INVALID_TIME_ZONE | Fuseau non valide |
| 503 SERVICE_UNAVAILABLE | Résultat potentiellement incertain ; reprise de la même opération |

## Vérifications

`test/g1b.integration.test.ts` remet à zéro uniquement `drivy_test`, sous garde de nom de base, puis applique 001 avec un propriétaire NOSUPERUSER/NOBYPASSRLS/NOCREATEDB/NOCREATEROLE. Des fixtures existent avant 002 pour éprouver le backfill réel sous FORCE RLS. Les appels API passent sous le vrai rôle drivy_app, les courses utilisent plusieurs connexions PostgreSQL et un verrou observable.

Contrôles exécutés : compatibilité des réponses avec le canon OpenAPI, initialisation sans accord, absence d’écriture GET, progression non probante, adoption/ancienne révision, activation non circulaire, mêmes/différentes commandes concurrentes, version de configuration périmée, perte de réponse, révocation pendant attente, audit en erreur et rollback intégral, refus RLS de modifier identité/rôles/preuves/autre école, preuve AP72 sans contenu personnel. Les fixtures sont synthétiques. Le résultat de la campagne finale et le commit sont consignés dans STATUS.md par l’intégration ; aucun déploiement distant ni parcours natif n’est déduit de ces tests serveur.
