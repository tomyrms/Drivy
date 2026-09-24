# Extensions, reclassements et exclusions

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

## Ce que signifie secondaire

Secondaire n’est pas obsolète. Les identifiants U restent stables pour comprendre les décisions de la première proposition ; les éléments intégrés au cœur ne sont plus décrits comme à développer après lui. Le porteur a explicitement corrigé le positionnement GPS et demandé l’inscription aux cours collectifs.

<a id="u01"></a>
## U01 · Reclassé : GPS et replay dans F15/F16

L’extension U01 n’est plus une phase différée. Capture volontaire, qualité/interruptions, replay et observations situées appartiennent au premier parcours. Le risque technique est traité tôt, et non utilisé pour reléguer la valeur recherchée. Les détails sont dans [GPS/replay](gps-replay.md).

<a id="u02"></a>
## U02 · Bibliothèque avancée d’itinéraires

Préparer des objectifs et des points manuels est possible dans le cœur. Une bibliothèque de modèles, partage inter-moniteurs et transformation d’un trajet personnel en itinéraire constituent une extension : revue de confidentialité, gestion de versions, nettoyage des habitudes/adresses et droits de partage. Retirer un nom ne suffit pas à garantir l’anonymat. Aucune conservation supplémentaire des traces n’est autorisée par anticipation de cette extension.

<a id="u03"></a>
## U03 · Messagerie intégrée

Les notifications de service et un contact scolaire existent sans chat. Une messagerie exige responsabilité de réponse, accès aux conversations, archivage, modération et politique de notification. Ne pas créer un chat nécessaire pour comprendre si l’inscription est confirmée.

<a id="u04"></a>
## U04 · Auto-réservation des leçons individuelles seulement

L’auto-inscription à un cours collectif est incluse en F18. La réservation autonome d’une leçon individuelle, demandes de déplacement et listes d’attente de créneaux restent différées : politique d’ouverture des disponibilités, ressources, durées et droits à stabiliser. Ne pas appliquer cette réserve aux sensibilisations publiées.

<a id="u05"></a>
## U05 · Paiement en ligne et facturation légale

Les packs composites et droits sont inclus en F17. L’intégration PSP, les paiements automatisés, remboursements prestataire, fiscalité, TVA, factures légales et rapprochement comptable sont différés. Un montant enregistré comme payé par TWINT est une information du journal, pas une intégration TWINT. Les coupons complexes et échéanciers automatiques exigent une décision distincte.

<a id="u06"></a>
## U06 · Analyses avancées, au-delà des indicateurs définis

**Reclassement V3 :** les statistiques opérationnelles et les encaissements enregistrés correctement définis passent au cœur **F23**. U06 ne désigne plus l’ensemble des statistiques. Restent différés : analyses longitudinales, comparaisons multi-écoles et prévisions nécessitant sources et finalités supplémentaires. Les scores d’aptitude, classements de moniteurs, mesure du refus GPS et taux de réussite sans population/résultat vérifié restent exclus. Une ventilation comptable ou rentabilité demande un modèle absent du pilote.

