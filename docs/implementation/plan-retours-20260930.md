# Liste de travail — retours du porteur, 30 septembre 2026

Cette liste reprend les demandes de la conversation du 30 septembre. Elle complète la reprise de Claude, sans modifier la livraison de conception conservée. Une case cochée exige une réalisation et une preuve adaptées ; code écrit, compilation, test simulateur et essai physique sont distingués.

**Lot fonctionnel intégré et testé** : source produit `fe9fe6b`, reprise Apple `e4eea1c`. Décisions et réalisations : [web](web-direction-20260930.md), [carte/GPS](carte-replay-gps-20260930.md), [planification](planning-defaults-20260930.md), [dossier/progression](dossier-progression-20260930.md). Tests Apple : 218 iPhone et 10 iPad réussis ; IPA129 vérifiée. Les essais GPS, batterie, grand texte et gestes réels restent distincts.

## 0. Reprise de Claude et environnement

- [x] Lire la demande initiale, retrouver le commit et les tâches laissées inachevées.
- [x] Corriger le test de filtre des trajets : réponse d'identité synthétique incorrecte, sans retirer le contrôle des droits.
- [x] Corriger la fermeture du dossier et de ses feuilles lors d'un échec de relecture des formations.
- [x] Afficher les erreurs de l'agenda à la réapparition de l'onglet.
- [x] Vérifier le backend du homelab et ses migrations ; code serveur déjà à jour, sauvegarde antérieure vérifiée.
- [x] Rétablir Docker Desktop après l'erreur des sockets, en conservant les données existantes.
- [x] Exécuter API 218/218 sur vraie PostgreSQL Docker et web 93/93 ; builds/typechecks réussis.
- [x] Compiler et vérifier l'IPA 0.7.0/build 83 (`8547d95`).
- [x] Terminer la lecture des résultats Apple `36716875435` de cette reprise : 198/198 iPhone, 10/10 iPad, aucun échec/ignoré.
- [ ] Vérifier sur appareil le parcours complet « Démarrer maintenant → préparation GPS ».

Preuves et détail : [reprise](reprise-bugs-20260930.md), [état](STATUS.md).

## 1. Carte et replay — agent carte/GPS

- [x] Suivre automatiquement le point pendant la lecture du replay, avec une caméra comparable au suivi GPS d'AllTrails.
- [x] Orienter la carte selon le déplacement pour voir clairement la direction prise.
- [x] Respecter le mode de suivi/orientation choisi, y compris après pause, déplacement du curseur ou reprise.
- [x] Permettre l'exploration manuelle de la carte, puis le retour explicite au suivi.
- [x] En leçon active, faire du bouton de recentrage une commande de suivi avec orientation, avec état compréhensible.
- [x] Gérer l'arrêt, les points sans direction fiable, les changements de direction et les ruptures de trace sans mouvements trompeurs.

## 2. Qualité du trajet et usages en leçon — agent carte/GPS

- [x] Diagnostiquer pourquoi la trace paraît peu dense, saccadée et éloignée des routes : acquisition, filtrage, stockage, transfert ou rendu.
- [x] Améliorer le rendu et le réglage de précision Core Location selon l’alimentation ; aucune fréquence physique supérieure n’est encore attestée.
- [ ] Mesurer la densité, la précision sur route, la fluidité réelle et la consommation sur appareil.
- [x] Comparer MapKit/Core Location et Mapbox à partir de leurs documents officiels. L'ancien projet utilisait Mapbox ; aucun code de cet ancien dépôt ne doit être importé.
- [x] Distinguer trace réellement mesurée, interpolation d'affichage et éventuel recalage sur route. Ne jamais présenter une position ou un trajet calculé comme une mesure réelle.
- [x] Afficher immédiatement les signalements persistés sur la carte de la leçon active, sans attendre le replay.
- [x] Retirer le nombre de positions enregistrées de l'interface terrain.
- [x] Permettre l'annulation de la leçon depuis le panneau actif, sans imposer l'enregistrement d'un bilan.
- [x] Arrêter et conserver correctement la capture lors de cette annulation, en respectant les états serveur et les demandes incertaines.
- [ ] Vérifier sur appareil suivi, orientation, précision, fluidité, interruptions et consommation ; ne pas déduire ces résultats du simulateur.

## 3. Planification et valeurs par défaut — agent planification

- [x] Rendre le lieu de rendez-vous facultatif au démarrage immédiat et à la planification.
- [x] Conserver le champ de lieu pour ceux qui souhaitent le renseigner.
- [x] Ajouter une préférence de formation par défaut dans les réglages et l'utiliser lorsque ce choix est valide pour l'élève.
- [x] Préselectionner le moniteur connecté lorsqu'il est éligible : Luc s'il planifie comme moniteur, un autre moniteur pour son propre compte.
- [x] Conserver la possibilité de changer le moniteur.
- [x] Ajouter un tarif par défaut configurable depuis les réglages web ou natifs, puis le préselectionner quand il est applicable.
- [x] Garder l'intervalle entre deux leçons et les autres détails de rendez-vous, en les présentant comme options secondaires.
- [x] Placer procédures et conditions d'annulation dans des accès discrets en bas du formulaire, avec documents accessibles et obligations d'adoption conservées.
- [x] Réduire le nombre d'interactions pour arriver à une leçon créée, sans confirmer à la place de l'utilisateur une écriture ni élargir les droits.
- [x] Persister les préférences et vérifier leur application après rechargement/reconnexion, sur les interfaces concernées.

