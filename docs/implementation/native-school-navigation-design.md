# Navigation École et Élèves

Passe de présentation fondée sur les maquettes École/Dossier et la charte `02-experience/qualite-ui-ux-anti-slop.md`, en particulier AS03, AS04, AS05 et AS07. Les workspaces et les callbacks de droits restent inchangés.

- École distingue Organisation et Paramètres. Les coordonnées et le compte restent accessibles dans des sections simples. Le bâtiment décoratif et le texte générique répétant les rôles ont été retirés ; les rôles réels restent affichés.
- Élèves conserve recherche native, sélection à deux colonnes sur iPad et ajout direct. Invitations se retrouve dans École → Organisation et dans l’état vide, plutôt qu’en quatrième icône de la barre.
- La recherche vide propose d’effacer la requête ; l’absence de dossier explique la situation et montre l’ajout lorsque son callback est autorisé. Les erreurs et la pagination restent en place.
- Les lignes d’élèves sont plus compactes aux tailles ordinaires. Les tailles d’accessibilité gardent le texte complet, sans réduire la police.
- Dans le dossier, Planifier une leçon est l’action principale. Les formations se lisent en liste ; ouvrir une formation ou affecter un moniteur se trouve dans Gérer les formations. La création reste aussi directement proposée lorsque la liste est vide. Les archives gardent leurs restrictions.

Relecture ciblée et `git diff --check` effectués. Compilation Apple et rendu natif ciblé restent à faire pour cette passe. Aucun test physique ni contrôle VoiceOver n’est déclaré exécuté.
