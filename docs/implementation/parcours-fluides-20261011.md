# Parcours terrain fluides — deuxième passe (10-11 octobre 2026)

Suite du [démarrage instantané](demarrage-instantane-20261010.md), à la demande du porteur : « continue de fluidifier les parcours ». Deux audits en lecture seule (fin de leçon, pendant le trajet), puis corrections ; une relecture QA du lot.

## « Commencer la leçon » sans écran intermédiaire

Avant : la fiche s’ouvrait, se chargeait (squelette), le bouton « Commencer la leçon » passait en attente, puis « Démarrer le trajet », puis le rideau. Quatre états visibles avant la carte.

Maintenant, depuis Aujourd’hui : l’accord de l’élève est lu (lecture seule, attente dans le bouton). S’il vaut pour l’information actuelle de l’école et que la localisation exacte est accordée, le rideau se montre, la leçon commence (même file durable que la fiche, sans écran) et le trajet part ; la carte arrive avec sa première position. Sinon la fiche s’ouvre comme avant et la question d’accord s’y pose en ligne. Un départ direct qui échoue ouvre la fiche avec sa raison en tête.

Le départ du trajet sous le rideau (`SchoolTripDeparture`) est commun au démarrage instantané et à ce chemin.

## Fin de leçon

- **Une seule attente** : « Terminer la leçon » sur le trajet arrête le GPS à l’instant, sur l’appareil et sans réseau (rien n’est enregistré après), et ouvre aussitôt la fiche ; sa fin de leçon reprend la même tâche d’arrêt durable puis demande la fin à l’école. L’écran du trajet ne montre plus « Préparation du bilan… » avant elle.
- **Permis** : quand le permis n’est pas confirmé, la question vient tout de suite ; le trajet s’arrête en même temps, en tâche de fond. Le bilan s’ouvre une fois la feuille du permis descendue, plus pendant sa descente.
- **Retour** : une fois la fin confirmée par l’école, le trajet arrêté ne propose plus « Terminer la leçon » mais « Fermer le trajet » ; fermer la fiche ramène à Aujourd’hui (l’envoi du trajet continue seul) ; un bilan enregistré ferme le trajet après la descente de la feuille.
- **Fermeture sans écran vide** : la fiche garde son contenu pendant sa descente (`close()` au lieu de vider le modèle).
- **Aujourd’hui** : la dernière journée lue reste en mémoire (par compte, droits et jour, jamais sur l’appareil) et s’affiche aussitôt quand l’écran est recréé ; elle s’oublie dès qu’une leçon change ou qu’un trajet démarre, pour ne jamais montrer une leçon terminée comme à commencer.
- Une relecture des trajets inutile avant la fin d’une leçon démarrée est retirée.

## Pendant le trajet

- **Dock stable** : l’état d’envoi d’une observation flotte au-dessus du panneau ; « Signaler » ne bouge plus sous le doigt.
- **Haptiques** : un seul retour par geste (la fermeture de la palette n’en ajoute plus un) ; pause, reprise et échec en ont un.
- **Réduire les animations** : panneaux, bandeaux et changement de thème passent en fondu au lieu d’apparaître d’un coup (`DrivyMotion.present`).
- **Régularité** : horloges à la seconde à origine fixe ; icônes de commande à cadre fixe quand elles deviennent un indicateur.
- **Caméra** : glissement vers la première position enregistrée (plus de saut de zoom), changements de mode et « voir tout » animés.
- La liste d’élèves du planning réutilise le sélecteur du démarrage (recherche Drivy fixe, fonds de l’app).

## Relecture QA (agent dédié)

Corrigés : « Terminer » sur le trajet n’arrêtait plus le GPS avant la relecture réseau de la fiche (grave : hors ligne, leçon annulée, demande en file, le GPS continuait) ; trajet terminé resté affiché quand le bilan est enregistré depuis une étape poussée ; journée mémorisée périmée au retour d’un trajet ; fiche ouverte entre-temps remplacée par le départ direct ; départ direct posé après un changement de compte ; animation de groupe qui animait aussi la barre de navigation (retirée) ; retour haptique de pause joué en terminant depuis la pause.

## Vérification

IPA d’essai compilée sur chaque lot, sans avertissement Swift (un premier essai a échoué sur le temps de vérification de types du `body` de l’écran du trajet ; corps découpé en paliers). Aucun test exécuté, à la demande du porteur.

## Limites

- Rien n’a été vu tourner sur iPhone.
- Non traités : sélection et tracé incrémentaux de la carte pour les longs trajets (à mesurer d’abord), cibles de 56 pt pour la conduite, permis posé dans la même surface que l’attente (il reste une feuille), lectures en parallèle du chargement de la fiche de leçon.
