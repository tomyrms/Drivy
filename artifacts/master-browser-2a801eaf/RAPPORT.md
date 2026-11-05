# Master 2a801eaf — diagnostic navigateur

Base exacte : 2a801eaf6930976760b79372c75b3fa04efd1796, worktree initialement propre. Dispatch ctx_8131cd0f5820, tâche task_7dbf53db6fe0.

## Pending metadata

Le passage instrumenté local `node apps/web/node_modules/tsx/dist/cli.mjs scripts/dev/check-pending-recovery-106.ts metadata` est RÉUSSI, code 0 (`pending-diagnostic.log/.exit`). L’échec CI précis n’est pas reproduit à l’assertion finale. Cependant `pending-observations.json` relève store et DOM dans la même tâche navigateur :

1. notification : durability=saved, phase=verifying, ancien message ;
2. notification suivante : durability=saved, phase=uncertain, nouveau message de vérification, zéro occurrence DOM, titre Vérification en cours encore affiché ;
3. au contrôle local : phase=uncertain, une occurrence DOM.

La garde durability=saved ne garantit donc ni la fin de verify, ni le commit React. Source inchangée : command-store.verify écrit les métadonnées dès son passage en verifying puis attend la réponse ; la présentation lit ensuite le snapshot. C’est un défaut historique de synchronisation du harnais, indépendant de SchoolSettingsPilot. Proposition bornée soumise avant correction : attendre la sortie de verifying/sending du store, puis la présence du message exact final dans le DOM, conserver le compte exact égal à 1 et les contrôles de disparition de notice. Aucun sleep ni assouplissement d’assertion.

## Ouverture STAFF

Instrumentations seulement : stades séparés reload, heading, nom école, capture, fermeture et entrée du helper ; en cas d’échec, capture AVANT fermeture du navigateur de compteurs DOM limités à des labels fixes, sans URL, token, texte libre ni identité. Une catégorie fermée distingue ambiguïté de locator, timeout et autre erreur.

Parcours complet sur base dédiée PostgreSQL 18.6, mail dédié, image OIDC verrouillée déjà disponible : RÉUSSI, 115 contrôles, code 0 (`opening-instrumented.log/.exit`, `opening-result.json`). Aucun échec de cette tentative à exploiter : la cause du run CI 42117658229 reste non établie par observation directe.

Une hypothèse indépendante est reproduite sur le vrai build de cette base : session connue, /me retenu par une promesse contrôlée, l’entrée affiche simultanément H1 et H2 « Vos écoles ». Le sélecteur sans niveau du parcours échoue en mode strict (`entry-heading-diagnostic.json`, `entry-heading-rendered.log/.exit`, script mts conservé). Le contrôle équivalent existant check-entry-continuity-120 qualifie déjà level:1. Proposition bornée : qualifier level:1 au contrôle STAFF en conservant le contrôle distinct du nom de l’école ; ne pas modifier la copie produit pour satisfaire le test. Cette reproduction prouve le défaut latent du sélecteur, pas que ce fut l’erreur CI sans état exporté.

## Exécution et limites

Node portable v24.22.1 ; dépendances existantes reliées par jonctions, aucune installation. Premier lancement du parcours interrompu avant exécution faute de pg résolu (`opening-diagnostic.log`, code 1) ; node_modules local ne contenait que des caches, déplacés dans local-module-cache puis jonction vers les dépendances existantes de l’intégration. Première invocation Vite depuis la racine échouée (index.html absent), invocation corrigée depuis apps/web réussie ; aucune correction produit. La sonde initialement .ts hors package ESM échouait au chargement ; extension .mts corrigée avant sa seule exécution navigateur.

Les conteneurs PostgreSQL et mail dédiés portent le label de tâche ; le conteneur étranger idrive-stream-regression-db n’est pas touché. Le harnais possède et nettoie son conteneur Keycloak. Suites étendues, CI, push et déploiement NON EXÉCUTÉS. Store, draft, queue, backend, auth, dépendances verrouillées et workflow inchangés ; seul le harnais est instrumenté. Aucune modification STATUS. Cette phase de diagnostic précédait la décision du porteur consignée ci-dessous ; aucun budget antérieur n’a été remis à zéro.


