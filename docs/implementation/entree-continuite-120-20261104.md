# Entrée web : continuité et notice — R4 / #120

4 novembre 2026. Base `f34dbd3593196d6d4fc524a56675778f6090fbd0`, branche `tomyrms/issues-reactivite-106`. Task `task_5df79a21d596`, dispatch `ctx_4c3b42be2710`. Livrable U1/U3 seulement ; aucune clôture de #120. Le SHA de livraison est celui du commit contenant ce rapport, également transmis au coordinateur.

## Modification et cause

La notice dit désormais : « Déconnecté de cet appareil. La révocation de la session n’a pas pu être confirmée. » Le contrat SessionClosure et le stockage du drapeau sont inchangés ; failed/unknown déclenchent la notice, confirmed/not-attempted ne la déclenchent pas.

À la base, PortalEntryPage remplace SchoolsPending par SchoolsView après /me ; chaque branche crée son SignedInCodePanel. Le texte remonté dans typedCode survit, mais React remplace le champ et le hook local, puis autoFocus et le focus du titre déplacent la sélection/le focus. Le RED navigateur sur build de base confirme : valeur ABXYCDEFGH conservée, identité du nœud false, focus false, sélection [10,10,forward] au lieu de [2,5,backward].

Le formulaire AccountEntryPanel reste maintenant au même emplacement de l’arbre sur la page compte, avant/pendant/après la lecture et quand la session devient connue. Il partage le CodeForm existant ; le hook et son singleFlight restent montés. La présentation signedIn suit la session prouvée sans changer les requêtes, CSRF, générations ni gardes d’identité. Le formulaire masqué reste monté lorsqu’il est fermé. Le focus du titre dépend d’une navigation demandée, plus de la seule arrivée de loaded ; autoFocus est retiré du champ. Aucun délai de focus ajouté. SchoolsPending garde un export de présentation autonome utilisé par le test existant, via le formulaire commun, mais ne participe plus à la bascule de la page réelle.

Fichiers : `apps/web/client/logout-notice.ts`, `apps/web/test/logout-notice.test.ts`, `apps/web/client/portal/entry/{entry-page.tsx,schools-view.tsx,account-entry-panel.tsx,use-entry-session.ts,use-account-entry.ts}`, `scripts/dev/check-entry-continuity-120.ts` et ce rapport. Aucun fichier hors périmètre, STATUS, contrat R2, styles globaux, dépendance, lock, BFF ou protocole changé.

## Environnement et méthode

Orca worker-show --dispatch ctx_4c3b42be2710 --json --full expose launch.effective = Codex gpt-6-astra, effort high ; configuration effective Orca, pas attestation indépendante du serveur. Aucun changement de fournisseur/modèle, sous-agent, publication, PR, CI distante ou déploiement.

Skills lus réellement : `C:/Users/jtoma/.codex/skills/systematic-debugging/SKILL.md`, `test-driven-development/SKILL.md` et son `writing-good-tests.md`, `verification-before-completion/SKILL.md`, `ui-skills-root/SKILL.md`, `better-accessibility/SKILL.md` ; stubs Orca orchestration/orca-cli et guide versionné orchestration. Superpowers disponible via ces skills locaux ; pas d’attestation d’une version de plugin. `npx --no-install ui-skills categories` exit 1 : CLI absente, aucune installation ; routage manuel vers better-accessibility installé.

MCP réellement utilisé : Codebase Memory (list_projects, index_status, index_repository, search_graph, check_index_coverage, trace_path). Réindexation full par chemin absolu `C:/Users/jtoma/orca/workspaces/Drivy/issues-reactivite-106`, projet `drivy-r2-20261104`, génération 2026-11-04T14:36:15Z, 51938 nœuds / 196452 arêtes. Les trois chemins use-entry-session/use-account-entry/entry-page ont metadata_match, sans problème enregistré ; 963 fichiers exclus, 85 analyses partielles, 4 inutilisables dans le dépôt : preuve best effort. Recherche des trois symboles correspondants puis trace outbound PortalEntryPage : EntryFrame, useEntrySession, InvitationView, boutons, alertes, skeleton. Sources réelles lues après le graphe, notamment les deux hooks, formulaire, page, écoles, thème, tests existants et harnais browser. Un premier appel trace avec mauvais argument a été corrigé en function_name ; aucune conclusion tirée de son erreur.

Les huit modifications interrompues ont été conservées et reprises après confirmation du coordinateur, qui avait sauvegardé leurs octets. Les anciens artefacts ont été inspectés, puis le RED et le GREEN réexécutés. Aucun secret ni donnée réelle utilisé ; fixtures synthétiques, buildWebApp sur 127.0.0.1:port0, Edge headless via infra/dev/browser.ts, interceptions BFF, aucune PostgreSQL ni service d’identité réel.

