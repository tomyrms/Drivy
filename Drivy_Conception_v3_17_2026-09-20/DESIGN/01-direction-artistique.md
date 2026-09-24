# Direction A · Cartographie native

> **Choix utilisateur accepté** · Détails visuels proposés · [Accueil design](README.md).

## Promesse visuelle

**Le trajet devient le support de l’explication.** Une interface lumineuse, une carte fonctionnelle, un bleu franc et une hiérarchie de texte précise. L’identité vient de la relation entre séance, moment observé et prochaine étape, pas de fonds routiers décoratifs. La direction vaut pour le moniteur comme pour l’élève, mais la densité dépend de la tâche.

La décision remplace la recommandation « Carnet cartographique » ivoire/pétrole. Les principes utiles de celle-ci (trajet et récit, alternative sans GPS) sont conservés. L’ancien nom n’est pas une quatrième option active. [Historique des pistes](../02-experience/directions-artistiques.md).

## Les cinq règles d’expression

**Une zone de décision dominante.** Préparation : commencer la bonne séance. Capture : signaler un moment tout en connaissant l’état et en gardant un accès explicite à l’arrêt. Replay : revoir une observation. Cours : comprendre toutes les dates avant inscription. Web : trouver le dossier et agir sous les bons droits.

**Bleu intentionnel.** Le bleu signale l’action, la sélection et la trace par des rôles distincts. Il ne colore pas toutes les icônes, tous les titres et toutes les surfaces simultanément. Une limite de places ou un refus GPS n’est pas transformé en alerte rouge sans raison.

**Surfaces calmes.** Fond gris très clair, panneaux blancs, encre sombre. Les contenus longs, coordonnées, formulaires et montants reposent sur une surface opaque. Une ombre n’est utilisée que pour exprimer une superposition. Les listes n’ont pas chacune besoin d’une carte arrondie.

**Le texte utile, pas le texte accumulé.** Titres alignés à gauche, corps de lecture ample, labels permanents, montants alignés. Aucune phrase promotionnelle n’occupe la place du prochain rendez-vous. Les états vides expliquent le prochain geste sans note, pourcentage ou résultat inventé.

**Natif sans imitation.** SwiftUI et contrôles Apple fournissent la navigation et les interactions système. Les maquettes expriment une anatomie, pas une injonction à refaire une barre système en dessins. Le web adopte sa propre navigation clavier ; Android futur conserve son langage de plateforme. [S118](../06-gouvernance/sources.md#s118).

## Traduction de la direction retenue

Plans inspire la place de la carte, Waze le signalement, Flighty la hiérarchie et Things la sobriété. Drivy ne copie ni marque, ni actifs graphiques, ni communauté publique. Le [parcours visuel de leçon](LECON.html) utilise une carte schématique originale et les tokens communs.

Une information importante reste visible : élève, temps, état GPS, caractère privé, erreur ou envoi en attente. Les explications sur le modèle de données, la mémoire de la démonstration et l’absence de note automatique quittent le parcours courant, sans quitter la documentation ni les règles métier. Les icônes de catégorie gardent un libellé. Le statut utilise un symbole, un texte et une couleur ; le nombre de cartes décoratives n’est pas un objectif.

## Compositions par moment

| Moment | Composition | Ce qui reste visible | Ce qui reste secondaire |
|---|---|---|---|
| Avant la leçon | Fiche de prochaine séance, objectifs, choix de capture | Élève, formation et heure | Historique complet et statistiques |
| Capture | Carte + contexte compact + panneau de commandes | État local, arrêt, état de transfert distinct | Rédaction détaillée, prix et paramètres |
| Sans GPS | Fiche de séance et objectifs, bilan accessible | Absence d’enregistrement formulée normalement | Aucun écran cartographique cassé |
| Replay | Carte et chronologie d’observations coordonnées | Temps, état privé/publié, observation sélectionnée | Actions de collecte et de facturation |
| Agenda élève | Engagements puis offres explicitement non inscrites | Dates, catégorie, statut personnel | Compteurs promotionnels et autres élèves |
| Gestion | Navigation latérale, liste/détail, actions contextuelles | École, rôle, filtre et sélection | Carte décorative et données interdites |

## Palettes et marque

Les valeurs complètes sont dans le [système de design](../02-experience/design-system.md), produit depuis le même [JSON](../annexes/tokens-proposition.json) que le prototype. Ne recopier ni recalculer une palette différente dans chaque écran. Le sombre est composé de surfaces ardoise et d’un bleu éclairci, pas obtenu par un simple filtre d’inversion.

Le nom **Drivy** utilise provisoirement la police système et un traitement typographique simple. Le petit signe de trajet utilisé dans l’aperçu est un repère documentaire, **pas un logo final approuvé**. Le logo de l’école apparaît dans un cadre neutre avec le nom accessible ; il ne modifie ni le bleu de la trace ni les erreurs. Ne pas livrer de faux logo pour une école réelle.

## À ne pas reproduire

Pas de dégradé géant à l’accueil, de cartes statistiques en mosaïque sans tâche, d’effet vitre sur tous les formulaires, de score de conduite dérivé du GPS, de mascotte ou de confetti de validation. Pas de commande cachée dans un swipe seul. Pas de fausse présence, publication ou inscription obtenue pour rendre une maquette plus séduisante.

Les [critères anti-slop](../02-experience/qualite-ui-ux-anti-slop.md) restent applicables au code et au contenu autant qu’au rendu. Une interface sobre peut aussi être mauvaise : chaque état doit informer et proposer une action utile.

## Références et statut

Les principes Apple concernant hiérarchie, matériaux et continuité ont été reconsultés ; leur application à Drivy est une proposition, pas une validation par Apple. [S118–S120](../06-gouvernance/sources.md#s118). Les seuils de contraste et de reflow viennent des documents W3C, et non d’une appréciation esthétique. [S121–S125](../06-gouvernance/sources.md#s121).

Le [benchmark visuel fourni dans la conversation](../01-recherche/benchmark-visuel-apps.md) sert à la direction acceptée. Il n’est ni un classement officiel ni un test installé de chaque application. Aucun entretien n’est revendiqué. Le choix de l’option A repose sur l’accord exprimé dans cette conversation. Les maquettes servent maintenant de support à une revue concrète.
