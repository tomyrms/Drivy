<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="apps/ios/Drivy/Resources/Assets.xcassets/DrivyBrand.imageset/DrivyBrand-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="apps/ios/Drivy/Resources/Assets.xcassets/DrivyBrand.imageset/DrivyBrand.svg">
    <img src="apps/ios/Drivy/Resources/Assets.xcassets/DrivyBrand.imageset/DrivyBrand.svg" alt="Logo Drivy : la trace et son repère" width="112" height="112">
  </picture>
  <h1>Drivy</h1>
  <p><strong>La leçon au centre. Le suivi au même endroit.</strong></p>
  <p>Une application native iPhone et iPad pour le terrain.<br>Un portail web pour organiser l'auto-école, sur ordinateur comme sur mobile.</p>
  <p>
    <a href="#le-produit">Le produit</a> ·
    <a href="#refonte-du-portail-web">Refonte web</a> ·
    <a href="#développement">Développement</a> ·
    <a href="docs/product/ROADMAP.md">Roadmap</a> ·
    <a href="#documentation">Documentation</a>
  </p>
</div>

---

**Drivy accompagne le suivi pédagogique des auto-écoles suisses**, de la préparation d'un rendez-vous aux observations de conduite et au bilan de l'élève. Les usages du moniteur, de l'élève et de l'administration partagent les mêmes données, sans imposer la même interface à tous.

