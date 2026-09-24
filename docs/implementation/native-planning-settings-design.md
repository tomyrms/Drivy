# Réglages du planning

## Périmètre

Présentation de `SchoolPlanningSetupView` et état de lecture ciblé dans `SchoolPlanningWorkspace`, autorisé par l’intégration après constat qu’une vue seule ne pouvait distinguer liste vide et requête en cours. Références : E12, R09, R11 ; commandes et gardes du workspace relues. Aucun endpoint ni corps de mutation ne change.

## Disponibilités et fermetures

Ces sections précèdent les conditions et prestations. L’état explicite comprend `isLoadingAvailability`, `availabilityLoaded` et `availabilityError`. Une réussite exige les deux lectures terminées pour le moniteur courant, sous les générations courantes et sans annulation/révocation. Changement de moniteur, invalidation et actualisation générale réinitialisent cet état. Une ancienne réponse ne termine pas la lecture suivante.

Les erreurs de transport de cette lecture restent dans la section ; les refus d’accès suivent toujours la purge commune. Les listes ne sont annoncées vides qu’après réussite. Les commandes d’ajout attendent cette lecture, les lignes existantes et leurs versions restent la source des modifications. La fermeture de l’éditeur relit les disponibilités, y compris après vérification d’une demande incertaine.

## Formulaires

Les conditions et les prestations ont leurs propres sections de liste. Dans l’éditeur, les noms, références, montants et horaires conservent leurs libellés. Les dates et heures de fermeture se règlent séparément pour éviter une ligne trop large. Les validations existantes restent inchangées et le premier problème explique l’indisponibilité du bouton.

La commande principale reste en bas du formulaire. Les retraits conservent une présentation destructrice et leur motif. Approbation, activation et confirmation sont toujours manuelles ; modifier une valeur après relecture réinitialise la confirmation finale. Les champs sont gelés pendant l’envoi. La reprise incertaine reste celle du workspace et une demande vérifiée n’est pas remplacée par une nouvelle commande.

## Preuve

Diff et gardes de génération relus, `git diff --check` effectué. Compilation Apple groupée encore à confirmer pour ce lot. Aucun test de concurrence exécuté ni rendu de ce formulaire n’est revendiqué ; les états de lecture doivent être exercés avec retour tardif, changement de moniteur et erreur réseau lors de la recette correspondante.