## Passe bornée autorisée — résultat pour revue

Le porteur a autorisé explicitement « Oui, cette passe bornée », relayé par le coordinateur (message msg_7b8e98147cd2). Extension unique des budgets historiques, sans réinitialisation. Une seule passe corrective exécutée ; aucune répétition après échec.

Delta livré limité aux deux scripts et à ce rapport :

- Pending attend désormais metadata.durability=saved ET une entrée sortie de sending/verifying, puis le message exact de cette entrée réellement rendu. L’assertion de compte strict égal à 1 et le contrôle de disparition de notice restent intacts. Aucun délai fixe, timeout augmenté, retry ou règle produit changé.
- Ouverture cible le heading STAFF « Vos écoles » de niveau 1 ; le contrôle distinct du nom école est inchangé. Les six stades fixes reload/heading/nom/capture/fermeture/helper restent pour localiser un éventuel prochain refus.
- Les observations temporaires (abonnement au store, mesure DOM, capture de diagnostic) ont été retirées du delta ; leurs preuves restent localement dans ce dossier. Aucun changement produit/store/draft/queue/backend/auth/dépendance/workflow.

### Vérifications de cette passe

Préfixe Node de toutes les commandes : `C:/Users/jtoma/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe` (v24.22.1), avec `apps/web/node_modules/tsx/dist/cli.mjs`.

| Contrôle | Commande / preuve | Résultat observé |
|---|---|---|
| Metadata corrigé | `scripts/dev/check-pending-recovery-106.ts metadata` ; `pending-corrected-metadata.log/.exit` | **ÉCHEC, code 1** : page.goto attend load et dépasse 30 s à la première fixture (ligne 76, appelée ligne 104), avant le contrôle modifié. Aucune relance. |
| Race inchangé | `scripts/dev/check-pending-recovery-106.ts race` ; `pending-corrected-race.log/.exit` | **RÉUSSI, code 0**, Chromium 153.0.8010.12. |
| H1 avec /me contrôlé | `artifacts/master-browser-2a801eaf/entry-heading-corrected.mts` ; JSON/log/exit correspondants | **RÉUSSI, code 0** : H1 et H2 présents, sélection H1 unique, /me encore retenu. Aucun timeout accru. |
| Ouverture corrigée | `scripts/dev/check-school-opening.ts` ; `opening-corrected.log/.exit`, `opening-corrected-result.json` | **RÉUSSI, code 0**, 115 contrôles, OIDC/BFF/API/PostgreSQL réels synthétiques dédiés. |
| Diff | `git diff --check` | **RÉUSSI, code 0**. |

Le build produit exact 2a801eaf déjà construit reste valide : le delta ne modifie aucun fichier compilé de l’UI. Le scénario metadata antérieur instrumenté passait, mais ce résultat n’est pas transféré à la correction. Le timeout local actuel est distinct du compte DOM 0/1 de la CI : aucun contrôle de contenu n’est atteint. Les fichiers HTML et TSX de fixture sont présents et générés par le script ; race réussit ensuite sur ce même mécanisme. Cela ne démontre pas la cause du timeout, ni une contention : metadata a été lancé pendant le démarrage de la recette complète, donnée de contexte seulement. La cause de ce timeout reste inconnue, sans nouvelle correction autorisée.

Les conteneurs de base et mail dédiés à cette passe sont vérifiés par label task_7dbf53db6fe0 avant retrait ; le conteneur étranger n’est jamais modifié. Aucun push, qualification CI ou déploiement lancé par le worker. Cause exacte du run opening historique toujours non établie. Le delta est prêt pour revue de code, mais **la validation locale metadata corrigée n’est pas acquise** ; décision du coordinateur requise avant suite et unique qualification CI sur SHA publié.
