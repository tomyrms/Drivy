# Raccord UI école #106 — 5 novembre 2026

Base : 88f07c5e78b973719d342fa5ccbf23344a0137a2. Lot de présentation initial, aucun retour correctif du coordinateur ; budget logique précédent 2/2 inchangé.

SchoolSettingsPilot transmet désormais les coordonnées de SubmitResult.body validées par schoolSchema à useDraft.markSaved. La version confirmée sert au prochain If-Match ; une saisie postérieure reste visible et ne reçoit pas de message de sauvegarde. Les conflits affichent les champs concernés dans Alert et restent visibles au refresh, jusqu’à reprise explicite des coordonnées confirmées ou nouvel enregistrement. Le focus reste dans le champ pendant la réponse et revient au nom après résolution clavier.

Un reçu confirme l’opération, pas les coordonnées : l’écran suit les confirmations de son operationId puis relit la ressource validée. Corps absent/incomplet, mauvaise portée ou version non avancée : aucune valeur fabriquée ; relecture en échec = saisie conservée et nouvel envoi désactivé jusqu’à relecture explicite réussie. Aucun renvoi automatique. Un changement de personne/école/membership/epoch remonte l’éditeur et invalide ses callbacks tardifs.

## Preuves exécutées

Node portable : C:/Users/jtoma/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe, v24.22.1. Dépendances existantes, aucune installation.

- RÉUSSI, code 0 : `node apps/web/node_modules/tsx/dist/cli.mjs scripts/dev/check-reconciliation-ui-106.ts` ; `browser-final.log`, `browser-final.exit`, `results.json`. Vrai SchoolSettingsPilot, useDraft, runner et commandStore ; fetch synthétique seulement. Réponse différée, normalisation autre champ, conflit même champ, refresh, résolution clavier puis édition, précondition version 2/CSRF, epoch modifié pendant envoi ; reçu réel du store avec body=null, GET 503 puis reprise sans nouvel envoi.
- RÉUSSI, code 0 : depuis apps/web, `node node_modules/vitest/vitest.mjs run test/draft-rebase.test.ts test/command-core.test.ts test/command-store.test.ts` : deux fichiers existants, 29 tests. Le troisième chemin ne correspond à aucun fichier ; aucun test de store supplémentaire revendiqué. Journaux `tests.log`, `tests.exit`.
- RÉUSSI, code 0 : `tsc --noEmit` et `tsc -p tsconfig.check.json` ; `typecheck.log`, `typecheck.exit`.
- RÉUSSI, code 0 : `tsc -p tsconfig.server.json` puis `vite build` ; `build.log`, `build.exit`.
- RÉUSSI : captures `desktop.png` (1000×900), `narrow.png` (390×844) et `receipt.png` inspectées ; texte et contrôles lisibles, focus visible, absence de débordement horizontal vérifiée à 390 px. Détecteur Impeccable : `detector.json`, tableau vide. `git diff --check`, code 0.

## Diagnostics du harnais conservés

`browser-1` ÉCHEC : Response.url absent dans la nouvelle fixture, rejeté par schoolFetch ; URL exacte ajoutée comme dans le harnais existant. `browser-2` ÉCHEC : attente erronée d’un If-Match sans guillemets ; commandHeaders impose un ETag fort `"2"`, assertion corrigée sur ce contrat, sans assouplissement. `browser-3` ÉCHEC : vérification de focus avant le requestAnimationFrame de restitution ; attente conditionnelle ajoutée, assertion identique. Chaque défaut distinct a été corrigé une fois ; aucune boucle sur un même échec et aucun changement des tests existants. `browser-4` passe avec avertissement React de fixture (scopeToAccess appelé pendant render) ; déplacement de cette mutation dans l’action de fixture, puis passage final sans avertissement.

## Méthode et limites

Impeccable, Uncodixfy, orchestration, verification-before-completion et systematic-debugging réellement lus ; contexte Impeccable et DESIGN.md lus. Codebase Memory trouve la racine exacte sous drivy-reprise-native-106-20261104, mais index non surveillé du matin : vérification par rg/sources, aucune réindexation. Références : COMMENCER_ICI, synchronisation, R11/R12, scénario T024, registre106 et rapport logique précédent.

Contexte/useDraft, draft-model, queue, store, backend et dépendances inchangés. Seul TSX école produit modifié ; aucune nouvelle suite globale. NON EXÉCUTÉ : backend réel/PostgreSQL, CI, Safari, VoiceOver physique, push, déploiement. Les preuves Chromium sont synthétiques et ne qualifient ni le backend ni les appareils Apple. Documentation limitée au registre106 selon le mandat explicite ; STATUS partagé non modifié.
