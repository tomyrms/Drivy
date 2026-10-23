# Messagerie #65 : revue indépendante ciblée du 23 octobre 2026

## Périmètre et preuve

Revue statique du snapshot lu vers 03:22 +02:00 dans `dv-65-openai`, branche `openai/65-messagerie`. Fichiers examinés : `apps/api/src/messaging.ts`, `messaging-routes.ts`, migration `20261023_messaging_foundation.sql`, tests `messaging*.ts`, schémas existants pertinents. Les numéros ci-dessous désignent ce snapshot initial, avant corrections backend.

Aucun test exécuté, conformément au report vers #84. Aucun build, accès base, secret ou donnée réelle. Aucun code modifié par le relecteur. Ce document seul est autorisé après la revue. Aucun sous-agent ni commit. Les constats sont issus de lecture et de scénarios intercalés raisonnés, pas de reproduction exécutée.

Production fermée, mode test synthetic seulement. Transport opaque ne prouve pas E2EE. Confidentialité réelle non qualifiée. Aucun protocole cryptographique maison demandé.

## Constats initiaux transmis au backend et au coordinateur

### F1 · P1 · Première création et visibilité RLS

Sources : migration lignes 74–79 et 104–105, `messaging.ts` lignes 38–40 et 46–48.

La politique SELECT de conversation appelle une fonction SQL STABLE recherchant la conversation dans la même table. L'INSERT avec RETURNING exige cette politique SELECT sur la nouvelle ligne, mais la fonction utilise le snapshot de la commande, qui ne voit pas cette insertion. La première création private/general est donc exposée au refus RLS, contrairement à une réouverture de ligne préexistante.

Sémantique recoupée dans la documentation officielle PostgreSQL, sections « Function Volatility Categories » et « CREATE POLICY ». Reproduction PostgreSQL différée à #84. La politique doit pouvoir autoriser la ligne candidate sans exiger sa présence préalable dans la table.

### F2 · P1 · Révocation et compteur de séquence

Sources : `messaging.ts` lignes 94–99, `messaging-routes.ts` lignes 33–38, migration lignes 29 et 112–119.

Intercalage : INSERT message réussi, révocation concurrente d'appartenance commise, UPDATE compteur désormais masqué par RLS. Le résultat zéro ligne de cet UPDATE n'est pas contrôlé. Le message peut être commis avec un `last_sequence` inchangé. Dans GENERAL, un membre toujours éligible reprend ensuite cette séquence et heurte la contrainte UNIQUE.

Le verrou de conversation ne coordonne pas les modifications de droits. Contrôler l'effet de l'UPDATE et sérialiser les droits nécessaires avec leur révocation. Couvrir l'intercalage en test isolé lors de #84.

### F3 · P2 · Orientation incorrecte des rôles cumulés

Sources : migration lignes 58 et 62–67.

Un acteur LEARNER+INSTRUCTOR écrivant à son élève fait choisir son propre dossier par le CASE, puis rechercher l'affectation sur sa propre formation au lieu de celle du destinataire. La même paire peut être autorisée dans le sens inverse. Le schéma existant autorise le cumul de rôles.

Évaluer chaque orientation de relation avec le dossier élève et l'appartenance moniteur correspondants. Vérifier aussi le chemin ADMIN explicite lorsque les rôles se cumulent.

### F4 · P2 · Tri textuel des UUID

Sources : `messaging.ts` ligne 37, `messaging-routes.ts` lignes 9 et 49, migration ligne 18.

Le tri JavaScript sensible à la casse peut inverser l'ordre PostgreSQL des UUID. Exemple synthétique : acteur `a0000000-0000-4000-8000-000000000001`, pair `B0000000-0000-4000-8000-000000000002`. Le tri place B avant a, alors que les UUID SQL sont ordonnés a avant b. Le CHECK `person_low < person_high` rejette alors une paire valide.

Normaliser les UUID ou calculer LEAST/GREATEST sur leurs valeurs SQL uuid.

## Couverture et limites

Le test de pagination initial ne contient qu'un message et ne franchit aucun curseur. Aucun scénario concurrent orchestré ne couvre la révocation entre insertion et compteur. Aucune exécution de tests ne peut être déduite de leur présence.

Aucun contournement inter-écoles ou accès universel ADMIN supplémentaire établi par cette lecture. Cela ne constitue pas une qualification exhaustive. Pas d'audit global demandé ni réalisé.

