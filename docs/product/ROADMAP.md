# Drivy — Product Roadmap

Dernière mise à jour : 30 octobre 2026.

## Mandat et statut

Cette roadmap conserve les grandes idées du porteur **sans créer immédiatement d'epic ni d'issues de développement**. Une initiative n'est ni une fonctionnalité livrée, ni une décision d'architecture validée, ni une autorisation de commencer à coder.

Les cinq initiatives ci-dessous sont exploratoires. Aucun prix, date de livraison, prestataire de paiement, mécanisme juridique ou accès aux données n'est arrêté par ce document. Les questions ouvertes seront traitées au moment du cadrage.

**Aux agents :** travailler sur les issues effectivement ouvertes et autorisées. Ne pas transformer automatiquement les initiatives de cette page en tâches, ne pas réouvrir le lot annulé #340 / #341–#346 / #348–#369 et ne pas lancer une nouvelle refonte graphique.

Pour examiner le produit actuel, retrouver le code réellement intégré et déployé. Au relevé du 30 octobre, la PR #347 est ouverte : `codex/epic-311-rebuild` à `85482ee1a80483a776eb16022f9ef5e8e6f3ced6`, base `master` à `c94ec2bba979874c7539e960a2ec5c617ec1955d`. Ces SHA sont historiques, pas des versions à restaurer. Ne pas auditer l'ancien master en ignorant la refonte #311. Ce document ne constitue pas un nouvel audit des fonctionnalités manquantes.

## Vision produit : cinq initiatives à garder, pas cinq epics à lancer

| ID | Initiative | Maturité initiale | Horizon | Prochaine décision utile |
| --- | --- | --- | --- | --- |
| R01 | Administration de la plateforme Drivy | Idée | À définir | Définir les opérations minimales de gestion des écoles et les métadonnées accessibles |
| R02 | Accès d'assistance autorisé par une école | À étudier | À définir | Cadrer finalités, autorisations, périmètre juridique et sécurité avant tout accès |
| R03 | Application modulaire et offres commerciales | Idée | À définir | Choisir le socle et les modules optionnels sans fixer encore les prix |
| R04 | Abonnements et facturation SaaS de Drivy | Idée | À définir | Définir ce qui est vendu, facturé et considéré comme payé |
| R05 | Site vitrine et commercialisation | Idée | À définir | Définir le public, les promesses démontrables et le parcours de demande de démo |

Les IDs R01–R05 sont des identifiants de vision produit, pas les anciens tickets R01–R25 de l'epic frontend #311. Aucun numéro d'issue n'est attribué aux cinq initiatives.

## R01 — Administration de la plateforme Drivy

**Intention.** Un espace réservé à l'exploitant de Drivy pour retrouver les auto-écoles clientes et administrer la relation commerciale, distinct du portail d'administration de chaque école.

**Périmètre à explorer.** Répertoire des écoles, état du compte client, interlocuteurs autorisés, offre souscrite, modules disponibles, échéances et état des paiements de l'abonnement. Des indicateurs utiles peuvent être envisagés lorsqu'ils ont une finalité définie et une source fiable ; aucune collecte supplémentaire n'est décidée ici.

**Décisions ouvertes.** Quels rôles pour l'équipe Drivy ? Quelles opérations nécessitent une confirmation renforcée ? Quelles métadonnées sont réellement utiles ? Comment traiter une école pilote, archivée ou en litige ? Où tracer les actions de l'opérateur ? Quel périmètre minimal peut fonctionner avant la facturation automatisée ?

**Limites.** Voir une école cliente ne signifie pas accéder à ses élèves, trajets, notes ou messages. R02 traite séparément l'assistance. Distinguer le revenu mensuel de Drivy et le chiffre d'affaires propre de l'école ; ce dernier n'est ni une donnée automatiquement disponible ni une métrique autorisée par cette roadmap.

**Relations.** Réutiliser les notions d'école et d'opérateur déjà présentes après vérification du code. R03 fournit les droits aux modules ; R04 fournit les états commerciaux. Un panneau minimal peut précéder leur version complète.

## R02 — Accès d'assistance autorisé par une école

**Intention.** Aider une école à résoudre un problème dans son contexte sans donner par défaut un accès permanent à ses données à l'opérateur Drivy.

**Périmètre à étudier.** Demande d'assistance explicite, personne habilitée à l'approuver, périmètre minimal, durée limitée, révocation, traçabilité visible et actions permises. Une consultation en lecture seule serait un point de départ à évaluer, pas une décision d'implémentation définitive.

**Questions préalables.** Finalité exacte ; répartition des responsabilités ; information des personnes concernées ; cadre contractuel et juridique applicable ; preuve et conservation des autorisations ; actions interdites ; données masquées ; comportement hors connexion et après révocation ; traitement des incidents.

