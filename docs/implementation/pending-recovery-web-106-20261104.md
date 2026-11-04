# U2b1 — suivi web des demandes, #106

Livraison locale du 4 novembre 2026, branche `tomyrms/issues-suivi-web-106`, racine `C:/Users/jtoma/orca/workspaces/Drivy/issues-suivi-web-106`. Base L1a vérifiée : `67c37282ebccbbed3ec29dce0d93dc348985f121`. Code et tests : **`b0fabea0e653f9e845ff5942273a730faed5a871`** ; ce rapport est dans le commit documentaire suivant. Aucun merge, cherry-pick, push, PR, CI distante, déploiement ou clôture d’issue.

## Résultat et périmètre

`PortalPendingRequests` consomme désormais `snapshot.metadata`. Les trois erreurs ont un avertissement français près du suivi : lecture précédente impossible, enregistrement/mise à jour impossible, effacement impossible avec réapparition possible. L’avertissement existe aussi sans entrée et ne disparaît qu’au remplacement de l’état par `saved`. `saved/read`, `saved/write` et `saved/clear` restent silencieux ; aucune promesse de conservation du corps ou de résultat serveur.

Le résultat `pending` de `act` déclenche un retour local lié à l’entrée concernée. Le motif d’échéance utilise toujours le helper partagé ; un texte déjà porté par l’entrée n’est pas répété. Le retour local cesse d’être pertinent lorsque le magasin remplace l’entrée. Le changement d’école remonte le panneau interne pour retirer ses messages et sa confirmation d’arrêt précédents. Aucun moteur, droit, stockage ou transport modifié.

Le message de conservation possède une région polie persistante. Les alertes de demandes utilisent une seule région polie chacune, sans région parente concurrente ; le DOM vivant reste stable lors des rendus identiques. Aucun effet de focus ajouté. Les actions s’empilent en largeur compacte ; la grille et les mots peuvent se réduire et passer à la ligne à 320 px avec zoom CSS 200 %. Alert, Button, Dialog, tokens, Manrope et palette Drivy sont conservés. Le texte d’arrêt du suivi, qui distingue explicitement arrêt local et annulation serveur, est inchangé.

Fichiers : `apps/web/client/portal/runtime/pending-requests.tsx`, `apps/web/test/pending-recovery-106.test.tsx`, `scripts/dev/check-pending-recovery-106.ts`, ce rapport. Fixtures et captures ignorées sous `artifacts/pending-recovery-106/`. Aucun fichier R4, média, logique métier, backend, iOS, dépendance, lock, STATUS ou conception modifié.

## Runtime, références et méthode

Agent **Codex**, modèle **gpt-6-astra**, effort **high**. Vérifié par `orca orchestration worker-show --dispatch ctx_48e1a55ccbff --json --full`, chemin JSON `result.worker.startOptions.launch.effective`. Il s’agit des options effectives exposées par Orca, pas d’une attestation indépendante du serveur de modèle. Task `task_ff2c18b3ee64`, session `e70ccd2d-7e97-4880-9a63-9b8778ea8719`. Aucun changement de fournisseur/modèle, aucun sous-agent. Le coordinateur a précisé le chemin JSON après une question de préflight ; aucun retour correctif de revue consommé.

