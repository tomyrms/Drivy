# Qualification finale #84

`validation-finale.yml` est une entrée **manuelle**, sans déploiement, fusion,
activation générale, publication ni clôture d'issue. Elle réutilise les
quatre workflows existants via `workflow_call`. Un seul checkout résout
`candidate_ref`, puis tous les jobs vérifient le même SHA complet. Le SHA du
produit IPA vient de `git rev-parse HEAD`, jamais du SHA du workflow appelant.

## Amorçage sans fusionner les fonctionnalités

Le 23 octobre 2026, le coordinateur a poussé le premier lot CI `5cbc051`, puis
confirmé le refus HTTP 404 du dispatch direct de `validation-finale.yml`, absent
de la branche par défaut. Aucune fusion dans `master` n'est nécessaire avec le
point d'entrée suivant, déjà enregistré dans le dépôt :

```console
gh workflow run refonte-checks.yml --repo tomyrms/Drivy --ref openai/65-messagerie -f final_campaign=true -f candidate_ref=<SHA_COMPLET_DU_CANDIDAT>
```

Commande réservée au coordinateur après commit/push du présent lot bootstrap.
Le candidat doit contenir les scripts de qualification. Pour figer également la
définition CI, remplacer la valeur de `--ref` par le même SHA candidat.

Le workflow historique `refonte-checks.yml` est maintenant un wrapper :
- push/PR et dispatch normal : appel de `qualification-checks.yml` ;
- dispatch avec `final_campaign=true` : appel de `validation-finale.yml` ;
- la finale appelle directement `qualification-checks.yml`, **jamais le wrapper**.

Les trois jobs serveur/web/documentation sont déplacés sans modification dans
`qualification-checks.yml`. Il n'existe ni copie divergente de suites, ni cycle
récursif, ni double campagne API/web pour le lancement final. Les inputs requis,
le graphe sans cycle et la conservation des déclencheurs sont testés dans
`scripts/qualification/test-workflows.mjs`.

Les appels locaux utilisent la définition CI de la référence dispatchée. La
référence candidate est résolue une fois par la finale puis transmise sous forme
de SHA à chaque suite. Aucun changement des protections de branches, aucune
fusion feature et aucun bootstrap dans `master` ne sont effectués. Si des checks
requis se basent sur le nom complet des jobs, leur compatibilité reste à relire,
sans contourner les protections. Le dispatch direct de `validation-finale.yml`
reste possible ultérieurement lorsqu'il aura été intégré normalement dans la
branche par défaut.

Les déclencheurs push/PR existants restent actifs hors branche de travail. Le
motif `openai/**` n'est pas dans leurs push. La finale n'a aucun déclencheur
automatique. Sa concurrence est sérialisée, sans annulation d'une preuve en
cours. Les jobs API, web, documentation, navigateur, Apple, IPA et scripts
restent indépendants. La campagne Apple conserve sa compilation commune aux
deux simulateurs, avec une limite de 90 minutes. L'IPA est un job séparé pour
éviter de la construire deux fois.

## Preuves et échec fermé

- API : typage, build et suite Vitest complète avec PostgreSQL 17 et Mailpit
  isolés. Web : typage, build et suite Vitest complète dans un job indépendant.
- Navigateur : recette synthétique existante OIDC/BFF/API/PostgreSQL, résultat
  `PASSED` et liste de contrôles non vide exigés.
- Apple : `visual_only=false`, `unit_only=false`, `unit_test_scope=all`, sélection
  UI vide. Résultats iPhone **et** iPad obligatoires, avec cibles métier et UI
  effectivement présentes dans chaque arbre xcresult. Le script existant exécute
  toute la cible métier sur iPhone, la présentation et toute l'UI sur iPad.
  `VisualOrientationTests` reste le harnais de capture visuelle paramétré, exclu
  comme auparavant de la suite produit. Il n'est pas présenté comme exécuté.
  Si `MatrixMessagingRelayIntegrationTests.swift` est présent, la campagne
  complète et le mode métier `all` démarrent automatiquement PostgreSQL 17 natif
  et le relais Fastify HTTPS réel. Le mode GPS seul, les UI ciblées et les captures
  ne découvrent pas cette cible et ne démarrent pas ce service.
  Une CA éphémère est ajoutée au trousseau de confiance de chaque simulateur,
  sans désactiver TLS. L'URL loopback est injectée dans `EnvironmentVariables`
  du vrai fichier `.xctestrun`, consommé par `test-without-building -xctestrun`.
  Le parcours relais est également ajouté à l'iPad après remise à zéro des
  seules fixtures jetables. Clés TLS, base, état du relais et journaux serveur
  restent hors artefacts, dans le dossier temporaire nettoyé à la sortie.
  Ce raccord exige une exécution Apple réelle avant toute revendication de
  réussite du test de bout en bout, les tests Python du script ne la remplacent pas.
