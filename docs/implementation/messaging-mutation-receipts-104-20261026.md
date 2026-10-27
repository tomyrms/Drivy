# Messagerie — reçus de mutations et réponses retardées

26 octobre 2026, complément serveur de #104 et de `messaging-durable-mutations-104-20261026.md`.

## Cas corrigé

Une réaction A peut avoir été envoyée juste avant l'arrêt de l'app. Après reprise, l'app réémet A, reçoit sa confirmation puis envoie B. Sans identité de tentative, une ancienne copie de A arrivée après B peut remettre l'état A sur le serveur, même si l'app ignore sa réponse.

Les endpoints de réaction PUT/DELETE, d'épinglage PUT/DELETE, de vote PUT et de suppression DELETE (scope me/everyone) acceptent désormais un `Idempotency-Key` UUID facultatif. L'UUID désigne une tentative exacte ; il reste identique après coupure/reprise et change pour le choix suivant. Il est lié à l'auteur, l'école, la conversation, le message, au type de commande et au contenu accepté. Un autre contenu, endpoint ou contexte sous la même clé produit 409 `IDEMPOTENCY_MISMATCH`.

L'API réutilise `drivy.operation`, `drivy.audit_event`, le hachage canonique et le verrou de commande existants. Le verrou global auteur/UUID est pris après la personne et avant l'école, comme `schoolCommand`. L'effet métier, son reçu et son audit sont commis ensemble. Une répétition concurrente attend ce verrou puis restitue le reçu ; une répétition tardive de A après B restitue également A sans réappliquer A. Il n'y a ni deuxième moteur de commandes ni nouvelle table de file.

## Contrat et accès

Une réponse à une mutation identifiée contient `mutationReceipt: {operationId: UUID}` au premier niveau, en plus de `data`, `context`, `requestId` et `serverTime`. Ce reçu est renvoyé uniquement après le commit de la transaction ou la lecture d'un reçu existant. Le `requestId` HTTP demeure distinct. Le client vérifie l'identité du reçu avant d'acquitter A et de laisser partir B. Une relecture dont l'affichage ressemble à A ne remplace pas ce reçu.

L'identité, le statut actif de la personne et de l'école, le rattachement et son époque restent contrôlés sous verrou. Un reçu ancien ne dispense pas de ces contrôles. Sa conversation doit rester lisible ; aucun droit d'écriture n'est créé par le rejeu. Les politiques existantes des effets restent appliquées lors de la première exécution. Les corps stockés se limitent au résultat de la mutation (identifiants, réaction/choix/état), sans texte ni enveloppe de message. L'audit messagerie n'est lisible que par son auteur : être administrateur scolaire ne révèle pas les métadonnées des conversations privées d'autrui.

AP72 peut restituer la preuve à son auteur tant que la conversation est lisible, avec les mêmes filtres d'auteur et d'école. `resourceVersion:1` est la version initiale du reçu de cette mutation ; ce n'est pas une version distribuée du message ni un état courant. La reprise native utilise le endpoint de mutation et son reçu exact, pas AP72 pour reconstruire un corps.

La sourdine conserve sa précondition de version existante. L'envoi d'un message et les signalements conservent leurs identifiants métier existants. Les commandes d'administration du groupe et la fermeture du sondage ne sont pas converties par ce lot. Deux gestes indépendants sur deux appareils restent ordonnés par leur écriture effective au serveur ; le protocole ne prétend pas fournir un ordre total des gestes entre appareils.

## Compatibilité et installation future

Les anciens clients sans header gardent le comportement et la forme de réponse existants, sans reçu promis. Un nouveau client exige le reçu ; auprès d'une ancienne API qui ignore le header, il garde l'action incertaine et bloque la suivante avec une indication de mise à jour du service. Le stockage natif conserve ce même UUID dans son journal scellé.

Installation future uniquement, précédée de la sauvegarde prescrite : appliquer la migration additive `20261026_messaging_mutation_receipts.sql`, puis installer l'API sur **toutes** les instances avant de distribuer l'IPA qui exige les reçus. La migration ajoute uniquement les politiques d'insertion/lecture nécessaires et préserve les anciennes lignes. Ne pas mélanger instances ignorant les clés et instances les honorant pour ce parcours. Aucun déploiement n'est effectué ici ; une ancienne requête sans identifiant ne peut pas recevoir rétroactivement une protection.

## Vérification

Node 24, types API réussis. PostgreSQL 17.11 isolé, données synthétiques : les neuf nouveaux tests de mutations passent, ainsi que les 22 tests existants de messagerie v2, époques et migrations. Le passage final associe les neuf tests de mutations aux neuf tests de notifications : 18/18 réussis, incluant le filtrage privé de l'audit et le compte actif relu sous verrou pour les préférences.

Les régressions couvrent A/B/A tardif sur réaction, épingle et vote ; deux A réellement en attente sur le même verrou PostgreSQL ; refus de contenu/route différents, indépendance d'une même clé entre auteurs ; masquage et suppression ; AP72 limité à l'auteur, époque modifiée, compatibilité sans header et audit privé. La qualification Swift et UI est portée séparément par la campagne Apple du coordinateur. Aucun résultat de réseau physique ou de VoiceOver n'est déduit de ces tests serveur.
