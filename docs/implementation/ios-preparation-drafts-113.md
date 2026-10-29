# Préparation et souhait conservés — #113

29 octobre 2026, base `2d9a5f64`. La saisie pendant un envoi était déjà livrée (`24254a37`, PR #189), mais seule la rédaction du bilan terminé disposait d’un brouillon protégé.

## Réalisation native

- Coffre chiffré réutilisant `EncryptedAccountIntentStore`, écriture atomique synchronisée, protection complète et exclusion des sauvegardes. Pas de repli en clair. La suppression normale exige une lecture valide ; seul l’abandon explicite peut retirer un fichier illisible.
- Préparation/objectifs/note privée identifiés par **leçon** ; souhait de l’élève identifié par **formation**. Compte, API, école, adhésion, époque, type et ressource sont liés au chiffrement. Changer d’époque n’ouvre pas le brouillon des anciens droits.
- Le brouillon conserve version et contenu de base, dernier texte et éventuel contenu déjà envoyé. Une réponse de N correspondant au contenu envoyé ne transforme pas N+1 en faux conflit. Une autre modification serveur conserve la saisie et exige résolution ; la conservation locale seule ne valide jamais cette nouvelle base.
- Restauration seulement après relecture autorisée de la préparation/du souhait. Aucun envoi automatique à la réouverture, aucune publication, aucun partage de la note privée. Les mutations restent les commandes et reçus existants.
- Conservation après pause de frappe de 500 ms, au passage en arrière-plan, à la disparition de la fiche et avant fermeture explicite « Conserver le brouillon et quitter ». L’indication de conservation correspond au contenu effectivement écrit. Échec du coffre visible ; fermeture conservant le brouillon refusée si l’écriture échoue. Une fermeture du processus avant la première écriture ne constitue pas une conservation confirmée.
- Une erreur de lecture protège le fichier et ferme la saisie jusqu’à reprise ou abandon. Le bilan garde son propre coffre ; son ACK ne supprime plus un brouillon de préparation/souhait indépendant.

Références relues : R11, séparation des auteurs et portée F06, AP45–AP48, scénario T030 (brouillon invisible), store et scénarios existants des bilans. Aucun changement du contrat ni du dossier de conception.

## Vérification et recette

`git diff --check` exécuté. Tests préparés : fermeture/réouverture sans envoi, conflit persistant après nouvelle fermeture, N confirmé/N+1 conservé, échec de coffre/lecture illisible, chiffrement et isolation compte/époque/type/ressource. Le scénario de première écriture suspendue vérifie fermeture puis réouverture de N+1 sur la version N confirmée.

**NOT_EXECUTED ici** : tests Swift/UI, compilation Apple, VoiceOver physique. Le coordinateur exécute les contrôles Apple ciblés. Recette IPA : moniteur modifie objectifs/note puis conserve et rouvre ; élève modifie son souhait puis ouvre une autre leçon de la même formation ; réseau retardé pendant N, saisir N+1 puis fermer ; modification concurrente et coffre inaccessible ; vérifier absence d’affichage sous un autre compte/école. Aucune mesure physique ou web revendiquée.

Périmètre iOS seulement, sans EPIC #311, service, déploiement ou fusion. Corrige également la date documentaire de #117 au 29 octobre.

## Relecture des courses entre saisie et reçu

La revue indépendante a relevé trois chemins à sécuriser avant qualification Apple : retour à la valeur A pendant l’envoi de N, reçu AP72 du bilan qui doit conserver la préparation indépendante, et reçu AP72 de N qui ne doit pas transformer N+1 en conflit.

- Une saisie revenue à A reste une modification tant qu’une autre valeur N est en vol ou confirmée avant la relecture. Le coffre garde A avec la base envoyée N, y compris si la fiche est rouverte avant l’ACK. Fermer sans modifications ne court-circuite plus cette conservation.
- ACK direct et vérification AP72 reconnaissent désormais le même contenu confirmé, uniquement lorsque compte/époque, ressource et route correspondent à cette préparation ou ce souhait. Une commande d’une autre leçon récupérée dans la file n’est pas sa base envoyée.
- Vérifier le reçu d’un bilan retire seulement son propre brouillon, après conservation de la préparation ou du souhait indépendant. La dernière rédaction du bilan est comparée au corps durable de la commande acquittée : elle ne dépend plus d’une variable du premier envoi, disparue après une réponse perdue. Cette protection de N+1 est un effet de sûreté associé à #113 ; #114 n’est pas comptée comme nouvelle issue.

Six cas supplémentaires préparés, **non exécutés** : fermeture/réouverture avant puis après ACK en revenant à A ; AP72 préparation N/N+1 ; AP72 souhait N/N+1 ; AP72 bilan avec préparation locale ; AP72 bilan avec dernière rédaction locale ; commande d’une autre leçon exclue de la base envoyée. Ils se trouvent dans `SchoolLessonPreparationReactivityTests`, `SchoolLessonWishReactivityTests` et `SchoolLessonTextDraftTests`.

Le test existant du coffre indisponible dans `SchoolReportFlowTests` distingue désormais reçu durable et fermeture : texte et erreur restent visibles tant que le retrait local échoue ; après rétablissement du coffre et relecture, la fermeture ne produit pas un second PUT du bilan. Ce test ajusté n’a pas été exécuté ici non plus.
