# Supprimer son compte Drivy : parcours global

> Référence V3.13 · [Index](../README.md) · F01/F14 · [R103/R104](regles-etats.md#r103). Complément de conception explicite, pas un système exécuté ni une conformité certifiée.

## 1. Objectif et frontières

Une personne doit pouvoir demander la suppression de son identité Drivy et comprendre le traitement de ses données, même sans appartenance scolaire active. « Archiver cet élève », terminer une formation, quitter une école et supprimer un trajet sont des actions distinctes. Le responsable d’une école ne dispose jamais de la commande de suppression globale d’un élève.

Ce parcours complète le manque DM06. Le contrat d’entrée et de suivi est désormais écrit ; l’implémentation, le traitement opérationnel multi-écoles, les délais et les politiques de conservation sont à approuver et tester avant toute publication publique. Les exigences Apple ont été reconsultées : [S106](../06-gouvernance/sources.md#s106). Ne pas déduire une durée légale universelle de ce document.

## 2. Parcours app et web

Depuis Compte → Supprimer mon compte Drivy, expliquer la perte d’accès, les cours et créances à traiter, l’existence éventuelle de dossiers scolaires légalement conservés, les traitements chez les prestataires et le délai annoncé. Proposer l’export sans l’imposer ni le déclencher automatiquement. Sur l’app, signaler les éléments locaux non transférés connus de cet appareil ; le serveur ne peut pas inventorier tous les appareils hors ligne.

La session est réauthentifiée par le fournisseur d’identité : le serveur vérifie fraîcheur/auth_time et le contexte d’authentification, pas un booléen fourni par le client. Borne de fraîcheur proposée : cinq minutes, à approuver et matérialiser dans la configuration d’identité. Une panne d’identité suspend la demande sans afficher de succès ; un parcours d’assistance vérifiant la personne reste documenté, sans numéro de téléphone arbitrairement obligatoire.

AP193 produit un aperçu expirant proposé après quinze minutes. AP194 vérifie sa version, ses conditions et l’identité. Une modification des appartenances depuis l’aperçu demande une relecture explicite. Une dette, un élève archivé ou le fait d’être le dernier administrateur ne rendent pas le dépôt de demande inaccessible. La réponse expose le nombre total d’appartenances et au plus 100 lignes, puis AP200 donne les pages suivantes du même manifeste. La confirmation porte explicitement sur toutes les appartenances, même si la personne ne consulte pas chaque page ; aucune obligation de contacter le support au-delà d’un seuil technique. Le manifeste serveur est complet, lié à l’identité et figé sous une version ; les changements de périmètre imposent un nouvel aperçu.

Après confirmation, afficher « Demande de suppression reçue », le statut et le prochain point de suivi. Conserver un reçu de suivi sécurisé. La révocation des accès ordinaires intervient à PROCESSING et non lors de la simple ouverture de l’écran. L’enregistrement GPS en cours doit d’abord pouvoir être arrêté localement, sans réseau ; le retrait de la demande ne redémarre jamais une capture.

## 3. Contrat public de conception

| Opération | Rôle et résultat |
|---|---|
| AP193 POST /v1/me/account-deletion-previews | Propriétaire authentifié, aperçu global privé ; pas d’action destructive. |
| AP194 POST /v1/me/account-deletion-requests | Confirmation explicite, demande SUBMITTED, reçu limité. Pas de personId arbitraire dans le corps. |
| AP195 GET /v1/me/account-deletion-requests/current | Reprendre la dernière demande sans sélectionner une école ; 404 si aucune. |
| AP196 GET /v1/me/account-deletion-requests/{requestId} | Détail limité au propriétaire ; pas d’accès ADMIN scolaire. |
| AP197 POST .../{requestId}/withdraw | Retirer avant PROCESSING, sous If-Match ; pas de restauration magique après effacement. |
| AP198 GET /v1/account-deletion-status | Suivi très réduit avec reçu, sans session métier ni donnée scolaire. |

Les corps, enveloppes et erreurs sont dans [OpenAPI](../04-technique/openapi.yaml). Idempotency-Key = operationId pour les POST. 202 signifie commande non résolue : reprendre le même POST et sa clé, ou relire current pour la demande ; AP72 est scolaire et n’est pas utilisé ici. Une réponse 201 confirme seulement la création de l’aperçu ou de la demande.

## 4. Machine à états et concurrence

| État | Entrée et sortie | Action autorisée de la personne |
|---|---|---|
| SUBMITTED | Demande et preuve de confirmation durables | Lire, retirer sous version |
| IN_REVIEW | Inventaire minimal, information sur les rétentions et coordination des responsabilités | Lire, retirer tant que PROCESSING n’a pas commencé |
| PROCESSING | Frontière irréversible sous verrou ; accès métier révoqués et tâches durables | Suivi par reçu ; retrait refusé 409 DELETION_IRREVERSIBLE |
| COMPLETED | Tâches attendues réconciliées, compte supprimé et rétentions résiduelles explicitement expliquées | Suivi réduit, aucune reconnexion à l’ancien compte |
| WITHDRAWN | Retrait avant frontière irréversible | Ancien historique de demande limité ; aucun traitement destructif démarré |

Une contrainte garantit au plus une demande SUBMITTED/IN_REVIEW/PROCESSING par personne. Le verrou de personne/demande sérialise doublons, retrait et passage PROCESSING. Les commandes d’école et la révocation globale suivent la [discipline de verrouillage unique](../04-technique/transactions-v2.md#autorisation-et-commit) : accès d’identité, puis coordination scolaire si nécessaire, appartenances et objets métier. Une lecture de session sans verrou ne remplace pas cette frontière. Éviter de tenir une transaction SQL pendant un appel externe : les tâches sont reprises via outbox et clés idempotentes.

Une défaillance de prestataire conserve PROCESSING avec prochain suivi et alerte opérateur ; elle ne produit pas COMPLETED. Un doublon avec une autre clé renvoie la demande active existante, sans second job ; le reçu demeure limité au propriétaire. Les réponses rejouables contenant le reçu sont chiffrées et expirent selon la politique validée.

## 5. Identité, écoles, finances et données retenues

AccountDeletionRequest appartient à l’identité globale. AccountDeletionSchoolTask appartient à une école et ne révèle ni ses dossiers ni ses décisions aux autres écoles. Le responsable global orchestre des tâches avec droits étroits ; il n’obtient pas une lecture générale des traces privées. Une école ne peut pas refuser arbitrairement de recevoir la demande parce que la relation scolaire est terminée.

Les obligations contractuelles et les données soumises à une conservation justifiée ne sont pas supprimées aveuglément. Elles sont inventoriées par catégorie, finalité, autorité responsable, durée/règle et contrôle d’accès ; expliquer à la personne ce qui demeure. Une créance ne rend pas le compte actif à vie. Les anonymisations effectives et les suppressions sont distinguées dans le manifeste.

**Dernier administrateur.** Une procédure de continuité doit être convenue avant le pilote : contact vérifié du représentant de l’école, transfert explicitement accepté ou fermeture coordonnée de l’espace scolaire. Aucun nouveau responsable n’est nommé automatiquement, et le support ne s’attribue pas ADMIN par commodité. Ce cas ne bloque pas l’enregistrement de la demande ; il exige un traitement humain borné avec suivi communiqué, pas une attente indéfinie masquée. La procédure, les pouvoirs légitimes et les délais restent à valider en DM06 avant le lancement. Le compte ne passe pas faussement COMPLETED tant que le traitement convenu n’est pas réconcilié.

La suppression vise Drivy et ses liaisons d’identité, pas le compte personnel Apple/Google externe. Révoquer les sessions/refresh tokens et les autorisations de fournisseur applicables ; vérifier la politique du fournisseur choisi. Une restauration rejoue les tombstones avant réouverture des accès et ne réactive pas le compte par un ancien refresh token. Une inscription ultérieure est une nouvelle relation, pas la résurrection automatique des archives.

## 6. Reçu et sécurité

ReceiptToken : secret opaque à entropie élevée (au moins 256 bits proposés), généré serveur et lié exclusivement au suivi d’une demande. Vérification par hash et comparaison sûre ; le secret peut être conservé chiffré pour rejeu idempotent borné, jamais en clair dans les logs. Le client natif le garde dans Keychain. Le web ne le persiste pas dans localStorage ; session de suivi HTTP-only gérée par BFF et anti-CSRF si une écriture y est ultérieurement ajoutée.

AP198 n’accepte que le reçu dans Authorization, ne renvoie que statut, code de message, dernière mise à jour et prochain suivi. Un token OIDC normal n’y fonctionne pas ; le reçu n’ouvre aucun /v1/me ni route scolaire. No-store, rate-limit et aucune donnée personnelle dans URL, analytics, notification ou email de suivi. La fin de validité est annoncée au dépôt ; durée proposée de 90 jours, révisable selon délais réels. Après expiration/perte, une récupération assistée vérifie l’identité sans exposer la demande à un tiers. Une suppression plus longue ne doit pas devenir impossible à suivre : communiquer une prolongation sécurisée ou une voie vérifiée avant expiration.

## 7. Accès hors ligne, rétentions et effacement local

Les baux locaux, choix GPS et bornes décrits dans la synchronisation restent applicables ; un appareil hors ligne n’est pas effacé instantanément à distance. À reconnexion ou connaissance de révocation, arrêter toute collecte, invalider le scope, refuser les envois interdits et purger les caches concernés. Ne pas contourner une révocation avec le reçu de suivi. La demande explique la perte possible de fichiers jamais transférés. Le nettoyage de l’app n’efface pas des pièces conservées sous obligation scolaire sans la décision correspondante.

## 8. Critères de sortie

Les cas J29/E49 et T298–T310 doivent être exercés avec fournisseur d’identité, BFF, app Swift, worker et une seconde session. Tester notamment aucune école, école archivée, deux écoles, dernier ADMIN, dette, double clic, retrait concurrent, perte du reçu, prestataire indisponible et restauration. DM06 est désormais **spécifié côté contrat**, mais demeure **non validé opérationnellement**. Pas de publication store tant que parcours réel, délais, responsabilités, conservation et continuité d’école ne sont pas démontrés.

## Continuité d’école avant la frontière irréversible

[R104](regles-etats.md#r104) impose une vérification avant PROCESSING, pas seulement avant COMPLETED. Tant qu’une école ACTIVE dépend encore de l’unique ADMIN sortant, la demande reste IN_REVIEW, avec prochain suivi et procédure interne bornée. Une relève acceptée et vérifiée, ou une fermeture d’espace coordonnée par l’autorité compétente, doit résoudre la situation. Aucun accès de support n’est promu automatiquement. La personne n’a pas à annuler sa demande ni à téléphoner pour déclencher le traitement. La procédure détaillée et son délai restent bloquants avant lancement public, sans les inventer comme obligation légale.

Le traitement humain en interne n’est pas une obligation de passer par le support pour demander la suppression. Apple distingue ces cas : un traitement non instantané peut être organisé et annoncé, tandis qu’un parcours imposant appel/email n’est pas admis par défaut pour les apps ordinaires [S110](../06-gouvernance/sources.md#s110). Aucun statut d’industrie hautement réglementée n’est présumé pour Drivy.

AP200 GET /v1/me/account-deletion-previews/{previewId}/memberships utilise un curseur privé lié au manifeste ; il ne prend aucun schoolId choisi par un ADMIN. Expiration de l’aperçu : 410 et nouvelle revue, pas mélange de pages. AP194 valide le hash complet des appartenances, pas seulement les éléments reçus par le client. Les données de suivi AP198 restent minimisées et ne contiennent pas cette liste.