**Limites.** L'accord d'un administrateur scolaire n'est pas présenté comme une garantie juridique suffisante à lui seul. Ne pas créer de porte dérobée ni de contournement du chiffrement de bout en bout. Distinguer accès d'assistance, usurpation de session et action réellement effectuée par l'élève ou le moniteur. Aucun accès réel n'est autorisé par cette initiative.

**Condition de passage au développement.** Décisions produit, juridique et sécurité explicites, puis seulement découpage en epic et critères vérifiables.

## R03 — Application modulaire et offres commerciales

**Intention.** Permettre à une école d'utiliser une offre adaptée à ses besoins et à son budget, sans lui imposer toutes les fonctions.

**Exemples à examiner.** Messagerie et cours collectifs comme modules optionnels. Le contenu du socle, les autres regroupements, les noms des offres, les prix et les limites ne sont pas encore décidés. Cette piste ne réintroduit pas automatiquement un mode de séance sans GPS et ne modifie pas les décisions existantes sur les leçons.

**Distinctions nécessaires.** (1) Ce que le contrat de l'école donne le droit d'utiliser ; (2) ce que l'école choisit d'activer parmi ces fonctions ; (3) ce que le rôle de chaque utilisateur lui permet de faire. Un interrupteur de lancement technique n'est pas, à lui seul, un droit commercial.

**Questions ouvertes.** Granularité des modules ; droits serveur et clients iOS/web ; essais ; montée ou baisse de gamme ; effet sur les cours et réservations en cours ; lecture des historiques ; réactivation ; délais de conservation ; export ; anciens clients mobiles ; information des utilisateurs.

**Limites.** Cacher une entrée de navigation ne suffit pas à contrôler un accès. Désactiver un module ne doit pas supprimer silencieusement les données ni les engagements existants. Aucune règle de suppression ou suspension automatique n'est arrêtée ici.

## R04 — Abonnements et facturation SaaS de Drivy

**Intention.** Gérer ce que les auto-écoles paient à Drivy : offre, abonnement, factures, règlement, renouvellement et changement de plan.

**Périmètre à examiner.** Périodicité mensuelle/annuelle, essais éventuels, statut fiable des paiements, facture et avoir, renouvellement, annulation, incident de paiement et rapprochement des événements du prestataire retenu. Aucun fournisseur n'est sélectionné.

**Questions ouvertes.** Unité de prix (école, moniteur, modules ou autre), monnaie et taxes à faire vérifier, délais de grâce, prorata, période d'essai, litiges/remboursements, conséquences d'un impayé, conservation des documents et droits aux modules pendant les transitions.

**Limites.** Un retour de page de paiement ne prouve pas un paiement reçu. Ne pas retirer brutalement l'accès aux données ou aux leçons à cause d'un événement non confirmé. La facturation SaaS de Drivy est distincte des règlements que l'école reçoit de ses élèves et du chantier historique #45.

**Relations.** R03 cadre ce qui est vendu ; R01 consulte et administre les états ; R05 présente les offres une fois validées. Les indicateurs de revenu doivent reposer sur les faits disponibles, pas sur des compteurs de démonstration.

## R05 — Site vitrine et commercialisation

**Intention.** Un site public qui présente Drivy et permet à une auto-école intéressée de comprendre l'offre puis de demander une démonstration.

**Périmètre à examiner.** Présentation du produit, bénéfices démontrables pour les moniteurs et écoles, fonctionnalités réellement disponibles, captures autorisées, questions fréquentes, contact/démo et offres une fois cadrées. Identité visuelle cohérente avec Drivy, mais parcours distinct du portail métier.

**Questions ouvertes.** Public initial, langues, domaine et navigation, contenu et preuves, forme du contact, tarifs publics ou sur demande, responsabilité de mise à jour, accessibilité, données du formulaire et mesure d'audience proportionnée.

**Limites.** Pas de témoignages inventés, promesses réglementaires non vérifiées ou fonctionnalités futures annoncées comme disponibles. Un essai gratuit avec deux ou trois vrais élèves et une durée indicative d'une semaine reste une hypothèse ultérieure, pas un engagement commercial adopté.

**Relations.** Une présentation et une demande de démo peuvent précéder R04. Les prix, comparaisons d'offres et paiement autonome attendent les décisions R03/R04. L'essai réel nécessite un cadrage distinct des accès, de l'accompagnement et de la fin d'essai.

## Ordre de réflexion proposé, pas calendrier imposé

1. Préserver et stabiliser le produit actuel ; vérifier les issues existantes contre le code et les preuves, sans considérer une issue ouverte comme une fonction forcément absente.
2. Cadrer R03 (socle et modules) en parallèle d'un R01 minimal et de l'étude R02.
3. Concevoir R04 sur les offres réellement retenues ; préparer le contenu R05 sans attendre un paiement automatisé pour proposer une démo.
4. Étendre seulement après décision et essai : panneau complet, vente autonome, assistance autorisée, éventuellement essai gratuit.

