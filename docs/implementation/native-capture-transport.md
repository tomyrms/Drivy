# Transport natif de capture scolaire

Le module `SchoolCaptureAPI` prépare les lectures AP152, AP155, AP160 privé et AP191, les mutations AP153–154/AP156–158/AP190 ainsi que la vérification des deux autorisations AP154. Les DTO suivent le contrat canonique. Le replay privé possède une méthode dédiée : il ne sert pas de repli lors d’une lecture publiée refusée.

La clé publique Ed25519 provient de `/v1/capture-keys` sur l’API HTTPS configurée. Le vérificateur ignore les URLs contenues dans un JWT ; il contrôle signature, algorithme, type, issuer attendu, audience, sujet et identités de capture, école, appareil, diagnostic et leçon. Les preuves de collecte et de transfert ont des scopes différents. Un jeton simplement décodé n’ouvre jamais la collecte.

Le bail est fondé sur l’heure serveur et le temps monotone écoulé depuis le début de la requête. Il inclut donc le délai réseau de façon conservatrice, ne se prolonge pas après un changement d’horloge civile et n’est pas sérialisable pour une reprise après redémarrage.

L’encodage des lots utilise JavaScriptCore uniquement pour la fonction canonique constante, sur le JSON transmis en argument : le rendu des nombres suit ainsi ECMAScript comme au serveur, y compris les exposants et le zéro négatif. Aucun script distant ni objet hôte n’est exposé. La signature de transfert et l’identifiant d’opération sont exclus du hash. La précision doit être une mesure finie et non négative ; les séquences et instants sont strictement croissants.

Les mutations prennent une intention contenant les octets exacts à conserver avant émission. Elles relisent le compte avec le même jeton que celui de l’envoi et vérifient personne, école, appartenance et version des accès. L’accusé doit correspondre à la ressource attendue, et à l’empreinte pour un lot. Le transport ne supprime jamais l’intention locale et ne remplace jamais sa référence en cas d’échec.

Ce module n’est pas encore relié au collecteur local. Le journal chiffré spécialisé des chunks, la persistance du contexte autorisé et la fermeture durable sont à raccorder avant ouverture de la capture scolaire dans l’interface. Les trajets locaux et les exemples existants ne sont jamais envoyés automatiquement. Le choix « sans GPS » reste indépendant de cette réalisation.

Vérification à ce stade : DTO, lectures et vérification de signature compilés dans l’IPA 0.7.0/build21, run36054482531. L’encodage des lots et l’ajustement du bail à la seconde entière du JWT sont compilés dans le build22, run36055359269. Les mutations attendent le résultat du build lancé sur `e60e7d9`. Les vecteurs de signature et l’interopérabilité des chunks restent à exécuter avant l’activation. Aucun appareil ni profil de capture physique n’est déclaré qualifié.

Les clés privées dédiées ont été préparées le 24 septembre sur CT114 par `provision-capture-keys.mjs`, dans `api.env` root0600 avec sauvegarde privée. Aucun service n’a été redémarré par ce provisionnement et aucun profil de qualification n’a été ajouté. Le script conserve les clés existantes lors d’une reprise.

`SchoolCaptureInteropTests` conserve le vecteur ECMAScript fourni par le serveur (zéro négatif et deux exposants, hash`65e7f15eec6b99ce5ca16137a146a690bfabab9017619f8c7657da69e30b1ecd`), ainsi que le refus d’une précision d’exemple négative et d’un instant incohérent avec le segment. Ces trois tests sont écrits **NOT_EXECUTED** ; leur présence n’établit pas encore l’interopérabilité Apple.
