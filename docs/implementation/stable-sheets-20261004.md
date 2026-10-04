# Feuilles natives stables — 4 octobre 2026

## Retour sur build99

Le porteur rapporte une mauvaise hauteur à l’ouverture et des saccades lors du glissement vers le haut. La compilation de build99 avait réussi ; le dimensionnement et les gestes n’avaient pas été qualifiés sur appareil. Ce retour invalide le choix de hauteur mesurée décrit dans [la première livraison](compact-sheets-20261004.md).

Le code contient une rétroaction entre hauteur du contenu, hauteur de la zone défilante, hauteur du panneau et detent calculé. Il passe aussi de 320 pt à une hauteur mesurée après ouverture, et force la priorité au défilement. Ces mécanismes sont établis en source ; leur responsabilité exacte dans les saccades rapportées n’a pas été instrumentée sur appareil.

## Décision appliquée

Suppression intégrale de `DrivyComponents+Sheet.swift`, du conteneur de mesure, des préférences de géométrie, du binding de sélection et du dimensionnement `.form.fitted`. Aucun nouveau composant de redimensionnement ne les remplace.

Les dix racines de présentation utilisent directement les feuilles SwiftUI avec `.medium` et `.large`, sans sélection contrôlée. Les tailles de texte d’accessibilité emploient `.large`. La présentation iPad utilise `.form`. Les `ScrollView` natifs laissent le système gérer le geste d’agrandissement, le défilement et le clavier. La hauteur ne dépend plus du chargement, de l’état métier ou de la taille du contenu.

Surfaces : démarrage d’une leçon, préparation GPS, reprise du diagnostic, confirmation de départ, attente du choix GPS, accord GPS, préférences de leçon, période, choix d’école et Signaler. Les menus et contenus compacts sont conservés. Signaler conserve sa hauteur lors du passage thèmes → appréciations → confirmation ; sur iPad en largeur régulière, son popover retrouve les dimensions stables 480 × 560 pt avec contenu défilant.

Les accès, demandes conservées, protections de fermeture et confirmations après écriture durable restent identiques. La boussole, les positions, le replay et les assets ne changent pas.

## Références et vérification

AGENTS, COMMENCER_ICI, R46, AP161–164 et scénarios T427/T428 relus. UI Skills Root et SwiftUI UI Patterns (sheets), Impeccable craft-floor appliqués ; contexte Operate de DESIGN.md conservé. Relecture indépendante des dix points d’intégration. La compilation Release Apple sera la vérification exécutable de cette livraison ; aucune campagne longue de tests ou captures n’est lancée, conformément à la demande du porteur.

Compilation et livraison : en attente du push. Restent à qualifier sur appareil l’ouverture, le glissement entre hauteurs, le clavier, la rotation, les grands textes et VoiceOver. Aucun résultat physique, de fluidité ou de batterie n’est revendiqué. Aucun déploiement homelab.