## Complément iOS ciblé

Lecture vers 03:31 +02:00, demandée par le coordinateur pendant les corrections backend. Fichiers principaux : `MessagingProtectedStore.swift`, `MessagingOutboxCoordinator.swift`, `MessagingWorkspace.swift`, `MessagingHTTPTransport.swift`. Lecture des appels immédiats dans `MessagingViews.swift` et `MessagingDevelopmentEntry.swift` pour établir les scénarios. Aucun audit global, aucune compilation ni aucun test Apple exécutés.

Constats envoyés à blossom et clover avec `delivery: wake` :

- **I1 · P1 · Identité du transport non liée au contexte actif.** `MessagingHTTPTransport.swift:135–163` vérifie URL, mais pas l'identité/époque du fournisseur de jeton. Le refresh 401 peut fournir un jeton d'un autre compte. Les DTO réutilisent le scope demandé (`69`, `84–85`) et l'acquittement ne compare pas `senderPersonId` (`80–81`). Scénario : ancienne outbox A, fournisseur désormais B, même conversation GENERAL accessible à B. L'envoi est attribué à B, puis acquitté et retiré de la file A (`MessagingOutboxCoordinator.swift:56–60`). Prévoir contexte courant/génération contrôlé avant et après suspension, ainsi qu'identité de l'acquittement. Les réponses tardives du workspace n'ont pas de garde d'invalidation propre.
- **I2 · P1/P2 · Réentrance de la composition.** `MessagingViews.swift:155–157,193–202` ne verrouille pas l'envoi avant son premier await. Deux taps lancent deux `enqueue`, chacun crée son UUID (`MessagingOutboxCoordinator.swift:31–39`). La déduplication des retries par UUID ne fusionne pas ces deux intentions. De plus, une édition pendant encrypt/put est effacée par `draft = ""` à la reprise. Capturer le texte/version, verrouiller l'action et ne supprimer que le brouillon effectivement envoyé.
- **I3 · P2 · Snapshot partagé entre plusieurs acteurs.** `MessagingProtectedStore.swift:36–45,60–65,95–113` sérialise uniquement une instance. Plusieurs instances du même scope utilisent le même fichier. Leurs load/modify/save peuvent se chevaucher et le dernier remplacement perdre une entrée outbox ou un brouillon. Partager le propriétaire par scope ou coordonner tout le read-modify-write.
- **I4 · P2 · Lecture et silence confondus.** `MessagingHTTPTransport.swift:105–113` utilise Encodable synthétique avec `mutedUntil: String?`, qui omet la clé si nil. Le backend initial `messaging-routes.ts:73` impose une clé nullable mais non optionnelle. `MessagingWorkspace.swift:103` passe nil pour marquer lu : rejet du contrat. Encoder null seul ne suffit pas à la sémantique : `messaging.ts:115` effacerait alors la sourdine. Distinguer progression de lecture et mutation du silence.

Contrôles positifs limités à la lecture : les écritures de snapshot et temporaires utilisent les octets AES scellés, pas le JSON clair. Quand un fichier existe et que sa clé manque, `load` échoue avant `save` (`MessagingProtectedStore.swift:78–92`), sans fallback clair ni remplacement normal démontré. Le scope est lié au chemin, aux données authentifiées et au contenu du snapshot. Cela ne qualifie ni protection effective Apple, ni E2EE, ni comportement physique du Keychain.

## Seconde passe backend

Confirmation hibiscus reçue à 03:36 +02:00, puis relecture ciblée du service, de la migration, des routes et des tests associés. Le typage et `diff --check` sont annoncés réussis par le backend, non exécutés par le relecteur. Toujours aucun test PostgreSQL exécuté.

- **F1 corrigé statiquement** : migration lignes 145–150, SELECT évalue les colonnes de la ligne candidate et ne recherche plus sa présence préalable dans la table. Créations avec `DO NOTHING RETURNING`, puis lecture de l'existant (`messaging.ts:51–69`).
- **F2 désynchronisation du compteur corrigée statiquement** : `messaging.ts:156–167`, UPDATE RETURNING du compteur avant INSERT, résultat contrôlé, rollback commun en cas d'échec ultérieur. Les verrous des sources d'autorisation sont ajoutés dans la migration lignes 58–79. Leur comportement concurrent sur PostgreSQL reste à qualifier dans #84.
- **F3 corrigé statiquement** : migration lignes 87–97, chaque orientation sélectionne son dossier et son moniteur/admin correspondants.
- **F4 corrigé statiquement** : `messaging.ts:46,50`, normalisation lowercase avant comparaison et tri.

