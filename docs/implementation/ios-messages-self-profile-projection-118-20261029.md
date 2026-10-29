# Profil personnel commun dans Messages — #118 — 29 octobre 2026

Ce raccord dépend de la projection de profil commune de `SchoolWorkspace` réalisée dans le lot #118. Il complète le lot Messages `2966c01c`, sans reprendre sa réalisation dans le décompte des issues.

## Comportement

`SchoolRootView` transmet explicitement le workspace scolaire courant à la composition Messages. Les vues lisent son dernier nom et sa dernière photo personnels à l'affichage, sans conserver un second snapshot du profil. Le raccord exige le compte, l'école, l'époque d'accès et l'API de la portée Messages courante. La projection s'applique seulement au `personID` du compte : le nom, la photo et les droits des tiers restent ceux de l'annuaire Messages autorisé.

Les lignes de membres, leur recherche et leurs repères d'homonymes, la fiche ouverte depuis un membre, les auteurs et avatars, les votants et les résultats de recherche suivent cette projection. La cellule Exyte tient compte du nom dans son identité de rafraîchissement. Un retrait de photo personnel retourne réellement `nil`, sans repli sur l'ancienne photo du cache Messages. Les textes historiques des messages et des mentions restent intacts.

Le badge « Modification en attente » accompagne seulement le profil personnel concerné dans les membres et leur fiche. Il figure aussi dans l'en-tête partagé Compte/Profil, une seule fois dans cet en-tête, avec la photo projetée. Le badge ne prétend pas que le serveur a confirmé une intention locale. VoiceOver inclut son état dans le libellé de la ligne du membre.

Aucun changement de transport, de cryptographie, de droits serveur, de dépendance ou de stockage n'est apporté par ce raccord. Aucun déploiement n'est nécessaire.

## Recette ciblée à réaliser sur l'IPA intégrée

1. Depuis le profil du compte A, modifier le nom avec le réseau lent puis ouvrir Messages → Général → Membres : retrouver le nom projeté, le badge et la fiche concordante. La recherche doit retrouver le nouveau nom. Les autres membres gardent leurs noms.
2. Remplacer puis retirer la photo personnelle : l'en-tête Compte/Profil, la ligne de membre, sa fiche et les éventuels avatars personnels doivent suivre le dernier choix. Un ancien chargement de photo Messages ne doit pas rétablir l'image retirée.
3. Confirmer l'écriture, puis vérifier la disparition du badge sans fermer les surfaces déjà ouvertes. Vérifier les libellés VoiceOver et les grandes tailles de texte.
4. Changer d'école, d'époque d'accès, d'API ou de compte pendant une lecture : aucune projection du précédent contexte ne doit être appliquée à un tiers ni à la nouvelle portée.
5. Ouvrir une fiche de tiers et une conversation privée : vérifier que leur nom, leur photo et leurs actions restent issus du même participant autorisé.

## Vérifications et limites

Relecture statique des gardes de portée, des appels aux vues et du retrait de photo ; `git diff --check` exécuté. Aucun test Swift, aucune suite, aucun build ni parcours VoiceOver n'a été exécuté dans ce worktree Windows. La compilation Apple et la recette restent à effectuer par le coordinateur après intégration du socle #118 ; le raccord n'est pas compilable seul sur la base antérieure à ce socle.
