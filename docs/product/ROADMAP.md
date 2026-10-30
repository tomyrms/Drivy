# Drivy — Roadmap produit

[← Présentation du projet](../../README.md) · [Organisation du suivi](SETUP.md)

Dernière mise à jour : **30 octobre 2026**.

**Conserver les idées aujourd'hui. Créer les issues lorsqu'elles sont prêtes.**

Cette page est la référence de la vision produit. Chaque grande idée possède une fiche dans [`initiatives/`](initiatives). On peut enrichir, déplacer ou abandonner ces idées sans ouvrir d'epic et sans dépendre de GitHub Projects.

Une initiative n'est ni une fonctionnalité livrée, ni un cahier des charges validé, ni une autorisation de développement. Aucun prix, date de livraison, prestataire ou dispositif juridique n'est fixé par cette roadmap.

## Vue d'ensemble

| ID | Initiative | Maturité | Horizon | Prochaine décision utile |
| --- | --- | --- | --- | --- |
| R01 | [Administration de la plateforme](initiatives/R01-administration-plateforme.md) | Idée | À définir | Choisir les opérations indispensables et les métadonnées accessibles. |
| R02 | [Assistance autorisée](initiatives/R02-assistance-autorisee.md) | À étudier | À définir | Cadrer la finalité, les autorisations et les garanties juridiques et de sécurité. |
| R03 | [Modules et offres commerciales](initiatives/R03-modules-et-offres.md) | Idée | À définir | Définir le socle et les fonctions optionnelles, avant les prix. |
| R04 | [Abonnements et facturation SaaS](initiatives/R04-facturation-saas.md) | Idée | À définir | Définir ce que Drivy vend, facture et considère comme payé. |
| R05 | [Site vitrine et commercialisation](initiatives/R05-site-vitrine.md) | Idée | À définir | Définir le public, les preuves et le parcours de demande de démonstration. |
| R06 | [Revue finale de chaque page web](initiatives/R06-revue-finale-web.md) | Idée | Fin du périmètre fonctionnel web | Confirmer la stabilité suffisante, puis revoir chaque page avec Impeccable et Uncodixfy. |
| R07 | [Revue finale de chaque écran Swift](initiatives/R07-revue-finale-swift.md) | Idée | Après R06 validée et stabilisation native | Retrouver le skill personnel « Swift native composant », puis l'utiliser avec Impeccable et Uncodixfy. |

**R01–R07 sont des identifiants de vision produit**, pas des numéros d'issues ni les anciens lots R01–R25 de la refonte #311. R06 et R07 sont des intentions approuvées à conserver pour la fin du chantier, pas des développements à lancer maintenant.

## R01 — Administration de la plateforme Drivy

Un espace réservé à l'exploitant pour gérer les auto-écoles clientes, leurs offres, leurs modules et leur relation commerciale avec Drivy.

À cadrer : opérations minimales, rôles, métadonnées nécessaires, traçabilité et traitement des écoles pilotes ou archivées. L'accès commercial ne donne pas automatiquement accès aux élèves, aux trajets ou aux messages. Le revenu de Drivy reste distinct du chiffre d'affaires propre d'une auto-école.

**Fiche : [Administration de la plateforme](initiatives/R01-administration-plateforme.md).**

## R02 — Accès d'assistance autorisé

Aider une école dans son contexte avec une autorisation explicite, limitée et révocable, sans accès permanent par défaut à ses données.

À étudier avant développement : finalité, personne habilitée, périmètre, durée, journal d'accès, responsabilités, information et cadre applicable. L'accord de l'école ne suffit pas à lui seul à qualifier toute l'opération. Pas d'usurpation invisible ni de contournement du chiffrement de bout en bout.

**Fiche : [Assistance autorisée](initiatives/R02-assistance-autorisee.md).**

## R03 — Application modulaire et offres commerciales

