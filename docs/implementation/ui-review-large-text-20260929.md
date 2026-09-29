# Grandes tailles de texte — contrôle des rendus

## Source fb809bc, campagne 36581812616

Les dix PNG originaux de la [campagne](https://github.com/tomyrms/Drivy/actions/runs/36581812616) ont été ouverts individuellement : trajet actif, replay, profil, signalement et fin de leçon, chacun sur iPhone et iPad en portrait clair. [Dimensions et empreintes](proofs/ui-large-renders-fb809bc-20260929.json).

La demande du runner était `accessibility3`, mais les images révèlent une limite du montage de contrôle : le grossissement apparaît sur Live, Replay et Profil ; les feuilles Signal et Fin de leçon restent à taille normale. Ces quatre captures de feuilles **ne prouvent pas** le comportement en grandes tailles. Le réglage injecté dans l’environnement SwiftUI de la racine ne suffit donc pas à qualifier toutes les présentations. Le runner doit aussi régler la catégorie de texte du simulateur avant une nouvelle campagne.

Sur les six images réellement agrandies, les commandes principales sont lisibles. Live empile Signaler, Pause et Terminer la leçon, avec défilement indépendant du contenu et de la zone d’actions. Le replay conserve le transport et la distinction d’une lacune ; l’iPhone ne montre pas la liste d’observations dans le premier viewport, contrairement à l’iPad plus haut. Cela ne prouve pas un défaut de défilement, geste non exécuté ici. Le profil agrandit les champs et conserve le bouton d’enregistrement en bas. Le profil iPad utilise encore toute la largeur dans cette version antérieure à la correction `e720c45`.

Le bandeau des fixtures réduit volontairement l’espace disponible ; il n’appartient pas au produit Release. Les originaux n’ont été ni recadrés ni recomposés. Les rendus de la nouvelle grille et les présentations modales avec réglage système restent à rattacher à leurs propres preuves. Aucun test VoiceOver physique n’est déclaré.
