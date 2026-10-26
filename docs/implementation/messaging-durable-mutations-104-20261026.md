# Messagerie : intentions conservées après fermeture (#104)

26 octobre 2026. Complète `messaging-optimistic-104-20261025.md` sans changer les endpoints, les droits serveur ou le chiffrement des messages. La composition réelle injecte `MessagingProtectedStore` ; les doubles mémoire sont limités aux tests et au simulateur de qualification.

## Comportement réalisé

Réactions, épingles, votes, suppression pour moi/pour tous et sourdine ont désormais un journal scellé par compte, école, époque d'accès et URL API. Une entrée contient l'identité stable de l'intention, le dernier choix, l'état effectivement transmis dont la réponse reste incertaine, les confirmations et une horloge locale. La sourdine garde également sa version et sa borne de lecture. Les dates de sourdine sont normalisées à la précision réellement émise par le transport.

L'affichage immédiat reste une projection sur les pages serveur. Chaque choix est conservé indépendamment du HTTP : un second geste pendant une réponse lente atteint le journal sans attendre cette réponse. Aucune nouvelle requête ne part avant la conservation durable de son état logique. Après une fermeture, une réponse perdue est reprise avec le même état et le même `transmittingID`, puis le dernier choix est transmis avec un nouvel identifiant si différent. Les endpoints existants expriment un état final, jamais une bascule aveugle. L'envoi de messages garde sa file chiffrée FIFO et son `clientMessageId` existants.

Le transport envoie `Idempotency-Key` pour les réactions, épingles, votes et suppressions. Il exige un `mutationReceipt.operationId` correspondant avant de confirmer la tentative et d'envoyer le choix suivant. Le serveur conserve effet et reçu transactionnels : si la requête A arrive tard après sa reprise puis B, elle retrouve son reçu et ne réapplique pas A. Une simple relecture correspondant à la projection ne remplace jamais ce reçu. Si un ancien serveur ignore le header, l'intention reste incertaine, B attend et l'interface indique que le service doit être mis à jour. La sourdine possède déjà une version attendue : sa reprise reste sur cette précondition.

À l'ouverture, le journal est relu et projeté, puis les pages serveur sont revalidées. Les intentions restaurées sont reprises une fois ; les erreurs incertaines restent affichées et réessayables. Le retour de connexion reprend les entrées hors connexion. Les seuils de lenteur n'envoient aucune requête et ne prouvent aucun échec. Le masquage pour moi reste repris au retour de l'app car son élément n'est plus visible.

La sourdine ne revient plus silencieusement à son ancien état lors d'une panne. Elle indique son attente, son incertitude ou l'échec de conservation. Un conflit de version déclenche une relecture : une réponse perdue déjà appliquée est reconnue ; une progression de lecture sans autre changement de sourdine permet de reprendre avec la version courante. Une sourdine concurrente différente reste un refus explicite. La reprise n'invente jamais une borne de lecture. Les autorisations de notifications du système restent indépendantes.

Une erreur de stockage conserve la projection en mémoire, annonce « non conservée » et interdit le HTTP. Le masquage pour moi redevient visible pour permettre la reprise. Les données scellées illisibles ne sont jamais remplacées par un journal vide. Un changement de contexte ou un refus d'accès empêche la reprise sous le nouveau compte ; les fichiers du contexte précédent ne sont pas purgés sur une simple panne ou un refus conversationnel.

## Stockage et concurrence

Le journal occupe un fichier `-mutations.sealed` distinct, AES-GCM avec authentification liant périmètre et format. Les snapshots préexistants de brouillons/messages/signalements sont inchangés : une ancienne version de l'app qui les réécrit ne supprime pas les mutations. Aucune migration destructrice ni repli en clair. Taille bornée à 2 Mio et 500 cibles ; protection complète, exclusion des sauvegardes, écriture temporaire chiffrée, remplacement atomique et synchronisation du fichier/dossier.

Un verrou local couvre lecture-modification-écriture entre les instances du coffre. La comparaison de l'horloge empêche qu'une ancienne instance remplace une intention plus récente ou qu'un ancien acquittement la supprime. La file des écritures locales sérialise également conservation et retrait dans un workspace : un geste pendant le retrait durable garde sa projection et repart ensuite. Une reprise explicite après conflit local relit d'abord le journal partagé. Le format 2 conserve l'identité de requête ; le lecteur accepte le format 1 sans identité et le réécrit au nouveau format, tandis qu'un ancien binaire refuse le format 2 au lieu d'en perdre les identifiants.

## Vérification

Contrôle exécuté dans ce lot sur Windows : `git diff --check` sans erreur. Pas de compilateur Swift local ; les résultats Apple sont consignés par la campagne ciblée du coordinateur, séparément de ce document.

Scénarios ajoutés à `MessagingOptimisticMutationTests` : reprise hors connexion avec identité stable ; dernier choix conservé pendant HTTP suspendu puis réouverture ; ancienne réponse après changement de contexte ; refus d'une ancienne volonté préservant la suivante ; stockage indisponible sans HTTP puis reprise ; journal illisible sans écrasement ; sourdine puis réactivation avec même version/borne et précision transport ; lenteur sans nouvel envoi. `MessagingProtectedStoreTests` vérifie la réouverture du vrai coffre, la coexistence avec les brouillons, le chiffrement, le rejet de chaque autre périmètre, la corruption conservée, et les anciennes écritures/acquittements.

Le complément protocole vérifie un identifiant identique pour A/reprise de A après réouverture et un identifiant distinct pour B ; un ancien serveur sans reçu ne libère jamais B même si une relecture correspond à A. `MessagingHTTPTransportTests` couvre les headers et corps sur les sept formes de route, le reçu absent et le reçu incohérent. Les preuves PostgreSQL de non-réapplication d'A retardée et de revalidation des droits sont portées par le lot API associé.

Deux régressions couvrent l'erreur locale après un remplacement ou un retrait déjà effectué : la reprise relit l'horloge réellement conservée, ne restaure pas les autres cibles actives et ne renvoie pas une action déjà confirmée pour réparer un retrait local.

Suites Apple ciblées : `MessagingOptimisticMutationTests`, `MessagingProtectedStoreTests`, `MessagingCoreTests`, `MessagingHTTPTransportTests`. `SchoolNotificationSettingsTests` contient aussi la régression sur la huitième confirmation du lot #119, qui ne doit pas laisser un faux conflit.

## Limites de qualification

Pas de client web de messagerie identifié dans le dépôt : ce lot ne crée pas de parcours web. Le header/reçu optionnel étend le contrat, les anciens clients restent compatibles. Les requêtes d'une ancienne version de l'app, déjà parties sans identifiant, ne peuvent pas recevoir rétroactivement un reçu. Réactions/épingles/votes n'ont toujours pas de version distribuée par cible : deux appareils peuvent se croiser et le dernier nouvel état effectivement écrit au serveur l'emporte. La reprise identifiée évite de réappliquer une ancienne tentative ; elle ne crée pas un ordre total entre gestes indépendants de deux appareils.

Les tests utilisent des données synthétiques et des réponses suspendues ; ils ne constituent pas une recette réseau physique 1/5/15 secondes, une validation VoiceOver sur appareil ou une mesure de batterie. Ces preuves restent distinctes de la conservation/reprise vérifiée par tests ciblés.
