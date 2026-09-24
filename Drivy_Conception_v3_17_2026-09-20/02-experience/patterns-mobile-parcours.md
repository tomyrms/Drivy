# Patterns appliqués : téléphone, tablette et web

> Référence 3.10 · Spécifications d’interaction complémentaires aux [49 écrans](ecrans.md). Pas de nouveaux écrans ni de nouvelle navigation imposés.

**Parcours carte central :** depuis la séance, le moniteur ouvre « Signaler », choisit un thème puis un statut explicitement enregistrable. Le moment et l’ancre candidate sont ceux de l’ouverture ; rien n’est créé à l’annulation. Les repères sont retrouvables dans le replay privé et repris au bilan après sélection, sans publication ni note automatique. Les détails de [E23/E24](ecrans.md#e23) et de [R46](../03-fonctionnel/regles-etats.md#r46) prévalent sur les schémas anciens plus généraux. Pas de bouton photo live ni de remplacement par une saisie uniquement après la leçon.

## Cadre commun

Les règles serveur restent les mêmes. Un pattern explique leur présentation dans une fenêtre donnée ; il n’introduit ni un endpoint parallèle ni une confirmation optimiste sur une opération métier critique. Les [principes de plateforme](plateformes-tablette-web.md), les [tokens](design-system.md) et la [charte qualité](qualite-ui-ux-anti-slop.md) s’appliquent ensemble.

Les heuristiques de contrôle et de visibilité motivent les compositions proposées ; elles ne prouvent pas leur efficacité sans observation. [S67](../06-gouvernance/sources.md#s67). Les tailles 600/1024 de Drivy sont des seuils internes provisoires : elles ne sont pas rebaptisées « classes Apple » ou « classes Android ». L’adaptation dépend de la place réellement disponible et de la taille du texte. [S84](../06-gouvernance/sources.md#s84).

<a id="px01"></a>
## PX01 · Préparer et enregistrer une leçon

**Écrans :** [E22](ecrans.md#e22), [E23](ecrans.md#e23), [E44](ecrans.md#e44). **Question :** est-ce la bonne leçon et est-ce que cet appareil enregistre ?

Sur téléphone, le contexte de séance précède la carte : nom, catégorie, heure et objectifs. Le choix avec/sans enregistrement est présenté avant le départ. Pendant la capture, la carte devient dominante, avec un bandeau stable donnant l’état local et l’accès immédiat à l’arrêt. Une zone séparée indique les données en attente de transfert ; elle ne remplace pas l’état de collecte.

Sur tablette large :

```text
[Retour à la séance]      Élève · Formation       [État local]
┌────────────────────────────────┬─────────────────────────┐
│                                │ Objectifs de la leçon  │
│       Carte et trajet          │ Situation de collecte  │
│                                │ Pause      Arrêter      │
│ [Recentrer]                    │ État du transfert      │
└────────────────────────────────┴─────────────────────────┘
```

La colonne peut se transformer en panneau sur fenêtre étroite, mais l’état et l’arrêt restent accessibles. Le focus clavier reste sur l’action courante si sa position change ; une rotation ne crée pas un autre collecteur. La carte ne recentre pas continuellement après un déplacement manuel : le bouton Recentrer réactive un suivi explicitement visible. Le réglage de caméra ne touche pas au GPS.

**Cas contraignants :** appareil non qualifié, localisation approximative, permission refusée, premier point absent, réseau coupé, collecte arrêtée par le système. Dans ce dernier cas, afficher l’interruption constatée et l’état des données conservées, sans prétendre que les dernières minutes ont été enregistrées. Le moniteur peut continuer la séance sans trace. Une permission OS acceptée ne constitue jamais le choix de l’élève.

**Recette d’usage :** à l’arrêt, le participant trouve comment interrompre la collecte sans aide, peut expliquer si l’élève voit déjà la trace et distingue un arrêt GPS d’une fin de leçon. Le support réel et l’accessibilité sont vérifiés dans [MOB001–MOB012](../05-realisation/qualification-mobile-ui-ux.md#mob001).

<a id="px02"></a>
## PX02 · Revoir une situation sans perdre le contrôle

**Écrans :** [E24](ecrans.md#e24), [E08](ecrans.md#e08), [E09](ecrans.md#e09). **Question :** que s’est-il passé ici et quelle observation appartient au bilan partagé ?

La chronologie suit les horodatages enregistrés. La lecture x1 reflète les intervalles temporels ; un grand trou reste signalé, sans interpolation présentée comme une preuve. Un aperçu de tout le trajet est ajusté une fois à l’ouverture. Zoom manuel et pause de lecture sont deux actions distinctes. L’utilisateur reprend volontairement le suivi de caméra, sans lutte permanente contre l’application.

La liste d’observations constitue une alternative utilisable à la carte. Sélectionner une observation donne son contexte et son statut privé/partagé ; l’élève ne reçoit que les éléments publiés. La lecture au clavier et au lecteur d’écran passe par des commandes « observation précédente/suivante » et une valeur temporelle compréhensible. Un curseur graphique n’est pas le seul moyen d’avancer. [S68](../06-gouvernance/sources.md#s68).

En mode réduction des animations, préférer des changements de position discrets ou une transition réduite, sans balayage immersif imposé. Ne pas lire vocalement chaque coordonnée. Quand la géométrie est retirée, expliquer son indisponibilité et conserver uniquement le bilan textuel encore autorisé ; aucune mini-carte résiduelle ne subsiste.

**Point de revue :** la capture complète non publiée reste privée ; les points arrivés tardivement ne réécrivent pas un ancien bilan. La pagination ne fabrique pas de pauses. Ces règles sont celles de [GPS/replay](../03-fonctionnel/gps-replay.md), pas un réglage esthétique.

<a id="px03"></a>
## PX03 · Voir un cours puis s’inscrire

**Écrans :** [E25](ecrans.md#e25), [E26](ecrans.md#e26), [E31](ecrans.md#e31). **Question :** ce cours est-il seulement proposé ou suis-je inscrit à toutes ses dates ?

L’agenda distingue visuellement et textuellement offres et engagements. Les offres ne remplissent pas artificiellement le temps personnel comme des rendez-vous confirmés. Une fiche affiche toutes les dates, le lieu, la langue, les préalables, le coût ou droit utilisé, la capacité connue et son état. Sur petit écran, les dates restent lisibles avant le bouton, pas cachées dans une infobulle.

Séquence affichée : **Non inscrit → Confirmation en cours → Inscrit**, ou **Complet / refus expliqué**. Durant une réponse perdue, reprendre la même opération. Le bouton ne peut pas lancer plusieurs intentions parallèles. Le web, la notification et le lien profond ouvrent la même offre, jamais une inscription automatique.

Une modification des dates montre l’avant/après, les conditions préservées et l’action demandée. « Reconfirmer » ne rachète pas le cours. Un paiement en pack n’affiche pas une valeur zéro qui laisserait croire la formation gratuite : afficher le droit utilisé. Pas de liste d’attente ajoutée par une maquette sans fonctionnalité spécifiée.

<a id="px04"></a>
## PX04 · Onboarding avec raisons et reprise

**Écrans :** [E38](ecrans.md#e38) à [E44](ecrans.md#e44), [E47](ecrans.md#e47). **Question :** pourquoi cette information est-elle demandée maintenant ?

L’élève et le responsable ont des séquences différentes. La progression représente les étapes utiles de ce parcours, pas un pourcentage universel de profil parfait. La photo facultative propose « Plus tard » sans pénalité graphique. Les champs ont un label permanent, un clavier pertinent et une erreur qui préserve la saisie. Coller un mot de passe ou code reste possible ; aucune contrainte de mémorisation arbitraire n’est ajoutée.

Le passage web/app reprend seulement les données effectivement confirmées. Un brouillon local non synchronisé n’est pas promis sur l’autre appareil. Le changement d’école est annoncé avant d’appliquer le parcours ciblé. Les permissions système ne sont demandées qu’au moment de l’action utile : consultation de replay sans localisation, notification facultative, capture côté moniteur seulement.

À taille de texte élevée, la page défile naturellement et le bouton ne recouvre pas le dernier champ ni le focus. Les formulaires gèrent clavier matériel et virtuel. Ne pas réduire la police pour faire tenir une étape dans une capture de maquette.

<a id="px05"></a>
## PX05 · Gérer un dossier sans transformer l’archive en effacement

**Écrans :** [E34](ecrans.md#e34) à [E37](ecrans.md#e37). **Question :** quelle personne et quelle formation sont concernées, avec quelles conséquences ?

Le bureau privilégie la table paginée et les filtres explicites. La tablette utilise liste/détail si la fenêtre le permet ; le téléphone donne un résultat lisible puis la fiche. Une sélection de lot indique son périmètre : page visible ou sélection explicite, jamais « tous les élèves » par extrapolation d’un filtre partiellement chargé.

Avant archivage, l’aperçu montre engagements, droits, obligations et avertissements. Le résultat d’un lot distingue réussites et refus individuels. Le raccourci de clavier, le swipe et le menu contextuel mènent au même contrôle, sans contourner l’aperçu. Une icône de poubelle n’est pas employée pour « Archiver » si elle suggère l’effacement.

<a id="px06"></a>
## PX06 · Statistiques lisibles et honnêtes

**Écrans :** [E33](ecrans.md#e33), [E45](ecrans.md#e45), [E46](ecrans.md#e46). **Question :** de quelle période, unité et portée parle ce chiffre ?

Chaque indicateur donne période, unité, périmètre et fraîcheur. Une série temporelle ne remplace pas un instantané défini dans [M01–M09](../03-fonctionnel/statistiques.md). L’absence de droit n’affiche pas zéro ; l’absence de donnée n’est pas une croissance nulle. Les montants passent de centimes stockés à une présentation locale sans recomptage des packs.

Un tableau de valeurs ou résumé textuel accompagne le graphique. Le survol n’est pas indispensable pour comprendre une valeur sur tablette. Les animations décoratives de compteur n’améliorent pas la fiabilité d’un total. Le web peut montrer davantage de détails que le mobile, mais pas une formule de calcul différente.

## Contrat de remise d’un écran

La livraison associe état nominal, au moins un refus, taille étroite/large, grand texte, parcours clavier/lecteur d’écran et source de chaque donnée. Les liens F/R/E existants sont conservés. Les prototypes éventuels peuvent simuler un serveur uniquement avec une mention visible ; cette simulation ne devient pas le comportement d’une version pilote réelle.

## Rectification sans faux succès

Sur le relevé, la confirmation de présence porte seulement sur la présence. Sur la fiche de droit, l’action ADMIN montre la quantité dérivée, le lot et la conséquence avant confirmation. Sur la formation, le statut « À vérifier de nouveau » renvoie à la preuve touchée. Pas de badge vert unique fusionnant paiement, cours suivi et droit disponible ; une source manquante ne se remplit pas avec du texte généré.
