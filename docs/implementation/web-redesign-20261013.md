# Refonte du portail web — 13 octobre 2026

La refonte est implémentée sur `codex/refonte-portail-web`. Elle couvre le portail de gestion, ses pages d’entrée et les préférences personnelles. Les modifications préexistantes sont conservées. Aucun déploiement ni changement du client Apple n’est effectué.

## Direction et décisions

**Bureau de précision** est retenue après comparaison avec **Carnet de l’école** : rail stable, listes en tableaux, détails contextualisés, formulaires de largeur bornée et surfaces anthracite neutre en sombre. Le logo « La trace », Source Sans 3 et le cobalt Drivy restent les repères de marque. Les paramètres et dossiers sont organisés par tâche ; les cartes et badges répétés sont réduits.

Le [document de direction](web-redesign-design-20261013.md) décrit les deux pistes, les tokens et leurs mesures. Les références ont produit des décisions concrètes : [Shopify](https://help.shopify.com/en/manual/shopify-admin/shopify-admin-overview) pour les destinations stables, sa [recherche](https://help.shopify.com/en/manual/shopify-admin/admin-search) pour les accès directs aux réglages, [Stripe](https://docs.stripe.com/dashboard/basics) pour distinguer l’école des préférences personnelles, [Linear 2024](https://linear.app/now/how-we-redesigned-the-linear-ui) pour éprouver ensemble listes/détails/formulaires et ses [préférences](https://linear.app/docs/account-preferences) pour Clair/Sombre/Système. Documentation et captures officielles consultées ; aucune session authentifiée de ces produits n’est revendiquée.

## Organisation et pages migrées

| Espace | Pages et contenus couverts |
|---|---|
| Planning | Agenda hebdomadaire, choix moniteur, disponibilités et absences |
| Élèves | Liste filtrable et triable, dossier, complétion du profil, formations et bilans, invitations élèves, trajets et pagination |
| Équipe | Membres et droits, invitations équipe, accès aux horaires et absences d’un moniteur |
| Formations et tarifs | Vue par permis, offres, référentiels/compétences, procédures, prestations/prix, conditions commerciales ; listes, détails, versions et éditeurs |
| Paramètres de l’école | Coordonnées, confidentialité et adoption, informations demandées aux élèves, signalements, préparation et guide d’activation |
| Compte | Préférences personnelles Clair/Sombre/Système, écoles liées et menu du compte |
| Entrée | Connexion, acceptation d’invitation, ouverture d’école et gestion opérateur des liens d’ouverture |

Toutes ces pages utilisent les fondations communes. Les modifications de parcours sont ciblées ; les commandes métier existantes, les confirmations sensibles et leurs contrats restent présents. L’[inventaire détaillé](web-redesign-inventory-20261013.md) relie chaque fonction à ses composants, lectures, écritures et limites.

Les cinq entrées principales sont stables, avec les paramètres de l’école séparés visuellement et les sous-pages dans une navigation secondaire. Le sélecteur d’école apparaît uniquement quand le compte possède plusieurs écoles administrables. L’accueil d’une école active reste l’agenda ; la préparation affiche les prochaines actions fournies par le serveur.

**Compatibilité des liens** : les 18 chemins `/app/gestion/:schoolId/:section` restent inchangés. La réorganisation ne demande aucune redirection. Les identifiants de sélection, semaine, moniteur, audience et origine sont conservés. `/app/preferences` est la seule nouvelle page ; `focus` est limité à une liste de cibles de paramètres connues. Noms, e-mails et recherches de personnes ne sont pas inscrits dans les URLs.

## Parcours améliorés

- **Trouver un réglage** : recherche des intentions, champs et synonymes ; le résultat ouvre la bonne page, développe sa section si nécessaire et donne le focus au champ. Une seconde recherche vers la même cible fonctionne aussi.
- **Retrouver un élève** : recherche, actifs/archivés, filtre des profils incomplets, tri A–Z/Z–A et décompte réel. Le dossier puis les trajets conservent le contexte au retour. Les listes gardent leur contexte en mémoire dans le scope de l’école et des droits.
- **Résoudre un profil incomplet** : le dossier montre les informations administratives manquantes, leur validation et l’enregistrement. Le signal disparaît après confirmation et relecture. Une erreur de lecture ne masque plus silencieusement cette action.
- **Modifier les coordonnées** : formulaire direct, labels persistants, erreurs au champ et focus sur la première erreur. L’état distingue modification, envoi, confirmation et refus. La saisie reste disponible après un conflit ; la relecture remet à jour la version avant nouvel envoi.
- **Quitter un formulaire** : garde commun pour navigation, changement d’entité, retour/avance du navigateur et sortie du document. Les confirmations ne sont plus requises pour une simple sauvegarde des coordonnées. Adoption des textes, accès et actions destructives conservent leurs confirmations métier.
- **Travailler dans le catalogue** : états d’enregistrement cohérents et protection avant remplacement d’un formulaire ; références techniques rangées dans le détail, permis utilisé comme libellé de formation.
- **Choisir l’apparence** : accès depuis le compte ou les préférences ; changement immédiat, suivi du système, choix manuel prioritaire, conservation après rechargement et application avant React. Un échec du stockage de cette préférence est signalé.

La confidentialité conserve l’adoption existante et les vérifications d’impact : aucun nouveau brouillon administratif, aucune date d’effet ni publication intermédiaire ne sont introduits. Les dates de validité commerciales restent propres aux offres.

## Fondations à réutiliser

La référence de conception web est mise à jour dans [DESIGN.md](../../DESIGN.md). Le [document de direction](web-redesign-design-20261013.md#tokens-et-composants) fixe les couleurs sémantiques, mesures, rayons, typographie, états et structures.

Utiliser `ui.tsx` et `console/layout.tsx` pour les champs, boutons, tableaux, messages, détails et dialogues natifs. Réutiliser `AccountMenu`, `ThemeControl`, `SettingsSearch` et la barre d’enregistrement. Les nouvelles couleurs viennent des tokens de `styles.css`, jamais d’une condition de thème dans une page. Le contrôle personnel `drivy.web.theme` est la seule donnée ajoutée au stockage persistant ; les dossiers et recherches restent hors stockage du navigateur.

Les anciens styles de navigation en accordéon sont retirés et les règles communes dupliquées sont consolidées. Aucune bibliothèque d’interface ni dépendance de production n’est ajoutée. Le seul changement BFF sert le document des préférences ; contrats API, contrôle des permissions, OIDC et cloisonnement scolaire ne changent pas.

## Preuves et limites

La [galerie avant/après](proofs/web-redesign-20261013/index.html) conserve des captures non retouchées de la liste dense, du dossier et des coordonnées dans les deux thèmes. Les données sont fictives ; les noms des lignes de stress et la variété des formations ont été enrichis entre les deux campagnes. Les captures complètes et rapports locaux sont dans `artifacts/web-redesign-20261013/`. Le manifeste de la galerie porte les empreintes des fichiers retenus. Les [résultats et rapports de contrôle](proofs/web-redesign-20261013/reports/summary.json) sont également conservés avec la documentation.

Les [vérifications exécutées](web-redesign-verification-20261013.md) distinguent précisément rendus, interactions, calculs de contraste et recette intégrée. **18 parcours navigateur passent**, dont les sauvegardes, refus, conflits, relectures lentes, protections de saisie, retours, recherche profonde et thèmes. Les campagnes totalisent **186 configurations visuelles distinctes**, sans débordement ni erreur JavaScript, et **124 audits axe distincts** sans violation ou contrôle indéterminé. Les états retouchés ont ensuite été recapturés et contrôlés. Le typage, les **233 tests web** et le build passent. Il n’existe pas de script lint web distinct ; `git diff --check` passe. Le build garde deux avertissements : script de thème classique volontairement exécuté avant React et bundle principal de 657,31 Ko non compressé.

La visée [WCAG 2.2 AA](https://www.w3.org/WAI/WCAG22/quickref/) est contrôlée par contrastes, axe, clavier, focus, absence de débordement et rendu responsive. Les 60 couples de couleurs mesurés passent leurs seuils texte/contrôle. Ces résultats ne constituent pas une certification d’accessibilité.

**À qualifier** : OIDC/BFF/API/PostgreSQL réels, bloqués ici par le démarrage du moteur Docker sur son socket local ; zoom natif 200 % (reflow équivalent exécuté), lecteur d’écran et recette humaine des commandes métier longues. Le harnais rend les composants livrés avec des réponses BFF synthétiques et vérifie leur comportement, y compris rechargement ; il ne prouve pas une transaction PostgreSQL. Aucune qualification physique ni aucune mesure de performance ne sont déduites de ces essais.
