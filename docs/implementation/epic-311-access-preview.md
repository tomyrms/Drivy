# #311 — une page pour valider la direction artistique

À la demande du porteur du 28 octobre 2026, le premier aperçu se limite à « Modifier les accès ». Il permet lecture, édition en trois étapes (rôles cumulables, autorisations par domaine, relecture avec motif), confirmation et simulation d’un refus conservant le brouillon. Apparence claire/sombre/système ; composition desktop et mobile. Les composants shadcn/Base UI utilisent le nouveau thème indépendant.

## Limite explicite

`preview-311.html` est une entrée isolée avec deux personnes et une école fictives. Les écritures sont simulées en mémoire ; recharger réinitialise l’essai. Le réseau métier est intercepté sans délégation à une API réelle et la publication impose `connect-src 'none'`. Aucun compte réel, migration, changement d’autorisation serveur ou remplacement du portail déployé. Le SHA de compilation est affiché en pied de page et dans `preview-build.json`.

Le contrôleur extrait les commandes existantes (version, idempotence, motif, attente de confirmation) sans importer leur ancien rendu. La compilation refuse tout ancien JSX de console ou feuille de présentation historique dans son graphe. Les confirmations observées ici sont celles du jeu de données simulé ; elles ne qualifient pas le backend ni l’intégration authentifiée future.

## Vérifications limitées avant essai

- Typage client exécuté et réussi.
- Essai navigateur réel Chromium/Edge : rôles Administration + Moniteur cumulés, ajout d’une autorisation, motif, confirmation, lecture actualisée, refus conservant le brouillon, changement clair/sombre, largeur mobile 390 sans débordement ; aucune erreur JavaScript.
- Captures desktop 1440 et mobile 390, lecture/édition. La capture Atrium du viewport émulé présentait des tuiles répétées : captures produites avec le navigateur Playwright déjà présent dans l’environnement, sans modifier les tests du produit.
- Compilation et publication : reçu de livraison ajouté après exécution. Pas de grande campagne #309/#84, pas d’IPA, aucune issue close sur la base de cet aperçu.

## Essai du porteur

Ouvrir l’aperçu, cocher un rôle, poursuivre jusqu’aux autorisations puis relire. Saisir un motif et confirmer pour voir la fiche en lecture. Le menu Apparence change le thème ; « Simuler un refus » montre la conservation de la saisie. « Réinitialiser » repart des données fictives initiales. La suite de #311 attend le retour visuel du porteur.
