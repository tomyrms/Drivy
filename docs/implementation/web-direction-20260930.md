# Direction web du 30 septembre 2026

Le porteur demande une refonte visuelle du web, sur desktop, téléphone et tablette. Son choix : « Sobre et précise : listes compactes, carte dominante, peu de cartes décoratives, couleurs discrètes. » Il a ensuite explicitement exclu la refonte globale de l’app native. Aucun changement de `DrivyTheme.swift` ou des composants natifs n’appartient à ce lot.

## Réalisation

La structure web privilégie les tâches quotidiennes. Le rail commence par Agenda, Élèves et Trajets après la vue d’ensemble, puis distingue organisation et catalogue. Le menu mobile affiche les mêmes liens dans le flux ; il n’impose plus un ruban horizontal de quatorze destinations. Une sélection ferme le menu. Échap depuis un lien du menu le ferme et restitue le focus au déclencheur.

La vue d’ensemble présente les accès au travail quotidien avant la préparation de l’école. Les étapes terminées sont repliées, les étapes restantes sont des lignes courtes. Les fonctions disponibles utilisent une marque et leur nom plutôt qu’une répétition de badges colorés.

Les anciennes cartes de section deviennent des groupes plats, les listes et le détail s’alignent sur deux colonnes quand la largeur le permet. Les champs utilisent leur propre largeur disponible pour revenir à une colonne. Les titres, rayons et contrôles ont une échelle plus compacte ; les contrôles gardent 44 px et les champs tactiles 16 px. Les formulaires existants, leurs erreurs et leurs droits restent les mêmes.

Palette web forêt/papier dans `styles.css`, sombre assorti ; thème natif inchangé. Le fichier `DESIGN.md` distingue les deux. La refonte ne crée ni carte fictive sur la vue d’ensemble ni donnée de planning inventée.

## Guides consultés et usage

Le registre UI Skills a été parcouru via `categories`, puis les catégories visual, systems et accessibility ; le catalogue local `.claude/skills` a été inventorié. Le plafond initial de trois guides du routeur a été dépassé à la demande explicite du porteur de lire le maximum de guides utiles. Aucune installation ni modification de skill n’a été effectuée.

| Guide | Application dans ce lot |
|---|---|
| ui-skills-root | Relevé des catégories et choix selon le vrai périmètre web |
| better-layout | Alignements partagés, ordre des tâches, séparation liste/détail, largeur minimale corrigée |
| better-ui | Surfaces réservées aux états, rayons communs, feedback d’appui existant, survol conditionnel |
| better-accessibility | Menu sémantique, focus restitué, cibles, titres de détail uniques, retour à 320 px |
| better-typography | Échelle de titres réduite, police système, champs 16 px, badges qui se replient |
| better-colors | Palette par rôles, contrastes mesurés avec les couleurs rendues, distinction du client natif |
| better-writing | Actions nommées, suppression du texte répétitif dans les étapes terminées, explications de refus conservées |
| mobile-native | `dvh`, safe areas, survol selon capacités, champs qui ne déclenchent pas volontairement le zoom, aucun zoom bloqué |
| prefer-container-queries | Principe traduit en CSS natif pour formulaires et faits ; aucun ajout de Tailwind |
| anti-slop, anti-ai-slop-writing, no-ai-slop | Copie courte et métier, aucune phrase promotionnelle ou chiffre fictif |
| apply-design-system | Consulté, écarté : workflow Figma et bibliothèques publiées, absent de ce chantier |
| container-lines | Consulté, écarté : repères/carrés décoratifs sans utilité pour la gestion |
| minimalist-skill | Consulté, écarté : macro-espaces, fonds décoratifs et animations d’entrée contraires au choix compact |
| swiftui-ui-patterns | Consulté avant la correction de périmètre ; aucun changement natif effectué |

Les principes et tokens ont été transmis aux agents planning et carte. Les règles produit et l’instruction du porteur priment sur une recette de skill.

## Vérification exécutée

- TypeScript client/serveur : `npm run typecheck --prefix apps/web`, réussi.
- Production : `npm run build --prefix apps/web`, réussi.
- Suite web : `npm run test --prefix apps/web`, 93 tests réussis dans 7 fichiers.
- Navigateur IAB réel, composants de production rendus avec données synthétiques de `test/visual.tsx` et `shell=1` : rail/vues/dossier à 1440 px sombre, dossier à 390 px sombre, agenda à 390 px clair, vue d’ensemble et menu à 320 px clair, vue d’ensemble à 834 px clair. La navigation de semaine conserve les flèches autour de la date sur téléphone.
- Menu ouvert puis fermé avec Échap depuis un lien : `aria-expanded` repasse à faux et focus retourne sur Menu. Navigation vers Élèves puis ouverture du dossier vérifiées.
- Débordement à 320 px détecté puis corrigé : la largeur utile avec scrollbar vaut 305 px, largeur défilable relevée après correction 305 px. À 834 px, largeur utile et défilable 834 px.
- Contrastes WCAG calculés depuis les tokens CSS, préalablement relevés dans le navigateur pour les deux thèmes : [mesures](proofs/web-contrast-20260930.json). Tous les couples textuels testés dépassent 4,5:1 ; contours de champ testés dépassent 3:1.

Le paramètre `scheme=light` du banc synthétique applique les vrais tokens clairs depuis la feuille CSS pour les inspecter indépendamment du thème du poste. Aucun mécanisme de thème de développement n’entre dans le bundle produit.

Ces contrôles ne qualifient ni VoiceOver/NVDA, ni Safari sur appareil, ni clavier logiciel, ni zoom navigateur à 200 %, ni tous les états de tous les formulaires. Aucune compilation Apple ou mesure physique n’est revendiquée par ce lot. Le dossier de conception et son manifeste sont conservés.
