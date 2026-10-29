# #319 — Entrée, invitations reçues et récupération

Reprise du 29 octobre 2026 depuis `backup/311-entry-20261029-2050` (`0fdfb2de`), réintégrée en `96ccb29a`. Le JSX sauvegardé est conservé et terminé, sans réintroduire les composants historiques.

## Périmètre réalisé

`portal/entry` remplace connexion, code, création autorisée par code/invitation, choix des écoles, compte sans école, invitation reçue, récupération et page introuvable. `EntryFrame`, `AccountEntryPanel` et `entryRoutes` sont réutilisables par l’ouverture d’école. Les champs, erreurs, confirmations et menus utilisent les composants shadcn/Base UI du socle #311. Les labels restent visibles, les champs de mot de passe conservent les attributs de gestionnaire de mots de passe, le code accepte le collage et les erreurs de saisie déplacent le focus vers le premier champ à corriger.

La récupération ouvre le parcours du fournisseur d’identité uniquement à partir de l’URL renvoyée par le BFF. Sa page n’est pas déclarée reconstruite. Le formulaire d’origine conserve son intention en mémoire et efface le mot de passe à l’ouverture de la récupération, au changement d’étape et après une tentative d’authentification ou de création.

Les contrôleurs conservent les routes BFF, CSRF, confirmation d’invitation et reprise idempotente. Les fragments restent traités en amont par `main.tsx`. Les données scolaires ne sont ni ajoutées aux URL ni persistées dans un stockage navigateur. Une nouvelle lecture retire les anciennes appartenances ; une réponse d’une génération abandonnée, notamment après restauration du navigateur ou nouveau fragment, ne les réinstalle pas. Un refus définitif d’invitation retire le détail périmé. Un résultat inconnu conserve la demande et bloque changement de compte et abandon de l’invitation, y compris depuis le menu du compte.

Références relues : règles R01–R05, R95, R98 ; API AP01/AP02/AP04 ; scénarios T001/T002 et T005–T008. Le serveur reste l’autorité sur les droits et l’acceptation ; cette livraison d’interface ne requalifie pas les transactions métier.

## Raccords

- Production : `PortalEntryPage({ invitationLink })` pour `/app/` et `/app/invitation`, `PortalRecoveryPage` pour `/app/recover`, `PortalNotFoundPage` pour les adresses inconnues. Le coordinateur termine la sélection du nouveau portail et le retrait de l’ancien routage dans `main.tsx`.
- Ouverture : `AccountEntryPanel({ routes: entryRoutes, initialCode?, onSignedIn })` et `EntryFrame` sont publics. Aucun import de `account-entry.tsx`, `App.tsx` ou `ui.tsx` n’est nécessaire.
- Aperçu : import distinct `portal/preview/entry-preview.tsx`, puis `installEntryPreview(scene)` et `<EntryPreview scene={scene} />`. Scènes : `login`, `schools`, `empty`, `invitation`, `expired`, `unverified`, `mismatch`, `lost-reply`, `changed`, `slow`, `recovery`, `recovery-unavailable`. Le transport isolé refuse toutes les routes non prévues et ne délègue jamais au réseau réel. Ne pas l’installer pour les scènes console/ouverture.
- Aperçu local reproductible : démarrer Vite puis ouvrir `/app/test/entry-preview.html?scene=login`. Code fictif `DEMO-DEMO`. Les liens d’aperçu attendent les pages `connexion`, `ecoles`, `invitation`, `recuperation`, `ouverture`, `preferences`, `agenda` dans le routeur de l’aperçu principal.

## Vérifications exécutées

Sous Node **24.22.1**, dépendances du lockfile (`npm ci --ignore-scripts`, audit 0 vulnérabilité au moment de l’installation) :

- Typage client `tsc --noEmit` : **PASS**.
- Typage serveur et tests `tsc -p tsconfig.check.json` : **PASS**.
- Sept fichiers ciblés : modèles entrée, transport fictif, destination après connexion, récupération BFF, comptes BFF, invitations BFF et frontière portail : **74 tests PASS**.
- Recette interactive Atrium avec données fictives : soumission vide → deux erreurs et focus e-mail ; connexion → compte sans école ; deux écoles avec rôles distincts ; réponse perdue après confirmation → même demande, abandon et compte bloqués ; reprise au clavier → reçu confirmé et une appartenance. Aucun stockage local ajouté durant ces essais.
- Vérification DOM à 320/390 : pas de débordement horizontal de la page de connexion ; champs 16 px à 390. Inspection de captures viewport à 390 : connexion claire, invitation et reçu sombres ; composition desktop naturelle 1280 inspectée. Console sans erreur durant les passages inspectés.

Les premières captures Atrium sous émulation supérieure à la surface réelle et les captures pleine page répétaient des tuiles. Elles ont été écartées ; elles ne prouvent pas 1440 ni le bas d’une page longue. La matrice complète 390/1440 clair/sombre, gestionnaires de mots de passe réels, clavier mobile physique et VoiceOver restent à qualifier après l’essai du porteur. Aucune campagne étendue, aucun déploiement, aucune clôture d’issue dans ce lot.
