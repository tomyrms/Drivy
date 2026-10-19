# Audit intelligent du 18 octobre 2026 : plan de correction

**But :** corriger uniquement des défauts démontrés, sans refonte ni déploiement.
**Architecture :** contrôles locaux aux propriétaires existants : vérificateur OIDC et fiche équipe React. Les agents restent en lecture seule du produit. Le coordinateur implémente et intègre.
**Technologies :** TypeScript/Fastify, React, Vitest, Edge/Playwright existant. iOS Swift audité statiquement.
**Mandat :** mission utilisateur du 18 octobre 2026, AGENTS.md et DESIGN.md du dépôt.

## Contraintes

- Base `5482dd8`, branche `audit/intelligent-20261018`, worktree `C:/Users/jtoma/dv-audit-20261018`.
- Préserver le checkout principal et ses changements personnels.
- Aucun push, fusion, déploiement, donnée de production, nouvelle dépendance ou changement d’API.
- Aucun trim ou plafond arbitraire du sujet OIDC : conserver les identifiants textuels opaques valides.
- Les permissions et versions serveur restent autoritaires. Ne jamais écraser implicitement une version concurrente.
- Aucun succès revendiqué pour PostgreSQL, Swift ou VoiceOver non exécutés.

## 1. Sujet OIDC, P2 confirmé

Fichiers : `apps/api/src/auth.ts`, `apps/api/test/auth.test.ts`.
- [x] Ajouter des JWT réellement signés avec sujet nombre, booléen, objet, tableaux, null et chaîne vide.
- [x] Observer cinq acceptations incorrectes sur les sept cas invalides.
- [x] Exiger un sujet chaîne non vide avant construction d’Identity, sans modifier la valeur opaque.
- [x] Exécuter auth, suite unitaire API, typecheck et build. Conserver le comportement 503 de panne du fournisseur.
- [x] Revoir et committer séparément.

## 2. Brouillon des accès équipe, P1 reproduit et corrigé

Fichiers : `apps/web/client/console/people.tsx`, `scripts/dev/check-audit-regressions.mjs`.
- [x] Reproduire : première émission indisponible, AP72 sans trace, modification concurrente, renvoi 412, relecture version suivante.
- [x] Si le défaut est reproduit, conserver rôles, autorisations et motif lors d’une relecture concurrente.
- [x] Afficher le conflit avec Notice existante et empêcher une nouvelle écriture avant résolution explicite. Annuler reprend les nouvelles valeurs serveur.
- [x] Une confirmation de notre propre écriture doit toujours réinitialiser le formulaire. Un changement de membre ne doit pas hériter du brouillon précédent.
- [x] Tester refus/reprise, succès direct et renvoi confirmé, annulation, autre membre, abandon puis même membre, permissions et nouvelle version. Suite web, types et build réussis. Contre-revue Astra finale sans blocage identifié.
- [x] Revoir et committer séparément.

## Écartements initiaux

- Invitations surlignées deux fois : faux positif, seul le workspace courant rend ses sous-liens (`Console.tsx:315`).
- Révision de bilan obsolète : faux positif, le client Swift trie les séquences décroissantes (`SchoolLessonReportClient.swift:61`).
- Rechargement annuaire : la fraîcheur après des modifications externes est utile. Pas de TTL ajouté sans mesure.
- Regroupement agenda toutes les 30 secondes : déjà mémoïsé. Un coût DOM éventuel exige une mesure avant optimisation.
- Deep-links métier iOS : pas de contrat ni d’émetteur concret établi, pas de nouvelle fonctionnalité dans cet audit.
- Bilan obligatoire à la clôture : changement de règle produit, non retenu.
- Remaniement workspaces/configurations : CI API et web déjà explicites. Pas de refonte du packaging.

## Validation globale

Référence : API 127 tests unitaires, web 233 tests, typechecks et builds réussis sous Node 26.8.1 (Node 24 requis par le dépôt). Suite API complète tentée, PostgreSQL isolée absente et Docker indisponible. Recette UI uniquement loopback, BFF synthétique, vrais composants React. Rapport final dans `docs/implementation/audit-intelligent-20261018.md`, suivi dans STATUS.md.
