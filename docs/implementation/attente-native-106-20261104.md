# U2a — attente native #105/#106 — 4 novembre 2026

Livraison locale, qualification Apple **NON EXÉCUTÉE**. Base `0bdaf32483e3dc4dba9e75056eedb0c74cd43d4e`, branche `tomyrms/issues-attente-native-106`. Le commit de livraison est celui qui ajoute ce rapport (`git log -1 --format=%H -- docs/implementation/attente-native-106-20261104.md`). Aucun push, PR, CI, clôture/réouverture d’issue ou déploiement ; le run crypto883581ad est inchangé et ne prouve rien pour ce lot. STATUS reste hors périmètre suivant le mandat U2a.

## Runtime et références

`orca orchestration worker-show --dispatch ctx_4c378c3bb94f --json --full` : `result.worker.startOptions.launch.effective = {agent: codex, model: gpt-6-astra, effort: high}` ; session `e3e50807-6013-4a2a-9bca-a14ff216d0a9`, tâche `task_c60e343cbf71`. Configuration exposée par Orca, sans attestation indépendante du fournisseur. Guides locaux orchestration/orca-cli lus, guide versionné `orca skills get orchestration` chargé. Aucun sous-agent ni nouveau worktree créé par le worker.

Références : AGENTS, COMMENCER_ICI, DESIGN racine (portée Apple), docs/implementation/DESIGN, R100, T004–T007 et ligne U2a du contrat externe `C:/Users/jtoma/orca/workspaces/Drivy/issues-reactivite-106/docs/implementation/reactivite-restes-contrat-20261104.md`. Ces documents ne constituent pas une preuve produit.

Skills réellement chargés sous `C:/Users/jtoma/.codex/skills/` :

- `systematic-debugging/SKILL.md` : cause établie au source (idle/waiting/slow, unique sleep10, aucune ligne à5).
- `test-driven-development/SKILL.md` et `writing-good-tests.md` : horloge/frontières et cas de fin préparés avant implémentation ; assertions complémentaires d’annonces et réveil tardif ensuite. **Aucun RED/GREEN observé**, faute de Swift/Xcode comme prévu par le mandat ; aucun échec artificiel de compilation présenté comme RED.
- `verification-before-completion/SKILL.md`, `requesting-code-review/SKILL.md` et `code-reviewer.md` : revue personnelle du diff, invariants, compatibilité et limites ; revue indépendante réservée au coordinateur, délégation interdite.
- `impeccable/SKILL.md` 4.8.0, `reference/ios.md`, `adapt.native.md`, `audit.native.md`, puis `craft-floor.md` avant édition. Provenance `.installation-source.json` : pbakaus/impeccable, ref `2c95b1968ca74c5d2c4c0503dcee72f6d0d555ea`, source `.agents/skills/impeccable`, SHA256 du SKILL vérifié `fab04b31f946573b00a8559db1fc070f8ea5825254d491c2b13156e5661a86d7`.
- `uncodixfy/SKILL.md` : manifeste cyxzdev/Uncodixfy, ref `e0e028058b5259debdd94b78147c6d6c77bf7da2`, source `.`, SHA256 vérifié `efb88d150e40d34c5b997a25eb4b88655e8daa1628848568a7f50668f1bf1d10`.
- `swiftui-ui-patterns/SKILL.md` et `references/async-state.md` : état Observable local et annulation main actor ; `ui-skills-root/SKILL.md` lu, sélection directe des références installées, aucun téléchargement via npx.

`C:/Users/jtoma/.codex/skills/impeccable/scripts/impeccable.cmd context --target apps/ios/Drivy/SchoolJoinUI/SchoolWaitMonitor.swift` exécuté une fois, exit0. Contexte sans PRODUCT ni surface brief, plateforme non détectée : références natives chargées explicitement ; la correction ciblée suit l’existant, aucun init/hook/document produit ajouté. Le détecteur web est non applicable selon audit.native. Principes appliqués : ligne discrète temporaire, copie exacte sans promesse de réception, SF Symbol clock, footnote Dynamic Type, DrivyTheme.muted, fixedSize multiline et lien existant. Pas de carte, palette, font, mouvement ou dépendance ajouté. Prescriptions CSS/px/hover, palette alternative et motion décorative non applicables au natif et au mandat. Contraste, focus et taille réels restent à observer ; aucun score visuel inventé.

## Codebase Memory

Index créé par chemin absolu de CE worktree : `C:/Users/jtoma/orca/workspaces/Drivy/issues-attente-native-106`. Nom réellement retourné : `C-Users-jtoma-orca-workspaces-Drivy-issues-attente-native-106` (le nom proposé à l’appel n’a pas été retenu). `index_status` : ready, root exact, génération 2026-11-04T16:27:33Z, mode full, 51903 nœuds/196379 arêtes, watch actif. 963 fichiers exclus, 85 parse partial, 4 unusable ; aucune prétention de couverture totale.

`search_graph` sur SchoolWaitMonitor/SchoolWaitLine/announce, `trace_path(function_name: SchoolWaitLine, direction: inbound)` : quatre consommateurs AccessCode/CodeJoin/Join/Opening. `check_index_coverage(paths: [monitor, tests])` : no_recorded_issue, metadata_match, best effort. Lecture du source et recherches rg des run/retry/announcements et guards ensuite. `detect_changes` depuis origin/master : deux sources modifiées, sept symboles/modules impactés dont les quatre consommateurs, submitSignIn et retry. Aucune consultation d’index d’un autre worktree. Deux erreurs de découverte MCP corrigées : couverture demandée initialement avec path au lieu de paths, trace avec start_node au lieu de function_name ; aucune preuve déduite de ces erreurs.

## Implémentation et compatibilité

