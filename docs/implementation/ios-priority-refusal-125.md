# Refus GPS prioritaire — #125

29 octobre 2026. Le refus normal arrêtait déjà le collecteur local. Le manque confirmé était l'impossibilité de refuser pendant un accord en cours d'envoi ou sa vérification. Ce lot corrige le parcours natif ; aucune activation GPS obligatoire, modification serveur ou promesse de révocation instantanée sur un autre appareil déconnecté.

## Garanties

- L'élève peut exprimer le refus depuis la ligne ou la fiche d'accord, y compris pendant une lecture/envoi. La commande restrictive arrête localement avant toute attente réseau.
- Une intention distincte est conservée par le coffre AES-GCM existant, avec fichier protégé, clé Trousseau, authentification du compte/API, exclusion de sauvegarde et écriture synchronisée. Sa charge contient école, adhésion, époque, élève, portée générale/leçon et version de notice. Aucun repli en clair.
- L'accord déjà émis conserve son UUID et ses octets. Son ACK ne supprime jamais le refus. Quand il est rapproché, la version réelle est relue avant de former la commande de refus ; aucune version attendue n'est devinée.
- Une réponse incertaine garde les deux intentions : vérifier l'opération précédente reste possible, son renvoi comme accord et son abandon sont bloqués tant qu'un refus plus récent attend. L'absence de reçu n'est pas traitée comme un succès. Un changement de notice ou de portée demande un nouveau geste explicite ; les octets d'une commande admise ne sont jamais réécrits.
- Le refus local disparaît seulement après reçu durable du refus correspondant, ou relecture d'un refus SELF actuel avec aucune ancienne commande en attente. Une panne du coffre laisse la collecte bloquée. Le départ et l'ouverture/reprise de segment contrôlent la restriction avant et après leur attente locale.
- Une restriction conservée sous une ancienne époque continue à bloquer localement, mais son envoi sous une nouvelle époque n'est pas implicite. Les restrictions des autres comptes/API/écoles ne se mélangent pas.

Les mutations GPS restent dans SQLCipher ; le coffre de refus contient une intention préalable, pas un faux reçu. Le choix officiel affiché pour les autorisations continue à venir de l'école. Une intention non confirmée n'est pas un accord de démarrer.

Matrice native : lecture de notice, accord général/par leçon, refus SELF et choix verbal du moniteur sont présents ; les contrôles de partage du bilan restent dans leur parcours existant. Aucun service autonome d'export complet ou d'effacement intégral n'est livré par ce lot : aucune demande, progression, suppression distante ou disponibilité d'artefact n'est simulée.

Références relues : R41/R42, modèles AP152/AP153, receipt AP72, règles d'époque R35, contrat de notice et choix existant, tests de consentement du démarrage immédiat. La politique GPS_REQUIRED servie par l'école conserve ses gardes existantes.

## Recette

Compte élève, Profil → Accord GPS : lancer Accepter sur réseau ralenti, puis Refuser le GPS maintenant avant la réponse. Le refus doit rester visible comme en attente et la réponse ancienne ne doit pas le remplacer. Après réponse de l'école, le choix confirmé doit être Refusé. Refaire en interrompant le réseau : fermer/rouvrir doit retrouver l'attente protégée, vérifier la demande précédente avant transmission ; aucun départ GPS ne doit être permis localement. Refaire avec changement d'école et une notice renouvelée : aucun refus ne doit être attribué à l'autre école ni repris silencieusement sous un nouveau texte.

Si une ancienne opération reste inconnue, la restriction locale reste en place jusqu'au rapprochement ; l'application n'invente ni annulation distante ni reçu. Le GPS physique, le refus depuis un second appareil et la perte réelle du réseau restent à qualifier avec le porteur.

## Contrôles

Relecture indépendante : accès au refus pendant relecture/coffre indisponible corrigé ; abandon d'un refus conservé interdit pour éviter de reprendre un UUID déjà classé. `git diff --check` exécuté. Trois tests synthétiques ajoutés : accord retenu puis refus durable, isolation/chiffrement/reprise d'époque, réponse inconnue puis reprise du même UUID. Une sélection CI `consent` exécute seulement SchoolStartNowConsentTests, sans grande suite. Résultats Apple à reporter dans la livraison ; aucun essai physique présumé ici.
