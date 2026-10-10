# Aujourd’hui, palette Signaler et fin de leçon — 4 octobre 2026

## Retour du porteur

Le porteur valide les hauteurs natives de build100. Il demande de réserver la liste secondaire d’Aujourd’hui aux prochaines leçons, de rendre Signaler plus naturel qu’une page, et de confirmer la fin de leçon sans afficher fugitivement la fiche planifiée avant le bilan. Il a précisé que « page finale » désignait le panneau Signaler.

## Changements

- Aujourd’hui : la liste secondaire devient « Prochaine leçon » / « N prochaines leçons ». Elle conserve les leçons PLANNED dont la fin prévue est strictement future, sans répéter les leçons mises en avant. Un créneau déjà commencé reste visible. COMPLETED, CANCELLED, NO_SHOW, états inconnus et créneaux expirés sont exclus. Une leçon passée sans constat conserve sa priorité « À terminer » : le temps seul ne prouve pas sa réalisation.
- Signaler : palette de commandes sur la carte sur iPhone en texte standard ; catégories et appréciations restent dans le même composant. La palette s’affiche au-dessus de la carte sans modifier sa géométrie. Sa hauteur est plafonnée à 480 pt et bornée par l’espace disponible ; aucune mesure de contenu, aucun binding de hauteur, aucun geste de redimensionnement personnalisé. Popover natif sur iPad ; feuille native en grand texte sur largeur compacte. L’instant et l’ancre sont figés à l’ouverture, les confirmations suivent seulement une écriture locale durable.
- Fin de leçon : dialogue natif « Terminer la leçon ? » avant l’arrêt GPS ou la commande de réalisation. « Continuer la leçon » annule sans mutation. Le consentement acquis sur la carte est transmis à la fiche ; les autres entrées le demandent. L’intention n’est consommée qu’une fois, y compris après annulation ou lecture impossible.
- Passage au bilan : attente neutre pendant le constat et la lecture, à la place du formulaire planifié transitoire. Les erreurs, demandes conservées, conflits et exception de permis gardent leurs contrôles de reprise. Le parent protège fermeture et relecture au premier plan pendant la fin. Aucun délai artificiel ; transfert GPS indépendant du constat comme auparavant.

Aucun changement d’API, de contrat, de données de trajet, de partage ou d’identité visuelle. Les feuilles stables validées de build100 restent utilisées pour les autres parcours.

## Références et vérification

AGENTS et COMMENCER_ICI relus ; R07, R14–R16, R46, AP49, AP161–164 et T023, T025–T027, T412–T413. La décision de partage du 28 septembre prime sur l’historique de publication du dossier de conception. SwiftUI UI Patterns (sheets), UI Skills Root, Impeccable (layout, craft-floor, contexte Operate existant) et principes d’interaction appliqués.

Relecture indépendante du filtre et de la fin ; palette relue séparément, sans nouveau P0–P2 concret trouvé. Diff propre ; détecteur Impeccable layout `[]`, dont la portée principalement HTML/CSS ne qualifie pas SwiftUI. Trois tests Swift ciblés ajoutés au filtre (dont quatre cas paramétrés) ; harnais UI adaptés à la confirmation, à son annulation et à la palette. Ces tests ne sont pas déclarés exécutés sur Windows. Le porteur souhaite une IPA rapide : aucune longue campagne Apple ni capture native nouvelle n’est lancée.

Compilation Release Apple [37215218985](https://github.com/tomyrms/Drivy/actions/runs/37215218985) réussie sur `ffd860cf08450473c09a24bb190f0a38f220c490`. IPA 0.7.0/build101 non signée téléchargée ; empreintes du paquet, des métadonnées et du verrou de dépendances vérifiées. [Preuve de livraison](proofs/today-signal-finish-20261004.json). Signature et installation avec iLoader par le porteur. À qualifier sur appareil : rendu et gestes de la palette, petits écrans/paysage, VoiceOver et grands textes, confirmation avec et sans GPS, reprise d’erreur et transition au bilan. Aucun résultat physique GPS/batterie ou de fluidité revendiqué. Aucun déploiement.
