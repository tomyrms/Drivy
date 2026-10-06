# Passe de marque et direction artistique — 6 octobre 2026

Demande du porteur : donner à Drivy une identité reconnaissable dans le produit, pas seulement un logo. Méthode : skills `brand-identity` et `logo-design` lus avec leurs références et employés comme méthode (un mécanisme par direction, un seul élément fort, logo dessiné en noir d'abord, rendus regardés à 16 et 32 px, audit SVG). Travail réparti entre agents : trois pour l'audit, trois pour les territoires, trois pour la production. Résultat formalisé dans le [Drivy Brand System](brand-system.md).

**Statut : proposition.** Aucun fichier de l'app n'est modifié. Les écrans « après » sont des maquettes HTML capturées sous Windows, donc en Segoe UI et non en SF Pro, sur une carte schématique. Rien n'a été vu tourner sur appareil.

## 1. Audit de l'identité actuelle

### Ce qui a déjà une personnalité
- La ligne de temps du replay : lacunes GPS en pointillé, pastilles d'observation au-dessus de la piste.
- Les repères de carte : disque blanc à anneau coloré, en tirets tant que l'envoi est en attente.
- Les 12 pictogrammes de signalement (grille 64, trait 3,2 arrondi).
- L'heure en très gros sur Aujourd'hui et le chrono de leçon, en chiffres tabulaires.
- La palette ardoise bleutée et un cobalt tenu à trois rôles : action, sélection, trace.
- Les filets de 0,5 pt à la place des ombres, les rayons concentriques.

### Ce qui est générique
- Profil et réglages : liste groupée système.
- Progression : du texte et trois points de 7 pt, aucune représentation du chemin parcouru.
- Dossier et listes de leçons : sélecteur segmenté, lignes à chevrons, aucune image.
- Bilan : page de texte ; l'aperçu du trajet n'a ni départ ni arrivée.
- Carte : fond Apple standard beige, trait bleu uni.
- Lancement : écran vide. Aucun langage de mouvement propre.
- App Icon : un « d » blanc centré sur un carré cobalt, sans variante sombre ni teintée.

### Incohérences entre surfaces
- Trois signes : le « d » sur iOS, une flèche de navigation jamais approuvée sur le web, aucun symbole sur la page de connexion Keycloak.
- Deux cobalts (#245BD6 natif, #285CC4 web) et trois bleus sombres.
- Pas de wordmark dessiné, pas de favicon ni de manifest web, `theme-color` sombre verdâtre (#1d2520).
- `scripts/generate-app-icon.ps1` est obsolète et écraserait l'icône s'il était relancé.
- Le nom affiché de l'app est « Drivy Essais ».

Constat : la personnalité existe, mais elle est enfermée dans le replay. Le reste de l'app ne parle pas la même langue.

## 2. Directions explorées

Trois territoires stratégiquement distincts, chacun développé jusqu'au logo, à l'icône et à deux écrans.

| | A — La trace | B — L'instrument | C — Côte à côte |
|---|---|---|---|
| Ce qui est mis en avant | l'objet : le trajet annoté | l'outil : la mesure | la relation : moniteur et élève |
| Mécanisme | une ligne qui porte des moments : trait à bouts ronds + repère annelé | la graduation : crans, repère majeur, chiffre lu sur une règle | deux présences accolées dont l'une continue seule |
| Élément fort | la trace | le chiffre tabulaire | la paire de couleurs cobalt + vermillon |
| Palette | cobalt et ardoise conservés, un gris de rail ajouté | panneaux encre sur carte claire, cobalt en index | cobalt + vermillon #DB5A2A |
| Typographie | SF Pro, heures alignées contre un rail | SF Pro, capitales espacées, chiffres de 52 pt | SF Pro inchangé |
| Carte | grise, trace seule en couleur, départ annelé | grise, crans de minute sur la trace | inchangée (trace doublée écartée) |
| Mouvement | tracer, puis poser | caler sur un cran | rejoindre, lâcher |
| Logo | le d relu : anneau (repère) mordant une capsule (trace) | d dont la hampe est le repère majeur d'une graduation | d en deux pièces : demi-disque et hampe |
| App Icon | la trace traverse la tuile à fond perdu | face d'instrument encre, graduation au bord | fond clair, hampe vermillon qui sort du cadre |
| Écrans transformés | carte, replay, dossier, agenda, bilan, progression | leçon en cours, replay, agenda ; partiel ailleurs | progression, bilan, agenda ; rien sur la leçon en cours |
| Risque principal | ressembler à une app de course à pied | froideur, « tableau de bord SaaS » | vermillon proche du rouge d'erreur, lecture « pause » |

Idées de logo écrites puis écartées après rendu : virage + repère (se lit sèche-cheveux), chicane (un S, proche de Simy), trait à 45° + repère (curseur de réglages), deux anneaux reliés (c'est le symbole système du trajet), d à anneau détaché (se lit « ol »), vernier (égaliseur), deux capsules décalées ou inclinées (histogramme, barre oblique, pause).

## 3. Direction retenue : A — « La trace »

Comparaison sur les critères du produit, de 1 à 5. Ce sont des jugements, pas des mesures.

| Critère | A | B | C |
|---|---|---|---|
| Le GPS et la leçon au centre | 5 | 4 | 2 |
| Reconnaissable sans logo, sur combien d'écrans | 5 | 3 | 3 |
| Part de ce que Drivy possède déjà | 5 | 3 | 2 |
| Juste pour le moniteur, l'élève et l'école à la fois | 4 | 3 | 4 |
| Sobriété, pas de sur-marquage | 4 | 3 | 3 |
| Lisibilité en conduite | 5 | 4 | 5 |
| Réalisable en SwiftUI et MapKit sans dépendance | 4 | 4 | 3 |
| Singularité du signe | 3 | 2 | 4 |

Pourquoi A :
- c'est la seule direction qui change la leçon en cours, la carte, le dossier, la progression, l'agenda et le bilan avec deux primitives ;
- elle généralise un vocabulaire déjà dans l'app (replay, repères de carte) au lieu d'en importer un ;
- elle prolonge la promesse écrite dans le dossier de conception : le trajet comme support de l'explication ;
- elle ne demande ni seconde couleur ni police.

Ce que A reprend des deux autres : de B, la lecture à quatre niveaux (l'ancienne jauge à trois points ne montrait pas « pas encore vue ») et un grand chiffre tabulaire par écran de terrain ; de C, l'exigence d'un signe net en une couleur. Écarté de B : capitales espacées, panneaux encre, crans de minute sur la trace. Écarté de C : le vermillon et le double filet.

Faiblesses assumées de A :
- le signe reste un « d ». C'est une évolution du logo du 4 octobre, pas une rupture : le « d » reçoit une raison (un repère posé sur une trace) et une icône composée. Le « d » en deux pièces de C est plus singulier en silhouette, mais sans lien avec le produit ;
- le risque « app de course » est réel dès qu'une trace colorée domine. Parades inscrites dans le système : aucune statistique en vedette, vignettes à l'encre, carte grise ;
- les leçons d'une même école partent du même lieu : les vignettes se ressembleront en partie.

## 4. Écrans adaptés

Maquettes HTML dans [assets/brand-20261006/maquettes](assets/brand-20261006/maquettes), captures dans [assets/brand-20261006/ecrans](assets/brand-20261006/ecrans). Même structure et mêmes contenus que les captures réelles ; données fictives. Ajouts de démonstration à ne pas prendre pour des données : permis BE « Terminée », compétences « Stationnement », « Dépassement », « Attelage », titre « Moments ».

| Écran | Avant | Après | Ce qui change |
|---|---|---|---|
| Leçon GPS en cours | [capture](assets/brand-20261006/ecrans/avant-live.jpg) | [maquette](assets/brand-20261006/ecrans/apres-live.png) | carte grise, départ annelé, repères sur la trace, pictogramme sur Signaler, chrono agrandi |
| Leçon en cours, sombre | [capture](assets/brand-20261006/ecrans/avant-live-dark.jpg) | [maquette](assets/brand-20261006/ecrans/apres-live-dark.png) | même grammaire ; halo de trace sombre |
| Aujourd'hui | [capture](assets/brand-20261006/ecrans/avant-today.jpg) | [maquette](assets/brand-20261006/ecrans/apres-today.png) | les leçons suivantes forment un rail horaire ; l'« avant » montre l'état sans localisation |
| Agenda | [capture](assets/brand-20261006/ecrans/avant-agenda.jpg) | [maquette](assets/brand-20261006/ecrans/apres-agenda.png) | la journée en une ligne : passé à l'encre, leçon en cours en repère cobalt, suite en stations creuses |
| Dossier élève | [capture](assets/brand-20261006/ecrans/avant-dossier.jpg) | [maquette](assets/brand-20261006/ecrans/apres-dossier.png) | vignette de trace sur chaque leçon réalisée |
| Bilan d'une leçon | [capture](assets/brand-20261006/ecrans/avant-bilan.jpg) | [maquette](assets/brand-20261006/ecrans/apres-bilan.png) | parcours de compétence, trajet avec départ, arrivée et repères, fil des moments |
| Replay | [capture](assets/brand-20261006/ecrans/avant-replay-dark.jpg) | [maquette](assets/brand-20261006/ecrans/apres-replay-dark.png) | pouce = repère courant ; lacune GPS aussi sur la carte |
| Progression | [capture](assets/brand-20261006/ecrans/avant-progression.jpg) | [maquette](assets/brand-20261006/ecrans/apres-progression.png) | fil dernière leçon → prochaine étape ; parcours par compétence, quatre états |
| Lancement | [capture](assets/brand-20261006/ecrans/avant-launch.jpg) | [maquette](assets/brand-20261006/ecrans/apres-launch.png) | symbole seul, sans tuile ; il se trace à l'ouverture |
| Agenda iPad | [capture](assets/brand-20261006/ecrans/avant-agenda-ipad.jpg) | [maquette](assets/brand-20261006/ecrans/apres-agenda-ipad.png) | même rail, capsule d'onglets en haut |
| Bilan iPad | [capture](assets/brand-20261006/ecrans/avant-bilan-ipad.jpg) | [maquette](assets/brand-20261006/ecrans/apres-bilan-ipad.png) | texte à gauche, trajet et fil des moments à droite |

Doutes relevés pendant le maquettage :
- le rail horaire à hauteur de ligne casse avec Dynamic Type : la position des stations doit se calculer depuis la ligne de base du titre ;
- à grande taille de texte, le parcours passera sous le libellé de la compétence ;
- la lacune tiretée demande une `MapPolyline` à part ; les repères en tirets sont des vues `Annotation` ;
- les repères sur la carte n'ont pas de libellé visible : à traiter pour VoiceOver ;
- en sombre, le halo d'un repère sur la carte prend la couleur du halo de trace (#10151C), pas `surface`.

## 5. Ce qui est conservé

- Le nom, le cobalt #245BD6 / #91B5FF et ses trois rôles, toute la palette ardoise et les sémantiques.
- SF Pro et l'échelle Dynamic Type ; Source Sans 3 sur le web.
- Rayons 12 / 16 / 24, boutons 52 et 64 pt, filets, ombre réservée à la carte, Liquid Glass réservé aux boutons de carte.
- La structure de tous les écrans, la navigation, les contrôles natifs.
- Les 12 pictogrammes de signalement et la grille de la feuille Signaler.
- Le marqueur de position, le halo de trace, les repères en tirets « en attente », la ligne de temps du replay.
- Profil, réglages et formulaires, laissés natifs.
- Le « d » minuscule comme lettre du signe.

## 6. Ce qui change

| Élément | Avant | Après |
|---|---|---|
| Carte | standard beige | atténuée grise, la trace seule en couleur |
| Trajet | ni départ ni arrivée | départ annelé, arrivée pleine en bilan et replay, lacune tiretée |
| Niveau d'une compétence | trois points | parcours à trois stations, quatre états lisibles |
| Aujourd'hui, Agenda du jour | lignes séparées par des filets | rail horaire |
| Dossier | deux blocs de texte | fil « dernière leçon → prochaine étape » |
| Listes de leçons réalisées | texte seul | vignette de trace à l'encre |
| Bilan | liste d'observations | fil des moments le long d'un rail |
| Bouton Signaler | bulle de texte | pictogramme « poser un repère » |
| Mouvement | appui seulement | tracer puis poser, à trois endroits |
| Lancement | écran vide | le symbole se trace |
| Logo | d continu centré sur carré cobalt | repère mordant une trace ; wordmark et lockups |
| App Icon | une variante | composition à fond perdu ; défaut, sombre, teintée |
| Tokens | — | `rail` ajouté ; `DrivyMotion.trace` et `.settle` |

## 7. Recommandations restantes

1. **Valider à l'œil** la direction, le signe et l'icône avant toute ligne de Swift. Le choix est le mien, fait sur maquettes.
2. **Implémenter par lots vérifiables sur CI** (pas de toolchain Swift sur cette machine) : (a) token `rail`, `DrivyTraceLine`, `DrivyMarker`, `DrivyCompetencyTrack` et galerie ; (b) carte atténuée, départ, arrivée, lacune ; (c) rail horaire d'Aujourd'hui et de l'Agenda ; (d) fil du dossier et fil des moments ; (e) icône, lancement, pictogramme Signaler ; (f) vignettes.
3. **Vignettes de trace** : elles demandent une polyligne simplifiée servie par l'API, sous les mêmes droits que le trajet. À spécifier avant de coder ; c'est le seul point qui touche le serveur.
4. **Qualifier sur appareil** : rendu réel de `emphasis: .muted` en clair et en sombre, lisibilité en plein soleil, Dynamic Type XXL sur le rail horaire, VoiceOver sur le parcours, mouvement et Reduce Motion.
5. **Web** : remplacer la flèche par le symbole, ajouter favicon et manifest, unifier le cobalt puis remesurer les contrastes, corriger `theme-color`.
6. **Keycloak et e-mail d'invitation** : lockup en tête.
7. **Antériorité** : aucune recherche de marque n'a été faite. « Drivy » a été le nom d'un service d'autopartage, devenu Getaround en 2019 ; une recherche professionnelle (IPI, EUIPO) s'impose avant tout usage public.
8. **Ménage** : retirer `scripts/generate-app-icon.ps1`, renommer « Drivy Essais » au moment voulu, corriger les passages de `DESIGN.md` qui disent « SF Symbols uniquement » et « AppIcon seul ».
9. **Daltonisme** : les anneaux d'appréciation portent déjà un glyphe ; vérifier par simulation que succès et danger restent distincts sur la carte grise.
