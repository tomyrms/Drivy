# Équipe et accès natifs

L’écran École → Équipe et accès consulte AP07 et modifie rôles/autorisations via AP08. Le motif, la version et l’UUID de commande sont conservés dans la file chiffrée avant émission ; un résultat incertain est rapproché avec AP72. Le dernier administrateur ne peut pas être retiré. Une modification de ses propres droits provoque une relecture du périmètre.

La confirmation passe par une nouvelle authentification OIDC avec `prompt=login` et `max_age=0`. Le nouveau jeton doit identifier la même Person via `/me` avant de remplacer la session persistée. Le serveur reste responsable du contrôle de la claim signée `auth_time` ; le client ne remplace jamais cette preuve par `iat` ou un rafraîchissement.

Contrôle ciblé exécuté le 24 septembre 2026 sur l’hébergement : connexion éphémère du compte fictif moniteur avec le client `drivy-apple`, `/me` accepté, `auth_time` présente dans le jeton d’accès et âgée de moins de cinq minutes. Session fermée ensuite. Aucun jeton ni identifiant secret n’est enregistré dans cette note ; le compte `luc` n’a pas été utilisé. Cela vérifie la disponibilité de la preuve d’authentification, pas l’ensemble des parcours AP08 sur appareil.

Ajouter un élève permet d’attribuer LEARNER à un membre existant, puis d’ouvrir son dossier réel et sa formation. Une nouvelle personne passe par l’invitation canonique et sa vérification d’adresse ; le transport SMTP externe reste à configurer, aucun succès d’envoi n’est fabriqué.
