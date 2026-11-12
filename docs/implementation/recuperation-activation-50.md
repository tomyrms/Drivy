# Récupération du compte (#50) : activation, ce qui est prêt et ce qui dépend du porteur

11 novembre 2026. Rien n'est activé, aucun service d'exploitation n'est lu ni modifié, aucun courrier n'est envoyé.
Ce document complète `account-recovery-20261026.md` (contrat), `recuperation-qualification-50-20261104.md`
(recette Keycloak/Mailpit) et `recovery-direct-guard-50-20261105.md` (garde locale du chemin direct).

## Ce que livre ce lot

| Élément | Rôle | Preuve |
|---|---|---|
| `infra/deploy/configure-identity-smtp.py` | Écrit **uniquement** `smtpServer` dans le realm `drivy`, à partir d'un fichier de paramètres hors dépôt (mode 0600). Simulation par défaut (`--apply` pour écrire). Refuse un hôte ou un expéditeur d'exemple, un relais authentifié sans chiffrement hors boucle locale, un champ inconnu et un realm dont `resetPasswordAllowed` n'est pas déjà faux. N'écrit ni `resetPasswordAllowed` ni aucun autre champ. N'affiche jamais le mot de passe ni l'identifiant SMTP. | 16 tests locaux (`infra/deploy/test_configure_identity_smtp.py`), sans réseau, et exécution de la suite `scripts/qualification/run-python-tests.py` |
| `scripts/qualification/run-python-tests.py` | Inclut ces tests dans la campagne finale. | 84 tests locaux au total |

Le choix du fournisseur SMTP n'est pas fait par ce lot : le script accepte n'importe quel relais SMTP
authentifié ou non (STARTTLS, TLS implicite, ou clair sur boucle locale seulement).

## Fichier de paramètres (hors dépôt)

Chemin par défaut `/root/drivy-identity-smtp.json`, propriétaire de l'exécutant, mode 0600, jamais un lien.
Aucun exemple contenant des valeurs réelles ne figure dans le dépôt.

```json
{
  "host": "<nom du relais>",
  "port": 587,
  "security": "starttls",
  "auth": true,
  "from": "<adresse d'expédition sur un domaine contrôlé>",
  "fromDisplayName": "Drivy",
  "replyTo": "<facultatif>",
  "user": "<fourni par le prestataire>",
  "password": "<fourni par le prestataire>"
}
```

`security` vaut `starttls`, `ssl` ou `none` ; `auth` vaut vrai ou faux ; `user` et `password` sont obligatoires si
`auth` est vrai et interdits sinon. Le jeton d'administration de Keycloak, de courte durée, est lu dans un second
fichier 0600 (`--token-file`, défaut `/root/drivy-identity-admin-token`) et supprimé après usage.

## Procédure d'activation (à exécuter par l'opérateur, dans cet ordre)

1. **Sauvegarde** de la base et de la configuration d'identité, conformément au mandat du 28 septembre 2026.
2. Écrire le fichier de paramètres et le jeton (modes 0600). Ne jamais les passer en argument ni les coller dans une conversation.
3. `python3 infra/deploy/configure-identity-smtp.py` : simulation, doit afficher « Paramètres valides ».
4. `python3 infra/deploy/configure-identity-smtp.py --apply` : écrit `smtpServer`. La récupération reste fermée
   (`resetPasswordAllowed` faux, indicateur API/BFF faux, refus 503 de Caddy en place).
5. Supprimer le fichier de jeton. Garder le fichier de paramètres en 0600 sur le conteneur d'identité seulement.
6. **Garde du chemin direct** : installer `apps/web/server/recovery-direct-guard-main.ts` selon l'exemple de
   `recovery-direct-guard-50-20261105.md` (écoute privée, route Caddy exacte, `proxy-trusted-addresses`), puis
   vérifier le cloisonnement : aucune autre route publique n'atteint `reset-credentials`.
7. **Recette sur le vrai relais**, avec une adresse de test appartenant à l'opérateur : message reçu, lien à usage
   unique, expiration, rejeu refusé, réponse identique pour une adresse inconnue, 31e demande refusée en 429 sans
   courrier. Ne jamais réinitialiser un compte réel pour la recette.
8. **Activation** : `resetPasswordAllowed` à vrai dans le realm, puis `ACCOUNT_RECOVERY_ENABLED=true` (API et web)
   avec `PUBLIC_ORIGIN` en HTTPS, puis remplacement du refus 503 de Caddy par la route de la garde. Un échec à
   n'importe quelle étape remet les trois fermetures (indicateur, realm, refus 503).
9. **Parcours appareil** : « Mot de passe oublié » sur iPhone, retour dans l'app, nouveau mot de passe, reprise
   Face ID après expiration du jeton de renouvellement.

## Décision du porteur, seule chose qui bloque

**Choisir le fournisseur du relais SMTP.** Pour la poursuite, il devra fournir à l'opérateur, hors dépôt et hors
conversation :

- le nom d'hôte du relais, le port et le mode de chiffrement (STARTTLS ou TLS) ;
- l'identifiant et le mot de passe (ou clé d'API) d'envoi, créés pour Drivy seul ;
- une adresse d'expédition sur un domaine qu'il contrôle, avec SPF, DKIM et DMARC publiés pour ce relais
  (sans cela les messages de récupération risquent d'être rejetés ou classés indésirables) ;
- éventuellement une adresse de réponse.

Deux points de la décision touchent le fournisseur lui-même : le lieu de traitement des courriers (le principe de
résidence suisse n'est pas établi par ce lot) et l'acceptation qu'un sous-traitant voie les adresses des personnes
qui demandent une récupération. Ils appartiennent à l'inventaire des sous-traitants de #68.

## Non vérifié par ce lot

- Aucun envoi réel : ni le relais, ni la délivrabilité, ni SPF/DKIM/DMARC.
- Le script n'a pas été exécuté contre un Keycloak réel : seul son code est testé, avec un client d'administration simulé.
  Le comportement du `PUT` partiel du realm avec seulement `smtpServer` suit celui déjà employé par les recettes
  (`check-school-account-recovery.ts`), exécutées avec succès sur Keycloak 26.7.4 jetable.
- Face ID et le retour dans l'app sur appareil réel.
- Compteur de la garde : un processus, en mémoire (limite connue, voir le document de la garde).
