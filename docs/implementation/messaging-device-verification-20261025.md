# Vérification de ses appareils : persistance de la publication

25 octobre 2026. Candidat en revue, non qualifié sur Apple.

## Décision après revue P1

L'intention de publication cross-signing ne fait plus partie du snapshot `MessagingCryptoVault.State`. Un autre acteur ayant chargé un ancien snapshot peut réécrire `state.sealed` pendant un sync ou une sauvegarde. Un remplacement atomique de ce fichier ne prévient pas la perte d'un champ ajouté entre-temps.

Le coffre utilise donc un journal dédié `device-signing.sealed`, dans le même dossier compte/école/serveur. Son contenu est scellé avec AES-GCM, la clé dérivée du secret Keychain existant et un domaine d'authentification distinct `device-signing|<empreinte du coffre>`. Protection du fichier et exclusion de sauvegarde suivent les primitives du coffre. Aucun secret ni document crypto n'est journalisé dans les logs.

## Coordination

- Un verrou synchrone partagé par les instances du processus coordonne lecture, création et écriture du journal. La création SDK de l'identité privée et l'enregistrement de l'intention sont dans cette section critique, sans attente réseau.
- Une seconde instance relit le journal avant toute création. Elle reprend l'identité enregistrée ou échoue si sa machine ne possède pas le secret privé correspondant. Elle ne bootstrappe pas une identité de remplacement.
- L'acquittement relit le journal et exige la même intention. Il marque `completed` après publication et accusé de signature valides. Il ne supprime pas le journal : une instance au cache périmé ne peut confondre une publication terminée avec une absence de bootstrap.
- Les appels réseau sont hors verrou. Deux reprises concurrentes de la même intention peuvent recevoir un conflit serveur, puis réconcilier par lecture lors d'un nouvel essai. Elles ne peuvent remplacer l'identité existante.
- Les écritures ordinaires `save(State)` de sync/backup ne lisent ni n'écrivent ce fichier. Elles ne peuvent donc effacer l'intention, même à partir d'un snapshot ancien.

Ce verrou couvre les instances du processus app, pas une architecture multiprocessus avec extension partageant le coffre. Aucun tel partage n'est introduit ici. La correction ne prétend pas résoudre les mises à jour perdues préexistantes entre tous les champs de `state.sealed`.

## Reprise et compatibilité

La comparaison distante porte sur les clés publiques et leurs usages, pas sur des signatures pouvant être enrichies. Une réponse perdue est résolue par lecture de l'identité déjà publiée, sans la renvoyer comme nouvelle identité. Aucun reset et aucun changement de l'API ne sont requis.

Le champ `pendingDeviceSigning` du précédent candidat non commité est supprimé de `State`. Ce format candidat n'a pas été livré en production par ce travail. Le format de `state.sealed` déjà livré reste inchangé, et les coffres sans journal peuvent encore utiliser une identité distante existante s'ils possèdent le secret privé requis.

Une coupure ou une panne disque exactement entre création privée SDK et première écriture du journal reste fermée en erreur, jamais corrigée par un reset. Un journal corrompu est également refusé, sans repli en clair.

## Régression à exécuter

`testConcurrentBackupCannotEraseSigningIntentAndReopenResumesSameIdentity` ouvre deux adaptateurs réels SDK sur le même coffre. Le second charge son snapshot avant le bootstrap. La publication du premier est suspendue par une continuation du relais, pendant que le second exécute `enableBackup` et sauvegarde son état. Le test compare le journal avant/après, libère l'upload avec un refus, rouvre le coffre puis exige une reprise avec la même identité publique et une confiance SDK relue.

La barrière ne repose sur aucun délai arbitraire. Un échec avant l'upload libère l'attente et produit une assertion de préparation distincte. La reprise séquentielle existante lit désormais ce journal dédié.

Contrôles locaux : lecture de la revue et du diff, inventaire des références, `git diff --check`. **Aucune compilation ni exécution Apple du candidat à cette étape.** Le P1 est identifié par entrelacement statique, pas présenté comme une reproduction déjà passée sur runner.
