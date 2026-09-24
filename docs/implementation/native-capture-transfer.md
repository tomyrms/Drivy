# Transmission de la capture scolaire

`SchoolCaptureTransferCoordinator` transmet exclusivement les intentions du coffre SQLCipher spécialisé. Il ne crée ni GPS, ni segment, ni point. Le départ nécessite toujours une confirmation de la personne puis l'ouverture durable d'un segment par le coordinateur local.

Le transport relit les droits avant chaque mutation avec le même jeton d'accès que la commande. La lecture AP155 peut également être liée à une portée exacte. Le service invalide sa génération et appelle une fermeture locale synchrone en cas de révocation, disparition d'une capture connue, changement de compte ou expiration. Une absence de reçu AP72, qui peut signifier que la commande n'a pas été commise, ne provoque pas cette révocation.

Une tentative est enregistrée avant émission. Les octets et l'UUID viennent de la relecture du coffre ; aucune erreur ne les remplace. L'accusé est conservé avant de rendre un succès à l'écran. AP72 peut confirmer un commit, mais ne fournit ni preuve signée ni empreinte de lot : sa seule lecture ne supprime donc aucune intention.

Un départ renvoyé encore autorisé vérifie les deux signatures, les identités et la borne monotone puis installe atomiquement le contexte et l'accusé. Ce retour ne lance pas de collecte. Un départ renvoyé déjà arrêté, révoqué ou expiré est acquitté sans bail.

La transmission des données donne priorité à l'arrêt avant les lots et n'envoie aucun choix ou départ en attente. Une projection AP155 est relue avant/après ces transferts. Avant finalisation, sa version courante est réconciliée ; le manifeste vient du coffre. Une finalisation partielle reste un accord distinct. Les changements de droits ne réaffectent jamais les anciennes intentions à un nouveau contexte.

Le propriétaire `SchoolCaptureSessionController` est conservé à la racine de l'application. Préparation, Agenda et onglet Séance partagent le même journal. La récupération des sessions interrompues s'effectue une seule fois au lancement ; ouvrir une deuxième feuille ne scelle pas une collecte active. La source passe au propriétaire avant toute attente d'adoption ; fermer la préparation ne l'invalide plus. Un échec avant l'adoption arrête la source puis scelle l'autorisation inutilisée dans sa portée initiale.

La carte montre exclusivement les mesures dont l'écriture est confirmée. Pause, reprise, refus de l'élève, révocation et arrêt ferment la source avant les attentes disque/réseau. Un arrêt terminal peut attendre un scellement de pause en cours sans être perdu. Les retours tardifs ne remplacent pas un état arrêté. Les invalidations de bail sont limitées à la portée d'origine pour qu'une ancienne réponse ne supprime pas le bail d'un autre contexte.

Changer d'onglet ou fermer la vue conserve le trajet et ses commandes d'envoi. La synchronisation affichée vient du résultat AP158 durable. Un nouveau départ ne coexiste pas avec un trajet personnel en cours. Les données récupérées après relance demandent encore une entrée de reprise explicite ; elles ne réactivent jamais la source.

Le snapshot `5ff4cda` est compilé sur Apple (run IPA `36061409215`). La composition complète et les nouvelles vues attendent leur compilation groupée. Les scénarios réseau, le parcours physique et le traitement visible des anciens epochs restent à qualifier. Aucun profil d'appareil n'est déclaré qualifié par ce build.
