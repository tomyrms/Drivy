# Registre Drivy — vérification des 13 et 14 octobre 2026

Version produit : `1c43c35f3bbb6389719bdc55ebf0ee7f0d34b6fa`, branche `codex/portail-registre-20261013`. Référence avant : `afe2140`. Les captures et les parcours locaux utilisent des données fictives ; la recette CI utilise une base PostgreSQL isolée, Keycloak et SMTP de test.

Le [résumé dédupliqué](proofs/web-registre-20261013/coverage-summary.json) fait foi pour la matrice finale : les rapports ciblés remplacent les vues antérieures. Le rapport initial conserve deux échecs historiques dus au classement des mesures axe indéterminées ; les [mesures complémentaires](proofs/web-registre-20261013/manual-contrast-review.json) et le rapport ciblé final les résolvent.

## Résultats exécutés

| Contrôle | Résultat et preuve |
|---|---|
| Types, tests et build locaux | Typage réussi ; 233 tests web dans 21 fichiers réussis ; build réussi. Intégrité des 556 fichiers du dossier de conception inchangée. |
| API/PostgreSQL et web en CI | [Run 38475181117](https://github.com/tomyrms/Drivy/actions/runs/38475181117), SHA produit exact : 439 tests API dans 37 fichiers, dont 304 tests d’intégration dans 27 suites ; 233 tests web, types et builds API/web, intégrité documentaire réussis. |
| Navigateur intégré | [Run 38475181157](https://github.com/tomyrms/Drivy/actions/runs/38475181157) : 80 contrôles réussis avec Chromium 153, OIDC, BFF, API et PostgreSQL réels. [Rapport](proofs/web-registre-20261013/integrated-browser.json). Huit captures téléchargées ; première leçon planifiée inspectée. |
| Parcours locaux | 26 scénarios réussis, Edge 155, composants React réels et réponses BFF synthétiques. [Rapport](proofs/web-registre-20261013/interaction-results.json). |
| Rendu responsive | 35 états × 3 largeurs (1440, 1024, 390 px) × 2 thèmes : 210 configurations distinctes, aucun débordement horizontal du document ni erreur JavaScript. Les régénérations ciblées remplacent leurs vues initiales et ne sont pas comptées une seconde fois. |
| Accessibilité automatique | 140 configurations distinctes auditées avec axe 4.14, tags WCAG 2.2 AA et antérieurs ; aucune violation. Deux mesures indéterminées du titre d’un éditeur ont été résolues par inspection et mesure complémentaires, décrites ci-dessous. |
| Reflow et couleurs forcées | Reflow à 720 CSS px / DPR 2 et réduction des animations exécuté. Cases et radios natifs en couleurs forcées contrôlés ; SVG décoratifs masqués. |

Le build garde deux avertissements connus : script initial de thème classique volontairement exécuté avant React et bundle principal supérieur à 500 Ko. Aucun nouveau paquet n’a été ajouté.

## Parcours et états couverts

Les 26 scénarios couvrent : choix Clair/Sombre/Système, rechargement et premier affichage ; recherche de réglages jusqu’au champ ; menu du compte et retour du focus ; recherche/tri/pagination des élèves et homonymes ; fiche, trajet et retour au contexte ; lien natif vers un nouvel onglet ; dossier hors annuaire, annuaire en panne et dossier réellement absent ; panne secondaire du référentiel ; résolution durable d’un profil incomplet ; coordonnées enregistrées puis relues ; erreur réseau conservant la saisie ; sortie avec modifications par menu et historique ; signalements modifiés ; accès directs refusés aux rôles élève et moniteur ; états vide, erreur et chargement ; cases cochées, mixtes, désactivées et clavier ; recherche de compétence, validation avec Entrée et focus d’erreur ; conditions relues sans écriture anticipée ; champs d’un éditeur accessibles au clavier devant la barre d’actions.

Le harnais n’intercepte pas la toute première navigation d’un nouvel onglet natif Edge. Le test vérifie d’abord son ouverture et l’URL exacte, puis recharge cet onglet avec le harnais avant de vérifier le dossier. Cette limitation du test n’est pas présentée comme une session de production ou comme une preuve OIDC ; la recette intégrée est indépendante.

| Famille | Vues exercées dans les deux thèmes et aux trois largeurs |
|---|---|
| Gestion quotidienne | Agenda, disponibilités, absences, trajets |
| Élèves et équipe | Listes, fiche élève, fiche membre, invitations élèves et équipe |
| Catalogue | Formations, référentiels, procédures, offres, prestations, conditions, formulaire de référentiel |
| Paramètres | École, confidentialité, informations élèves, signalements, préférences personnelles |
| Entrée et préparation | Connexion, compte, invitation, ouverture, opérateur, aperçu ; six étapes du guide : identité, confidentialité, profil, formations, tarifs et revue |
| Composants | Cases, confirmation, radios de thème, champs et erreurs — page de test exclue du build public |

Les anciennes routes restent celles de l’inventaire : aucune migration d’adresse n’est nécessaire. Les recherches nominatives et la pagination vivent dans la mémoire du contexte de l’école ; elles se conservent pendant la navigation, pas après un rechargement complet.

## Défauts rencontrés puis corrigés

- Aide de checkbox répétée dans le nom accessible : libellé et description sont désormais associés séparément.
- Barre d’actions couvrant des champs sur petit écran : elle reste dans le flux lorsque la largeur ou la hauteur est au plus 640 px. Le parcours clavier sur écran large vérifie que le champ focalisé passe devant la barre.
- Vues de statut empilées dans une demi-colonne mobile : elles occupent une ligne entière au-dessus des sélecteurs.
- Action de création répétée pendant l’édition du catalogue : masquée tant qu’un formulaire est ouvert ; annulation et retour conservés.
- Fixture d’invitation d’équipe portant un code élève : remplacée par une invitation e-mail fictive. Douze captures et huit audits des deux audiences régénérés ; aucun changement produit.
- Revue locale de composants débordante sur mobile : wrapper de test responsive corrigé.

Deux audits automatiques supplémentaires après parcours clavier gardent une mesure indéterminée du titre `Nouveau référentiel` à 1440 px. La vérification complémentaire résout ces deux cas : neuf points du titre sur neuf atteignent bien le titre, sans élément superposé ; contraste calculé **14,67:1 en clair** et **14,00:1 en sombre**, pour un seuil texte de 4,5:1. Les mesures indéterminées brutes restent conservées et ne sont pas présentées comme des audits automatiques entièrement déterminés. Aucun champ ni focus n’est masqué.

## Inspection visuelle et limites

La racine a inspecté les trois écrans représentatifs et les contrôles dans le navigateur, puis les captures mobile et tablette. Une seconde lecture de seize fichiers finaux couvre aussi l’agenda, la confidentialité, les invitations, les conditions, la préparation, la revue et l’opérateur. Aucun recouvrement ou texte coupé bloquant n’y est observé. Les captures sont brutes ; la [galerie avant/après](proofs/web-registre-20261013/index.html) compare les quatre vues à 1440 px dans les deux thèmes et fournit des compléments mobiles.

Le raccourci de zoom natif essayé dans le navigateur n’a pas changé la largeur CSS ni le DPR : **le vrai zoom navigateur à 200 % reste non qualifié**. Le reflow géométrique ne le remplace pas. Lecteur d’écran, Safari, recette avec une auto-école et essais physiques GPS/batterie/VoiceOver ne sont pas revendiqués. Aucun résultat axe ni calcul de contraste ne constitue une certification WCAG complète.