> **Projet en développement.** Ce README décrit le dépôt et son produit, pas une certification de disponibilité en production. Les livraisons, résultats de tests et limites sont consignés dans le [suivi d'implémentation](docs/implementation/STATUS.md). La refonte du portail web a été intégrée à la branche par défaut par la [PR #347](https://github.com/tomyrms/Drivy/pull/347), à partir de `85482ee1` ; l'état vérifiable se lit dans le [suivi d'implémentation](docs/implementation/STATUS.md).

## Le produit

| Pour le moniteur | Pour l'élève | Pour l'auto-école |
| --- | --- | --- |
| Préparer la journée, conduire la leçon, relever les observations et rédiger le bilan. | Retrouver ses rendez-vous, ses bilans et sa progression. | Organiser les élèves, l'équipe, les formations, les tarifs et le planning. |
| Une interface native iPhone/iPad adaptée au terrain. | Un parcours personnel dans l'application. | Un portail web distinct, adapté aux tâches de gestion. |

### Les parcours au cœur de Drivy

- **Agenda et leçons** — planning, disponibilités, préparation et suivi du rendez-vous, avec une distinction entre une demande et sa confirmation.
- **Trajet et observations** — capture GPS dans l'application native, signalements pendant la leçon et relecture du trajet, dans le cadre des autorisations applicables.
- **Bilans et progression** — évaluations, objectifs et historique de formation ; les contenus gardés privés par le moniteur restent distincts des informations accessibles à l'élève.
- **Dossiers et équipe** — formations par permis, affectations pédagogiques, invitations, rôles et accès à l'école.
- **Cours collectifs** — séries et séances, inscriptions, attente, appel et suivi des règlements sur place ; présence, paiement et accomplissement sont des faits séparés.
- **Messagerie native** — conversations de l'école et échanges autorisés, avec un fil intégré via Exyte Chat. L'activation et la qualification du service se suivent séparément dans la documentation.

Le portail web n'est pas un client de capture GPS. L'application native et le web se complètent ; ils ne sont pas deux copies du même écran.

Ces parcours décrivent le périmètre fonctionnel travaillé dans le dépôt ; tous ne sont pas qualifiés sur la branche par défaut. Le [suivi d'implémentation](docs/implementation/STATUS.md) et les PR indiquent ce qui est réellement disponible et testé.

## Refonte du portail web

La refonte [#311](https://github.com/tomyrms/Drivy/issues/311) renouvelle la présentation du portail : **shadcn/ui avec Base UI**, une composition inspirée de **Cal.com et Untitled UI**, et l'identité Drivy — cobalt, Manrope et thème sombre Soft Charcoal. Elle a été intégrée à la branche par défaut par la [PR #347](https://github.com/tomyrms/Drivy/pull/347). Le portail vit sous `apps/web/client/portal` ; l'ancien client (`App.tsx`, `console/*`, `styles.css`) est retiré.

Un aperçu isolé, alimenté par des **données synthétiques**, existe dans le portail (`apps/web/preview-311.html`). Il ne remplace ni une session authentifiée, ni les droits serveur, ni les données d'une école. Les choix visuels et les limites de cette refonte sont décrits dans la [direction artistique](DESIGN.md) et le [guide web/BFF](apps/web/README.md).

## Architecture

| Composant | Technologies et rôle | Sources |
| --- | --- | --- |
| **Application native** | Swift 6, SwiftUI ; interfaces iPhone/iPad, leçons, GPS, bilans et messagerie. SQLCipher pour le stockage local concerné. | [`apps/ios`](apps/ios) |
| **Portail et BFF** | React, TypeScript, Vite et Base UI ; serveur Fastify de même origine pour la session web. La refonte #311, intégrée par la PR #347, a introduit shadcn/ui et Tailwind CSS ; le portail vit dans `apps/web/client/portal`. | [`apps/web`](apps/web) |
| **API métier** | TypeScript, Fastify et PostgreSQL ; droits scolaires, contrats, versions et commandes idempotentes. | [`apps/api`](apps/api) |
| **Identité et exploitation** | OpenID Connect avec Keycloak ; configurations locales, déploiement et outils de construction. | [`infra`](infra) · [`scripts`](scripts) |

Les permissions sont contrôlées par le serveur, pas seulement par les boutons affichés. Une mise à jour locale de l'interface ne doit pas annoncer comme acquis une réservation, un droit ou un règlement encore non confirmé.

### Organisation du dépôt

```text
apps/
  ios/                 Application native, projet XcodeGen et tests Apple
  web/                 Client web, composants et serveur BFF
  api/                 API métier et persistance
infra/                 Environnements et configuration d'exploitation
scripts/               Développement, builds et déploiement
docs/
  implementation/      Décisions, livraisons et état vérifiable
  qa/                  Rapports et qualification
  product/             Roadmap, fiches d'idées et organisation du suivi
```

La [conception de référence](Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md) est conservée séparément. Les décisions plus récentes et leur réalisation se trouvent dans `docs/implementation`.

## Développement

### Choisir la bonne base

Avant de travailler, vérifier la branche, son commit et les PR actives. Ne pas repartir automatiquement d'un ancien `master` si la fonctionnalité étudiée a évolué ailleurs. La refonte web est intégrée dans `master` depuis la [PR #347](https://github.com/tomyrms/Drivy/pull/347) (`85482ee1`) ; vérifier l'état réel du dépôt avant de repartir d'une branche ancienne.

Lire d'abord [AGENTS.md](AGENTS.md) et [DESIGN.md](DESIGN.md). Conserver les travaux des autres agents et utiliser une branche ou un worktree séparé.

### API et web

**Prérequis :** Git, Node.js **24.x**, npm ; Docker et un environnement local d'identité pour les parcours authentifiés.

```sh
# À la racine : dépendances de l'API
npm ci

# PostgreSQL local pour le développement et les tests (port 55432)
docker compose up -d --wait postgres

# Le web possède son propre lockfile
npm ci --prefix apps/web

# Typage et construction, sans lancer les suites de tests
npm run typecheck
npm run build
npm run typecheck --prefix apps/web
npm run build --prefix apps/web
```

**Attention : les scripts npm de la racine ne construisent pas le web.** Ses commandes doivent être lancées explicitement avec `--prefix apps/web`.

Pour les parcours réels avec connexion, suivre le [guide d'identité locale](docs/implementation/dev-identity.md), le [guide API](apps/api/README.md) et le [guide web/BFF](apps/web/README.md). Ils précisent PostgreSQL, Keycloak, les migrations et les variables de configuration. La construction seule ne crée ni compte ni école et ne configure pas ces services.

### iPhone et iPad

La configuration Apple est déclarée dans [`apps/ios/project.yml`](apps/ios/project.yml) et générée avec XcodeGen. La cible d'essai actuellement déclarée est **iOS/iPadOS 26.0** ; elle ne constitue pas un engagement sur le minimum commercial.

Sur un Mac avec Xcode et XcodeGen compatibles :

```sh
cd apps/ios
xcodegen generate
open Drivy.xcodeproj
```

Les paramètres d'identité et d'API doivent correspondre à l'environnement autorisé. Les commandes de construction de référence se trouvent dans [`scripts/ios/build-ipa.sh`](scripts/ios/build-ipa.sh).

Pour les essais sur appareil, le workflow [**IPA d'essai · iLoader**](https://github.com/tomyrms/Drivy/actions/workflows/ipa-essai.yml) produit le paquet lié au commit choisi. La signature et l'installation sont réalisées par le porteur avec iLoader. Vérifier la branche, le SHA et la disponibilité de l'artefact avant installation.

### Vérifications et livraison

Une compilation réussie ne vaut pas validation fonctionnelle. Le flux de travail distingue **implémentation → build ou IPA → essai utilisateur → tests pertinents et revue → intégration**. Les contrôles indispensables de sécurité et les protections du dépôt restent en place.

<details>
<summary>Commandes de tests et précautions</summary>

```sh
# API : tests ne nécessitant pas de base
npm run test:unit

# API : suite avec la base de test configurée
npm test

# Web : suite propre au client et au serveur BFF
npm test --prefix apps/web
```

La suite PostgreSQL doit utiliser **une base dédiée aux tests**, selon le [guide API](apps/api/README.md). Ne jamais la pointer vers une base d'école ou de production. Les contrôles de fixtures peuvent modifier ou vider les données de test.

Les tests Apple et la campagne intégrée sont décrits dans [les workflows](.github/workflows) et le [suivi de qualification](docs/qa). Distinguer tests automatisés, essais sur appareil, contrôles non exécutés et résultats associés à un ancien commit. Ni la génération de l'IPA ni un aperçu synthétique ne remplacent ces preuves.

</details>

## Roadmap

**Les grandes idées sont conservées dans les fichiers du dépôt, sans créer d'issues avant leur cadrage.** La [roadmap produit](docs/product/ROADMAP.md) est la référence de ces initiatives ; leur présence ne lance pas de développement.

| Initiative future | Sujet à cadrer |
| --- | --- |
| [R01 — Administration de la plateforme](docs/product/initiatives/R01-administration-plateforme.md) | Gérer les écoles clientes et leur relation avec Drivy. |
| [R02 — Assistance autorisée](docs/product/initiatives/R02-assistance-autorisee.md) | Étudier un accès temporaire, limité et traçable avec le cadre approprié. |
| [R03 — Modules et offres](docs/product/initiatives/R03-modules-et-offres.md) | Adapter les fonctionnalités disponibles aux besoins des écoles. |
| [R04 — Facturation SaaS](docs/product/initiatives/R04-facturation-saas.md) | Gérer les abonnements que les écoles paient à Drivy. |
| [R05 — Site vitrine](docs/product/initiatives/R05-site-vitrine.md) | Présenter le produit et préparer sa commercialisation. |

Ces initiatives sont exploratoires : pas de dates, de prix ou de prestataire décidés. Lorsqu'un sujet est cadré et validé, il peut devenir une epic avec des issues de réalisation. Les [issues existantes](https://github.com/tomyrms/Drivy/issues) restent le suivi du travail déjà décidé.

## Documentation

| Je cherche… | Point d'entrée |
| --- | --- |
| L'état des réalisations et les limites connues | [Suivi d'implémentation](docs/implementation/STATUS.md) |
| La vision et les idées futures | [Roadmap produit](docs/product/ROADMAP.md) |
| Le fonctionnement du suivi, des labels et du Kanban facultatif | [Organisation du projet](docs/product/SETUP.md) |
| Les parcours et contrats de conception | [Commencer ici](Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md) |
| Les composants et règles visuelles | [Direction artistique](DESIGN.md) |
| L'API, l'environnement et la persistance | [Guide API](apps/api/README.md) |
| Le portail et les sessions navigateur | [Guide web/BFF](apps/web/README.md) |
| Les règles de contribution des agents | [AGENTS.md](AGENTS.md) |

## Contribuer sans perdre le contexte

Travailler sur une issue autorisée ou un périmètre convenu, conserver les décisions produit et documenter ce qui a réellement été livré. Une idée de roadmap n'est pas une tâche à coder automatiquement. Un ticket fermé ou un build vert ne suffisent pas à certifier tous les parcours.

Ne publier aucun secret, jeton, donnée d'élève ou position GPS dans le code, les captures ou les artefacts. Pour les démonstrations, utiliser des données synthétiques. Tout changement d'infrastructure doit conserver son cadre d'autorisation, ses sauvegardes et son retour arrière.

---

<p align="center"><strong>Drivy</strong><br>Le terrain dans l'application. L'organisation dans le portail.</p>
