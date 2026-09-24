# ADR 0002 — entrée scolaire dans le client Apple

Date : 24 septembre 2026. État : implémentation et qualification en cours.

## Parcours et périmètre

Après le premier IPA, le porteur demande de poursuivre vers l'application complète. Cette tranche rend utilisables les lectures G1A depuis le client : connexion système, écoles autorisées et rôles, recherche d'un élève, dossier et formations. Elle reprend E01, E02, E06 et E07. Le compte reste accessible sans appartenance scolaire. Le laboratoire personnel reste explicitement accessible et conserve sa base existante ; ses séances ne deviennent pas des leçons scolaires.

Le serveur reste la source des appartenances et des autorisations. Les six lectures sont celles du contrat OpenAPI 3.11.0, sans endpoint parallèle ni nouveau schéma scolaire. Aucun compteur, dossier de démonstration ou agenda fictif n'est ajouté au client livré.

## Persistance et échecs

La tranche n'ajoute aucune table métier. Les données de lecture restent en mémoire, sans cache HTTP persistant. L'état d'authentification est conservé dans un espace Keychain distinct de la clé SQLCipher du laboratoire. L'authentification passe par AppAuth et le navigateur système, avec code d'autorisation et PKCE ; aucun secret de client natif n'est embarqué.

La déconnexion et le changement d'école invalident immédiatement les projections concernées. Les réponses déjà parties sont écartées selon la génération du contexte, y compris après une recherche remplacée ou une ouverture de dossier différente. Les erreurs de droits imposent la disparition des données devenues inaccessibles. Sans réseau, aucune nouvelle lecture scolaire n'est présentée comme vérifiée ni disponible depuis un cache autorisé hors ligne : cette tranche ne délivre pas de lease de consultation.

Le transport refuse les redirections avec Bearer, les destinations configurées non conformes, les enveloppes incompatibles et les identifiants scolaires ne correspondant pas à la requête. Les pages et réponses sont bornées, les curseurs restent opaques et les dates civiles restent distinctes des instants.

## Environnements et preuves

Le porteur a choisi de réutiliser l'hébergement de l'ancien Drivy et fourni l'accès Homelab. L'API et Keycloak sont désormais déployés sur des chemins HTTPS distincts, avec des bases neuves et des comptes de service dédiés. Les URL de l'API et du fournisseur, le client public et le callback sont des paramètres du build ; aucun accès de l'ancien historique n'est copié dans cette refonte. Un build sans ces paramètres indique explicitement que la connexion scolaire n'est pas configurée.

Un fournisseur réel local permet de qualifier l'échange OAuth/PKCE et les droits de l'API sur des identités synthétiques explicites. Cet environnement loopback n'est pas joignable depuis l'iPhone. Les réponses des six lectures exécutées sur PostgreSQL sont partagées avec les tests Swift et validées contre le contrat canonique à chaque test serveur. Les preuves natives doivent couvrir décodage, erreurs, contexte obsolète, pagination, déconnexion et présentation iPhone/iPad. Voir [l'état courant](STATUS.md) pour les résultats réellement exécutés.

La tranche suivante [G1B](g1b-school-setup.md) ajoute la configuration et l'activation de l'école, avec confirmations distinctes et commandes persistées sous chiffrement avant émission. Invitations, acceptation, préparation et planification, puis leçon sans GPS et bilan publié restent à réaliser. La qualification physique des capteurs continue séparément ; elle ne réduit pas le périmètre fonctionnel demandé.
