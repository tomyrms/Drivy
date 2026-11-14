# R03 — Application modulaire et offres commerciales

[← Roadmap produit](../ROADMAP.md)

| Maturité | Horizon | Décision de développement |
| --- | --- | --- |
| Cadré | Volet V1 dans R01 | [Epic #452](https://github.com/tomyrms/Drivy/issues/452) |

## Volet retenu le 11 novembre 2026

Le porteur demande la gestion des modules par école dès la première version de son administration. Le suivi est intégré à [l’epic R01 #452](https://github.com/tomyrms/Drivy/issues/452), avec [#455](https://github.com/tomyrms/Drivy/issues/455) pour les offres/droits et [#456](https://github.com/tomyrms/Drivy/issues/456) pour les conditions personnalisées.

Les droits seront contrôlés côté serveur et cohérents entre web et iOS. Messagerie et cours collectifs sont les premiers candidats de catalogue ; les attributions restent configurables et les acquis leçons/GPS sont préservés. Le modèle retenu est un montant initial unique puis une mensualité, avec remises par école. Les prix exacts et extensions de gamme restent à configurer ou préciser.

Le texte de réflexion ci-dessous conserve le contexte des extensions ; ne pas créer une seconde epic pour le volet déjà suivi. Aucun module n’est déclaré livré ou désactivé par cette décision documentaire.

## L'idée

Vendre une application adaptée aux besoins de chaque auto-école : un socle utile, puis des fonctionnalités optionnelles plutôt qu'une offre unique imposant tous les modules.

Une école qui n'utilise pas la messagerie ou les cours collectifs pourrait choisir une offre sans ces fonctions. Une autre pourrait avoir accès à l'ensemble du produit. Le découpage et les prix restent à réfléchir.

## Trois notions différentes

| Notion | Rôle envisagé |
| --- | --- |
| Droits de l'offre | Ce que le contrat de l'école lui permet d'utiliser. |
| Choix de l'école | Ce qu'elle décide d'activer parmi les fonctionnalités disponibles. |
| Permissions utilisateur | Ce que chaque élève, moniteur ou administrateur peut faire. |

Un interrupteur technique de déploiement ne remplace pas les droits commerciaux. Masquer une rubrique de navigation ne suffit pas à rendre une fonctionnalité inaccessible côté serveur.

## Exemples à examiner

La messagerie et les cours collectifs sont les premiers exemples proposés de modules optionnels. Le contenu exact du socle, les autres regroupements, les limites d'usage et les noms des offres ne sont pas fixés.

Cette initiative ne remet pas automatiquement en cause les décisions existantes sur le GPS et les leçons. Elle n'autorise pas à retirer aujourd'hui des fonctionnalités aux écoles pilotes.

## Questions à trancher

Comment faire évoluer l'offre sans perturber une leçon ou un cours déjà engagé ? Que peut-on encore consulter après une baisse de gamme ? Comment traiter l'historique, la réactivation, les exports et la conservation ? Quel comportement pour une ancienne version de l'application ? Comment présenter un module indisponible sans encombrer l'interface de promotions ?

Il reste également à définir la granularité des modules, leur tarification éventuelle et le fonctionnement d'un essai. Aucun quota, prix ou délai de grâce n'est adopté ici.

## Relations avec les autres initiatives

[R01](R01-administration-plateforme.md) administre les droits commerciaux ; [R04](R04-facturation-saas.md) gère les abonnements ; [R05](R05-site-vitrine.md) présente les offres une fois décidées.

## Extensions à cadrer

Définir le socle et les modules retenus, puis les transitions d'offre et le devenir des données. Vérifier leur faisabilité sur l'architecture du moment avant de découper l'implémentation iOS, web et serveur.

**Désactiver un module ne signifie jamais supprimer silencieusement son historique ou ses engagements. Cette fiche ne lance aucune modification du produit.**
