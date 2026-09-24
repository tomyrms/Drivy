# Journal natif de capture scolaire

Le module `SchoolCaptureCore` apporte le journal durable séparé du laboratoire G0. Il ne demande aucune permission GPS, ne crée aucune source de localisation et n'envoie aucune requête. Le futur collecteur ne pourra démarrer qu'après installation d'une autorisation serveur vérifiée et écriture du segment. Aucun adaptateur n'importe `DrivingSession`, `RecordedPoint` ou un parcours `EXAMPLE`.

Références : [GPS/replay](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/gps-replay.md), [synchronisation](../../Drivy_Conception_v3_17_2026-09-20/04-technique/synchronisation.md), [serveur AP152–158](g2-capture.md) et [transport natif](native-capture-transport.md). La conception conservée reste intacte.

## Coffre et écritures

`SQLCipherSchoolCaptureStore` est un acteur. Sa connexion SQLCipher non `Sendable` et ses statements restent confinés à cet acteur. `CipherConnection` et `SQLValue` sont extraits du magasin G0 sans modification de leur fonctionnement ; le schéma, la clé et les données G0 restent inchangés.

Le journal scolaire utilise `Application Support/SchoolCapture/capture-v1.sqlite`, une clé aléatoire dédiée de 32 octets dans Keychain (`ch.drivy.school-capture.database.v1`, `AfterFirstUnlockThisDeviceOnly`, sans synchronisation) et un identifiant d'installation conservé dans la base. Une base existante sans sa clé est refusée. Aucun fichier de secours en clair n'est créé. Répertoire, base, WAL et SHM sont protégés après premier déverrouillage et exclus des sauvegardes. Les transactions utilisent `synchronous=FULL` ; cette connexion scolaire active aussi `fullfsync` et `checkpoint_fullfsync`.

Les six tables locales servent à l'installation, la capture, ses segments, les mesures, les lots et les intentions réseau. Ces représentations se trouvent toutes dans SQLCipher. Les points d'un lot, son hash, son identifiant d'opération et les octets exacts de sa requête sont écrits dans la même transaction. Les métadonnées de file permettent de contrôler les portées sans décoder à chaque mesure les anciens lots entiers.

Chaque retour réussi d'une méthode d'écriture suit le commit durable. Une erreur de protection constatée après commit reste une erreur incertaine : il faut relire l'identité conservée, jamais inventer une nouvelle commande. Aucun contenu de mesure, preuve signée ou clé n'est journalisé.

## Interface du transport

1. `openDefault()` ouvre le coffre hors du MainActor ; `installationID()` fournit l'identité d'appareil à employer pour AP190/AP154.
2. `stage(mutation)` écrit une évaluation, un choix ou une demande de départ. Les mutations de lots, d'arrêt et de finalisation sont produites uniquement par les méthodes du journal à partir de ses données durables.
3. `pending(scope:deviceID:)` retourne les opérations non acquittées de cette personne, école et origine API. Les intentions d'un ancien epoch restent présentes avec leur portée originale. `queuedMutation(id:scope:)` relit aussi une opération déjà acquittée.
4. `markAttempted(id:scope:)` grave la tentative **avant** l'émission et retourne la mutation exacte à transmettre. Une portée différente est refusée, sans réécriture des corps ni remplacement d'identifiant.
5. `acknowledge(id:scope:result:)` conserve le résultat après validation de son identité. Pour AP156, capture, segment, indice, hash et date du premier accusé doivent correspondre au lot conservé. Une répétition ne remplace pas un autre hash ou une autre identité.

Il n'existe pas de suppression automatique sur un code HTTP. Une réponse perdue conserve l'intention ; le transport peut renvoyer les mêmes octets sous la même portée. Une intention ancienne ne devient pas renvoyable parce que le compte s'est reconnecté. Le rapprochement après réduction de droits reste un état explicite à traiter par l'intégration réseau.

La transaction de `stage` n'admet qu'un choix non acquitté par personne/école/élève, que ce choix soit global ou lié à une leçon. Deux écrans ou deux connexions locales ne peuvent donc créer simultanément deux choix concurrents après une prélecture de file vide. La même identité d'opération et les mêmes octets restent rejouables.

Après AP153 acquitté, AP152 fournit le choix courant. Un accusé durable ne signifie pas que ce choix est encore actuel, ni qu'un GPS est autorisé.

## Bail, segments et arrêt

`acceptAuthorization(operationID:authorization:lease:scope:deviceID:)` exige le bail monotone issu de la vérification Ed25519 du module API. Il lie la réponse à la commande, à l'école, à la personne, à l'appareil, à la leçon, au choix et au diagnostic. La réponse et l'acquittement AP154 sont écrits atomiquement. Le bail reste uniquement en mémoire et n'est jamais reconstruit depuis le JSON chiffré. Une ligne déjà présente après relance ne reçoit pas un nouveau bail par cette méthode.

