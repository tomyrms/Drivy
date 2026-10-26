# Entrée native de récupération de compte (#50)

26 octobre 2026. Le porteur demande de préparer l'intégration et de choisir le relais e-mail plus tard.
La configuration effective du fournisseur déployé n'a pas été inspectée ni modifiée dans ce lot.
Références : `COMMENCER_ICI.md`, sécurité/vie privée (identité OIDC), décision
`connexion-native-20261015.md` et critères de l'issue #50.

La connexion ordinaire reste dans le formulaire natif. « Mot de passe oublié » ouvre une feuille qui lit
`GET /v1/account-recovery/options`, sans adresse, mot de passe ni jeton. Ce contrat annonce seulement si
le parcours de récupération est configuré. Par défaut, il répond indisponible et sans URL.
La feuille explique alors que la récupération par e-mail n'est pas encore disponible, avec une reprise.

Quand le parcours est configuré, « Continuer dans le navigateur » ouvre le point d'entrée contrôlé
`/app/recover`, sous la même origine HTTPS que l'API. Les destinations étrangères, autres ports,
identifiants d'URL, paramètres, fragments et autres chemins sont refusés par le client natif.
Le fournisseur existant prend en charge le lien e-mail et le changement de mot de passe. Ce passage
par navigateur est limité à la récupération ; il ne remplace pas la connexion native.

Le champ mot de passe est vidé à l'entrée du parcours. Revenir dans l'app n'annonce aucun envoi ni
aucune récupération réussie et ne crée pas de session. La personne revient à la connexion et utilise
son nouveau mot de passe. Aucune identité, adhésion, clé de messagerie, préférence Face ID ou donnée
du Trousseau n'est effacée par cette entrée. Face ID reste le verrou local ; il ne réinitialise pas le mot
de passe du compte. La politique de révocation des sessions appartient au flux du fournisseur et à sa
recette intégrée, pas à une déduction depuis l'ouverture du navigateur.

## Vérification préparée

- `SchoolAccountRecoveryTests` : disponibilité, absence d'identité dans la requête, destination contrôlée,
  réponses incohérentes/redirigées, réseau, limitation et annulation.
- `SchoolAccountRecoveryUITests` : entrée depuis la connexion, état sans service, retour à la connexion,
  entrée configurée sans faux message d'envoi. Les transports sont synthétiques et n'envoient aucun mail.
- `SchoolFormProtectionUITests` complète #143 pour le profil : absence de dialogue sans modification,
  confirmation après saisie et conservation après « Continuer ». Les protections du profil contre
  glissement et fermeture pendant un envoi existaient déjà ; le bouton de maintien est désormais explicite.

Tests Apple à exécuter. Aucun résultat physique, SMTP réel ou récupération d'un compte réel revendiqué.
La recette du fournisseur isolé et la préparation d'activation sont documentées avec le lot serveur/web.

## Exécution UI Apple

Au commit `bd5cbdc`, les deux parcours de récupération passent sur iPhone et sur iPad dans le
[run 40332822066](https://github.com/tomyrms/Drivy/actions/runs/40332822066). Les captures iPhone des deux états
ont été inspectées : titre et actions visibles, aucun message promettant un e-mail envoyé.
Ce run global reste **en échec**, avec deux autres tests cours et le test profil en échec par appareil.
La vidéo du profil montre que le tap XCTest ciblait le conteneur du bouton « Continuer » et laissait
l'alerte ouverte ; le helper de bouton terminal et une assertion de fermeture remplacent ce ciblage.
Les corrections attendent une nouvelle exécution ; les tests unitaires du client de récupération
seront également inclus dans la campagne complète.