Permettre aux écoles de choisir une offre adaptée à leurs besoins, notamment sans messagerie ou sans cours collectifs lorsqu'elles ne les utilisent pas.

À cadrer : socle, modules, droits commerciaux côté serveur, choix de l'école et permissions des utilisateurs. Définir aussi les effets d'une montée ou baisse de gamme sur les engagements, l'historique et la réactivation. Aucune suppression silencieuse des données et aucun prix adopté ici.

**Fiche : [Modules et offres](initiatives/R03-modules-et-offres.md).**

## R04 — Abonnements et facturation SaaS de Drivy

Gérer les abonnements que les écoles paient à Drivy : factures, règlement confirmé, renouvellement, changement d'offre et incidents.

À cadrer : unité de prix, périodicité, prestataire, essais, taxes à faire vérifier, prorata, résiliation et délais de grâce. Ne pas confondre ce chantier avec les règlements des élèves auprès de leur école ou la finance future #45.

**Fiche : [Facturation SaaS](initiatives/R04-facturation-saas.md).**

## R05 — Site vitrine et commercialisation

Présenter publiquement Drivy, ses usages et les fonctionnalités réellement disponibles, puis permettre à une auto-école de demander une démonstration.

À cadrer : public, langues, contenus, captures autorisées, contact et offres commerciales. Une présentation avec demande de démo peut précéder la facturation automatisée. L'essai gratuit avec quelques vrais élèves reste une hypothèse à étudier, pas une offre déjà décidée.

**Fiche : [Site vitrine](initiatives/R05-site-vitrine.md).**

## R06 — Revue finale de chaque page web

Quand les fonctionnalités du périmètre retenu sont quasiment terminées et stabilisées, revoir chaque page et sous-vue du portail et de la web app mobile avec **Impeccable et Uncodixfy**, tous les deux. Installer les outils manquants au moment du lancement, vérifier leur chargement dans chaque agent et documenter leur usage réel.

Affiner espacements, alignements, hiérarchie, densité, typographie, micro-interactions et compositions trop génériques. Conserver la refonte récente, shadcn, la DA Drivy et les fonctions existantes ; partir de la dernière version effectivement intégrée, pas de l'ancien master ni d'un inventaire figé. Inclure les futures pages de tableau de bord et statistiques lorsqu'elles seront livrées.

**Fiche : [Revue finale web](initiatives/R06-revue-finale-web.md).** Aucune issue créée pour cette intention ; l'ancien lot #340 reste annulé.

## R07 — Revue finale de chaque écran Swift

Après la revue web R06 terminée et validée, et lorsque le périmètre natif est suffisamment stable, appliquer le même travail écran par écran à l'application **Swift/SwiftUI sur iPhone et iPad**.

Utiliser **Impeccable + Uncodixfy + « Swift native composant »**, le skill personnel créé par Tomas. Retrouver le vrai skill et installer/charger ce qui manque au lancement ; ne pas inventer son contenu ni le remplacer par un outil au nom voisin. Adapter les grilles aux conventions Apple, sans transposer des composants web dans le natif.

**Fiche : [Revue finale Swift](initiatives/R07-revue-finale-swift.md).** Aucune issue créée pour cette intention ; pas de lancement en parallèle de la revue web.

## Ordre de réflexion proposé

