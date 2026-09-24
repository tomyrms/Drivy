# Transmission de la capture scolaire

`SchoolCaptureTransferCoordinator` transmet exclusivement les intentions du coffre SQLCipher spécialisé. Il ne crée ni GPS, ni segment, ni point. Le départ nécessite toujours une confirmation de la personne puis l'ouverture durable d'un segment par le coordinateur local.

Le transport relit les droits avant chaque mutation avec le même jeton d'accès que la commande. La lecture AP155 peut également être liée à une portée exacte. Le service invalide sa génération et appelle une fermeture locale synchrone en cas de révocation, disparition d'une capture connue, changement de compte ou expiration. Une absence de reçu AP72, qui peut signifier que la commande n'a pas été commise, ne provoque pas cette révocation.

Une tentative est enregistrée avant émission. Les octets et l'UUID viennent de la relecture du coffre ; aucune erreur ne les remplace. L'accusé est conservé avant de rendre un succès à l'écran. AP72 peut confirmer un commit, mais ne fournit ni preuve signée ni empreinte de lot : sa seule lecture ne supprime donc aucune intention.

Un départ renvoyé encore autorisé vérifie les deux signatures, les identités et la borne monotone puis installe atomiquement le contexte et l'accusé. Ce retour ne lance pas de collecte. Un départ renvoyé déjà arrêté, révoqué ou expiré est acquitté sans bail.

La transmission des données donne priorité à l'arrêt avant les lots et n'envoie aucun choix ou départ en attente. Une projection AP155 est relue avant/après ces transferts. Avant finalisation, sa version courante est réconciliée ; le manifeste vient du coffre. Une finalisation partielle reste un accord distinct. Les changements de droits ne réaffectent jamais les anciennes intentions à un nouveau contexte.

État : code en cours d'intégration, compilation Apple et scénarios réseau à exécuter. Le raccord des interruptions de l'adaptateur, de la vue de leçon et des anciens epochs reste nécessaire. Aucun collecteur n'est activé par ce service seul.