**R1 · P1 · Course résiduelle sur l'époque attendue, transmise hibiscus et clover avec wake.** La nouvelle garde `messaging-routes.ts:40–42` lit et compare `access_epoch` avant le verrouillage des droits (`messaging.ts:125–127`). Si une mutation concurrente passe l'époque de 1 à 2 entre ces opérations tout en conservant une appartenance active éligible, le verrou protège ensuite l'état nouveau, mais `canRead` ne compare pas l'époque attendue. La requête de l'ancien contexte peut encore écrire et la réponse `messaging-routes.ts:46` annonce l'ancienne époque mémorisée. Faire cette comparaison sous verrou d'appartenance ou la refaire après acquisition avec l'époque attendue portée par l'acteur. Scénario raisonné, non exécuté.

Les nouveaux tests lus couvrent plusieurs pages, une reprise ascendante, le cumul de rôles, les intentions concurrentes et lecture/silence. Ils ne sont pas déclarés passants. L'intercalage époque/prise de verrou reste à couvrir. I4 est corrigé côté backend par distinction champ absent/null et contrôle de version de silence (`messaging.ts:172–199`, routes lignes 94–98). Raccord iOS encore à vérifier par blossom.

Aucun audit global ni nouvelle qualification de confidentialité.

### Contrôle final R1 à 03:42 +02:00

Après annonce du commit backend `f01b047`, lecture de `messaging-routes.ts:40–42` : `FOR SHARE OF m,p` protège désormais la comparaison d'époque jusqu'au commit. **R1 corrigé statiquement.**

**R3 · P2 · Inversion directe d'ordre des verrous introduite par cette correction.** `execute` verrouille maintenant l'appartenance, puis `messaging_lock_rights` demande SHARE sur l'école (migration ligne 65). La commande scolaire existante prend UPDATE sur l'école (`commands.ts:79`) avant de verrouiller ou modifier l'appartenance (`commands.ts:84`, révocation `administration.ts:53`). Intercalage : l'envoi détient l'appartenance et attend l'école, la révocation détient l'école et attend l'appartenance. Deadlock/timeout, sans fuite établie, mais échec de l'une des opérations. Harmoniser l'ordre personne → école → appartenance tout en conservant le contrôle d'époque protégé. Transmis hibiscus et clover avec wake, sans exécuter de test. Ce contrôle porte uniquement sur la régression immédiate du verrou ajouté.

## Seconde passe iOS

Corrections annoncées par blossom à 03:40 +02:00, relues sans compilation ni test Apple. Retour adressé à blossom et clover avec wake.

- I1 : contrôles de contexte courant avant/après transport, headers d'identité/époque attendues, validation du contexte de réponse et de l'expéditeur d'acquittement présents (`MessagingHTTPTransport.swift:174–214,94–102`). Le workspace contrôle les réponses tardives, la composition transmet le fournisseur courant. Cohérent statiquement, sans qualification exécutée.
- I2 : garde `sending` avant premier await et capture de la saisie, conservation du texte modifié pendant l'enqueue (`MessagingViews.swift:257–274`). Le double enqueue décrit initialement est corrigé statiquement.
- I3 : verrou statique partagé couvrant les méthodes synchrones read-modify-write (`MessagingProtectedStore.swift:23,39–84`). Aucun await sous ce verrou dans les sections lues. Corrige la course inter-instances dans le processus.
- I4 : markRead omet la mutation de silence, sourdine transmet la version attendue. Raccord au contrat backend corrigé. Le transport refuse actuellement nil avec expectedVersion (`MessagingHTTPTransport.swift:152`), donc l'annulation explicite du silence reste non exposée, à documenter si hors périmètre actuel.

**R2 · P2 · Version de lecture figée dans la route UI.** `MessagingViews.swift:138–141,227–230` utilise la version capturée lors de l'ouverture. `MessagingWorkspace.swift:131–134` jette la réponse markRead et le refresh de liste après sourdine (`142–146`) ne met pas à jour la route ouverte. Scénario : ouvrir version 0, marquer lu crée version 1, puis sourdine envoie encore expectedVersion 0 et échoue en faux conflit. Une seconde modification de sourdine après la première rencontre le même problème. Maintenir l'état courant par conversation, actualisé depuis les réponses, et le consulter au moment de l'action.