Lus : AGENTS, COMMENCER_ICI, DESIGN.md racine (section Web #311 et portée native distincte), R11/R12/R100, synchronisation/reprise AP72, T020 réponse perdue, rapport L1a `command-recovery-web-106-20261104.md`, rapport R2 du worktree `issues-reactivite-106`, sections L1/U2b. Sources réelles lues : panneau, command-store, command-recovery, console/context, school-api, command-core/receiptMatches, Alert, Button, CSS et configuration Vite. Références de harnais : `infra/dev/browser.ts`, `check-portal-311.mjs`, `issues-reactivite-106/scripts/dev/check-entry-continuity-120.ts` en lecture seule.

Skills chargés depuis `C:/Users/jtoma/.codex/skills/` :

- `systematic-debugging/SKILL.md` : cause source vérifiée (métadonnées non consommées, pending ignoré), reproduction avant correction ; investigation des échecs de fixture par lecture du contrat réseau.
- `test-driven-development/SKILL.md` et `writing-good-tests.md` : deux régressions navigateur sur le vrai composant et le vrai magasin, RED observé avant code produit, puis GREEN.
- `verification-before-completion/SKILL.md` : sorties récentes contrôlées avant commit.
- `requesting-code-review/SKILL.md` et `code-reviewer.md` : revue personnelle du diff selon alignement, sécurité, séparation UI/logique, tests et limites ; pas de délégation conformément au mandat explicite.
- `impeccable/SKILL.md`, références `harden.md`, `clarify.md`, `craft-floor.md` (avant édition). `.installation-source.json` : `pbakaus/impeccable`, ref `2c95b1968ca74c5d2c4c0503dcee72f6d0d555ea`. SHA256 du skill vérifié : `fab04b31f946573b00a8559db1fc070f8ea5825254d491c2b13156e5661a86d7`.
- `uncodixfy/SKILL.md` et `.installation-source.json` : `cyxzdev/Uncodixfy`, ref `e0e028058b5259debdd94b78147c6d6c77bf7da2`, SHA256 vérifié `efb88d150e40d34c5b997a25eb4b88655e8daa1628848568a7f50668f1bf1d10`.

Launcher Windows `C:/Users/jtoma/.codex/skills/impeccable/scripts/impeccable.cmd` exécuté **depuis ce worktree** : `context --target apps/web/client/portal/runtime/pending-requests.tsx` une fois, exit 0. Le moteur fonctionne ; aucun téléchargement/install supplémentaire nécessaire. Absence de PRODUCT et de hook signalée : refinement borné autorisé, donc aucun init, hook, nouveau document produit ou redesign. Application concrète : erreurs proches de leur cause, alternative vérifiable, pas de badge de succès, pas de texte décoratif, pas de blocage global, contrôle des formats et clavier. Les recommandations de palette, police, motion, service worker, nouveau flux d’interview et sous-agents ne s’appliquent pas à ce correctif contraint ; le système Drivy et le mandat priment. `ui-skills-root/SKILL.md` lu ; CLI `ui-skills` absent, aucune installation tentée. Les deux skills UI imposés sont effectivement chargés et appliqués.

## Codebase Memory

Index créé par chemin absolu dans **ce** worktree ; nom retourné par le moteur : `C-Users-jtoma-orca-workspaces-Drivy-issues-suivi-web-106` (unique à cette racine). Index full du `2026-11-04T15:37:51Z` : 51 951 nœuds, 196 491 arêtes. Aucun index d’un autre checkout réutilisé.

`check_index_coverage` : panneau, command-store et console/context `no_recorded_issue`, `metadata_match`, génération concordante. `search_graph` : PortalPendingRequests, useCommandSnapshot, resend, ConsoleContext ; `trace_path` sortant puis source réel : helpers de reprise, pendingActions, store.resend/verify/release, composants UI, contexte et reloadSchool. `detect_changes` exécuté en fin de travail : son défaut compare origin/master, donc inclut également L1a ; le diff Git de notre base isole les trois fichiers de code/tests. Impact de présentation : PortalConsole et aperçu existant ; aucun appel de transport nouveau.

Limites : 963 fichiers exclus, 85 parses partiels, 4 inutilisables (dont OpenAPI), faux liens interlangages dans le traçage de noms génériques. Le graphe n’est ni une preuve exhaustive ni une qualification produit ; les sources ont été relues. Une première requête trace_path a été refusée (`function_name is required`), puis corrigée ; aucun résultat n’a été simulé.

## Tests et preuves récentes

Node portable **v24.22.2**, PATH du processus uniquement. `npm ci --ignore-scripts` racine, `--prefix apps/web`, `--prefix infra/dev` : exit 0, respectivement 111/153/1 paquets, locks inchangés. npm rapporte 3 vulnérabilités modérées dans les dépendances web verrouillées ; aucune mise à jour hors mandat.

| Commande | Résultat |
|---|---|
| `npm test --prefix apps/web -- test/pending-recovery-106.test.tsx` avant code produit | RED : 2 échecs attendus, exit 1 — avertissement de lecture absent, motif d’échéance absent après retour pending |
| Même test pendant construction du harnais | Débordement zoom détecté puis corrigé ; reçu synthétique initial incomplet et Response.url absent, corrigés au niveau du double réseau après lecture du contrat, aucune assertion affaiblie |
| `npm test --prefix apps/web -- test/pending-recovery-106.test.tsx test/command-core.test.ts test/command-store-code.test.ts test/command-latency-106.test.ts test/command-conflicts.test.ts test/agenda-intentions.test.ts test/command-recovery-106.test.ts` | **7 fichiers, 118 tests passent, exit 0**, dernière exécution 16:58:57 locale : 116 L1a inchangés + 2 scénarios UI composites |
| `npm run typecheck --prefix apps/web` | **exit 0** |
| `npm run build --prefix apps/web` | **exit 0**, avertissement existant sur theme-init.js sans type=module |
| `node apps/web/node_modules/tsx/dist/cli.mjs scripts/dev/check-pending-recovery-106.ts` | **PASS, exit 0**, harnais complet autonome |
| `impeccable.cmd detect --json apps/web/client/portal/runtime/pending-requests.tsx apps/web/test/pending-recovery-106.test.tsx scripts/dev/check-pending-recovery-106.ts` | Une exécution finale, **[]**, exit 0 |
| `git diff --check`, `git diff --cached --check` | **exit 0** avant commit |

Logs finaux : `artifacts/pending-recovery-106/final-tests.log`, `typecheck.log`, `build.log`. Résultats navigateur : `metadata-results.json`, `race-results.json`, `all-results.json`. Pas de campagne complète supplémentaire, conformément au mandat.

Le test TSX lance le harnais Vite/React/Playwright-core existants, avec serveur local 127.0.0.1/port 0 et Edge headless. La fixture temporaire importe le **vrai** PortalPendingRequests via le **vrai** ConsoleContext, le **vrai** commandStore et le CSS réel. Aucun composant copié ni hook de test dans le bundle produit. Réseau et exceptions Storage synthétiques ; aucun service réel ni identité réelle.

Couverture exécutée : lecture refusée sans fausse absence ; écriture refusée avec entrée et après confirmation sans entrée ; effacement refusé après suivi ; retour saved/clear et saved/write ; saved/read vide silencieux ; reload avec corps null, sans renvoi ; dialogue et sens de l’arrêt conservés ; changement d’école masque le suivi/message précédent ; arrivée de notice sans vol de focus ; Tab/Shift-Tab ; deux rendus identiques sans mutation des régions vivantes ; pending déjà expliqué sans doublon ; bouton de renvoi rendu avant échéance, attente CSRF synthétique, horloge passée sans rendu intermédiaire, retour pending visible, zéro émission supplémentaire, entrée complète inchangée dont operationId, vérification disponible, reçu tardif accepté. `unknown/read` et `unknown/clear` avec entrées ne sont pas produits par ce vrai store : le constructeur échoué et clear donnent une liste vide ; aucune mutation privée du store pour fabriquer ces combinaisons.

## Captures et limites

36 captures de matrice : `{read,write,clear}-{320,390,1440}-{light,dark}-{1,2}.png` sous `artifacts/pending-recovery-106/`, plus `expired.png`, `keyboard-focus.png`, `confirmed-storage-refused.png`. Débordement document et contenu des Alert contrôlés dans chaque combinaison ; thèmes par l’attribut réel `data-theme`.

Inspection visuelle effectuée sur : `write-320-dark-2.png`, `write-390-light-1.png`, `read-1440-dark-1.png`, `expired.png`, `confirmed-storage-refused.png`, `keyboard-focus.png`, `clear-320-light-2.png`, `read-390-dark-2.png`, `write-1440-light-1.png`. Texte, boutons et focus visibles, sans coupe ; à 320 px/200 %, les mots longs passent à la ligne et la page défile verticalement. La première capture à zoom avait révélé un dépassement interne malgré l’absence de débordement document : grille minmax et retour à la ligne ajoutés, puis captures régénérées et inspectées.

Il s’agit d’**Edge, viewports simulés et zoom CSS**, pas de Safari, zoom natif, VoiceOver ou lecteur d’écran physique. Les régions ARIA et leur stabilité DOM sont contrôlées ; aucune annonce audio réelle ou conformité WCAG globale n’est revendiquée. Aucun PostgreSQL, Apple, GPS, batterie ou autre résultat physique. Les seuils 5/10 s, L2/L3/L4 et parcours natifs restent hors lot. La phrase métier existante de demande conservée n’a pas été modifiée dans le moteur ; l’avertissement adjacent expose explicitement l’échec de suivi local. Qualification et intégration ultérieures appartiennent au coordinateur, sans mise à jour STATUS par ce worker.
