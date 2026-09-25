# Système de design partagé (iOS et web)

Passe du 25 septembre 2026, demandée par le porteur : harmoniser l’apparence de toute l’application selon la direction A « Cartographie native » (`DESIGN/01-direction-artistique.md`) et les tokens 3.8 (`annexes/tokens-proposition.json`). Aucune règle métier, donnée, droit ou contrat n’est modifié par cette passe.

**Référence d’application : [`DESIGN.md`](../../DESIGN.md)** à la racine (principes, tokens clair/sombre, règles de page, catalogue iOS ↔ web, états, matériaux, mouvement, accessibilité, glossaire, interdits, vérification). Ce fichier-ci ne garde que les décisions de la passe et leurs preuves. Statut : la direction A est validée par le porteur ; les valeurs 3.8, durées de mouvement et largeurs de panneau restent des propositions en attente d’acceptation visuelle ; le signe de trajet n’est pas un logo approuvé.

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

Les tokens CSS du portail (`apps/web/client/styles.css`) reprennent désormais exactement les valeurs claires et sombres de `DrivyTheme`, y compris bordure de contrôle, danger, surfaces succès/alerte et désactivé.

## Harmonisation par écrans (agents parallèles, 25 septembre)

- **Carte** (`UI/DrivyComponents+Seance.swift`) : un seul en-tête, dock, bouton d'arrêt, commandes Liquid Glass, écran sans position et vocabulaire d'état GPS pour le trajet personnel, le GPS scolaire et le replay ; GPS refusé/interrompu en alerte, jamais en rouge.
- **Leçons et bilans** (`UI/DrivyComponents+Agenda.swift`) : état de leçon et état de bilan uniques, ligne de leçon commune (agenda, dossier, bilans), corps de bilan identique en aperçu et en lecture (« Prochaine étape » en tête), note de compétence, barre d'action basse avec justification de l'état désactivé.
- **École et administration** (`UI/DrivyComponents+Ecole.swift`) : barre d'outils identique sur les quatre onglets, ligne d'entité unique (élèves, membres, invitations, catalogue), champ de formulaire à libellé permanent, présentation unique d'une demande incertaine (« Demande à vérifier » → « Vérifier auprès de l'école » → « Renvoyer la même demande » → référence).
- **Fusion des doublons** : une seule ligne libellé/valeur (`DrivyKeyValueRow`), une seule barre d'action basse (`DrivyStickyActionBar`, reprise par `DrivyFormActionBar`), un seul style destructif (`DrivyDangerButtonStyle`).
- Composants système ajoutés : `DrivyKeyValueRow`, `DrivyLoadingState`, surface groupée commune, galerie DEBUG `design-system`.
- Choix à valider par le porteur : couleurs des statuts d'observation alignées sur le signalement (Attention orange, À retravailler rouge) ; ordre du bilan avec la prochaine étape en tête, contrairement aux maquettes 08/09.

## Vérification

Compilation de l’IPA réussie sur GitHub Actions pour les lots poussés jusqu’à `c07b4c6` (run `36131760336`). Typecheck et build Vite du web réussis localement. `DESIGN.md` : `npx @google/design.md lint` sans erreur (avertissements : pas de token `primary`, tokens non référencés par un composant), export `dtcg` avec couleurs, espacements, rayons et typographie ; contrôle documentaire qui ne qualifie pas le produit. Captures simulateur iPhone 17 Pro clair/sombre du build `905b124` relues (run `36135841808`, 24 écrans décodés depuis le journal) : rendu propre ; défauts corrigés ensuite (bandeau de revue masquant la barre d’onglets, nom d’école répété, bouton « Aujourd’hui » déplacé près de la semaine, séparateurs de la liste d’élèves) ou transmis au chantier trajet (aperçu de carte, commandes sur l’eau, chronologie du replay) ; VoiceOver, grand texte, sombre et essais physiques restent à qualifier sur appareil.
