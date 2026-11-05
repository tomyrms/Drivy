# U106 — sortie et brouillons connus, 5 novembre 2026

Livraison locale sur `tomyrms/issues-sortie-brouillon-106`, base exacte
`e2edc85ed092237016620079d52d11eb7a2d02b5`. Aucun push ni CI distante.

## Comportement

Le handler `SchoolRootView.signOut` utilise `SchoolOnboardingExitModel.begin/finish`.
Avant reset, il capture la personne, l’API, toutes les memberships courantes et la
portée du modèle vivant si elle appartient à cette personne/API. Les couples
portée/kind sont dédupliqués ; STUDENT et STAFF sont retirés pour chaque membership,
indépendamment des rôles actuels. Aucun formulaire n’est conservé par ce modèle.

Le modèle vivant est invalidé avant masque et suppression synchrone. Le store
existant reçoit `remove(scope:kind:discardingUnreadable: true)` pour chaque cible,
même après un échec précédent. Aucun répertoire, clé ou autre intention n’est retiré.
La révocation push précède toujours la fermeture IdentitySession. Le contrôle de
trajet existant reste à l’entrée du geste ; aucun nouvel arrêt GPS n’a été ajouté.

Après fermeture locale, seuls les échecs affichent une `SchoolErrorNotice` avec
Réessayer. L’erreur d’IdentitySession conserve son propre affichage. Le réessai
ne reprend que les références échouées, sans données de formulaire. Le début
d’une nouvelle connexion invalide les callbacks de sortie et retire ces références :
une nouvelle session peut écrire exactement le même fichier. Aucun réessai ancien
n’est autorisé après cette transition, même si la nouvelle connexion échoue.

`purgeOnboardingDraft` retourne désormais un Bool ignorable par les anciens appelants,
invalide le modèle et annule ses écritures différées. Le retrait du brouillon en mémoire
par `clearOnboardingDraft` n’annonce plus une suppression réussie après erreur disque.
La réconciliation après une confirmation/relecture ignore désormais un modèle invalidé.
Les commandes conservées/en vol ne sont pas annoncées annulées. Fermeture ordinaire,
Plus tard, changement d’école et panne réseau ne déclenchent pas cet orchestrateur.

## Limite de conservation

La purge concerne les portées **connues à la sortie**. Le stockage existant utilise
un hash de compte/API/école/adhésion/époque/kind, sans index énumérable. Les anciennes
adhésions et époques inconnues ne peuvent pas être retrouvées ici. Aucun scan global,
nouveau format, migration ou suppression de clé partagée n’est introduit. Une politique
de conservation couvrant ces fichiers anciens reste à définir séparément. Les références
de réessai sont en mémoire seulement et ne survivent pas à une fermeture du processus.

## Préparation et preuves

- Runtime : `gpt-6-astra`, effort `high`, vérifiés dans le `turn_context` de la session
  courante, extraction limitée à model/effort. Aucun changement de modèle.
- Skills lus : `C:/Users/jtoma/.codex/skills/systematic-debugging/SKILL.md`,
  `test-driven-development/SKILL.md` et `writing-good-tests.md`,
  `verification-before-completion/SKILL.md` sous la même racine. Tests initiaux écrits
  avant le modèle ; aucun RED/GREEN exécuté ni revendiqué sur Windows.
- UI : `C:/Users/jtoma/.codex/skills/impeccable/SKILL.md` (4.8.0), références
  harden et craft-floor ; `C:/Users/jtoma/.codex/skills/uncodixfy/SKILL.md`.
  `impeccable.cmd context --target apps/ios/Drivy/SchoolUI/SchoolRootView.swift`
  exécuté ; DESIGN.md lu. Mode Operate : notice existante, français court, reprise
  explicite, aucun succès décoratif, palette/typo/layout conservés. Les prescriptions
  HTML/CSS et typographie de site ne s’appliquent pas à ce composant SwiftUI natif.
  Dynamic Type et groupement accessible proviennent du composant SchoolErrorNotice.
- Codebase Memory : index créé par chemin absolu du worktree, projet
  `C-Users-jtoma-orca-workspaces-Drivy-issues-sortie-brouillon-106`, 53 046 nœuds,
  202 327 arêtes initiales. Recherche `signOut|purgeOnboardingDraft|clearOnboardingDraft`,
  trace sortante de Root.signOut (23 dépendances, profondeur 2), puis lecture des sources
  Root/ProfileWorkspace/SelfProfileIntent/AccountIntentStorage/IdentitySession/Vault.
  L’index signale des parsings partiels hors des sources étudiées ; il ne remplace pas
  la lecture du code. Contrat des restes L4, F21, R97–R100 et scénario T191 consultés.
- `git diff --check` exécuté sans erreur. `Get-Command xcodebuild` confirme son absence.
  Aucun test Swift, build Apple, rendu, capture, VoiceOver, GPS ou batterie exécuté.

## Tests préparés et recette restante

`SchoolOnboardingExitTests` exerce le même orchestrateur que Root avec le vrai
EncryptedSchoolOnboardingDraftStore (racine temporaire unique, clé synthétique) :
feuille fermée ; plusieurs memberships/kinds ; autres compte/API/époque conservés ;
modèle vivant ; sauvegarde différée annulée ; fermeture ordinaire sans purge ;
reconnexion sans restauration ; suppression refusée d’un fichier illisible avec sortie
effective, autre kind retiré et réessai idempotent ; ancienne sortie face à une nouvelle
connexion ; lecture initiale tardive ; confirmation en vol et sa relecture tardive.
Les callbacks API et push/identité sont injectés, pas de réseau ni Keychain réelle.
La seule attente temporelle est bornée à 100 ms. Nettoyage limité aux racines de test.

Sur Mac configuré avec les dépendances verrouillées existantes, préparer le projet via
la procédure du dépôt, puis exécuter (destination à remplacer par un simulateur installé) :

```sh
xcodebuild test -project apps/ios/Drivy.xcodeproj -scheme Drivy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -onlyUsePackageVersionsFromResolvedFile -only-testing:DrivyTests/SchoolOnboardingExitTests -only-testing:DrivyTests/SchoolOnboardingDraftTests -only-testing:DrivyTests/SchoolProfileWorkspaceTests
```

Puis la suite DrivyTests et la recette UI sur iPhone/iPad, clair/sombre et texte
d’accessibilité : échec purge + erreur Trousseau simultanés, reprise, nouvelle connexion,
fermeture de feuille puis sortie, trajet en cours annulé/confirmé. Vérifier lisibilité,
défilement de la connexion sous la notice, focus et annonce d’erreur sur Apple.
Ces contrôles sont **NON EXÉCUTÉS**. Aucun résultat produit n’est déduit du diff.

Fichiers modifiés : RootView, ProfileWorkspace, nouveau ExitModel, nouveau ExitTests,
et ce rapport. STATUS et registre laissés à leur propriétaire selon le mandat.
SHA du commit local communiqué dans le retour de livraison (le rapport est dans ce commit).
