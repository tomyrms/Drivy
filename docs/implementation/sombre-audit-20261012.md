# Audit du thème sombre « Soft Charcoal » — 12 octobre 2026

Demande du porteur : vérifier que le thème sombre livré le 11 octobre ([décisions](dark-soft-charcoal-20261011.md)) est appliqué partout, corriger ce qui ne l’est pas, sans refonte et sans toucher au thème clair. Branche `claude/sombre-audit-20261012`, partie de `claude/icones-signaler-20261012`.

## Méthode

1. **Lecture du code** des 150 fichiers Swift de l’app : couleurs littérales, opacités posées sur les tokens, `colorScheme` forcé, `presentationBackground`, `listRowBackground`, matériaux, ombres, séparateurs, contrôles système (`Toggle`, `DatePicker`, `Picker`, `Stepper`, `PasteButton`), ponts UIKit (carte, marque de lancement), Asset Catalog.
2. **Captures du simulateur** (iPhone, iOS 26, CI) des 54 écrans admis par `capture-screens.sh`, en clair et en sombre, avant correction (`4e26b0d`, runs `38185517604` et `38185519317`) puis après (`6c27eb7`, runs `38187221803`, `38187223716` et `38187225343`).
3. **Couleurs mesurées sur les pixels** : couleurs dominantes de chaque capture sombre, comparées aux valeurs de `DrivyTheme`.
4. **Bascule à chaud** : nouvelle option `visual_hot_switch` du workflow « Refonte · iOS ». L’app est lancée en clair sans forcer l’apparence, puis le simulateur passe en sombre et revient en clair. Chaque capture est comparée au pixel près avec celle d’un lancement à froid.
5. `python scripts/ios/theme-contrast.py` : 204/204 couples sombres au-dessus de leur seuil, clair inchangé.

## Écrans vérifiés (54, en clair et en sombre)

Moniteur : Aujourd’hui, Agenda, Élèves, fiche et dossier (un et plusieurs permis), leçon (réalisée, prévue, annulée, avec observations, avec tarif, fin de leçon, en feuille), planification, réglages de planification, démarrage immédiat, choix du GPS, préparation du trajet, leçon en cours sur carte (GPS actif, en attente de position), palette Signaler, liste des observations, replay, invitations (liste, création, détail, code), Profil, compte.

Élève : Leçons, Progression, Profil, mes informations (et erreur), choix d’école, sans école, accueil en sept étapes (bienvenue, informations, formation, GPS, relecture, prêt, équipe).

Transversal : connexion (et erreur), code et lien d’invitation (saisie, aperçu, erreur), verrouillage, écran de confidentialité, squelettes de chargement, galerie du design system.

## Constats

### Sain, laissé tel quel

- **Palette rendue conforme.** Sur les 54 captures sombres, les fonds mesurés sont exactement `#17191C` (page), `#1D1F23` (page d’une feuille), `#272A2E` / `#2A2D31` (blocs), `#34383D` (remplissage neutre), `#3D70E2` (aplat bleu), `#2F3B54` (sélection) et `#473338` (erreur). Aucun noir pur hors de l’îlot dynamique et de l’arrière-plan système derrière une feuille.
- **Aucune couleur littérale dans les vues.** Les seuls `Color.black` / `.white` sont des masques de fondu (rail du replay, squelettes), la marque « La trace » (validée, non modifiée) et un aperçu DEBUG.
- **Hiérarchie.** Chaque bloc est plus clair que sa page, les feuilles montent d’un niveau, les rangées de formulaire passent par `drivyFormRows()` et les listes pleine largeur par `drivyPlainRows()`.
- **Ponts UIKit.** La carte (tracé, liseré, marqueur de position) et la marque de lancement se redessinent via `registerForTraitChanges`.
- **Aucun `preferredColorScheme` ni `colorScheme` forcé.** Feuilles, popovers et menus héritent de l’apparence du système.
- **Bascule à chaud.** Les 54 écrans passent de clair à sombre puis reviennent au clair sans relance. Les écarts restants sont l’heure, le chronomètre, une animation ou une notification du simulateur. Au premier essai, le dossier était resté clair : c’était le premier lancement après le démarrage du simulateur. Relancé en deuxième position (run `38189188465`), il est identique au pixel près sous la notification.
- **Couleurs de signal.** Lisibles sur la page, sur un bloc et sur la carte en sombre (valeurs inchangées).