Voir [F23 et M01–M09](statistiques.md), [R92–R96](regles-etats.md#r92) et les scénarios T215–T232.

<a id="u07"></a>
## U07 · SMS et automatisations de relance avancées

Push de service, annonces ciblées et in-app sont inclus via F11/F19. Les SMS payants, relances financières automatiques et campagnes marketing restent des extensions avec coût, canal et consentements/préférences propres. Aucune obligation de livraison push pour accéder à une place.

<a id="u08"></a>
## U08 · Automatisation réglementaire étendue

Le statut d’exigence, preuve externe et validation des cours inclus sont dans F03/F18. Un assistant complet pour toutes les démarches, tous les cantons et toutes les catégories demeure différé. Les profils non qualifiés restent inactifs ; ne pas inférer un droit de conduire depuis une checklist.

<a id="u09"></a>
## U09 · Ressources avancées et cours particuliers de groupe

Sites, salles et formateurs des séries incluses sont gérés dans le cœur. Parc de véhicules partagé, remplacements complexes et suivi individuel GPS de groupes nécessitent d’autres règles. Le téléphone d’un moniteur ne prouve pas le trajet de chaque élève moto. Un libellé de véhicule ne remplace pas une réservation de ressource.

<a id="u10"></a>
## U10 · Agendas externes

Le calendrier interne est inclus. Synchronisation Google/Apple/CalDAV, invitations externes et disponibilité inter-écoles demandent des autorisations et une politique de source de vérité. Une offre non réservée ne doit pas être exportée comme engagement personnel. Aucun connecteur n’est requis pour le pilote.

<a id="u11"></a>
## U11 · Biométrie de confort

Déverrouillage local sous lease et clés sécurisées, jamais nouvelle source d’autorisation métier. À ajouter après validation des données hors ligne et du comportement de révocation.

<a id="u12"></a>
## U12 · Optimisation et déduplication de médias

Optimisation de transferts et stockage après mesure réelle ; ne pas mélanger la déduplication de médias avec l’idempotence des chunks, qui est déjà indispensable à F15. Pas de partage de fichiers entre écoles par hash sans contrôle d’accès indépendant.

<a id="u13"></a>
## U13 · Liste d’attente et rattrapage autonome de blocs

Au pilote, un cours plein affiche « Complet ». Liste d’attente, priorité de réattribution, délais de réponse et inscription autonome à un bloc nécessitent des règles supplémentaires. Aucun élève n’est inscrit automatiquement lorsqu’une place se libère. Les rattrapages restent traités par le personnel avec preuves et profil applicable.

## Exclusions conservées et précisées

<a id="x01"></a>
**X01 : score global ou aptitude automatique.** Le GPS ne mesure pas toutes les compétences de conduite ; les évaluations qualitatives restent humaines. Une future étude peut instruire une métrique, pas la faire passer pour une vérité.

<a id="x02"></a>
**X02 : gamification sans besoin démontré.** Les badges décoratifs ne remplacent ni bilan ni preuve de formation. Réexamen sur observation, pas réintroduction par parité.

<a id="x03"></a>
**X03 : identité décorative héritée automatiquement.** Les anciens fonds/effets ne constituent pas la DA du nouveau produit. Cette exclusion ne concerne absolument pas la carte fonctionnelle du GPS central.

<a id="x04"></a>
**X04 : interaction imposée ou élaborée en mouvement.** Aucune saisie n’est obligatoire pendant le déplacement. Cette exclusion **ne supprime pas l’observation pédagogique pendant la leçon** : conserver un moment puis qualifier un thème/statut lors d’un arrêt adapté, ou compléter au bilan. Le nombre de boutons ne constitue pas une validation de sécurité. L’ergonomie et les conditions d’usage restent à tester avec des moniteurs. Aucun accès photo en Live Map. Voir [R46](regles-etats.md#r46) et [parcours de saisie](gps-replay.md#saisie-pendant-lecon).

<a id="x05"></a>
**X05 : reconstruction écran par écran de l’ancien logiciel.** L’archive informe les besoins et risques ; la nouvelle conception conserve la valeur utile sans recopier son architecture ou supprimer arbitrairement ses données.

## Frontières de plateformes V3

Le **web de gestion, le support tablette et les onboardings** ne sont pas des extensions différées : F20–F23 et la matrice de plateformes les intègrent au pilote proposé. Android reste une cible prévue dont la disponibilité dépend d’une qualification propre ; il ne faut pas l’annoncer comme testé. Le relais GPS en direct entre téléphone et tablette, le tableau de positions de tous les moniteurs et la capture de fond dans un simple navigateur ne sont pas promis. Un outil de formulaires totalement arbitraires ou une BI universelle n’est pas ajouté pour rendre l’école configurable.
