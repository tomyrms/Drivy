# Messagerie : époque de chiffrement et reprise (#84)

Décision d’implémentation du 24 octobre 2026, correctif P1-3 autorisé par le coordinateur. Aucun changement d’activation.

## Invariant

Une nouvelle intention ne doit pas être acceptée avec une enveloppe préparée pour une ancienne composition de participants. L’app conserve l’`expectedMembersEpoch` utilisée pour le chiffrement, avec les octets et l’identifiant d’intention, dans sa file scellée. Un retry ne modifie aucun de ces éléments et ne rechiffre jamais automatiquement.

Le POST de message reçoit `expectedMembersEpoch` au premier niveau, entier sûr positif ou nul. Ce champ ne fait pas partie de l’enveloppe opaque `{scheme,keyId,payload}` ni de son empreinte d’idempotence. Il est optionnel au décodage uniquement pour résoudre des intentions historiques déjà acceptées. Pour une intention nouvelle, absent ou périmé signifie `409 MESSAGING_MEMBERS_CHANGED`.

Ordre serveur : droits courants, verrous, synchronisation des liens, recherche d’intention/empreinte, contrôle d’époque, allocation de séquence et écriture. Un acteur encore autorisé retrouve l’acquittement déjà accepté malgré un changement de membres ; un expéditeur désormais révoqué reste refusé avant déduplication. Aucun droit n’est accordé par l’époque annoncée par le client.

## Conservation locale et échecs

`MessagingPending.recoveryContent` conserve le contenu original dans le snapshot AES-GCM existant afin de permettre une recomposition volontaire. Ce contenu n’entre dans aucun DTO réseau et n’est jamais exploité pour remplacer silencieusement une intention. L’archive ancienne reste décodable avec epoch/contenu de récupération absents. Une nouvelle mise en file sans époque de chiffrement est refusée avant persistance.

Le stockage refuse une réécriture du même identifiant avec un autre ciphertext, une autre époque, des mentions, une réponse, un sondage ou un contenu de récupération différents. Un conflit réseau ne supprime pas l’entrée. L’erreur distingue le changement de participants d’un incident temporaire, sans conseiller un retry qui modifierait le chiffrement.

Le contenu récupérable est conservé, mais aucun nouveau parcours UI de recomposition volontaire n’est livré par ce correctif. Les anciens éléments sans contenu de récupération ne sont pas réinterprétés ni supprimés.

La liste des destinataires et l’époque doivent provenir de la même instruction SQL, donc du même snapshot MVCC. Deux SELECT successifs peuvent associer les anciens membres à la nouvelle époque lorsqu’un retrait est intercalé, et rendre le CAS inefficace. Une régression PostgreSQL intercale un vrai retrait après lecture, sans substituer les résultats SQL : RED observé (époque 1 avec anciens membres), puis GREEN avec snapshot unique.

Le refresh automatique conserve le conflit en mémoire par intention et conversation. Il restaure l’erreur après chargement du fil concerné seulement, continue les autres fils et revalide le contexte après chaque suspension pertinente. Il ne réinjecte pas une erreur de l’ancien compte après changement de contexte.

## Preuves et limites

Tests ajoutés avant l’implémentation : contrats/outbox Swift, restauration du snapshot protégé, séparation wire/locale, erreur explicite ; API PostgreSQL pour absence/péremption d’époque, non-consommation de séquence, idempotence historique, conflit d’intention, retrait/réintégration et valeurs invalides.

Le premier RED API a observé 5 échecs sur 6 : une nouvelle intention sans époque était acceptée, et le champ attendu était inconnu du contrat. Le premier GREEN ciblé a réussi 6/6 sous Node 24 et PostgreSQL 17 isolés. Le rapport de campagne `artifacts/qa84-epoch-report.md` consignera les vérifications complémentaires de concurrence et de suite complète.

Swift/Apple : tests préparés, pas exécutés sur le poste Windows dépourvu de Swift. Aucun résultat physique, aucune interopérabilité E2EE via le vrai relais et aucune activation réelle ne sont déduits des tests PostgreSQL à enveloppes synthétiques. Le coordinateur reporte les résultats finaux du SHA intégré dans STATUS.
