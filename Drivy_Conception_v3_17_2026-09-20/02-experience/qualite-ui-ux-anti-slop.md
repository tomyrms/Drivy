# Qualité UI/UX et prévention de l’AI slop

> Référence 3.10 · [Index](../README.md). Cette charte est une exigence de qualité proposée pour Drivy, pas une mesure automatique de l’origine d’un contenu.

**Application à la leçon :** une seule action dominante « Signaler », pas une explication sous chaque bouton. Les catégories restent nommées ; les erreurs, l’absence de GPS et la confidentialité ne disparaissent pas au nom du minimalisme. La grille de revue vérifie aussi ce qui a été déplacé dans l’aide, pas seulement un nombre de mots arbitraire. [Atelier visuel](../DESIGN/LECON.html).


La revue courante exige aussi une correspondance entre apparence et effet : pas de chevron de navigation pour un statut qui enregistre immédiatement ; pas de labels sur tous les points pour simuler une carte riche ; pas de disparition des erreurs pour alléger la composition. Le point sélectionné lie thème, statut et instant sans recourir à la couleur seule. La variante de densité est une fixture, non un résultat MapKit.

## Définition utile et frontière

« AI slop » désigne, dans son acception numérique, du contenu de faible qualité produit généralement en quantité par IA. [S69](../06-gouvernance/sources.md#s69). Le terme n’est ni un standard d’interface ni une liste de couleurs interdites. Une réalisation aidée par IA peut être examinée et pertinente ; une réalisation manuelle peut rester générique ou trompeuse.

L’objectif de Drivy est de **ne pas livrer de production non vérifiée**. On juge le résultat dans sa tâche : réserver une place, expliquer une leçon, protéger un trajet, retrouver un dossier. Une capture jolie n’est pas une preuve de bon fonctionnement.

## Identité à maintenir

Le **Cartographie native (option A)** place le trajet réel et son explication au centre. L’identité repose sur l’organisation de la leçon, les mots du métier, des surfaces de lecture stables et une cartographie sobre. Elle ne dépend pas d’une décoration de route serpentante derrière chaque formulaire, d’un dégradé omniprésent ou d’une grille de statistiques sans source.

Les composants standard iOS/Android sont des points d’appui, pas des signes de manque d’originalité. L’originalité doit se voir dans la pertinence pédagogique, pas dans un bouton Retour réinventé. Les effets ne sont admis que s’ils indiquent profondeur, continuité ou état. Le [système de design](design-system.md) reste la référence des tokens ; cette charte n’introduit pas un deuxième thème concurrent.

## Dix exigences de revue

<a id="as01"></a>
### AS01 · Une tâche identifiable

Chaque écran cite un rôle, une question utilisateur et la prochaine action. Le responsable doit pouvoir expliquer pourquoi chaque bloc est présent. Un bloc retiré qui n’affecte ni compréhension ni action est candidat à suppression. L’écran de préparation n’est pas une landing page promotionnelle.

<a id="as02"></a>
### AS02 · Données et succès véridiques

Aucun chiffre par défaut pour remplir un graphique, aucune évaluation pédagogique déduite de la seule géométrie, aucun prénom réel dans les fixtures. Les données de démonstration portent explicitement ce statut dans les environnements de démonstration. « Inscrit » exige la confirmation serveur ; « Partagé » exige la publication. Un état inconnu ne devient pas « Aucun problème ».

<a id="as03"></a>
### AS03 · Hiérarchie au lieu d’accumulation

Une zone de décision ne présente pas plusieurs actions visuellement primaires concurrentes. L’arrêt de collecte reste identifiable sans un nuage de boutons flottants. Une liste dense du web n’est pas transformée en vingt grandes cartes sur tablette si cela ralentit la recherche. Les espacements regroupent des objets liés ; ils ne remplacent pas leurs libellés.

<a id="as04"></a>
### AS04 · Des mots précis et humains

Employer les noms de la [référence métier](../03-fonctionnel/regles-etats.md), avec labels adaptés à l’utilisateur. Éviter « révolutionnez », « expérience premium », « propulsé par IA » ou des félicitations automatiques sans rapport avec l’action. Drivy, sensibilisation, leçon, bilan, inscription et dossier ne changent pas de nom entre deux écrans. Les messages expliquent la conséquence et la récupération, pas le code interne seul.

<a id="as05"></a>
### AS05 · Les cas difficiles sont des écrans réels

Pour chaque interaction, livrer aussi hors ligne, chargement, vide, refus, erreur, reprise et concurrence si pertinents. Le bouton visible doit effectuer une action définie ou annoncer une indisponibilité motivée. Aucun bouton « Exporter » factice, aucun toast de succès simulé dans une version utilisable par une école. Une maquette non interactive reste explicitement une maquette.

<a id="as06"></a>
### AS06 · Respect de la plateforme sans imitation forcée

Navigation, sélecteurs, menus, clavier et feuilles suivent les conventions natives lorsque la bibliothèque retenue les expose correctement. Une surface web ne prétend pas être Liquid Glass natif. Android conserve son retour système et ses compositions adaptatives ; il ne reçoit pas une copie dessinée de l’iPhone. Les différences n’altèrent pas les règles métier.

<a id="as07"></a>
### AS07 · Accessibilité et usage réel avant effet

Les textes suivent les réglages système. La couleur n’est jamais l’unique statut. Une alternative textuelle accompagne les observations de carte ; un bouton remplace le glisser obligatoire. Un lecteur d’écran n’annonce pas un flux de positions à chaque seconde. Réduction des animations/transparences, contraste et focus sont examinés sur le rendu effectif. Les normes web et les APIs natives ont leurs champs distincts. [S68](../06-gouvernance/sources.md#s68).

<a id="as08"></a>
### AS08 · Dépendances et code examinés

Un agent ne choisit pas une bibliothèque sur la seule présence d’un exemple. Il donne la version, la source officielle, la compatibilité avec le binaire retenu et les tests de refus. Les types ne sont pas contournés pour faire passer une démo. Les secrets, autorisations et règles financières ne résident pas dans des composants d’écran. Pas de dépendance supplémentaire pour un effet qui peut être omis.

<a id="as09"></a>
### AS09 · Documentation proportionnée et traçable

Une règle canonique, des liens et une recette valent mieux que cinq formulations divergentes. Une promesse « sécurisé », « fluide » ou « compatible iOS 27 » doit donner un périmètre et une preuve. Les sources générées mais non consultées sont retirées. Les tests seulement rédigés portent NOT_EXECUTED. Une relecture ne transforme pas une hypothèse en décision approuvée.

<a id="as10"></a>
### AS10 · Validation humaine du contenu pédagogique

Le moniteur reste auteur et validateur du bilan partagé. Le cœur de Drivy ne reçoit pas un chatbot, un score de conduite automatique ou un générateur de bilan simplement parce que le SDK en permet un. Une future aide rédactionnelle aurait besoin d’un besoin validé, de provenance, d’une validation humaine et d’un traitement de données spécifique. Elle ne devrait ni compléter un trou GPS par invention ni publier d’elle-même. Cette charte n’ajoute pas une fonction d’IA à la roadmap.

## Exemples Drivy : résultat attendu

Les valeurs ci-dessous sont fictives ; elles illustrent la microcopie, pas une leçon réelle.

| À refuser | Formulation/composition proposée | Pourquoi |
|---|---|---|
| « Votre parcours exceptionnel est optimisé ! » | « Bilan enregistré sur cet appareil. Il sera envoyé à la reconnexion. » | Décrit état et prochain événement sans fausse publication. |
| « Réservation réussie » dès la pression | « Confirmation en cours… » puis « Vous êtes inscrit » uniquement après résultat définitif | Ne transforme pas une intention en droit acquis. |
| « Sold out » dans un parcours français | « Complet. Aucune place disponible actuellement. » | Terme compréhensible ; pas de liste d’attente prétendue si absente. |
| « 92 % prêt pour l’examen » calculé au GPS | « Objectif à retravailler : observation aux intersections », rédigé par le moniteur | Ne déduit pas une compétence invisible dans la trace. |
| Carte et six panneaux de statistiques sur une séance | Carte, élève/formation, objectifs, état, commandes essentielles | Distingue terrain et pilotage d’activité. |
| Un bouton gris « Continuer » sans raison | « Date de naissance requise pour cette prestation », lié au champ et à sa finalité | L’utilisateur comprend le préalable sans subir un formulaire opaque. |
| « Données supprimées » quand seul le partage s’arrête | « Trajet retiré du bilan partagé » ou état réel de la demande d’effacement | Respecte retrait, archivage et effacement distincts. |

## Méthode de livraison pour un développeur ou un agent

Avant de dessiner, lire l’écran existant dans le dossier, ses règles et sa recette. Produire un exemple nominal et un cas contraignant avec le même composant. Expliquer les interactions, la source de données et les différences iOS/Android/web. Une proposition nouvelle doit montrer quel problème de cette référence elle résout, pas remplacer la navigation par le template familier de l’agent.

La revue suit cet ordre : comportement et autorisations, contenu, hiérarchie, accessibilité, puis détails visuels. Le développeur fournit les états et un diff limité. Le reviewer ouvre les sources des APIs risquées et teste au moins un refus. Les correctifs gardent une trace du défaut et une recette reproductible. Les données élèves ne sont pas envoyées à un service de génération externe pour produire des maquettes ou des tests.

**Brief prêt à transmettre :**

> Implémente l’écran désigné de Drivy à partir de sa spécification et de ses états. Ne crée aucune donnée de succès ou statistique fictive dans le parcours réel. Préserve les règles serveur et les deux choix avec/sans GPS. Utilise les composants natifs qualifiés et les tokens existants. Traite grand texte, lecteur d’écran, fenêtre étroite, erreur, attente et refus. Toute dépendance ou capacité non vérifiée doit être signalée, pas simulée. Livre les preuves d’exécution séparément des tests seulement écrits. N’ajoute aucune fonctionnalité d’IA sans décision produit explicite.

## Décision d’acceptation, pas score esthétique

La revue note pour chaque AS : **respecté avec preuve, écart à corriger ou non applicable avec motif**. Une moyenne ne compense pas une fausse confirmation, une fuite ou un arrêt GPS inaccessible. Un défaut purement cosmétique peut être planifié, mais son importance est motivée. Aucun outil de détection d’IA ni pourcentage « zéro slop » ne constitue une validation.

La [qualification mobile](../05-realisation/qualification-mobile-ui-ux.md) prévoit les tâches d’observation et les cas concrets. Les tests documentaires de ce dossier ne vérifient ni la beauté ni l’absence d’erreur de la future application.