## Vérifications récentes

PATH Node portable `C:/Users/jtoma/AppData/Local/Temp/drivy-orchestration-20261104/node-v24.22.2-win-x64` préfixé uniquement dans les processus. Version vérifiée v24.22.2. Dépendances déjà présentes à la reprise, aucune nouvelle installation.

| Commande / cas | Résultat observé |
|---|---|
| Build de base, puis `node --import ./apps/web/node_modules/tsx/dist/loader.mjs scripts/dev/check-entry-continuity-120.ts --red` | Build exit 0, navigateur exit 1 attendu : nœud/focus/sélection perdus après /me retenu 15 s |
| `npm run typecheck --prefix apps/web` | exit 0 |
| `npm test --prefix apps/web -- test/logout-notice.test.ts test/entry-code-open.test.tsx test/account-entry-route.test.ts` | exit 0, 3 suites / 18 tests verts |
| `npm run build --prefix apps/web` après restauration du correctif | exit 0 |
| `node --import ./apps/web/node_modules/tsx/dist/loader.mjs scripts/dev/check-entry-continuity-120.ts` | exit 0, PASS 11 groupes de contrôles |
| `git diff --check` | exit 0 (avertissements CRLF→LF seulement) |

Le RED récent remplace temporairement seulement les cinq sources de présentation par HEAD, avec sauvegarde des octets et restauration dans finally ; script local ignoré `artifacts/entry-continuity-120/verify-red.py`. Un essai avait résolu Node26 via subprocess Windows : rejeté pour la qualification et refait avec chemin absolu Node24 (version dans browser-red-final.log). La première campagne ciblée avait révélé l’export SchoolsPending supprimé (1 suite en erreur, 11 tests passés) : export rétabli sans modifier le test hors périmètre, puis 18/18 verts. Une tentative d’attente des animations a été interrompue car elle attendait aussi les squelettes infinis ; le harnais attend maintenant seulement les animations finies, et sa dernière exécution est verte.

Le harnais vérifie : saisie au milieu puis sélection arrière avant la libération de /me après 15 s ; même nœud actif, même valeur, mêmes bornes/direction ; actualisation avec deuxième réponse retenue ; session inconnue puis connue ; /me en erreur puis reprise avec réponse retenue ; soumission en cours conservée, champ readonly, un seul appel access-code et retour après refus sans nouvel envoi ; autre action focalisée non volée ; absence d’école ; Tab et Shift-Tab. Le succès visuel est celui de la lecture /me, pas une admission fictive. Aucune réussite de mutation n’est fabriquée.

## Preuves visuelles et limites

Artefacts ignorés sous `artifacts/entry-continuity-120/` : `red-results.json`, `browser-red-final.log`, `build-red-final.log`, `green-results.json`, `browser-final.log`, `typecheck-final.log`, `tests-final.log`, `build-final.log`. 24 captures finales : `{waiting,error,success,empty}-{320,390,1440}-{light,dark}.png`, plus `zoom-200.png` et les captures des transitions `green-*.png`. Vérification automatique de l’absence de débordement horizontal dans chaque combinaison et au zoom CSS 200 %. Thème réellement appliqué vérifié avant capture, transitions finies attendues ; aucune modification de styles pour obtenir les captures.

Captures ouvertes et inspectées à la reprise : `red-known-session-me-arrives.png`, puis finales `waiting-320-light.png`, `waiting-1440-dark.png`, `error-320-light.png`, `error-390-dark.png`, `success-390-dark.png`, `success-1440-light.png`, `empty-320-dark.png`, `empty-1440-light.png`, `zoom-200.png`. Champs, erreurs, boutons, skeletons et titres lisibles sans coupe observée dans cet échantillon. Les premières captures pendant transition de thème montraient des couleurs intermédiaires ; les captures finales inspectées les remplacent après stabilisation.

Limites : Edge headless Windows, pas Safari ni iPhone/iPad réel ; le maintien du nœud et du focus ne qualifie pas le clavier logiciel Apple. Zoom CSS 200 %, pas zoom natif du navigateur. Aucun VoiceOver/lecteur d’écran, mesure de contraste exhaustive, appareil physique, GPS ou batterie. Pas de campagne métier PostgreSQL ni de suite complète hors cible, conformément au mandat ciblé. Les lots L1–L4, la qualification Apple et l’intégration restent séparés ; STATUS à mettre à jour par leur propriétaire. Aucun droit provisoire, soumission automatique, nouveau sous-titre ou mécanisme d’authentification ajouté.
