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
