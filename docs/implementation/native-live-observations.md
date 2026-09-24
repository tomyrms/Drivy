# Client natif des observations privées

Le module `SchoolObservationAPI` transporte AP161–164 et réutilise `SchoolPrivateGeoObservation`, déjà partagé avec le replay privé. Il ne contient ni collecteur, ni import G0/EXAMPLE, ni permission GPS. Le [contrat serveur](g2-live-observations.md) définit les refus et le rattachement au brouillon par AP49.

`SchoolObservationClient` expose la liste paginée privée, la résolution des compétences du curriculum exact de la formation, la preuve AP72 et les mutations. Chaque lecture/mutation spécialisée relit `/me` avec le même jeton que la requête suivante et vérifie personne, école, membership, accessEpoch et rôle INSTRUCTOR. Le serveur conserve l'autorité sur le moniteur désigné et l'affectation. Les réponses vérifient leur école, leçon, formation et auteur selon les identités attendues ; URLs finales, tailles et types de contenu sont bornés.

L'intention est un `PendingSchoolCommand` du journal chiffré existant ; aucun journal supplémentaire n'est introduit. L'écran doit sauvegarder et relire cette intention avant `send`, puis acquitter exactement cette entrée après résultat valide. L'encodage `SchoolObservationBody` conserve les champs nuls requis, y compris sans GPS. Les octets archivés sont envoyés tels quels, avec leur `operationId` et leur version. Une réponse HTTP validée reste retournée même après annulation tardive de la tâche afin de permettre l'acquittement durable ; une annulation réseau sans réponse laisse la demande incertaine.

| kind natif | Cible durable | AP72 |
|---|---|---|
| `createObservation` | resourceVersion 0, resourceID nil, routeResourceID leçon, expectedVersion nil | CREATE_GEO_OBSERVATION / GeoObservation |
| `updateObservation` | resourceVersion courante, resourceID observation, routeResourceID leçon, expectedVersion nil | UPDATE_GEO_OBSERVATION / GeoObservation |
| `removeObservation` | Même ciblage que la modification | REMOVE_GEO_OBSERVATION / GeoObservation |

La création n'envoie pas If-Match. Modification/retrait envoient la version archivée de l'observation. Une preuve exige operationId/type/type de ressource/identifiant attendu et une version supérieure à celle de l'intention. Les droits changés, réponses incohérentes, IDEMPOTENCY_MISMATCH, retrait déjà observé et erreurs réseau ne permettent aucun oubli automatique de la demande. ANCHOR_NOT_READY conserve une intention réessayable après transfert du lot. Seul un refus métier explicite du premier envoi frais peut permettre une correction suivant les règles existantes de l'outbox ; cette possibilité ne s'applique jamais à une demande reprise ou déjà incertaine.

`SchoolLessonReportClient.drafts` accepte désormais jusqu'à 100 identifiants uniques d'observations privées. Ces identifiants restent dans le modèle ; ils ne sont pas envoyés par SaveReportDraft et le serveur ne les efface pas lors d'une sauvegarde du texte. Le raccord UI rend l'accès aux observations privées explicite. Le bilan textuel peut être publié avec les sélections vides : cela ne partage pas ces observations. La publication sélective reste une tranche distincte, sans masquage de cette limite.

Cette note décrit le code et sa relecture statique. La compilation Swift et la recette UI sont prises dans le snapshot Apple groupé ; elles ne sont pas revendiquées depuis l'environnement Windows.