Interprétation implémentée et testée : « formation par défaut » doit sélectionner une formation autorisée de l'élève, éventuellement à partir d'une offre préférée ; ce réglage ne crée pas une inscription implicitement. Un tarif par défaut reste une version commerciale valide, modifiable avant confirmation.

## 4. Dossier élève et filtres — intégration principale

- [x] Conserver les filtres déjà présents dans le dossier.
- [x] Ajouter le filtre par année précise.
- [x] Ajouter le filtre par mois précis.
- [x] Permettre de combiner mois et année, ou d'utiliser chacun séparément.
- [x] Prévoir un retour simple à l'ensemble des leçons et un état vide compréhensible.
- [x] Appliquer les filtres aux données autorisées avec la bonne pagination, sans faire passer une page partielle pour tout l'historique.

## 5. Progression, compétences et synchronisation — intégration principale

- [x] Revoir les liens entre dossier, leçon, observations, bilan et progression.
- [x] Corriger les données périmées après une modification, un retour d'écran, un changement d'onglet ou une reconnexion.
- [x] Vérifier que moniteur, élève et administration voient les données prévues par leurs droits, avec les règles de partage du 28 septembre.
- [x] Conserver le principe apprécié des trois points pour les niveaux de compétence.
- [x] Clarifier l'état « pas encore vu »/découverte, « avec accompagnement » et « en autonomie » dans la représentation.
- [x] Permettre de revenir à « pas encore vu » après une sélection accidentelle, avec sémantique serveur correcte et sans falsifier une observation historique.
- [ ] Revoir l'interface de sélection et de lecture des compétences, y compris iPad, grand texte et accessibilité.
- [x] Ajouter les tests utiles de propagation et de retour à l'état initial ; vérifier la durabilité après relecture.

## 6. Observations et bilan — intégration principale, cohérence avec le design

- [x] Rendre plus compact le composant « À retravailler / Attention / Points positifs » de la leçon.
- [x] Revoir la présentation des cadenas : conserver une visibilité compréhensible sans icônes envahissantes.
- [x] Appliquer la correction aux autres usages du même composant.
- [ ] Vérifier les observations compactes peuplées sur appareil ; les captures Apple de ce lot contiennent un état vide.
- [x] Compacter et clarifier également le bilan lorsque sa présentation répète ces problèmes.
- [x] Conserver le partage et la confidentialité effectifs ; le changement visuel ne modifie pas les droits.

## 7. Nouvelle direction artistique de la webapp uniquement — agent design

Choix explicitement retenu par le porteur : **sobre et précise, listes compactes, carte dominante, peu de cartes décoratives, couleurs discrètes**. Il demande une refonte réelle de l'apparence actuelle de la webapp, qu'il juge trop générique et artificielle. **Clarification explicite : mobile/tablette/desktop désignent les formats de la webapp ; aucune refonte globale de l'identité native iOS/iPadOS n'est demandée.** Les changements natifs restent limités aux parcours et composants ciblés dans les sections 1 à 6.

- [x] Parcourir le catalogue UI Skills et sélectionner les guides réellement nécessaires pour chaque chantier.
- [x] Définir pour le web les principes de composition, typographie, densité, couleur et hiérarchie.
- [x] Refaire la webapp sur desktop, mobile et tablette, en priorisant une interface de bureau pratique.
- [x] Conserver le thème et l'identité native iPhone/iPad ; ne compacter que les composants explicitement visés par les retours.
- [x] Réduire les empilements de cartes, les grands blocs vides, les badges répétitifs et le texte décoratif.
- [x] Garder les actions principales faciles à atteindre et les actions secondaires accessibles sans surcharger les écrans.
- [x] Harmoniser les composants web pour que les améliorations se retrouvent partout dans la webapp.
- [x] Vérifier le rendu réel web en clair/sombre et tailles compactes/larges : navigateur à 320/390/834/1440 px, contrastes et clavier.
- [ ] Qualifier le zoom texte web à 200 % et les lecteurs d'écran sur appareil.
- [x] Vérifier séparément les captures Apple des seules modifications natives ciblées.

## 8. Livraison et preuves — intégration principale

