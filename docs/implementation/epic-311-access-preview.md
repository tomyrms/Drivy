# #311 — une page pour valider la direction artistique

À la demande du porteur du 28 octobre 2026, le premier aperçu se limite à « Modifier les accès ». Il permet lecture, édition en trois étapes (rôles cumulables, autorisations par domaine, relecture avec motif), confirmation et simulation d’un refus conservant le brouillon. Apparence claire/sombre/système ; composition desktop et mobile. Les composants shadcn/Base UI utilisent le nouveau thème indépendant.

## Limite explicite

`preview-311.html` est une entrée isolée avec deux personnes et une école fictives. Les écritures sont simulées en mémoire ; recharger réinitialise l’essai. Le réseau métier est intercepté sans délégation à une API réelle et la publication impose `connect-src 'none'`. Aucun compte réel, migration, changement d’autorisation serveur ou remplacement du portail déployé. Le SHA de compilation est affiché en pied de page et dans `preview-build.json`.

Le contrôleur extrait les commandes existantes (version, idempotence, motif, attente de confirmation) sans importer leur ancien rendu. La compilation refuse tout ancien JSX de console ou feuille de présentation historique dans son graphe. Les confirmations observées ici sont celles du jeu de données simulé ; elles ne qualifient pas le backend ni l’intégration authentifiée future.

## Vérifications limitées avant essai

- Typage client exécuté et réussi.
- Essai navigateur réel Chromium/Edge : rôles Administration + Moniteur cumulés, ajout d’une autorisation, motif, confirmation, lecture actualisée, refus conservant le brouillon, changement clair/sombre, largeur mobile 390 sans débordement ; aucune erreur JavaScript.
- Captures desktop 1440 et mobile 390, lecture/édition. La capture Atrium du viewport émulé présentait des tuiles répétées : captures produites avec le navigateur Playwright déjà présent dans l’environnement, sans modifier les tests du produit.
- Compilation Vite réussie, graphe de 2 424 modules sans ancien rendu. Avertissements non bloquants : initialiseur de thème statique volontairement non bundlé, bundle JS de 594 Ko (186 Ko gzip) à fractionner lors de la généralisation. Pas de grande campagne #309/#84, pas d’IPA, aucune issue close sur la base de cet aperçu.

## Publication exécutée

- Aperçu : <https://shulker.ch/drivy-preview/>.
- SHA produit : `1812bd6056a970d94dd661443f2bcbbf3ac0a872` (branche `codex/epic-311-rebuild`). Manifeste public `preview-build.json` et pied de page cohérents.
- Publication statique isolée sur Caddy uniquement, 13 fichiers. Aucun changement de services produit, de base, de migrations ou de données. Origine différente du portail authentifié, pour isoler également le stockage navigateur des commandes.
- Sauvegarde exacte de Caddy avant ajout de route ; validation du candidat, comparaison des autres hôtes, rechargement et service actif réussis. En-têtes CSP/noindex/HSTS/nosniff vérifiés ; HTML servi identique à l’artefact.
- Contre-vérification après publication par le coordinateur : HTTPS 200 et parcours navigateur complet de cet aperçu (rôles cumulés, confirmation, lecture actualisée, refus conservant le motif, thèmes et mobile 390 sans débordement) réussis, aucune erreur JavaScript.
- Reçu et point de retour arrière : `20261028T202042Z-1812bd6056a9`. Le script de publication contient le rollback avec contrôle des empreintes avant restauration. Pas de retrait de l’aperçu effectué : il reste disponible pour l’essai du porteur.

Le porteur a indiqué « c’est déjà bien mieux » avant la publication ; son essai de l’URL reste attendu. La reconstruction complète et le raccord authentifié ne sont pas déclarés validés.

## Essai du porteur

Ouvrir l’aperçu, cocher un rôle, poursuivre jusqu’aux autorisations puis relire. Saisir un motif et confirmer pour voir la fiche en lecture. Le menu Apparence change le thème ; « Simuler un refus » montre la conservation de la saisie. « Réinitialiser » repart des données fictives initiales. La suite de #311 attend le retour visuel du porteur.
