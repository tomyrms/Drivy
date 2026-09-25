# Système de design partagé (iOS et web)

Passe du 25 septembre 2026, demandée par le porteur : harmoniser l’apparence de toute l’application selon la direction A « Cartographie native » (`DESIGN/01-direction-artistique.md`) et les tokens 3.8 (`annexes/tokens-proposition.json`). Aucune règle métier, donnée, droit ou contrat n’est modifié par cette passe.

## Sources de méthode

Skills installés dans `.claude/skills/` depuis le registre ui-skills.com (dépôts sources MIT, voir `.claude/skills/README.md`) : `swiftui-ui-patterns`, `swiftui-liquid-glass`, `apple-design`, `write-swift`, `baseline-ui`, `fixing-accessibility`, `improve-ui`. Le registre complet (306 entrées) a été relu ; les principes retenus proviennent aussi de `make-interfaces-feel-better`, `mobile-native`, `to-spring-or-not-to-spring`, `polish`, `clarify`, `harden`, `layout`, `typeset`, `balise-ux-writing` et de la référence iOS d’`impeccable`. Ils restent subordonnés au dossier de conception.

## Client Apple

- **Tokens** (`UI/DrivyTheme.swift`) : palette complète des tokens 3.8 (surfaces succès/alerte, bordure de contrôle, désactivé, trace), `DrivySpacing` (4 à 48), `DrivyRadius` (champ 12, contenu 16, panneau 24), `DrivyMotion` (appui en ressort sans rebond, retour système en ease-out, nul sous Réduire les animations).
- **Composants** (`UI/DrivyComponents.swift`) : pastille d’état (symbole + texte + couleur), point d’état, en-tête de section, avatar à initiales, ligne de navigation, groupe de lignes séparées, colonne horaire, état vide avec une action, carte à rayons concentriques, en-tête de contexte, message en ligne, tracé schématique (illustration, jamais une position enregistrée).
- **Matériaux** : Liquid Glass uniquement pour les commandes flottant sur la carte (suivre, voir tout le trajet, pastilles d’origine), groupées dans `GlassEffectContainer`. Les surfaces de lecture restent opaques (`materialPolicy.forbidGlobalGlassTheme`).
- **Signalement** : tuiles de catégorie et de statut de grande taille, retour d’appui 0,96, retour haptique de sélection ; le retour haptique de succès n’est émis qu’après l’écriture locale durable de l’observation.
- **Écrans harmonisés** : connexion, Séance, Agenda, Élèves/dossier, École, compte, trajet en cours, GPS scolaire, replay, historique, signalement, bilan (rédaction et lecture élève, « Prochaine étape » en tête), dossier et détail de formation, catalogue, invitations, équipe, choix GPS et préparation de capture. Rayons codés en dur remplacés par les tokens.
- Contrôles natifs conservés : navigation par onglets et piles, feuilles, formulaires groupés, titres larges sur les écrans de premier niveau.

## Web

`apps/web` : survol limité aux pointeurs capables de survol, retour d’appui sur `:active`, `text-wrap: pretty`, contrôles non sélectionnables, `theme-color` par apparence, rayons partagés avec le client Apple, `aria-busy` pendant le chargement initial, action désactivée expliquée.

## Vérification

Compilation de l’IPA réussie sur GitHub Actions pour les lots poussés jusqu’à `c07b4c6` (run `36131760336`). Typecheck et build Vite du web réussis localement. Aucune capture n’a encore été relue ; VoiceOver, grand texte, sombre et essais physiques restent à qualifier sur appareil.