- [x] Relire les changements des agents ensemble et résoudre les incohérences entre parcours.
- [x] Mettre à jour les décisions d'implémentation et cette liste sans modifier le manifeste de conception.
- [x] Exécuter les tests métier avec PostgreSQL réelle et les contrôles web adaptés.
- [x] Compiler et tester Swift/UI sur GitHub Actions, puis vérifier l'IPA finale pour iLoader.
- [x] Déployer les changements serveur nécessaires sur le homelab, avec sauvegarde vérifiée avant chaque déploiement : `fe9fe6b`, migrations001–021.
- [x] Vérifier services, migrations, droits et routes après déploiement : trois services actifs, empreintes des migrations, chemins de processus, santé interne et barrières HTTPS conformes. [Preuve](proofs/deployment-retours-20260930.json).
- [x] Mettre à jour `STATUS.md` avec les résultats exécutés et les essais physiques restant à faire.

Les agents travaillent sur des périmètres distincts : carte/capture/replay ; planification/défauts ; refonte visuelle web uniquement. L'intégration principale prend dossier, progression, bilan, cohérence générale et livraison.

## 9. Organisation des informations et parcours web — retour complémentaire

- [x] Auditer les destinations et les difficultés de retour entre pages, au-delà de la palette.
- [x] Regrouper le menu principal en Planning, Élèves, Équipe, Formations et tarifs, Réglages.
- [x] Faire de Planning l’accueil quotidien ; placer préparation et activation dans Réglages.
- [x] Relier chaque formation aux compétences, procédures et tarifs associés.
- [x] Conserver sélection, semaine et moniteur dans les allers-retours ; ajouter les liens vers dossier et disponibilités.
- [x] Sur mobile, ouvrir le détail à la place de la liste, avec retour et restitution du focus.
- [x] Faire passer le suivi avant les formulaires administratifs dans le dossier.
- [x] Séparer les invitations élèves et personnel ; conserver les brouillons non soumis lors des renvois de catalogue.
- [x] Vérifier les parcours au navigateur, les anciennes routes et les règles de restauration : 100 tests web, typecheck et build.
- [x] Déployer cette nouvelle organisation : `b5c6c38`, sauvegarde vérifiée avant installation ; services, migrations et empreintes des assets publics vérifiés. [Preuve](proofs/deployment-web-architecture-20260930.json).

[Décisions et répartition des informations](web-architecture-20260930.md) · [preuve de vérification](proofs/web-architecture-20260930.json).

## 10. Esthétique et ergonomie de chaque écran web — retour complémentaire

Le porteur valide le progrès de l’organisation, mais demande de reprendre les composants et l’esthétique écran par écran. Périmètre : web responsive uniquement.

- [x] Relancer des agents, parcourir les styles UI Skills et coordonner une direction cohérente.
- [x] Revoir identité, typographie, palette, espaces, contrôles, tableaux et états de sélection.
- [x] Reprendre connexion, compte, invitation, agenda, disponibilités, élèves/dossier/bilans, équipe, catalogue et réglages.
- [x] Réduire les badges ordinaires et replier les formulaires secondaires ; donner la priorité aux noms, dates, horaires et prix.
- [x] Vérifier chaque destination au navigateur sur desktop et mobile, avec contrôle complémentaire tablette et sombre.
- [x] Vérifier filtres, retours, formulaires et confirmations au clavier ; consigner les limites d’accessibilité.
- [x] Exécuter typecheck, tests et build sur le lot final.
- [x] Déployer sur le homelab après sauvegarde vérifiée et contrôler les fichiers réellement servis : `946476a`, trois services actifs, migrations 001–021 conformes, JavaScript/CSS/police identiques au build local. [Preuve](proofs/deployment-web-craft-20260930.json).

## 11. Deuxième passe des layouts web

- [x] Revoir les 18 destinations et leurs formulaires avec les guides UI Skills et trois agents.
- [x] Réduire les étages d’en-tête et les espaces inutiles ; préserver lisibilité et cibles tactiles.
- [x] Adapter la composition liste/détail à la largeur utile ; conserver sélection et retour de focus.
- [x] Recomposer annuaires, disponibilités, trajets, catalogue, réglages et entrée.
- [x] Contrôler desktop/mobile, tablette sombre, 320 px, noms longs, états vides/erreur/lecture seule et clavier.
- [x] Exécuter les 104 tests web, typecheck et build sur le lot final.
- [x] Déployer après une nouvelle sauvegarde vérifiée et contrôler les fichiers publics : `e30e4ea`, services actifs, migrations 001–021 conformes, assets HTTPS identiques au build testé. CI : 224 tests API et 104 tests web réussis. [Preuve](proofs/deployment-web-layout-pass2-20260930.json).

[Compte rendu et limites](web-layout-pass2-20260930.md).

## 12. Revue de l’application native iPhone et iPad

- [x] Répartir les écrans entre trois agents, avec UI Skills et guides SwiftUI.
- [x] Examiner les parcours, identifier les espaces inutiles et les actions peu accessibles.
- [ ] Finaliser les corrections et la revue croisée des sources.
- [ ] Compiler et exécuter les tests sur les runners Apple iPhone et iPad.
- [ ] Examiner les captures du lot courant, avec variantes de taille de texte, thème et orientation.
- [ ] Produire et vérifier l’IPA non signé pour iLoader ; consigner les limites restantes.

[Périmètre et résultats](native-ui-pass-20260930.md).
