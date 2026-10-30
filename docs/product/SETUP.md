# Activer Drivy — Product Roadmap

## État réel au 30 octobre 2026

- La roadmap est enregistrée dans [ROADMAP.md](ROADMAP.md), sur `docs/product-roadmap-20261030`, sans nouvelles issues pour R01–R05.
- Les dix labels colorés existent. Le classement des 59 issues ouvertes relevées a été complété et relu : 52 ajouts et 7 issues déjà classées. Preuve : [exécution de métadonnées](https://github.com/tomyrms/Drivy/actions/runs/41055279346). Cela n'est ni un audit d'avancement ni une campagne de tests de l'application.
- Le Project GitHub, ses cartes brouillons et ses vues **n'ont pas été créés depuis cette conversation**. Le connecteur disponible ne fournit pas les actions Projects, et aucun terminal authentifié à GitHub n'est disponible ici pour les activer.
- [project.json](project.json) est une configuration, pas un tableau distant déjà opérationnel. [setup_project.py](setup_project.py) est le programme d'activation explicite depuis un terminal autorisé.

## Prérequis

Python 3.10 ou ultérieur et GitHub CLI (`gh`), authentifié sur le compte `tomyrms` avec les permissions de dépôt et `project`. Utiliser l'authentification locale de GitHub CLI ; **ne jamais coller de jeton dans un chat, un fichier suivi ou un journal**.

Documentation : [GitHub CLI Projects](https://cli.github.com/manual/gh_project) et [schéma Projects GraphQL](https://docs.github.com/en/graphql/reference/projects). L'activation passe par ces API, pas par un déploiement du produit.

## Depuis le dépôt local, sans toucher au travail des agents

Créer une copie de travail séparée. Si le dossier cible existe déjà, l'inspecter et réutiliser uniquement la bonne copie ; ne pas le supprimer ni effectuer de reset forcé.

```sh
git fetch origin docs/product-roadmap-20261030
git worktree add --detach ../Drivy-roadmap-setup origin/docs/product-roadmap-20261030
cd ../Drivy-roadmap-setup

gh auth status
# Si le droit project manque, l'accorder via le parcours local de GitHub CLI :
gh auth refresh -s project

# Affiche le plan local, sans aucune requête ni écriture distante :
python docs/product/setup_project.py

# Après lecture du plan, crée/réutilise les métadonnées du Project :
python docs/product/setup_project.py --apply
```

Sous Windows, `py -3` peut remplacer `python` selon l'installation ; vérifier que sa version est au moins 3.10. Le script refuse un compte différent de `tomyrms`. Les erreurs n'affichent ni jeton ni réponse privée complète.

## Ce que fait --apply

1. Recherche le projet utilisateur nommé exactement **Drivy — Product Roadmap** ; réutilise le projet privé ouvert correspondant, ou le crée. Plusieurs correspondances, un projet public/fermé ou une erreur de droits provoquent un arrêt, sans réouverture ou changement de visibilité d'un projet existant.
2. Rattache le dépôt, prépare les sept statuts et les champs Nature, Maturité, Horizon, Priorité, Effort, Début cible et Fin cible. Les options existantes conservent leurs identifiants ; les champs incompatibles ne sont pas écrasés.
3. Ajoute les cinq initiatives en **brouillons propres au Project**, avec leur texte de roadmap et leur marqueur R01–R05. Ne crée aucune issue dans le dépôt, ne démarre aucun développement et ne transforme aucune idée en exigence validée.
4. Rattache les issues existantes ouvertes en excluant le lot annulé #340/#341–346/#348–369 et les PR. Une carte déjà archivée n'est pas réintroduite. Les statuts, dates et priorités saisis par une personne sont conservés ; une carte nouvellement importée va au Backlog, sans prétendre connaître l'avancement de son code.
5. Prépare les vues **Vision produit**, **Développement**, **Backlog** et **Roadmap**. Une vue existante du même nom conserve ses réglages. Les dates ne sont pas inventées ; les cartes terminées ne sont pas masquées par un filtre `is:open`.
6. Relit les cartes et vues et affiche l'URL réelle du projet. Si une opération échoue, les écritures déjà réussies restent visibles : corriger l'erreur puis relancer, sans supprimer le projet ni recréer les cartes à l'aveugle.

Les issues #45 et #63 restent des pistes différées ; leur rattachement ne constitue pas une autorisation de les développer. Les labels ne sont pas modifiés par ce script, ils ont déjà été traités séparément.

## Vérifications finales dans l'interface GitHub

Ouvrir l'URL imprimée après activation. Dans **Développement**, contrôler la disposition Board et le regroupement par **Status** : Backlog, Prêt, En cours, À tester par Tomas, Tests et validation, Bloqué, Terminé. Dans **Roadmap**, sélectionner **Début cible** et **Fin cible** lorsque l'interface le demande. Laisser les dates vides tant qu'elles ne sont pas décidées.

Contrôler la visibilité privée, les cinq brouillons, l'accès au dépôt depuis le projet, les filtres et les éventuelles automatisations par défaut. Ne pas activer de clôture automatique des issues ou marquer un travail validé seulement parce qu'une branche existe. Une vue interrompue après sa création peut nécessiter de corriger son filtre dans GitHub : le script ne remplace volontairement pas les choix d'une vue préexistante.

Il restera à trier l'avancement réel des cartes après examen des branches, PR et preuves : **étiqueté n'est pas développé**, et **issue ouverte n'est pas fonction forcément absente**.

## Vérifications effectuées sur l'outil

Syntaxe Python vérifiée et cinq contrôles locaux réussis avec réponses simulées : extraction d'une initiative, initiative absente, pagination, conservation des options et conservation d'une valeur de statut. **Aucune exécution --apply authentifiée ni qualification d'intégration Projects n'a été effectuée ici.** Ces contrôles locaux ne prouvent pas que les permissions ou toutes les mutations réussiront sur le compte de destination.

Aucun code applicatif, donnée scolaire, secret, migration, test de Drivy ou déploiement homelab modifié par cette préparation. La branche documentaire n'est pas fusionnée automatiquement dans `master` ni dans la refonte active.
