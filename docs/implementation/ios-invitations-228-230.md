# Invitations : recherche, références et échéances (#228–#230)

29 octobre 2026. Base `c94ec2bb`, branche `codex/ios-planning-invitations-20261029`, après le lot planning `b96cee66`.
Les trois issues sont ouvertes et sans commentaire lors de la relecture GitHub. Aucun correctif dédié retrouvé
dans les branches/PR consultées ; les lignes de `master` ne proposent ni recherche, ni référence, ni échéance active.

## Réalisation

- #228 : champ de recherche natif, filtre de statut explicite et conservation de la sélection par UUID. La recherche
  utilise uniquement les libellés déjà autorisés (formation, rôle, adresse masquée, référence non secrète). Elle ignore
  accents et casse et n’interroge jamais les codes à usage unique, jetons, contacts complets ou nouvelles sources.
  Elle ne lance aucune requête. AP10 ne proposant que `limit`/`cursor`, les résultats couvrent les pages chargées :
  cette limite est indiquée tant qu’un curseur existe, y compris en cas de résultat vide. « Afficher la suite » reste
  manuel et disponible après un résultat vide ; aucune aspiration automatique à la saisie ou au filtrage.
- Une actualisation relit au maximum le nombre de pages déjà explicitement chargé, en suivant les nouveaux curseurs,
  puis publie cette fenêtre en une fois. La sélection reste si son UUID est relu ; les éléments absents disparaissent.
  La pagination ne rétrograde pas une version et les réponses périmées ne remplacent pas une lecture plus récente.
  Un refus d’accès vide aussi les références et toutes les données filtrables. Filtres et recherche restent en mémoire
  dans la vue ; aucune préférence ni donnée supplémentaire n’est persistée.
- #229 : chaque ligne et sa fiche portent une référence dérivée de l’UUID existant. Aucun identifiant métier nouveau
  et aucun secret ne sont créés. Les quatre derniers caractères suffisent normalement ; les références qui entrent
  effectivement en collision dans les pages chargées sont allongées avec `HomonymReference`. L’allongement est conservé
  pendant la session même si un homonyme disparaît. Le tri, le filtre et un renouvellement gardent cette référence.
  La découverte d’une collision sur une page ultérieure peut donc allonger sa forme abrégée ; l’UUID complet reste
  permanent, consultable et sélectionnable en fiche. Les confirmations rappellent la référence ; commandes et navigation
  continuent d’utiliser l’UUID complet et la version examinée.
- #230 : une invitation encore en attente affiche une seule ligne d’échéance dans le fuseau de l’école, avec les mêmes
  données et le même format français qu’en fiche. Date ou fuseau indisponible ne reçoit pas de valeur de remplacement.
  Les états acceptée/utilisée, révoquée et expirée confirmés restent prioritaires. À l’échéance, l’état local devient
  « Échéance passée » et rejoint le filtre « Échues » sans prétendre à une transition serveur. La mise à jour est
  programmée au prochain instant d’expiration connu ; le retour au premier plan actualise l’horloge et relit la fenêtre
  déjà chargée. Aucun minuteur ne fait de requête de mutation ni de polling permanent.

## Intégration native

Choix : `searchable`, `Picker` et `NavigationSplitView` existant, sans dépendance supplémentaire. Les composants
`DrivyEntityRow`, `DrivyContactRow`, `DrivyEmptyState`, `DrivyStatusBadge`, les couleurs `DrivyTheme` et les espacements
existants conservent la direction artistique. Référence et échéance sont des métadonnées à retour à la ligne ; les
badges restent réservés aux états inhabituels. La cellule annonce ensemble libellé, rôle, référence, statut et échéance
à VoiceOver. L’identité de la fiche dépend de l’UUID, jamais du rang ou de la forme abrégée de sa référence.

Références relues : `COMMENCER_ICI.md`, F02/R02/R05/R11/R12 et AP10 du parcours invitations, E02/E16/J20–J22/R98,
T175/T190, `g1c-invitations.md`, `native-invitations-design.md`, `api-trajets-codes.md`, modèles/client/tests existants.
Skills utilisés : `ui-skills-root`, `swiftui-ui-patterns`, `swift-native-components` et références adaptation à la DA /
kits et navigation. Les règles d’accès, de stockage chiffré et de reprise des opérations restent celles du workspace.

## Vérification et limites

Exécuté : revue des appels, du diff et `git diff --check`. Neuf tests ciblés **préparés uniquement** couvrent :
recherche sans secret ; frontière d’échéance et priorité des états confirmés ; fuseaux/heure d’hiver/date inconnue ;
collision de références/renouvellement ; recherche sans réseau et pagination manuelle ; actualisation bornée avec
sélection conservée ; mutation vers le bon UUID complet ; perte de droits pendant l’actualisation ; réponse tardive
de pagination d’une ancienne actualisation.

**NOT_EXECUTED** : tests Swift/UI, compilation Apple, interaction iPhone/iPad, Dynamic Type et VoiceOver physique.
Le coordinateur compile l’IPA en fin de vague ; les tests sont différés jusqu’au retour du porteur. Le retour à la
liste, le clavier de recherche, la lecture des longues références et le changement d’échéance au premier plan restent
à vérifier sur cette IPA. Recherche globale côté serveur et preuve d’absence dans les pages non chargées ne sont pas
promises. Les changements distants restent tributaires d’une relecture réussie, signalée en cas d’échec.

Aucun changement API, web, EPIC #311, workflow, dépendance, stockage de secrets ou déploiement. Aucun push, fusion
ou clôture d’issue réalisé par ce lot. Le suivi `STATUS.md` est consolidé par le coordinateur.
