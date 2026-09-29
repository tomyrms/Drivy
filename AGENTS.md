# Drivy — réalisation de la refonte

## Référence et mandat

Lire `Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md`, puis la règle, le contrat et les scénarios du parcours travaillé. Le dossier de conception est une livraison conservée avec son manifeste : écrire les décisions d'implémentation dans `docs/implementation/`.

Le porteur a autorisé la réalisation le 24 septembre 2026 : base vide, aucun import de l'ancien projet ; compilation Apple sur GitHub Actions, IPA non signé puis signature et installation par lui avec iLoader. À sa demande, l'ancien dépôt est renommé `tomyrms/Drivy-old` et reste privé ; `tomyrms/Drivy` est un nouveau dépôt public avec un historique neuf. Ne jamais y transférer les anciennes branches ou leurs exports de sessions. Après l'initialisation, développer sur une branche de travail ; aucun déploiement du service public n'est implicite. Le 28 septembre 2026, le porteur a autorisé les déploiements sur le homelab pour la phase 2, chacun précédé d'une sauvegarde de la base.

## Construction

- Swift natif iPhone/iPad, web distinct, TypeScript/Fastify et PostgreSQL. Android ultérieurement.
- Construire des parcours verticaux. Les 101 concepts documentés ne sont pas un plan de 101 tables.
- UI et communication françaises ; identifiants anglais. Accessibilité, erreurs et persistance font partie du parcours.
- Droits scolaires relus au serveur, OIDC pour l'identité, aucune autorisation provenant seulement de l'interface.
- Pas de position inventée, pas de succès avant écriture durable, pas de repli de stockage chiffré vers du clair.
- Partage automatique avec l'élève (décision du 28 septembre 2026) : trajet, observations, bilan et objectifs d'une leçon réalisée lui sont visibles sans publication ; ce que le moniteur garde privé ne lui est jamais montré. Voir `docs/implementation/decisions-2026-09-28.md`.
- App = terrain (moniteur, élève), web = bureau (administration de l'école). Un trajet se lance toujours avec un élève ; le laboratoire G0 local est retiré de l'app.
- Peu de texte à l'écran : pas de sous-titre explicatif ni de note sous les sections, un badge seulement pour l'inhabituel, une explication seulement en cas d'erreur.
- Tests métier avec vraie PostgreSQL ; tests Swift et UI sur runner Apple. Un contrôle documentaire ne qualifie pas le produit.
- Ne jamais enregistrer secrets, jetons, données de personnes ou positions dans les logs/artefacts de CI.

## Vérification et suivi

Mettre à jour `docs/implementation/STATUS.md` avec ce qui est exécuté et ce qui reste à qualifier. Aucun résultat physique GPS/batterie/VoiceOver ne peut être inventé depuis le simulateur. Dépendances verrouillées, contrat OpenAPI canonique 3.11.0.