### Corrigé

**Interrupteurs et calendriers en bleu pastel.** Cause : la teinte système est `accent`, c’est-à-dire l’encre `#86ABF8` choisie pour les liens et les symboles. Un interrupteur activé devenait une piste bleu pâle sous un pouce blanc (2,1:1), visible sur « Inviter un élève ». Le jour courant sélectionné d’un `DatePicker` aurait porté un chiffre blanc sur ce même bleu. C’était le point « à voir sur appareil » resté ouvert le 11 octobre.

Correctif : `drivyControlTint()` (`DrivyComponents+Ecole.swift`) pose `accentFill` (`#3D70E2`, le bleu du bouton principal) sur les 14 interrupteurs et les 4 sélecteurs de date. La règle du thème est respectée : un aplat bleu qui porte du blanc prend `accentFill`. En clair, `accent` et `accentFill` valent tous deux `#245BD6` : rien ne change.

Vérifié : la capture sombre d’« Inviter un élève » ne diffère qu’à l’emplacement de l’interrupteur. Les 54 captures claires sont identiques au pixel près, sauf l’heure affichée (planification, fin de leçon), le chronomètre et la carte qui se charge (leçon en cours), une animation (squelettes) ou un léger anticrénelage (écart inférieur à 8/255).

### Vu, non corrigé (système ou hors thème)

- **Bouton « Coller » désactivé** (code et lien d’invitation) : c’est le `PasteButton` du système, désactivé faute de contenu dans le presse-papiers. Il forme une pastille bleu nuit en sombre et bleu pâle en clair. Comportement système, cohérent dans les deux apparences.
- **Champ de recherche** (Élèves, historique) : fond système `#2E2F34`, à peine plus froid que `surfaceMuted`. C’est la barre de recherche native.
- **Deux `Divider()` sans le filet du thème** (démarrage immédiat, préparation du trajet) : le séparateur système est un peu plus marqué que `border` en sombre. Les aligner changerait le clair : laissés tels quels.
- **Alertes et feuilles d’actions** : leurs boutons prennent le bleu système (`#0A84FF` en sombre), car l’app ne déclare pas de couleur d’accent globale dans l’Asset Catalog. En déclarer une changerait aussi le clair : décision au porteur.
- **Fonds de carte bleus** sur le replay et le bloc « Trajet » : les coordonnées synthétiques sont en mer et MapKit dessine de l’eau, dans les deux apparences.
- **Leçons de l’élève en liste simple**, alors que le dossier du moniteur est en blocs : écart de mise en page, pas de thème.

## Reste à vérifier à la main

- Sur appareil : carte sombre réelle, Liquid Glass des commandes, ombres des panneaux, interrupteurs et calendrier ouvert avec `accentFill`, alertes.
- États jamais capturés : appui (bouton secondaire en `accentSoft`, rangées), menus contextuels et déroulants ouverts, clavier, calendrier déplié d’un `DatePicker`.
- Contraste accru, Réduire la transparence, grand texte, iPad et paysage : non capturés dans cette passe.
- Écran de lancement (`LaunchBackground`) : iOS le met en cache, jamais vu.

## Builds et tests

- IPA d’essai compilée sur `6c27eb7` (run `38187227306`). L’IPA ne compile pas la cible de tests.
- Captures : 6 runs réussis, 54 écrans en clair, en sombre et en bascule à chaud.
- Tests Swift et parcours UI : non lancés. Aucune logique n’a été modifiée : un modificateur de teinte et une option de capture.