`beginSegment` grave une génération locale puis `append` accepte seulement des mesures de cette génération tant que le bail demeure valide. Temps et séquences sont strictement croissants ; une mesure hors du segment ou du bail est refusée. Le mapping temporel doit provenir du futur adaptateur qualifié, pas de l'heure civile choisie par l'utilisateur. Le module ne prétend pas pouvoir attester une mesure physique à partir de nombres fournis par un appelant.

Les lots contiennent au plus 250 points, avec les plafonds serveur de 200 segments, 2 000 lots et 100 000 points par capture. Une pause ferme le segment et son lot incomplet. La reprise explicite utilise un nouveau segment ; elle n'interpole pas l'interruption. Un segment vide conserve `expectedPointCount=0`, `expectedChunkIndices=[]` et `lastSequence=null`.

`SchoolCaptureLocalCoordinator` ordonne les callbacks sur MainActor et borne leur attente à 1 000 mesures. Son appelant lui fournit une fermeture synchrone du collecteur. `pause`, `stop` et `recover` ferment l'admission et appellent cette fermeture **avant leur premier await**. Les callbacks déjà admis sont drainés ; les callbacks tardifs d'une ancienne génération sont refusés. Un défaut d'écriture ferme aussi l'admission et la source, sans annoncer une sauvegarde réussie.

`stopAndSeal` retire le bail mémoire, ferme le dernier segment, fige les lots et le manifeste, puis conserve l'intention AP157 dans la même transaction. Répéter cet arrêt retourne la même intention. Le transport intervient ensuite. Une panne disque peut empêcher le scellement, mais ne remet pas en marche le collecteur arrêté.

`recoverInterrupted(deviceID:)` scelle localement toutes les captures encore ouvertes de l'installation, y compris celles d'un compte ou d'un epoch précédent, en conservant leur portée d'origine. Aucun résultat personnel n'est retourné par cette méthode et aucune émission n'en découle. L'instant exact d'une fermeture forcée étant inconnu, la borne conservatrice est le dernier fait durable (une milliseconde après le dernier point pour la borne exclusive), limitée par l'expiration. Le segment est marqué `APP_TERMINATED`. Aucune position ni durée de collecte supplémentaire n'est créée.

Un AP154 dont la réponse avait été perdue peut revenir déjà arrêté, révoqué ou expiré. `acknowledge(.authorization)` rapproche alors la commande et conserve la projection terminale, sans installer de bail. Une réponse `AUTHORIZED` continue d'exiger `acceptAuthorization` et sa preuve vérifiée.

## Version courante et finalisation

`reconcileProjection(_:scope:)` reçoit une projection AP155 issue du transport contrôlé. Elle exige les mêmes identités et bornes immuables, et une version au moins égale à celle conservée. Elle ne modifie ni les mesures, ni le manifeste, ni les intentions déjà créées ; elle ne réactive jamais la collecte. Une projection terminale retire la capacité mémoire. Lorsqu'une révocation est reçue pendant la collecte, l'intégration doit d'abord arrêter sa source avec le coordinateur : un acteur de stockage n'arrête pas à lui seul le matériel GPS.

Après un upload postérieur à l'arrêt, le serveur peut avoir incrémenté la version. La séquence normale est donc : acquitter les lots, relire AP155, appeler `reconcileProjection`, puis `stageFinalization(expectedVersion:allowPartial:)`. Cette dernière exige un arrêt local scellé et acquitté. Sans décision explicite `allowPartial=true`, chaque lot attendu doit avoir son reçu durable. Une intention de finalisation déjà créée conserve sa version et ses octets ; une nouvelle lecture ne réécrit pas une commande incertaine.

## État de qualification

Le 24 septembre 2026 : revue statique du coffre, des identités, de la reprise et des frontières d'acteur ; vérification de l'extraction exacte de `CipherConnection` et contrôle de diff. Compilation et exécution SQLCipher sur Apple **NOT_EXECUTED** pour ce nouveau module à la rédaction de cette note ; elles sont regroupées dans la prochaine compilation native, pas dans l'IPA correctif urgent précédent.

L'activation matérielle reste fermée : il faut encore raccorder le collecteur qualifié et son minuteur d'expiration, l'affichage d'état, les événements de révocation/déconnexion, le rapprochement réseau/AP72 des anciennes portées, les règles de purge locale et la recette interrompue sur appareil. Aucun profil physique approuvé n'est inventé. Le choix de poursuivre une leçon sans GPS reste disponible.