Aucune date n'est inventée pour remplir une frise. Aucun de ces points n'autorise un agent à développer toutes les idées sans validation.

## Organisation cible dans GitHub Projects

Nom : **Drivy — Product Roadmap**. Projet privé recommandé ; la documentation de ce dépôt reste soumise à la visibilité actuelle du dépôt.

| Vue | Présentation | Contenu |
| --- | --- | --- |
| Vision produit | Tableau | Les cinq initiatives en brouillon ; maturité, horizon, décisions ouvertes |
| Développement | Kanban | Les issues existantes et autorisées, regroupées par Status |
| Backlog | Tableau | Les issues existantes à trier, avec labels, priorité et effort quand connus |
| Roadmap | Chronologie | Initiatives ; dates cibles seulement lorsqu'elles sont réellement décidées |

**Champs.** Nature (Initiative / Issue), Maturité (Idée / À étudier / Cadré / Prêt à découper / En développement), Horizon (Maintenant / Ensuite / Plus tard / À définir), Priorité (P0 / P1 / P2 / P3), Effort (XS / S / M / L / XL / À estimer), Début cible et Fin cible. Laisser priorité, effort et dates non déterminés plutôt que les inventer.

**Status pour le Kanban.** Backlog → Prêt → En cours → À tester par Tomas → Tests et validation → Terminé ; Bloqué lorsqu'une dépendance empêche réellement d'avancer. Le statut d'une carte ne doit pas être déduit de la simple présence d'une branche.

**Règles.** Une initiative reste un brouillon Projects, pas une issue du dépôt. Sa maturité ne remplace pas l'état de développement. La transition « Prêt à découper » requiert l'accord du porteur et un cadrage suffisant. Convertir ensuite seulement en epic avec périmètre, dépendances et critères ; éviter les doublons existants. Les issues annulées ne sont pas importées dans le backlog actif.

**Flux de livraison.** Agent : petit lot cohérent, branche isolée, build et contrôles indispensables, IPA si iOS ou aperçu si web. Tomas essaie ; les tests pertinents, la revue et la fusion suivent selon le mandat. Un build ou une validation visuelle ne suffit pas à fermer une issue dont d'autres critères restent manquants. Déploiement homelab sur autorisation distincte ; aucune automatisation ne doit marquer tout travail fusionné « Terminé » sans vérifier ce flux.

## Labels du dépôt

Les labels indiquent le type et la zone, pas le statut du Kanban. Conserver les labels existants lors de l'ajout. Ne pas ajouter de labels todo/in-progress/done qui dupliqueraient Status.

| Label | Sens |
| --- | --- |
| type:bug | Correction d'un dysfonctionnement décrit ; sa reproduction actuelle reste à vérifier |
| type:feature | Fonctionnalité à construire ou compléter |
| type:ux | Interface, navigation et expérience utilisateur |
| type:refactor | Organisation ou simplification du code sans changement fonctionnel visé |
| type:qa | Tests et qualification |
| type:security | Sécurité, confidentialité et protections |
| area:ios | Application iPhone/iPad |
| area:web | Portail et web app |
| area:backend | API, services et données |
| area:infra | Infrastructure, CI et exploitation |

Une issue peut concerner plusieurs zones. Les labels ne certifient pas son avancement ni sa priorité. Les brouillons Projects utilisent les champs personnalisés ; les labels du dépôt s'appliquent aux issues lorsqu'elles existent.

## Mise en place et limites

Cette documentation et le manifeste voisin `project.json` conservent la vision sans nouvelles issues. Le script `setup_project.py` prépare l'activation du projet via GitHub CLI depuis un environnement authentifié disposant des droits Projects : exécuter d'abord sans `--apply` pour voir le plan.

La publication de ces fichiers **ne signifie pas que le Project, ses brouillons ou ses vues sont créés**. Leur création distante doit être confirmée par les réponses GitHub et une relecture. Le connecteur utilisé pour rédiger cette roadmap ne fournit pas les mutations Projects. Ne pas demander à l'utilisateur de coller un jeton dans la conversation.

Les paramètres visuels non exposés par l'API (notamment le choix du regroupement et des champs de dates selon la version) doivent être vérifiés dans l'interface du Project. Aucun déploiement du produit n'est nécessaire pour cette organisation.

### Références de fonctionnement GitHub

- https://docs.github.com/en/issues/planning-and-tracking-with-projects/creating-projects/creating-a-project
- https://docs.github.com/en/graphql/reference/projects
- https://cli.github.com/manual/gh_project

Les besoins produit proviennent des décisions et idées du porteur ; ces références décrivent GitHub, pas une validation juridique ou commerciale de Drivy.
