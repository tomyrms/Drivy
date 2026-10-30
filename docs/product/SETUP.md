# Organiser la roadmap et le suivi de Drivy

[← Roadmap produit](ROADMAP.md) · [← README](../../README.md)

Dernière mise à jour : **30 octobre 2026**.

## L'organisation retenue

| Besoin | Référence |
| --- | --- |
| Garder une grande idée sans lancer son développement | [ROADMAP.md](ROADMAP.md) et une fiche dans [`initiatives/`](initiatives). |
| Réfléchir au périmètre, aux limites et aux décisions ouvertes | La fiche de l'initiative, mise à jour au fil des échanges. |
| Suivre un travail autorisé | Une issue existante ou une nouvelle issue après validation du cadrage. |
| Classer les tickets | Labels de type et de zone, sans leur attribuer un avancement fictif. |
| Voir les travaux en colonnes | Le [Kanban du Project privé n°2](https://github.com/users/tomyrms/projects/2), facultatif. |
| Vérifier ce qui a réellement été livré | PR, commits et [suivi d'implémentation](../implementation/STATUS.md). |

**Les fichiers sont la référence de la vision produit. GitHub Projects n'est pas nécessaire pour noter ou modifier une idée.** Il reste disponible comme présentation complémentaire ; aucune suppression du Project ou de ses cartes n'est demandée.

## Ajouter ou faire évoluer une idée

Créer une fiche dans `initiatives/` avec un identifiant stable, une intention, les questions ouvertes, les limites et la prochaine décision utile. Ajouter son lien au tableau de `ROADMAP.md`. Ne pas inventer de date, prix ou architecture pour remplir le document.

Les maturités utilisées sont **Idée → À étudier → Cadré → Prêt à découper → En développement**. Le passage au développement exige une décision du porteur. À ce moment-là seulement, créer l'epic et son découpage, puis ajouter leurs liens à la fiche.

Une fiche n'est pas une issue et n'autorise pas un agent à coder automatiquement. Les IDs de vision R01–R05 ne sont pas les anciens lots de réalisation de #311.

## Labels du dépôt

Les dix labels ont été créés et colorés. Le classement initial des **59 issues ouvertes relevées le 30 octobre** a été complété : 52 ajouts et 7 issues déjà classées. C'est un relevé historique, pas une affirmation du nombre d'issues encore ouvertes aujourd'hui.

Preuves : [application des couleurs](https://github.com/tomyrms/Drivy/actions/runs/41054400220) et [classement du backlog](https://github.com/tomyrms/Drivy/actions/runs/41055279346).

| Label | Usage | Couleur |
| --- | --- | --- |
| `type:bug` | Dysfonctionnement décrit ; reproduction actuelle à vérifier. | Rouge `#D73A4A` |
| `type:feature` | Fonctionnalité à construire ou compléter. | Vert `#0E8A16` |
| `type:ux` | Interface, navigation et expérience utilisateur. | Mauve `#A371F7` |
| `type:refactor` | Organisation du code sans changement fonctionnel visé. | Violet `#5319E7` |
| `type:qa` | Tests, vérifications et qualification. | Jaune `#FBCA04` |
| `type:security` | Sécurité, confidentialité et protections. | Rouge foncé `#B60205` |
| `area:ios` | Application iPhone et iPad. | Bleu `#1D76DB` |
| `area:web` | Portail et web app mobile. | Cobalt `#245BD6` |
| `area:backend` | API, services et données. | Bleu-vert `#006B75` |
| `area:infra` | Infrastructure, CI et exploitation. | Violet foncé `#6F42C1` |

Conserver les labels existants lors d'un ajout. Une issue peut concerner plusieurs zones. Les labels ne prouvent ni sa priorité ni son avancement ; ne pas dupliquer le champ Status du Kanban avec des labels todo/in-progress/done.

## Project existant : état vérifié après activation

**Le Project a été créé et vérifié** : [Drivy — Product Roadmap, n°2](https://github.com/users/tomyrms/projects/2).

Vérification en lecture seule effectuée le 30 octobre 2026 avec GitHub CLI et l'API GraphQL, sur le compte `tomyrms` et avec le périmètre `project`, après exécution de `setup_project.py --apply`. Le tableau ci-dessous reprend les valeurs réellement lues.

| Élément | État vérifié le 30 octobre 2026 |
| --- | --- |
| Projet | Utilisateur `tomyrms`, privé, ouvert et lié à `tomyrms/Drivy`. |
| Idées | Cinq brouillons R01–R05, pas cinq issues de dépôt. |
| Développement | 59 issues ouvertes rattachées ; PR et lot annulé exclus. |
| Champs personnalisés | Nature, Maturité, Horizon, Priorité, Effort, Début cible, Fin cible. |
| Vues | Vision produit, Développement, Backlog et Roadmap ; une vue par défaut « View 1 » subsiste. |
| Kanban | Vue Développement en Board, regroupée par Status. |
| Dates | Aucune date cible saisie. |
| Avancement initial | Les 59 cartes importées sont en Backlog ; ce n'est pas une qualification de leur code. |
| Idées historiques | #45 et #63 ont Maturité=Idée et Horizon=Plus tard. |
| Automatisations | Seul l'ajout automatique des sous-issues est actif ; clôture automatique, Item closed et Pull request merged désactivés. |

Les sept statuts sont **Backlog, Prêt, En cours, À tester par Tomas, Tests et validation, Bloqué, Terminé**.

### Ce qui reste éventuellement à régler dans Projects

Le choix visuel des champs **Début cible / Fin cible** de la chronologie reste à confirmer dans l'interface. Le schéma public de l'API Projects expose les vues et leur regroupement, mais pas le choix des champs de dates d'une chronologie. La vue « View 1 » peut être conservée ou retirée à la demande du porteur. Le tri de l'avancement réel nécessite de lire les branches, PR et preuves ; la présence d'une branche ne signifie pas « En cours » ou « Terminé ».

Aucun de ces réglages ne bloque l'utilisation de la roadmap en fichiers.

## Pas de synchronisation automatique

Une modification de `ROADMAP.md` ou d'une fiche ne déplace pas une carte et ne remplace pas son contenu dans Projects. Inversement, déplacer une carte ne modifie pas les documents.

Le script [`setup_project.py`](setup_project.py) et sa configuration [`project.json`](project.json) sont conservés comme outils optionnels de mise en place. Ils ne constituent pas un service de synchronisation. Ne pas relancer `--apply` simplement pour mettre une idée à jour et ne pas recréer un second projet.

Les sections `## R01 — …` à `## R05 — …` de `ROADMAP.md` restent disponibles pour l'extraction attendue par le script. Le détail des initiatives se lit désormais dans les fiches. Les brouillons existants du Project ne sont pas remplacés par cette réorganisation.

## Maintenance optionnelle depuis un terminal autorisé

Python 3.10 ou ultérieur et GitHub CLI authentifié avec les droits nécessaires sont requis seulement pour ce script, pas pour modifier les documents sur GitHub. Ne jamais coller un jeton dans le chat, un fichier suivi ou un journal.

Depuis une copie de travail propre de la bonne branche :

```sh
gh auth status

# Plan local, sans requête ni écriture distante
python docs/product/setup_project.py

# Uniquement si une intervention sur les métadonnées Projects est décidée
python docs/product/setup_project.py --apply
```

Une absence de droits Projects doit être résolue par le parcours d'autorisation local, pas en copiant un secret. Sous Windows, `py -3` peut remplacer `python` selon l'installation.

Avant de relancer, relire le script, la configuration et l'état distant. Préserver les champs, cartes, vues, dates et priorités déjà modifiés par une personne. En cas d'échec partiel, vérifier les écritures réussies avant reprise plutôt que supprimer et recréer le projet.

## Confidentialité et périmètre

Le Project est privé (vérifié le 30 octobre 2026), mais **le dépôt et ses fichiers sont publics**. Le lien vers un espace privé ne rend pas confidentiel le contenu des fichiers. Ne pas y consigner de secret, donnée d'élève ou stratégie commerciale confidentielle.

Les tickets de finition annulés **#340, #341–#346 et #348–#369** restent exclus. Les idées #45 et #63 ne deviennent pas des développements autorisés du fait de leur classement.

Cette organisation documentaire ne modifie ni le Project, ni les labels, ni les issues, et n'implique aucun déploiement. La roadmap en fichiers est publiée sur `master` ; le Project reste une vue facultative et n'est pas synchronisé automatiquement.