Aucun défaut de syntaxe Swift évident repéré dans cette lecture ciblée. Cela ne vaut pas compilation Swift 6 ni qualification Apple. Aucun code modifié par le relecteur.

## Dernière lecture ciblée à 03:48 +02:00

Déclenchée après signal blossom, limitée aux modifications annoncées, sans réaudit.

- **R1 et R3 corrigés statiquement** : backend annoncé `b55465c`, routes lignes 43–49 prennent les verrous personne, école, appartenance dans cet ordre, puis comparent l'époque. Timeouts présents lignes 32–33. Pas de test de concurrence exécuté par le relecteur.
- **R2 corrigé statiquement** : état de lecture courant par conversation, réponses markRead/silence fusionnées et boutons consultant cet état. `mergedReadState` refuse le retour à une version antérieure et conserve une progression maximale. Fixture lue, non exécutée.
- Correctifs `await DrivyAPIClient.permits` et `self.error` présents. L'échec IPA précédent est une information rapportée par le coordinateur, pas une exécution du relecteur. Aucun résultat de la compilation suivante encore constaté.
- Validation avant put : schéma/identifiant de clé limités à l'alphabet API, enveloppe non vide et base64 au plus 12 000 caractères. Reprise au plus 20 entrées par appel, sans rechiffrement ni nouvel identifiant. Moniteur réseau arrêté à disparition et callbacks périmés filtrés par génération. Signature `DrivyAvatar(name:size:)` compatible, sans photo fournie. Cohérence statique seulement.

**R4 · P1 · Purge globale déclenchée par refus d'une seule conversation.** La reprise automatique `MessagingWorkspace.refreshVisible` transmet le premier `accessChanged` à `recordFailure`, qui lance `revocationStore.purge(scope:)` (`MessagingWorkspace.swift:211–217`). Le transport classe également 401 et 404 comme `accessChanged`. Une conversation privée devenue interdite en tête de file peut donc provoquer, au retour réseau, la suppression de toutes les autres intentions et de tous les brouillons du scope, même ceux d'un GENERAL toujours autorisé. Un refus conversationnel ou un jeton expiré ne confirme pas une révocation globale compte/école. Conserver les autres données, ou réserver la purge globale à une révocation globale explicitement confirmée. Transmis blossom et clover avec wake. Aucune reproduction exécutée.

État à cette lecture : F1–F4, I1–I4 et R1–R3 corrigés statiquement, R4 ouverte. Tests métier et Apple toujours non exécutés par cette revue, confidentialité réelle et E2EE non qualifiées.

## Conclusion après delta R4, 03:50 +02:00

**R4 corrigée statiquement.** Le transport distingue maintenant 404 (`conversationUnavailable`) de 401/403 (`accessChanged`). La reprise ne s'arrête pas sur `conversationUnavailable`, conserve l'intention refusée et poursuit les autres entrées de son lot borné. Le workspace ne déclenche plus aucune purge globale automatique sur ces erreurs, et l'injection `revocationStore` a été retirée de la composition. Sur 401/403, seule la mémoire affichée est effacée et la reprise arrêtée, sans supprimer la file ni les brouillons scellés.

Fixture ajoutée et lue : ordre déterministe privée inaccessible, puis GENERAL accepté, seule la privée restant dans la file. Fixture non exécutée. Aucun nouveau P1/P2 ni risque syntaxique évident identifié dans ce dernier delta. Retour envoyé à blossom et clover avec wake.

**Bilan final de cette revue ciblée : tous les constats identifiés F1–F4, I1–I4 et R1–R4 sont corrigés en lecture statique.** Cette clôture n'est ni un audit global, ni une preuve de fonctionnement. Aucun test métier/PostgreSQL/Apple, aucune migration ni compilation n'a été exécuté par le relecteur. Les résultats typecheck et IPA rapportés par les autres agents restent distincts de cette preuve. Aucun résultat de l'IPA suivante n'est revendiqué ici. Aucun code modifié, aucun commit effectué par le relecteur, seul ce document autorisé a été écrit.

Activation réelle toujours exclue, confidentialité réelle et E2EE toujours non qualifiées. La qualification exécutée relève de #84 et des validations prévues, sans protocole cryptographique maison.
