# Défauts Messages : bascule de synchronisation et bouton des précédents (1er novembre 2026)

Branche `claude/messages-defauts-20261101`. Suite de `tests-ui-instables-20261101.md` : les deux défauts décrits alors.

## 1. Bulle qui bouge à la bascule « en cours de synchronisation » : confirmé, corrigé

Cause, établie sur master : à 5 s, la ligne d'état sous la bulle gagne « Synchronisation… » (15,7 pt). La liste est ancrée en bas : le texte de la bulle monte de 13,4 pt sous le doigt, 5 s après l'ajout, c'est-à-dire pendant la fenêtre où les appuis de retrait se sont perdus (cinq échecs à 5,0 à 5,8 s, runs 41229249440, 41256319407, 41257019945). Mesures : hiérarchies des runs 41229249440 (texte à y 725,7) et 41257019945 (y 712,3), et contrôle ciblé rouge sur master (run 41260444123 : cadre de la bulle 672,7 puis 659,3).

Ce qui n'est **pas** prouvé : que ce décalage soit la cause directe de l'appui perdu. Un contrôle qui tape à 4,9 s sur une coordonnée fixée à l'avance est vert sur master (run 41260444123) ; il est retiré, il ne distinguait rien. Le lien reste une hypothèse (concentration des échecs entre 5,0 et 5,8 s, aucun hors fenêtre).

Correctif (`MessagingConversationView.statusLine`, `MessagingWorkspace.hasPendingMutation`) : la ligne d'état garde sa hauteur tant que le message porte ma réaction ou une intention en cours. L'emplacement est réservé dès l'ajout, au moment où la capsule fait déjà bouger la bulle ; « Synchronisation… » le remplit à 5 s sans rien déplacer.

Essai abandonné (`b808d970`) : indicateur en surimpression sous la ligne. Il supprimait le décalage (vidéo du run 41262108155) mais, pour le dernier message, l'indicateur passait derrière le composeur, donc invisible.

À valider à l'œil : tout message sur lequel j'ai réagi garde ~16 pt d'espace sous sa bulle (la réaction retirée et confirmée libère l'espace). Choix fait pour éviter un clignotement à chaque réaction confirmée vite.

Preuves : contrôle ciblé `MessagingThreadDefectsUITests/testBubbleStaysInPlaceWhenTheSyncStateAppears` : runs 41268464654 et 41268473463, réussis ; `MessagingLatencyUITests` (la fixture et le test des cinq secondes ne changent pas) : cinq secondes réussi sur ces deux runs ; quinze secondes réussi sur 41268464654, échec sur 41268473463 par blocage du simulateur (60 s entre deux requêtes d'interface, `Tap` à 100 s au lieu de 41 s), échec identique au run 41269500778 (fenêtres de 5, 10 et 15 s manquées, requêtes d'interface de 5 à 60 s), réussi au run 41270474652 : deux passages verts sur quatre exécutions, les deux échecs venant du runner et non de l'indicateur (le contrôle de la bulle attend et trouve `messaging.mutation.slow`) ; tests métier de messagerie (`unit_only`, périmètre messaging) : run 41268482749, réussi (73 tests).

## 2. Bouton « Charger les messages précédents » derrière la barre de navigation : n'existe plus sur master

Mon constat initial venait du commit `6a46d787` (bouton à y 48 à 66, derrière la barre y 78 à 132), avant les réserves d'espace en tête de fil (`contentInsets`). Sur master, la vidéo du run 41262108155 montre le bouton sous la pastille épinglée, à environ y 206 pt, grisé avec son indicateur pendant le chargement de la page ancienne. Aucun correctif. Un contrôle que j'avais écrit échouait pour une raison de sélecteur (le libellé du bouton change pendant le chargement) : retiré. La branche `claude/cles-messagerie-169-170-141` n'a aucun commit hors de master (`git log origin/master..origin/claude/cles-messagerie-169-170-141` est vide) : aucun conflit.