`Phase` devient idle/waiting/pending/slow. À0 waiting garde le libellé d’action sans ligne ; à5 pending rend « Demande en cours » (`wait-pending`) ; à10 slow rend « La réponse tarde. » (`wait-slow`). `wait-retry` n’existe que pour slow avec closure fournie. `announcement(title:)` fournit titre/palier5/palier10, idle silencieux ; le modifier ne poste que pour la phase encore actuelle, sans focus forcé. `onPhase` demeure un événement par changement, pas un tick.

`init(slowAfter:sleep:now:)` ajoute une horloge monotone injectable avec valeur par défaut ; appels existants inchangés. Les deux échéances sont relatives au même départ, le second sleep retire le temps déjà écoulé. Seuils indicatifs soumis à l’ordonnancement du MainActor, sans délai réseau ou résultat métier implicite. Les gardes token/phase et annulation bloquent les vieux réveils et anciennes completions. Le corps de retry reste identique : cancel précédent, attendre sa fin, réexécuter la closure existante. Aucun operationId créé par le moniteur.

Consommateurs **non modifiés** : AccessCode ne fournit une relance que pour inspect/code, pas création/connexion ; CodeJoin et Join gardent isReady/isBusy/!isConfirmed puis les closures verify/retry/accept/inspect avec leurs guards ; Opening garde isBusy/receipt nil puis submit. Tous rendent automatiquement le palier par SchoolWaitLine et gardent les titres par schoolWaitAnnouncements. Authentification, droits, modèle, journaux et renvois restent chez leurs propriétaires.

## Tests préparés et limites

Les cinq tests existants sont conservés et enrichis, cinq ajoutés : frontières4.999/5/9.999/10 ; réponse rapide ; relance annulée/même UUID ; relance après réponse sans effet ; phases/texte annoncés une fois ; réponse entre seuils ; completion ancienne ; continuation de timer libérée par annulation ; timer hostile obsolète ; réveil à8 suivi du palier10 à10. L’horloge pilotable stocke des échéances et reprend les continuations annulées avec CancellationError, puis revérifie Task.isCancelled ; le double hostile est explicitement distinct de Task.sleep et toutes ses continuations sont reprises. Les yields sont des passes bornées d’ordonnancement, pas des attentes réelles de5/10 secondes.

Ces tests vérifient le moniteur et les messages destinés au modifier ; ils ne prouvent ni la restitution VoiceOver réelle, ni le rendu SwiftUI, ni l’idempotence serveur. Aucune exécution Swift, suite Apple, build, simulateur, capture native, VoiceOver ou mesure physique réalisée. La revue statique ne vaut pas compilation Swift6.

## Commandes et contrôles réellement exécutés

- Orca skills get orchestration, worker-show --help puis worker-show --dispatch ctx_4c378c3bb94f --json --full : exit0.
- Get-Content des références, Get-ChildItem des deux skills, Get-FileHash des SKILL : exit0 ; lectures volumineuses tronquées reprises par sections pertinentes.
- git status --short (propre avant édition), git rev-parse HEAD, git branch --show-current : exit0, base et branche ci-dessus.
- rg des symboles/consommateurs/R100/scénarios/contrat : exit0 sur chemins résolus. Un glob PowerShell passé littéralement à rg a rendu exit1 (syntaxe Windows), repris par `rg ... SchoolJoinUI -g '*View.swift'`.
- Get-Command swift,xcodebuild -ErrorAction SilentlyContinue : exit1, aucune commande trouvée ; aucune installation.
- Scripts Python d’édition ciblée : exit0. Ce ne sont pas des tests produit.
- git diff --check, git diff --stat et lecture complète du diff des deux Swift : exit0. Avertissement Git CRLF→LF de normalisation, pas un échec de test.
- MCP list/index/status/search/coverage/trace/detect : succès après correction des deux appels indiqués plus haut ; les réponses MCP ne portent pas d’exit code shell.

## Recette Apple à exécuter séparément au candidat

Après autorisation distincte et génération du projet avec les versions verrouillées existantes, sur runner Apple : `xcodebuild test -project apps/ios/Drivy.xcodeproj -scheme Drivy -destination 'platform=iOS Simulator,id=<UDID du runner>' -only-testing:DrivyTests/SchoolWaitMonitorTests CODE_SIGNING_ALLOWED=NO`, puis suite native pertinente au candidat. Ne pas lancer cette commande sur le run crypto883581ad.

Sur fixtures synthétiques des quatre parcours, retarder la réponse à15s : capturer0/4.999/5/9.999/10/15s, puis réponse avant5 et entre5/10, et relance à10 suivie d’une réponse ancienne. Vérifier ligne absente initialement, copies exactes, retry absent sans closure, aucune transition après fin et aucune création/double effet de la même intention. Recette T005/T006/T007 existante pour l’autorité et l’idempotence, indépendamment du moniteur.

Faire iPhone compact et iPad (portrait/paysage et fenêtre étroite), clair/sombre/contraste accru, Dynamic Type standard puis AX5, Réduire les animations activé/désactivé, clavier matériel : texte entier, action visible et atteignable, pas de saut de focus ni piège clavier. Sur appareil physique avec VoiceOver : titre au démarrage, une annonce à5 et10, silence après succès, aucun tick ni annonce ancienne pendant retry, ordre de lecture stable. Consigner SHA/appareil/OS/scénario et captures natives réelles sans données personnelles. Aucun HTML/image de substitution.

Autonomie : périmètre de trois fichiers respecté, aucune adaptation consommateur nécessaire, aucune installation ni accès production. Zéro correction demandée par revue consommée sur les deux autorisées ; revue indépendante et qualification Apple restent à faire avant intégration.