- Scripts : gardes de preuve, sélection iOS, captures iOS et provisionnement
  synthétique. Celui-ci réutilise `scripts/dev/setup.ts` sur runner GitHub hébergé
  éphémère : PostgreSQL/Keycloak/Mailpit loopback via Compose, Edge pour le
  scénario existant, état temporaire local jamais archivé. Ne pas lancer ce
  bootstrap contre un laboratoire local déjà utilisé. Zéro test ou test ignoré
  fait échouer les contrôles.
- Crypto : job indépendant, Rust 1.99.0 et `cargo test --locked` sur le prototype
  Matrix existant. Au moins quatre scénarios réussis, aucun scénario ignoré ou
  filtré. Cette preuve de primitives n'est pas une preuve du FFI iOS ni de la
  résidence du service. Les cibles bibliothèque/doctests vides ne comptent pas
  comme des scénarios supplémentaires.
- IPA : contrôle existant du paquet appareil non signé, empreintes et métadonnées
  du SHA testé. Une IPA ne prouve pas la réussite des tests.
- Les rapports Vitest archivés ne contiennent que des compteurs/statuts. Les
  messages, valeurs d'assertion et sorties console ne sont pas copiés dans ces
  artefacts. Les autres artefacts restent ceux des suites synthétiques existantes.
- La conclusion attend `success` de chaque job obligatoire. Échec, annulation,
  job ignoré, rapport absent, cible vide ou test ignoré ne peuvent produire une
  qualification automatisée positive. Aucun `continue-on-error` n'est ajouté.

## Vérification locale des outils, pas du produit Apple

### IPA pour recette physique de Messages

L'accès physique est compilé uniquement sur demande explicite, sans fixture de
conversation ni simulation de réussite. Il ne nécessite pas d'avoir déjà achevé
la recette VoiceOver physique, précisément destinée à cette IPA. Exemple réservé
au coordinateur :

```console
gh workflow run ipa-essai.yml --repo tomyrms/Drivy --ref <SHA_CANDIDAT> -f messaging_qualification=true
```

Pour tester et construire ce même mode dans la campagne finale, ajouter
`-f messaging_qualification=true` au dispatch du wrapper. La valeur est propagée
aux compilations simulateur et IPA via le même script, sans activer ce mode sur
les push ordinaires. `build-info.json` conserve
`messagingQualificationBuildRequested`, `messagingGeneralQualification=NOT_CLAIMED`
et `physicalQualification=NOT_EXECUTED`. Aucune configuration ou mise en ligne
du service n'en découle.

### Tests des scripts

```console
python -B scripts/qualification/run-python-tests.py
node --test --import tsx --test-reporter=tap scripts/dev/provision-school.test.mjs
```

Le second exige `npm ci`, `npm ci --prefix infra/dev --ignore-scripts`, le
laboratoire synthétique PostgreSQL/Keycloak préparé par `scripts/dev/setup.ts`
et Edge installé par Playwright. Sans ce laboratoire, le résultat est bloqué,
pas un succès de test unitaire. Sur Windows, utiliser Git Bash dans `PATH`
plutôt que le lanceur WSL si WSL est absent.

## Limites qui restent des blocages de recette

Le workflow orchestre les tests présents, il n'invente pas les scénarios des
issues. Le coordinateur doit relier la matrice figée aux preuves du dernier SHA
et vérifier les critères absents. En particulier, au 23 octobre 2026, la vague
cours sur `vague/cours-collectifs` n'était pas intégrée dans le candidat messagerie.
Un vert sur ce candidat ne clôture donc pas la recette globale #83/#84.

Le run Apple initial `40031925552`, API/web `40031983397` et navigateur
`40031985954` sur `e2657c4` sont des diagnostics antérieurs à ces modifications,
pas des preuves de cette orchestration. Le premier dispatch de celle-ci reste à
exécuter par le coordinateur. GPS réel, autonomie, VoiceOver physique, réception
réelle et preuves opérationnelles/hébergement restent distincts et ne sont pas
qualifiés par ces simulateurs. L'activation de la messagerie après les tests
reste une décision d'intégration séparée, jamais une action de ce workflow.