**Maintenant :** poursuivre et stabiliser le périmètre déjà autorisé. Examiner le code récent, les PR et les preuves avant d'assimiler une issue ouverte à une fonctionnalité absente. Le tableau de bord et les statistiques de l'auto-école ont leur suivi de réalisation dans [l'epic #373](https://github.com/tomyrms/Drivy/issues/373), distinct des idées différées.

**Ensuite, lorsque le porteur décide d'ouvrir ces sujets :** cadrer les modules et les offres (R03), envisager un panneau opérateur minimal (R01) et étudier séparément l'assistance (R02).

**Puis :** concevoir la facturation sur les offres retenues (R04) et préparer la présentation commerciale (R05). Le contenu du site vitrine peut avancer sans attendre un système de paiement complet.

L'ordre commercial R01–R05 est une proposition de dépendances, pas un calendrier approuvé ; leurs horizons restent « À définir ». **Pour la finition globale, l'ordre demandé est explicite : périmètre fonctionnel quasiment terminé → R06 web → validation de R06 → R07 Swift.** Définir le périmètre de la version avec le porteur au lancement, sans attendre indéfiniment toutes les idées à très long terme. Les corrections urgentes de sécurité ou de fonctionnement ne sont pas reportées à ces revues.

## De l'idée à la réalisation

| Maturité | Signification | Issue nécessaire ? |
| --- | --- | --- |
| **Idée** | Intention conservée, avec son contexte. | Non. |
| **À étudier** | Questions produit, technique, juridique ou sécurité à éclaircir. | Non, pas automatiquement. |
| **Cadré** | Objectif, limites et décisions principales documentés. | Pas encore obligatoire. |
| **Prêt à découper** | Le porteur a validé le lancement et le périmètre. | L'epic peut être créée. |
| **En développement** | Les tickets autorisés sont suivis avec leurs preuves. | Oui, avec les liens vers l'epic et les PR. |

Pour ajouter une idée, créer une fiche et une ligne dans le tableau. Décrire l'objectif, les questions ouvertes, les limites et la prochaine décision utile. Ne pas imposer dès maintenant des fichiers à modifier ou une architecture conçue pour un code qui aura évolué.

Pour lancer un sujet, relire la fiche avec le porteur, vérifier l'existant, décider ce qui entre dans le lot, puis créer les issues. Mettre ensuite le lien de l'epic dans la fiche plutôt que dupliquer tous ses tickets dans cette roadmap.

## Sources de vérité et suivi

- **Vision future :** cette roadmap et ses fiches.
- **Travail autorisé :** les [issues du dépôt](https://github.com/tomyrms/Drivy/issues), leurs décisions et les PR.
- **Réalisation et qualification :** le [suivi d'implémentation](../implementation/STATUS.md) et les preuves associées au commit.
- **Kanban facultatif :** le [Project privé n°2](https://github.com/users/tomyrms/projects/2), conservé comme vue de travail. Il n'est pas nécessaire pour lire ou modifier les idées en fichiers.

Le Project et ces fichiers ne sont **pas synchronisés automatiquement**. La création et l'état du Project ont été vérifiés par API le 30 octobre 2026 ; cette organisation documentaire n'en modifie ni les cartes ni les vues. **R06 et R07 sont ajoutées aux fichiers de roadmap uniquement, pas aux brouillons du Project.** Voir [SETUP.md](SETUP.md).

Le dépôt est public : les documents suivis y sont publics également. Garder les secrets, données personnelles et informations commerciales confidentielles dans un espace privé autorisé, pas dans ces fiches.

## Consignes aux agents

Ne pas développer automatiquement les initiatives R01–R07, ni les convertir en issues sans décision du porteur. Les idées historiques [#45](https://github.com/tomyrms/Drivy/issues/45) et [#63](https://github.com/tomyrms/Drivy/issues/63) restent elles aussi différées tant que leur cadrage n'a pas changé.

Ne pas rouvrir le lot de finition annulé **#340, #341–#346 et #348–#369**. R06/R07 conservent la demande de revue globale pour plus tard, sans annuler cette décision ni recréer ses tickets maintenant. Ne pas lancer une nouvelle refonte graphique au prétexte d'organiser la roadmap.

Pour le web, partir de la version récente issue de **#311**, désormais intégrée dans `master` par la [PR #347](https://github.com/tomyrms/Drivy/pull/347). Vérifier le commit réellement utilisé et ses corrections. Cette roadmap n'est pas un audit des fonctionnalités manquantes ni une autorisation de déploiement.
