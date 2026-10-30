# Connexion native et récupération — #195, #197, #198, #199

29 octobre 2026. Branche `codex/ios-auth-195-199`, base `master` `c94ec2bba979874c7539e960a2ec5c617ec1955d`. Lot iOS isolé de la reconstruction web #311 ; aucune modification web, API, contrat, dépendance, workflow ou configuration homelab.

## État vérifié avant réalisation

Les quatre issues sont ouvertes sans commentaire au moment de la lecture GitHub. Les sources de `master`, leurs historiques et les PR #180/#279 ont été rapprochés :

- #195 : toutes les erreurs de connexion étaient attachées au champ mot de passe et effacées à la moindre édition. `AppAuthPasswordAuthorization.failure` assimilait tout le domaine OAuth du point de jeton à des identifiants incorrects.
- #197 : bouton désactivé selon la saisie, sans aide après interaction ; validation clavier silencieuse.
- #198 : l’absence de configuration de récupération proposait la même reprise qu’une panne temporaire.
- #199 : `PasteButton` ignorait silencieusement les contenus dépassant 2 048 octets ; le formatage d’une chaîne arbitraire pouvait aussi conserver seulement huit caractères.

#193 et #194 sont déjà réalisés dans `512d5ca9` (fusion #279) : entrée de récupération depuis l’invitation, retour « Modifier le code », effacement du mot de passe et invalidation de la portée précédente. #196 comporte déjà une disposition verticale en taille d’accessibilité ; aucune nouvelle adaptation de noms n’est ajoutée ici. #50 reste une intégration préparée : activation SMTP et protection directe du fournisseur ne sont pas comprises dans ce lot.

## Comportement réalisé

Les erreurs de connexion sont affichées au niveau du formulaire, sur les deux entrées. La classification utilise exclusivement les codes structurés AppAuth et HTTP : 429 impose une attente, 408/5xx restent des indisponibilités, `invalid_grant` produit un refus générique d’identifiants, les erreurs de configuration du client restent distinctes. Aucun texte du fournisseur, corps HTTP, adresse ou secret n’est affiché ou journalisé. La découverte du fournisseur utilise également cette classification. L’état typé permet d’effacer seulement un refus d’identifiants lors de leur correction ; une panne ou limitation ne disparaît pas parce qu’un champ change.

La saisie garde les règles préexistantes : adresse non vide contenant `@`, mot de passe existant non vide, sans regex ni longueur supplémentaire. L’aide apparaît après sortie du champ ou validation clavier. Le bouton, le clavier et les deux connexions partagent ces règles. Les erreurs de service sont annoncées à leur changement, sans annonce à chaque caractère. Les champs conservent leur libellé et leur ordre de focus.

Quand la récupération est explicitement non configurée, la feuille propose « Revenir à la connexion » sans bouton de reprise inutile ni contact inventé. Une erreur de lecture conserve « Réessayer » et « Fermer ». Aucun mail envoyé, session créée ou récupération réussie n’est annoncé. La récupération depuis l’invitation conserve les informations utiles et efface déjà le mot de passe.

Le collage valide le contenu complet avant de remplacer la saisie, conserve la limite en octets UTF-8 et réutilise le parseur existant. Un contenu excessif, une origine étrangère ou un code non reconnu laisse la saisie précédente intacte et explique le refus. La saisie manuelle et le collage système ne tronquent plus un texte excédentaire en un autre code valide. Aucun collage ne déclenche d’inspection réseau ou de création automatique.

## Références et contrôles

Références lues : `COMMENCER_ICI.md`, règles R01–R05, contrat API et identité, scénarios T001/T004–T008 ; `account-recovery-20261026.md` et `recuperation-native-50-20261026.md`. La récupération utilise toujours `GET /v1/account-recovery/options` et l’origine contrôlée existante. Les protections serveur et l’écriture durable du Trousseau restent les mêmes.

La classification AppAuth a été vérifiée contre la révision verrouillée `a972daac82d449d58ab119e91c68153e29ddac33` : [OIDError.h](https://github.com/openid/AppAuth-iOS/blob/a972daac82d449d58ab119e91c68153e29ddac33/Sources/AppAuthCore/OIDError.h), [OIDAuthorizationService.m](https://github.com/openid/AppAuth-iOS/blob/a972daac82d449d58ab119e91c68153e29ddac33/Sources/AppAuthCore/OIDAuthorizationService.m). Le statut HTTP sous-jacent doit primer car AppAuth peut construire une erreur OAuth à partir d’un 429 JSON.

Exécuté : revue de code, vérification du périmètre de diff et `git diff --check`. Aucun compilateur Swift/SDK Apple disponible dans ce worktree Windows. Compilation Release et IPA à effectuer sur GitHub Actions par le coordinateur ; ce document ne les annonce pas réussies.

Préparés, **non exécutés** : `NativeAccountTests` (classification structurée, 429 imbriqué, timeout/5xx, absence de classification par texte, persistance des pannes, règle de saisie, limites exactes UTF-8 et collage sans réseau/troncature), `SchoolSignInFeedbackUITests` (panne conservée, refus d’identifiants effacé, attente conservée, validation après interaction), `SchoolAccountRecoveryUITests` (retour utile et distinction absence de configuration/panne). Les nouveaux états visuels sont réservés à DEBUG simulateur et utilisent des données synthétiques.

## Essai puis qualification

1. Connexion : saisir une adresse incomplète, passer au mot de passe, corriger ; vérifier aide, ordre de focus, bouton et clavier. Essayer une panne réseau puis modifier l’adresse : le retour de panne demeure au niveau du formulaire.
2. « J’ai un code » : coller un contenu non reconnu ou trop long après un code déjà saisi ; vérifier refus lisible et saisie intacte, puis coller un code/lien valide. Aucune vérification ne démarre avant l’action explicite.
3. Depuis chaque connexion, ouvrir « Mot de passe oublié ». Sans configuration, revenir directement ; avec une panne, réessayer ou fermer. L’e-mail et l’intention d’invitation doivent rester, le mot de passe doit être vide.
4. Après validation du porteur : exécuter les suites ciblées préparées, compiler les cibles de tests et vérifier iPhone/iPad, grandes tailles de texte et VoiceOver. Aucun résultat de lecteur d’écran physique n’est déduit de la revue statique ou du simulateur.

Aucune suite exécutée pendant le développement, aucune fusion, clôture d’issue ni mise en service. Le lot ne prétend pas achever #50 ou les campagnes de qualification globales.
