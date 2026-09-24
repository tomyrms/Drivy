# Livraison du design et recette

> Référence 3.17 · [Accueil design](README.md). Cette recette ne remplace pas les scénarios métier T ni mobiles MOB.

**Passe visuelle courante :** [APPLICATION.html](APPLICATION.html) et [LECON.html](LECON.html) partagent les composants ; [application](../annexes/verification-application-v3-17.json), [carte](../annexes/verification-atelier-v3-17.json) et [cohérence](../annexes/verification-composants-v3-17.json) sont des contrôles HTML/documentaires. Vingt compositions ne signifient pas 49 écrans testés. Les rapports antérieurs et les huit SVG de carte sont historiques ; aucun fichier Figma n’est créé. Aucun succès documentaire ne qualifie les usages natifs.


## Passage du design à Swift

Le [système de design](../02-experience/design-system.md) et les [tokens](../annexes/tokens-proposition.json) sont la référence des surfaces Drivy. Créer des couleurs sémantiques clair/sombre dans les ressources Apple et les consommer par leur rôle, sans hex dispersés dans les vues. Les composants système utilisent leur propre rendu qualifié ; ne pas imposer les couleurs du prototype à toutes les barres natives.

Employer les styles sémantiques de texte, leur adaptation Dynamic Type et des espacements qui laissent croître le contenu. La référence 17 pt du corps ne devient pas une taille fixe. Les styles de capture gardent état et arrêt lisibles avec grand texte. Ne pas utiliser une réduction globale de police pour faire rentrer la maquette dans un iPhone étroit. [S120](../06-gouvernance/sources.md#s120).

Navigation et présentation restent celles de l’[architecture Swift](../04-technique/architecture-client-swift.md), avec service GPS hors des vues. MapKit dessine un vrai fond avec ses attributions. Le SVG de démonstration n’est jamais embarqué comme fausse carte du produit. Les dessins système, safe areas, clavier et focus sont qualifiés dans le binaire, pas reproduits pixel à pixel depuis Chromium.

Le web partage les rôles visuels, pas les composants SwiftUI. CSS sémantique, formulaires réels, labels et navigation clavier sont nécessaires. Android aura sa traduction native ; ces maquettes ne constituent pas sa réalisation.

## Contrôles à exécuter sur le produit

| Cas | Procédure et résultat attendu | Statut de livraison |
|---|---|---|
| UX01 · Comprendre la capture | À l’arrêt, demander si cet appareil enregistre et si l’élève voit déjà le trajet. Les deux états sont identifiables sans aide. | À TESTER AVEC UTILISATEURS |
| UX02 · Arrêter localement | Sans réseau, trouver Arrêter ; la collecte cesse et le transfert reste distinct. | NON EXÉCUTÉ SUR APP |
| UX03 · Sortir de la carte | Fermer puis retrouver la séance ; état de capture inchangé par simple navigation. | NON EXÉCUTÉ SUR APP |
| UX04 · Sans GPS | Préparer et publier un bilan textuel sans écran de panne ni pression pour accepter le GPS. | NON EXÉCUTÉ SUR APP |
| UX05 · Replay/caméra | Lecture x1 puis zoom manuel ; lecture indépendante et aucun recentrage forcé. | NON EXÉCUTÉ SUR APP |
| UX06 · Lacune et retrait | Aucune liaison fabriquée entre segments ; trace retirée sans géométrie ou vignette résiduelle. | NON EXÉCUTÉ SUR APP |
| UX07 · Offre versus engagement | Expliquer son inscription à partir de l’agenda ; ouvrir une offre ne réserve rien. | À TESTER AVEC UTILISATEURS |
| UX08 · Toutes les dates | Lire une série entière et ses conditions avant confirmation, même à grand texte. | NON EXÉCUTÉ SUR APP |
| UX09 · Résultat encore en cours | Simuler 202 puis refus/confirmation ; ne jamais afficher Inscrit avant réponse finale. | NON EXÉCUTÉ SUR APP |
| UX10 · iPad étroit | Redimensionner avec clavier ; sélection et brouillon conservés, arrêt accessible. | NON EXÉCUTÉ SUR APP |
| UX11 · Texte et reflow | Tester tailles Dynamic Type maximales puis web 320 CSS px ; formulaires lisibles, planning avec liste équivalente. | NON EXÉCUTÉ SUR APP |
| UX12 · Contraste rendu | Clair/sombre/contraste accru et carte dense ; texte, états, focus et tracé lisibles. | NON EXÉCUTÉ SUR APP |
| UX13 · Clavier et lecteurs d’écran | Ordre logique, libellés, erreurs annoncées, focus restitué et non masqué. | NON EXÉCUTÉ SUR APP |
| UX14 · Réduire animations/transparence | Commandes sémantiquement identiques ; aucun mouvement obligatoire ni fond illisible. | NON EXÉCUTÉ SUR APP |
| UX15 · Archive | Aperçu des conséquences et bloqueurs ; aucune confusion avec suppression globale. | NON EXÉCUTÉ SUR APP |
| UX16 · Pack | Expliquer droits réservés, utilisables et règlement, sans additionner des unités hétérogènes. | À TESTER AVEC UTILISATEURS |
| UX17 · Données privées | Personnel sans droit : ni note privée, ni trace, ni métrique financière à zéro comme substitut. | NON EXÉCUTÉ SUR APP |
| UX18 · Onboarding | Continuer sans photo/notification ; refus GPS indépendant de la complétude administrative. | NON EXÉCUTÉ SUR APP |
| UX19 · États dégradés | Nom long, aucune donnée, erreur, preuve à vérifier ; aucun contenu inventé pour remplir. | NON EXÉCUTÉ SUR APP |
| UX20 · Ressources et rendu Apple | Comparer composants natifs réels avec l’anatomie attendue ; pas de faux Liquid Glass custom ni police redistribuée. | NON EXÉCUTÉ SUR APP |

## Conditions d’acceptation proposées

Aucun état critique trompeur ni fonction nécessaire inaccessible n’est accepté au gel du premier parcours. Les contrastes opaques prévus sont contrôlés automatiquement, puis les fonds réels sont évalués sur appareil. Les fautes d’alignement et de densité se traitent sans réduire les tailles sous les objectifs Drivy.

La validation esthétique appartient au porteur. La compréhension doit ensuite être observée avec des moniteurs et des élèves ; aucun entretien n’a été réalisé ici. Recruter des profils et appareils représentatifs du pilote sans en inventer le nombre. Ne pas annoncer une conformité WCAG globale à partir d’un calcul de palette. [S121–S125](../06-gouvernance/sources.md#s121).

## Source de vérité et changements

Un changement de token part du JSON canonique puis régénère les tableaux et le prototype. Un changement métier part de sa spécification, non du HTML. Une évolution de maquette garde son identifiant VIS et la liste des écrans E couverts. La direction A reste une décision, les pixels restent itérables.

Les variantes système à contraste accru et les configurations iOS/iPadOS 26/27 doivent être testées dans les builds retenus. Cette passe ne revalide pas leur disponibilité publique ni les versions de Xcode ; les références de plateforme existantes restent datées. Pas de nouvelle API propre à iOS 27 inventée pour décorer une maquette.

## Ce que le prototype ne simule pas

Pas de GPS, API, stockage durable de données personnelles, notification, réservation, paiement ou suppression réels. La capacité et les textes d’exemple sont fictifs. Les animations illustrent des transitions de présentation seulement ; elles ne certifient ni la fluidité native ni l’autonomie. La carte fictive, la police de navigateur et les ombres documentaires ne sont pas une capture de l’interface finale.

## Recette complémentaire issue des écarts de la galerie

Les cas suivants restent **NON EXÉCUTÉS SUR APP**. Leurs variantes HTML sont vérifiées séparément ; aucun résultat de navigateur n’est converti en succès Swift.

| Cas | Objet | Résultat à obtenir sur le produit | Statut |
|---|---|---|---|
| UX21 | Consultation élève | Depuis son agenda, ouvrir une leçon puis un bilan : aucune commande moniteur ni note privée. | NON EXÉCUTÉ SUR APP |
| UX22 | Destination de gestion | Cours/catalogue du web personnel ne basculent pas vers inscription/achats élève. | NON EXÉCUTÉ SUR APP |
| UX23 | Retour à capture | Fermer, naviguer, rouvrir : même capture et points ; pas de nouvelle autorisation. | NON EXÉCUTÉ SUR APP |
| UX24 | Bilan complet | Travail, constat et suite conservés ; aperçu exact, erreurs reliées aux champs. | NON EXÉCUTÉ SUR APP |
| UX25 | Compétence non observée | Choisir puis retirer un niveau : entrée absente de la commande, pas note zéro ; contexte requis si observé. | NON EXÉCUTÉ SUR APP |
| UX26 | Réponse inconnue | Après délai sans résultat, reprendre la même intention ; ni succès ni nouvelle réservation implicite. | NON EXÉCUTÉ SUR APP |
| UX27 | Repère temporel | Accéder à une observation : temps, marqueur et commentaire issus du même segment. | NON EXÉCUTÉ SUR APP |
| UX28 | Intervalle sans points | Placer la lecture dans une lacune : pas de curseur géographique ni segment de raccord. | NON EXÉCUTÉ SUR APP |
| UX29 | Archive et filtre | Archiver une ligne filtrée : recherche conservée, sélection et focus cohérents. | NON EXÉCUTÉ SUR APP |
| UX30 | Aucun résultat | Filtre sans correspondance : aucun détail/actions périmés ; distinguer erreur réseau. | NON EXÉCUTÉ SUR APP |
| UX31 | Formulaire grand texte | 200 % web et Dynamic Type natif : libellés, champs, erreurs et choix lisibles, pas seulement paragraphes. | NON EXÉCUTÉ SUR APP |
| UX32 | Brouillon et périmètre | Naviguer conserve les données dans leur portée ; changer de compte purge l’ancien contenu et réconcilie ses opérations selon droits. | NON EXÉCUTÉ SUR APP |

### Portée historique des contrôles de galerie

Le contrôleur historique parcourait les 15 compositions et la planche en clair/sombre à 320, 390, 834 et 1440 CSS px. Il vérifie aussi les 15 compositions à texte 200 %, les retours de focus, les séquences de formulaire, les issues de réservation et les points du replay synthétique. Il contrôle les formes de commandes de brouillon contre SaveDraftCommand sans faire d’appel réseau.

Le standard décrit l’agrandissement du texte et de ses contrôles sans perte de contenu/fonction [S126](../06-gouvernance/sources.md#s126). La galerie ne remplace pas l’essai de toutes les tailles Dynamic Type, du zoom de navigateur, des lecteurs d’écran ou de toutes les collisions. Le [rapport historique V3.9](../annexes/verification-prototype-v3-9.json) donne les comptes exacts, les données mesurées et ses limites.

## Compléments à qualifier après la galerie

Les états nouveaux de reprise/scellement et d’export sont spécifiés, non simulés par la galerie actuelle. Les tester sur UI native et web connectées avec timeouts et retrait d’autorisation. Inspecter les captures du sélecteur d’applications par scène, les fichiers temporaires et caches : l’absence de nom dans un log ne prouve pas l’absence de contenu sensible sur disque. Les nouveaux MOB du [plan mobile](../05-realisation/qualification-mobile-ui-ux.md) portent ces preuves. Palette A et 32 critères UX existants inchangés.

## Saisie pédagogique pendant la leçon

UX33–UX36 : le repère privé, le formulaire thème/statut à l’arrêt, la sélection explicite au bilan et l’arrêt du GPS depuis le formulaire sont illustrés dans la galerie complémentaire. Dans l’atelier V3.16, fermer la qualification puis ouvrir le menu de séance est nécessaire pour arrêter le GPS ; cet accès supplémentaire reste à arbitrer, sans qualifier l’usage en mouvement. Les commandes de démonstration utilisent GeoObservationCommand sans ancre GPS inventée. La mémoire est volatile et un rechargement l’efface ; ce n’est pas la persistance native. Le besoin est confirmé par le porteur ; l’ergonomie et les conditions d’usage restent proposées et NOT_EXECUTED sur appareil. [Parcours de référence](../03-fonctionnel/gps-replay.md#saisie-pendant-lecon) · [Registre des interactions](../annexes/interactions-live-v3-11.json).

## Signalement centré carte

T423–T434 complètent les recettes existantes. À vérifier dans la galerie : ouvrir sans créer, annuler, thème/statut explicites, ancre figée, reprise de la sélection en redimensionnant, accès permanent aux commandes, mémoire effacée au rechargement, différence privé/publié. Les contrôles historiques de cette galerie sont dans `annexes/verification-live-prototype-v3-14.json` et ne changent pas le statut NOT_EXECUTED des tests natifs.

## Recette de finition des quatre vues

Ces critères complètent les variantes E23/E24 ; ils ne sont pas de nouveaux tests métier T ni des tests Swift déjà exécutés. Les assertions HTML correspondantes sont dans le [rapport courant](../annexes/verification-atelier-v3-16.json).

| Objet | À obtenir sur l’application | Statut natif/utilisateur |
|---|---|---|
| Sens du statut | Conséquence d’enregistrement comprise avant l’appui, correction possible ; pas de chevron de navigation | NON EXÉCUTÉ |
| Continuité | Catégories → statut → retour conserve l’ancre/instant et le focus ; transition interrompable | NON EXÉCUTÉ |
| Sélection | Même thème entre point et panneau ; statut lisible sans la couleur | NON EXÉCUTÉ |
| Proximité | Toutes les observations accessibles séparément, y compris au même instant | NON EXÉCUTÉ |
| Carte réelle dense | Trajet, position, points et commandes lisibles sur MapKit réel sans mutiler le fond | NON EXÉCUTÉ |
| Réduction des mouvements | Mêmes actions, pas de transition imposée ; vérifier le réglage système réel | NON EXÉCUTÉ |

La fiction dense teste la disposition, pas la fidélité géographique ni les performances d’une longue trace. Aucun seuil de sûreté en déplacement n’est déduit de l’animation de 200 ms ou des cibles en CSS px.
