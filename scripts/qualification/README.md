# Qualification finale #84

`validation-finale.yml` est une entrée **manuelle**, sans déploiement, fusion,
activation fonctionnelle, publication ni clôture d'issue. Elle réutilise les
quatre workflows existants via `workflow_call`. Un seul checkout résout
`candidate_ref`, puis tous les jobs vérifient le même SHA complet. Le SHA du
produit IPA vient de `git rev-parse HEAD`, jamais du SHA du workflow appelant.

## Amorçage sans fusionner les fonctionnalités

Inspection distante du 23 octobre 2026 : `master` ne contenait que
`ipa-essai.yml`, `refonte-checks.yml`, `refonte-ios.yml` et
`school-opening-e2e.yml`. Le nouveau workflow doit être présent sur la branche
par défaut avant son premier dispatch.

1. Faire relire puis intégrer une **PR CI seulement** sur `master`, avec les
   cinq workflows, `scripts/qualification/` et le correctif de SHA dans
   `scripts/ios/build-ipa.sh`. Aucun fichier applicatif de la branche messagerie
   ni historique de l'ancien dépôt n'est nécessaire.
2. Reporter ces mêmes changements CI dans le candidat de travail et figer son
   SHA. Le candidat doit contenir les scripts de qualification. Une référence
   ancienne sans ces scripts échoue explicitement.
3. Le coordinateur choisit le workflow depuis la référence portant sa définition
   relue. Les appels réutilisables locaux utilisent cette même définition CI.
   Exemple à exécuter **uniquement sur décision du coordinateur** :

   ```console
   gh workflow run validation-finale.yml --repo tomyrms/Drivy --ref master -f candidate_ref=<SHA_COMPLET_DU_CANDIDAT>
   ```

   Pour qualifier également une nouvelle définition CI de la branche de travail,
   utiliser son SHA dans `--ref` et `candidate_ref`, après l'amorçage sur `master`.
   Ne jamais considérer le vert obtenu avec une autre définition CI comme sa
   qualification. Aucun contournement des protections de branche n'est requis.

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
