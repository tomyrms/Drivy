# Observations privées pendant la leçon — AP161 à AP164

Implémentation du 24 septembre 2026, dans la refonte. Référence immuable : [R46](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/regles-etats.md#r46), [saisie pendant la leçon](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/gps-replay.md#saisie-pendant-lecon) et [OpenAPI 3.11.0](../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml). Cette tranche est serveur ; le raccord au signalement scolaire natif et sa recette restent distincts.

## READY du parcours

1. **Action utilisateur :** le moniteur désigné conserve un moment privé, le qualifie explicitement par thème/statut, le relit ou le retire. Ouvrir le panneau n'appelle aucun endpoint. Sans GPS, les trois champs d'ancrage restent nuls.
2. **Source de vérité :** le serveur fixe école, leçon, formation et auteur depuis l'identité courante. Le thème appartient au curriculum de la formation. Les statuts ATTENTION / TO_REWORK / POSITIVE sont des événements ; ils ne changent aucune note finale ni progression.
3. **Échec et concurrence :** verrou de leçon, version de l'observation pour modification/retrait, idempotence durable par auteur et corps exact. Le lot contenant un point doit être confirmé avant son observation. Un échec transitoire n'écrit aucune preuve de succès. Une arrivée LIVE après publication exige une revue explicite.
4. **Persistance minimale :** une seule table `geo_observation`, justifiée par les événements antérieurs au brouillon. Aucun nouveau brouillon n'est créé par le signalement. Les IDs du brouillon sont une projection ; AP49 rattache dans sa transaction les événements actifs de son auteur, augmente leurs versions, et retourne les IDs réels. Aucun backfill d'observations, aucune donnée G0 ou EXAMPLE importée.
5. **Contrat et UI :** AP161–164 canoniques, détaillés ci-dessous. L'UI doit relire les versions après constat, distinguer « conservé sur l'appareil », « en attente » et « enregistré au serveur », puis préserver l'intention en cas de conflit. La confirmation sans position doit être explicite quand l'ancre est devenue interdite.
6. **Preuve attendue / obtenue :** un parcours PostgreSQL isolé vérifie double envoi concurrent, refus de droits, rollback sans preuve, reprise après lot absent, rattachement/versionnement, purge d'ancre, retrait et absence de publication implicite. Typage et build passent. Pas de qualification de sécurité en conduite, ni mesure physique, ni recette complète native annoncée.

## Routes et intentions

Préfixe `/v1/schools/{schoolId}`. Réponses sous `{data,requestId,serverTime}`, sans cache. Identifiants UUID normalisés en minuscules. `Idempotency-Key` doit être identique à `operationId`.

| Route | Corps / précondition | Réponse | AP72 commandType |
|---|---|---|---|
| GET `/lessons/{lessonId}/geo-observations` | `cursor?`, `limit` 1–100, défaut 50 | Page privée `items`, `nextCursor` | — |
| POST `/lessons/{lessonId}/geo-observations` | `GeoObservationCommand`, sans If-Match | 201 `GeoObservation` + ETag | `CREATE_GEO_OBSERVATION` |
| PUT `/geo-observations/{observationId}` | Même DTO + If-Match observation | 200 `GeoObservation` + ETag | `UPDATE_GEO_OBSERVATION` |
| POST `/geo-observations/{observationId}/remove` | `{operationId,reason}` + If-Match observation | 200 `{operationId,accepted:true}` | `REMOVE_GEO_OBSERVATION` |

AP72 utilise `resourceType=GeoObservation`, l'identifiant de l'observation et sa version réellement commitée, y compris après retrait. Aucun texte ni ancre ne figure dans la preuve AP72 ou les champs d'audit. La preuve reste soumise aux droits pédagogiques courants. Un replay POST/PUT relit la projection actuelle plutôt que de restituer une ancienne ancre purgée ; après retrait, `OBSERVATION_REMOVED` indique de consulter la preuve, sans ressusciter le texte.

Le corps canonique contient `operationId`, `draftId`, `captureId`, `segmentId`, `pointSequence`, `competencyId`, `text`, puis les métadonnées `origin`, `observedAt`, `eventKind`, `eventStatus`. Les références et le statut peuvent être nuls conformément au schéma. Pour LIVE, instant, type et statut sont explicites ; MARKER exige compétence/statut nuls, QUALIFIED exige une compétence et un statut choisis. Sans `origin`, le corps hérité est REVIEW avec brouillon obligatoire. L'auteur n'est jamais accepté dans le corps.

`observedAt` conserve l'instant d'ouverture. Une qualification LIVE ne peut pas le remplacer. Une correction temporelle explicite passe par REVIEW et un brouillon actuel. L'heure de l'événement reste indicative, distincte de celle de la mesure et de la réception ; la borne technique refuse seulement un instant supérieur de plus de cinq minutes à l'heure serveur. Aucun intervalle GPS ou temps commercial n'est déduit de cet instant.

## Droits, ancrage et clôture

Les lectures et mutations privées exigent le moniteur désigné, son rôle INSTRUCTOR actif et une affectation actuelle à la formation. ADMIN seul, élève, autre moniteur ou autre école n'accèdent pas à AP161. Le serveur verrouille aussi les personnes et relit l'habilitation avant l'idempotence. La table est en FORCE RLS avec privilèges d'écriture bornés ; les liens de contexte sont contrôlés en base.

Une ancre exige un triplet complet, une capture de cette leçon encore utilisable, puis un lot reçu contenant réellement la séquence. Les points sont déchiffrés uniquement pour cette vérification ; ni coordonnées ni copie de trace ne sont ajoutées à l'observation, à son audit ou à ses logs. Une mesure après `observedAt` ou hors des bornes de capture est refusée. Le serveur ne prétend pas déduire l'état local du collecteur : l'absence d'ancre pendant pause, lacune ou avant mesure reste aussi une obligation du client.

AP49 rattache les événements privés de l'auteur sous le verrou de leçon. Une arrivée LIVE tardive peut rejoindre le brouillon initial avant publication ; elle augmente aussi la version du brouillon. Modification/retrait augmente la version de l'observation et celle du brouillon concerné. La limite de 100 événements actifs par auteur/leçon préserve `ReportDraft.geoObservationIds.maxItems=100`. Elle est contrôlée sous le même verrou que l'ajout.

Retirer vide le texte et les références GPS de la ligne, tout en gardant une tombstone et l'audit. Détruire un lot invalide les ancres qui le référencent et leurs versions, ainsi que la version du brouillon concerné. Aucun déplacement silencieux vers un autre point. Les mécanismes complets de rétention/purge et publication géographique restent dans leur tranche dédiée.

| Code | Effet client |
|---|---|
| 409 `ANCHOR_NOT_READY` | Attendre l'acquittement du lot, reprendre la même intention ; aucune opération commitée. |
| 409 `ANCHOR_INVALID` | Revue explicite de l'ancre ; ne pas substituer une position. |
| 409 `OBSERVATION_REVIEW_REQUIRED` | Conserver l'intention, relire le brouillon et créer une nouvelle mutation après décision. |
| 409 `LESSON_STATE_CONFLICT` | Leçon annulée/non réalisée ; ne pas la réactiver. |
| 409 `CURRICULUM_VERSION_MISMATCH` | Rechoisir une compétence autorisée. |
| 409 `OBSERVATION_REMOVED` / `OBSERVATION_LIMIT_REACHED` | Relire les événements privés et la preuve éventuelle. |
| 412 `VERSION_CONFLICT` | Relire ; ne pas deviner la version après rattachement. |
| 422 `OBSERVATION_TIME_CHANGED` / `OBSERVATION_TIME_INVALID` | Relire l'instant ; correction explicite en revue. |
| 409 `IDEMPOTENCY_MISMATCH`, erreur réseau/droits | Aucun oubli automatique d'une intention déjà incertaine. |

AP54 conserve sa garde explicite : aucune sélection textuelle ou géographique n'est publiée par cette tranche. Un bilan textuel peut être publié avec `captureSelection:null` et `textObservationSelection:[]`. Les événements privés restent privés ; ni le compteur ni MARKER ne deviennent une évaluation élève.

AP160 restitue aussi les observations privées autorisées dont l'ancre correspond à une mesure effectivement incluse dans sa page de replay. Les événements sans ancre restent dans AP161 ; aucune position ne leur est attribuée. Une page sans mesure n'ajoute aucune observation ancrée, et la purge du lot retire ces observations du replay sans supprimer le texte privé conservé dans AP161.

## Vérification exécutée

`npm run typecheck --workspace @drivy/api` et `npm run build --workspace @drivy/api` réussis. Une seule recette ciblée : `npm exec --workspace @drivy/api -- vitest run test/capture-observations.integration.test.ts`, PostgreSQL 17 du conteneur local port 55435, base dédiée `drivy_observation_test`. Migrations 001–009 appliquées sous owner non-superuser, sans BYPASSRLS ni CREATEROLE ; 40 tables sur 40 en FORCE RLS. La recette utilise seulement des données synthétiques et une qualification de capture synthétique locale, jamais un profil d'appareil approuvé pour l'hébergement.

Le test accepte l'URL de recette `drivy_test` ou celle de sa base réservée, puis crée/réinitialise uniquement `drivy_observation_test` dans ce cluster. Il exige donc un opérateur local/CI capable de préparer cette base. Aucun déploiement, migration distante ni envoi externe exécuté dans cette tranche.
