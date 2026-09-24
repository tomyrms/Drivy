# Drivy V3.15 : appliquer la direction visuelle retenue

> 20 septembre 2026 · Source V3.14 conservée intacte · Documentation et prototype seulement.

## Décision et portée

Le porteur a accepté la recommandation : composition cartographique, signalement rapide, hiérarchie claire et sobriété des listes, inspirées respectivement de Plans, Waze, Flighty et Things. Le [benchmark](../01-recherche/benchmark-visuel-apps.md) est une recherche précédemment fournie, pas une nouvelle preuve d’efficacité de Drivy. Cette passe applique la direction à quatre vues de E23/E24 : carte, catégories, statut et replay privé. Elle n’ajoute ni écran métier, ni route, ni modèle.

Les détails de composition ne sont pas automatiquement validés par cet accord général. Le besoin de signalement en cours de leçon reste explicite ; son usage en mouvement n’est pas qualifié.

## Changements réellement réalisés

| Élément | Mise en œuvre | Garantie maintenue |
|---|---|---|
| Carte de leçon | Carte dominante, élève/temps/état compacts, action Signaler fixe, observation privée sur une ligne | Pas de position inventée ; accès sans défilement à l’action principale |
| Catégories | Six icônes avec libellés explicites, sans paragraphes répétés | Ordre stable, aucune catégorie sélectionnée implicitement |
| Statut | Trois lignes, une instruction commune « Le choix enregistre. » | Statut explicitement choisi ; pas de note ni publication automatique |
| Signalement | Instant et ancre figés à l’ouverture, ajout seulement après choix, annulation et correction | Ouvrir/fermer n’ajoute pas d’erreur ; la saisie n’est pas repoussée systématiquement après la leçon |
| Replay privé | Chronologie manipulable, lecture x1/x2/x4, observation liée à son repère | Temps de lecture basé sur le temps écoulé ; manipulation de la carte indépendante du bouton Lecture |
| Texte | Explications de démonstration hors de l’écran ; aide au second niveau | États hors ligne, erreurs, confidentialité et différence arrêt GPS/fin de leçon conservés |
| Adaptations | Clair/sombre, petit format, fenêtre iPad, texte agrandi, mouvements réduits | Contenu défilant si nécessaire, actions de sortie accessibles |
| Handoff | Huit SVG et sources locales du prototype | Aucun fichier .fig, aucun composant Figma ou build Swift revendiqué |

**Arbitrage encore à éprouver :** les commandes GPS secondaires sont regroupées dans le menu de séance, avec une confirmation distincte pour arrêter le GPS ou terminer la leçon. La vue de qualification garde une sortie fixe ; l’accès à l’arrêt depuis cette vue demande de la fermer. Ce coût d’accès supplémentaire est une proposition ergonomique, pas une preuve de sécurité. Si la qualification utilisateur ou la règle d’accès immédiat impose un contrôle d’arrêt permanent, cette commande doit redevenir visible avant mise en œuvre du client natif. Le choix d’une interface plus légère ne clôt pas cet arbitrage.

## Références alignées

Les entrées README, COMMENCER_ICI et la synthèse pointent vers [LECON.html](../DESIGN/LECON.html). La direction, les fiches E23/E24, les composants, la grammaire cartographique, la microcopie, la grille anti-slop, la recette et D33 distinguent la direction acceptée des détails proposés. La [galerie complémentaire](../DESIGN/MAQUETTES.html) reste disponible pour les autres écrans ; ses anciennes représentations de leçon ne remplacent plus les quatre vues courantes.

Le contrat OpenAPI 3.11.0, les tokens 3.8 et le registre de traçabilité sont comparés à la source par empreinte. Ils ne sont pas renumérotés. Les 434 scénarios métier et 68 scénarios mobiles restent non exécutés sur le produit. La révision graphique ne crée pas de nouvel endpoint ou table pour un contrôle d’interface.

## Vérifications de cette passe

[Rapport du prototype](../annexes/verification-atelier-v3-15.json) : 36 contrôles et 64 combinaisons de disposition (quatre formats, deux apparences, deux tailles de texte et quatre vues). Les scénarios exercés couvrent ouverture/annulation, instant figé, choix explicite, ajout/correction, privé, sans GPS, hors ligne, échec d’écriture, pause/arrêt/clôture, replay, clavier et retour de focus. Les mesures sont en CSS px ; elles ne valent pas mesures en points UIKit ni test Dynamic Type natif.

[Rapport structurel](../annexes/verification-visuel-v3-15.json) : cohérence source/génération, invariants de marque et de portée, artefacts inchangés et huit SVG sans bitmap. [Rapport lecteur](../annexes/verification-lecteur-v3-15.json) : liens, identifiants, navigation, recherche et ouverture de la galerie complémentaire. [Contrôle documentaire](../annexes/verification-documentaire.json) : liens Markdown, cas JSON et registres, sans service réel.

Le [point d’entrée courant](../annexes/verifier-livraison.py) expose cette portée ciblée. **Les anciens contrôles spécialisés fichiers/mobile/galerie V3.14 n’ont pas tous été rejoués sur V3.15.** Leurs rapports restent historiques ; ils ne sont pas comptés comme réussites de cette passe. Le chargement initial de la galerie est contrôlé, pas l’intégralité de ses anciennes interactions.

L’intégrité de la source couvre 438 fichiers. L’intégrité de la livraison est recalculée après génération et vérifiée dans le ZIP final. Une empreinte ne mesure pas la qualité de la conception.

## Limites du prototype et des exports

Trois observations fictives sont préchargées. Les modifications restent en mémoire de la page et disparaissent au rechargement. Pas de GPS, réseau, serveur, persistance durable, authentification ou partage. La carte est un canevas vectoriel inventé, pas une carte réelle ni une utilisation de MapKit. Le replay utilise un trajet synthétique continu ; les lacunes et transitions difficiles décrites ailleurs ne sont pas toutes simulées ici.

Aucun compte Figma n’est connecté. Les SVG se composent de tracés et de texte ; leur import Figma, regroupement de calques, substitution de police et conformité exacte restent à constater. Les ombres CSS, l’Auto Layout, les variables et les interactions ne sont pas transférés automatiquement. [Guide](../DESIGN/PASSAGE_FIGMA.md).

Aucun essai utilisateur, appareil Apple, VoiceOver natif, build SwiftUI, mesure de batterie, test routier, audit juridique ou transaction backend n’a été réalisé. La prochaine revue visuelle doit juger les quatre vues, pas supposer que les 49 écrans ont été redessinés.
