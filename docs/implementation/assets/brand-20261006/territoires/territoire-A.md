# Territoire A : « La trace »

## Idée centrale
Une leçon est une ligne qui porte des moments. Un trait à bouts ronds + un repère annelé (disque blanc cerclé) : ce couple dessine la marque, la carte, le temps, la progression et le mouvement.

## Personnalité
Un carnet de route tenu proprement : factuel, calme, précis. Jamais de performance.

## Principes graphiques
1. Plein = parcouru, gris = à venir, pointillé = inconnu (lacune GPS, envoi en attente). Le pointillé ne signifie jamais « futur ».
2. Un repère est toujours posé sur une ligne ; pas d’anneau décoratif isolé.
3. Une seule ligne par écran, deux au plus.
4. Le repère courant est le seul agrandi.

## Formes caractéristiques
Trait 3 pt (interface) / 6 pt (carte), bouts ronds. Repère : disque blanc, anneau 3 pt, halo blanc qui interrompt la ligne. Départ : petit anneau encre. Rayons 12/16/24 conservés.

## Palette
Gardés tels quels : cobalt #245BD6 / #91B5FF, texte #18212B / #F2F5FA, canvas #F7F8FA / #10151C, surface #FFFFFF / #19222E, sémantiques. Ajoutés : `rail` #C3CDD9 / #3A4757 (ligne non parcourue ; #D9E0E9 disparaît sur blanc) et `lacune` #8795A8 / #7C8A9C (pointillés).

## Traitement de la couleur
Cobalt = ce qui est vivant ou atteint : trace en cours, repère courant, action. Le passé est à l’encre (vignettes, rail du matin). Les sémantiques ne vivent que dans l’anneau d’un repère.

## Typographie
SF Pro inchangé. Traitement propre : l’heure est une graduation. Heures et durées en chiffres tabulaires semibold, alignées à droite contre le rail ; libellés regular. SF Rounded écarté : il tire vers Fitness.

## Iconographie
SF Symbols et les 12 pictogrammes restent. Un seul glyphe ajouté : « poser un repère » (trait + anneau) sur Signaler.

## Style cartographique
`MapStyle.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)` : carte grise, la trace seule en couleur. Deux `MapPolyline` superposées (blanc 11, cobalt 6, `lineCap: .round`). Lacune : polyline `dash`. `Annotation` pour le départ (anneau encre 14 pt) et les repères (28 pt, anneau 3 pt). Arrivée dessinée seulement en replay.

## Surfaces et cartes
Filets 0,5 pt, ombre réservée aux panneaux flottants. Vignette de trace : carré 44 pt, rayon 12, fond surfaceMuted.

## Mouvement
Un seul geste, « tracer » : le trait se dessine (`trim`, 0,35 s, ease-out), puis le repère se pose (échelle 0,9→1, 0,18 s). Trois endroits : lancement, bilan de fin de leçon, changement de niveau. Reduce Motion : fondu. Jamais en conduite.

## Philosophie du logo
Six idées :
1. Trace en virage, repère posé sur l’apex.
2. Trace en chicane, repère au milieu.
3. Trace droite à 45° et repère décentré (le pouce du replay).
4. Deux anneaux reliés (départ, arrivée).
5. Le « d » relu : l’anneau est un repère, la hampe une trace, séparés par un halo.
6. Le « d » relu où le repère chevauche la trace et la mord de son halo.

J’ai construit 1 : rendue, elle se lit sèche-cheveux ou articulation (`symbol-black-v1`). 2 donne un S (Simy). 3 est un curseur de réglages. 4 est le SF Symbol du trajet. 5 se lit « ol » (`-v2`). Retenue : 6. Un anneau parfait et une capsule, l’anneau entame la hampe d’une morsure concave, exactement le halo des repères sur la carte. Le « d » acquis reçoit une raison ; ce n’est pas une route en forme de lettre : deux primitives, aucune chaussée.

## Philosophie de l’App Icon
La trace traverse la tuile de haut en bas à fond perdu, décalée à droite ; le repère, large, vient la mordre à gauche. Elle continue hors de l’icône. Le fond reste cobalt : assumé.

## Dans l’app (7 endroits)
1. Carte live : carte grise, départ annelé, repères sur la trace.
2. Bouton Signaler : glyphe « poser un repère ».
3. Listes de leçons : vignette de la trace réelle, à l’encre ; sans trace, trois points gris.
4. Progression : niveau = parcours à trois stations (remplace les trois points).
5. Dossier : fil vertical « dernière leçon → prochaine étape ».
6. Aujourd’hui / Agenda du jour : rail horaire, anneau cobalt sur la leçon en cours.
7. Replay : ligne de temps existante ; écran de lancement : le trait se trace.

Écarté : un fil de leçon dans le panneau live (illisible en début de leçon, distrayant en conduite) ; un parcours ordonnant les compétences entre elles (ordre inventé).

## Risques et limites
- Strava : réel dès qu’une trace colorée domine. Parades : aucune statistique (km, vitesse, allure), vignettes à l’encre, carte claire et grise, repères pédagogiques.
- Les leçons d’une même école partent du même lieu : silhouettes proches, « unique » est une promesse partielle.
- La vignette exige une polyligne simplifiée servie par l’API (non vérifié) et ne doit rien révéler à qui n’a pas le droit de voir le trajet.
- Le logo reste un « d » sur fond bleu : évolution, pas rupture. À 16 px la morsure disparaît.
- Le rail de niveau porte l’information par la position : libellé texte obligatoire (VoiceOver, daltonisme).

## Test « capture sans logo »
Passe sur la carte, le replay, le dossier, l’agenda. Échoue sur Profil, formulaires et la feuille Signaler, où rien n’est une ligne ; y forcer un rail serait du décor.
