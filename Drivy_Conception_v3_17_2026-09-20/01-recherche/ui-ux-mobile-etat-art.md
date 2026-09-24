# Recherche UI/UX et mobile : décisions pour Drivy

> Référence 3.10 · Recherche du 19 septembre 2026. [Index](../README.md). Sources primaires techniques, source lexicographique pour « slop » ; conclusions produit proposées, pas efficacité mesurée.

## Ce que cette recherche doit résoudre

Drivy n’a pas besoin d’un thème de plus. Il faut que l’on comprenne immédiatement si une leçon est enregistrée, si une place est réellement réservée, ce qui sera partagé et quelle action suit. iPhone, iPad et futur Android doivent partager ce sens, sans imiter aveuglément la forme de l’autre plateforme. Le web reste l’espace de gestion détaillée ; il n’acquiert pas une promesse de capture GPS native.

Le relevé V3.3 sur Apple, Android, l’accessibilité et la qualité reste daté. V3.6 le complète par les sources natives S97–S105 ; les conclusions d’intégration sont alignées sur Swift natif confirmé. Les anciennes références à des couches d’interface partagées restent consultables dans le registre historique des sources, sans constituer la pile retenue. Le benchmark des écoles n’est pas réétudié.

## État vérifié des plateformes

**iOS 27 n’est pas traité comme une rumeur.** La page Apple Developer présente iOS 27 ; son tableau Xcode distingue Xcode 27 des lignes 27.1/27.2 indiquées bêta. Xcode 27 y exige macOS Tahoe 26.6 ou ultérieur et inclut le SDK iOS 27. Ces observations n’établissent ni la compatibilité de chaque dépendance Swift, ni celle du matériel de développement disponible. [S62](../06-gouvernance/sources.md#s62), [S63](../06-gouvernance/sources.md#s63).

Depuis le **28 avril 2026**, Apple exige Xcode 26 ou ultérieur et les SDK 26 concernés pour les soumissions. Depuis le **31 août 2026**, Google Play exige, pour les nouvelles apps téléphone/tablette et leurs mises à jour ordinaires, Android 16/API 36 ou ultérieur. Le minimum de déploiement utilisateur reste une décision distincte. Ces exigences doivent être relues au dépôt réel. [S64](../06-gouvernance/sources.md#s64), [S88](../06-gouvernance/sources.md#s88).

**Proposition :** concevoir et qualifier iOS/iPadOS 26 et 27 ; fixer le minimum commercial après inventaire des appareils pilotes. Préparer Android techniquement dès le début, avec mise à disposition ultérieure. Les builds bêta servent à détecter les régressions, pas à constituer implicitement le canal de production.

## Observations et traduction, sans copier un style

| Observation documentée | Application proposée à Drivy | Limite / preuve à obtenir |
|---|---|---|
| Apple distingue la couche des commandes et le contenu dans son nouveau système. [S65](../06-gouvernance/sources.md#s65) | Matériaux natifs possibles sur navigation et commandes ; bilans, montants et données d’élève sur fond stable. | Lire sur carte claire/sombre, en grand texte, en réduisant la transparence. |
| Liquid Glass est un matériau adaptatif, pas une couleur transparente fixe. [S66](../06-gouvernance/sources.md#s66) | Pas de simulation par empilement de cartes floutées ; repli opaque et hiérarchie conservée. | Captures du vrai binaire, pas seulement navigateur. |
| Les heuristiques privilégient état visible, contrôle et prévention d’erreurs. [S67](../06-gouvernance/sources.md#s67) | Distinguer capture locale, transfert et publication ; pas de toast « terminé » ambigu. | Demander au participant de dire qui peut déjà voir son bilan. |
| WCAG 2.2 traite notamment cibles, focus, reflow et gestes complexes. [S68](../06-gouvernance/sources.md#s68) | Alternatives au glisser du replay ; formulaires navigables ; carte accompagnée d’une liste. | Audit web et essais natifs séparés. |
| Apple documente SwiftUI et son interopérabilité UIKit [S97](../06-gouvernance/sources.md#s97). | Présentation SwiftUI, API UIKit ciblée si besoin démontré, essais VoiceOver sur les compositions. | Une interface native ne prouve pas l’accessibilité du parcours Drivy. |
| Android préconise des compositions suivant la fenêtre. [S84](../06-gouvernance/sources.md#s84) | Liste/détail et carte/panneau suivant l’espace réel, pas le nom de l’appareil. | Réduire la fenêtre pendant une capture sans la redémarrer. |
| MapKit pour SwiftUI expose des cartes et superpositions [S98](../06-gouvernance/sources.md#s98). | MapKit direct proposé pour Apple ; mesurer longues traces et caméra. | Choix de présentation indépendant de la capture et des géométries serveur. |
| Core Location documente des sessions d’autorisation et de fond [S73](../06-gouvernance/sources.md#s73), [S99](../06-gouvernance/sources.md#s99). | Qualifier un profil natif minimal pour la séance bornée ; ne pas exiger Always sans justification. | Inspecter Info.plist et observer le binaire sur appareil verrouillé. |

Ces applications sont des décisions de conception Drivy. Elles ne sont pas attribuées aux éditeurs comme si Apple ou Google avaient audité une auto-école.

## Priorités UX retenues

**D’abord la tâche.** En début de leçon, afficher élève, formation, objectifs et choix d’enregistrement. Ne pas consacrer le premier écran à quatre indicateurs génériques. Dans le web, au contraire, une liste filtrable et une vue d’activité peuvent servir la gestion.

**Ensuite la confiance.** « Disponible », « Demande en cours » et « Inscrit » ne partagent pas la même coche. Le nombre de places affiché est une observation datée ; seule la réponse autorisée confirme l’inscription. Les libellés restent identiques entre app et web.

**Puis la continuité.** Fermer une feuille, afficher une autre destination ou faire pivoter l’iPad ne termine pas la collecte. Le retour système n’est pas un bouton d’arrêt caché. Les opérations encore inconnues restent reprises avec leur identité, jamais recréées pour rendre l’écran artificiellement rassurant.

**Enfin l’expression visuelle.** La direction A Cartographie native conserve une identité typographique et sémantique, tandis que les contrôles natifs respectent leur plateforme. L’identité scolaire nom/logo/contact ne change ni les erreurs, ni l’avertissement GPS, ni les contrastes nécessaires. L’accent scolaire libre n’est pas configurable au pilote.

## Ce que « AI slop » apporte réellement au projet

Merriam-Webster décrit l’acception numérique comme du contenu médiocre, généralement produit en quantité au moyen de l’IA. [S69](../06-gouvernance/sources.md#s69). Pour Drivy, le problème visé est une production non examinée : écrans génériques, texte creux, états inventés, dépendances non vérifiées ou documentation qui semble complète sans définir le comportement.

Nous n’en déduisons pas qu’un dégradé, une police, un arrondi ou une icône prouve une origine IA. Le contrôle s’appuie sur l’utilité et la véracité du résultat, quel que soit son auteur. La [charte](../02-experience/qualite-ui-ux-anti-slop.md) formule les refus et les preuves attendues.

## Parcours de lecture et décision

| Besoin | Référence |
|---|---|
| Faire des écrans utiles, lisibles et non génériques | [Charte anti-slop et qualité](../02-experience/qualite-ui-ux-anti-slop.md) |
| Appliquer les principes aux situations concrètes | [Patterns mobile](../02-experience/patterns-mobile-parcours.md) |
| Développer l’intégration iOS 26/27 et iPad | [iOS et iPadOS](../04-technique/integration-ios-ipados.md) |
| Préparer Android sans le promettre déjà disponible | [Android](../04-technique/preparation-android.md) |
| Isoler les capacités natives et sécuriser le cycle mobile | [Intégration transverse](../04-technique/integration-mobile-transverse.md) |
| Décider sur la base de tests et non d’adjectifs | [Qualification](../05-realisation/qualification-mobile-ui-ux.md) |

## Limites et maintien de la recherche

Les documentations évolutives sont datées dans [S62–S96](../06-gouvernance/sources.md#s62). Les détails de versions, règles des stores, raisons de confidentialité et comportements de permissions sont à revérifier avant chaque publication majeure. Aucun test utilisateur, GPS, build natif ni essai de batterie n’a été effectué ici. Les références HIG/DocC sans texte exploitable ne sont pas interprétées à partir de leur seul titre. Les transcriptions WWDC accessibles constituent les preuves effectivement consultées.


<a id="décision-dapplication-de-la-recherche-v34"></a>
## Application de la recherche aux clients natifs
Le porteur a choisi Swift natif, et non une interface mobile mutualisée. Le [client Apple](../04-technique/architecture-client-swift.md) traduit ce choix en responsabilités, état, réseau et persistance. Les recommandations ne prouvent pas une application plus rapide sans mesure. La mutualisation concerne le contrat, les fixtures et les références métier ; Android futur représente un second chantier.

<a id="reconsultation-ciblée-v37"></a>
## Sources mobiles reconsultées et limites
Les références [S111](../06-gouvernance/sources.md#s111) et [S112](../06-gouvernance/sources.md#s112) précisent token APNs et environnement ; la liaison vers les comptes est une règle propre à Drivy. [S113](../06-gouvernance/sources.md#s113) est une archive limitée aux positions en cache et au filtrage matériel, pas une preuve de comportement de fond iOS récent. [S114](../06-gouvernance/sources.md#s114) appuie la revue des actes importants, sans multiplier les confirmations des saisies courantes. [S115](../06-gouvernance/sources.md#s115) éclaire les verrous, pas leur exécution.

Le relevé [S116](../06-gouvernance/sources.md#s116)/[S117](../06-gouvernance/sources.md#s117) distingue publication Apple 27.0 le 14 septembre 2026, bêtas et exigences de l’outil ; les six combinaisons Drivy restent non qualifiées. Cette passe ne reconfirme pas les tarifs des écoles ni tous les profils réglementaires. La date d’une source n’est pas la date d’un test de l’app.
