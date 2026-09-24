# Transport natif de capture scolaire

Le module `SchoolCaptureAPI` prépare les lectures AP152, AP155, AP160 privé et AP191 ainsi que la vérification des deux autorisations AP154. Les DTO suivent le contrat canonique. Le replay privé possède une méthode dédiée : il ne sert pas de repli lors d’une lecture publiée refusée.

La clé publique Ed25519 provient de `/v1/capture-keys` sur l’API HTTPS configurée. Le vérificateur ignore les URLs contenues dans un JWT ; il contrôle signature, algorithme, type, issuer attendu, audience, sujet et identités de capture, école, appareil, diagnostic et leçon. Les preuves de collecte et de transfert ont des scopes différents. Un jeton simplement décodé n’ouvre jamais la collecte.

Le bail est fondé sur l’heure serveur et le temps monotone écoulé depuis le début de la requête. Il inclut donc le délai réseau de façon conservatrice, ne se prolonge pas après un changement d’horloge civile et n’est pas sérialisable pour une reprise après redémarrage.

Ce module n’est pas encore relié au collecteur local. Le journal chiffré spécialisé des chunks, le hash canonique partagé Swift/JavaScript, la persistance du contexte autorisé, les appels de mutation et la fermeture durable sont à raccorder avant ouverture de la capture scolaire dans l’interface. Les trajets locaux et les exemples existants ne sont jamais envoyés automatiquement. Le choix « sans GPS » reste indépendant de cette réalisation.

Vérification à ce stade : lecture du contrat et revue du code ; compilation Apple à effectuer dans le prochain lot d’intégration. Les vecteurs de signature et l’interopérabilité des chunks restent à exécuter avant l’activation. Aucun appareil ni profil de capture physique n’est déclaré qualifié.
