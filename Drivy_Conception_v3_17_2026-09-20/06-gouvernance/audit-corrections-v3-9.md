# Audit V3.9 : relier le design aux vrais états de Drivy

> **19 septembre 2026 · Référence 3.9**, remplace la V3.8. [Index](../README.md) · [Fonctionnalités](../01-fonctionnalites-prevues.md) · [Maquettes](../DESIGN/MAQUETTES.html).
> Documentation et prototypes documentaires seulement. L’application native et les archives sources ne sont pas modifiées.

## Résultat et niveau de preuve

Cette passe traite **sept ensembles de défauts ou de compléments d’interaction**. Plusieurs défauts sont reproduits dans le HTML livré en V3.8, pas seulement supposés à la lecture. Ils ne constituent pas des vulnérabilités ou bugs reproduits dans l’ancienne application Swift. Les références fonctionnelles et techniques sont alignées sur ces corrections, sans créer de nouvelle règle commerciale.

La direction **A · Cartographie native** reste retenue, avec sa palette claire/bleue et sa variante sombre. Swift natif, GPS et replay centraux mais capture facultative, tablette, web de gestion, cours volontaires, packs et onboarding restent conservés. Le contrat API **3.7.0 est inchangé octet pour octet**. Le design doit respecter le contrat, et non simplifier ses champs pour faire entrer une maquette dans un cadre.

Une quinzième composition complète « Mes leçons » côté élève. Les 15 compositions illustrent **16 références d’écran sur 49**. Les 33 autres ne sont pas déclarées dessinées. La consultation élève existait déjà dans le périmètre : ce n’est pas une nouvelle fonction produit ajoutée au pilote.

## Base et méthode

La source est le ZIP V3.8 complet, extrait dans un répertoire de contrôle puis copié pour correction. Sept vérificateurs hérités ont réellement été exécutés avant modification et passent. Le [rapport initial](../annexes/controle-v3-8-avant-correction.json) conserve leurs sorties : leur succès n’avait pas détecté les écarts ci-dessous.

Le contrôle structurel concerne tous les fichiers Markdown, registres, schémas, exemples et liens. La **revue sémantique approfondie de cette passe** se concentre sur les jonctions entre maquettes, rôles, capture, bilan, chronologie, inscription et archivage. Ce n’est pas une nouvelle relecture juridique de chaque offre d’école, ni une certification exhaustive de toutes les transitions métier possibles.

La navigation et les formulaires ont été exercés dans Chromium avec des données fictives. Les [preuves V3.8](../annexes/preuves-audit-v3-9.json) contiennent fichiers, lignes et empreintes sources ainsi que les observations initiales. Les lignes désignent la **source avant correction**, pas les documents courants. La [comparaison reproductible](../annexes/comparaison-prototype-v3-8-v3-9.json) rejoue les mêmes intentions utilisateur sur les deux versions.

La recherche externe est ciblée sur le texte agrandi et les dialogues web : [S126](sources.md#s126), [S127](sources.md#s127), reconsultation de [S125](sources.md#s125). Les versions Apple, les tarifs et les règles scolaires ne sont pas présentés comme tous revérifiés. Aucune nouvelle API iOS 27 n’est prescrite dans cette passe.

## Constats et corrections

<a id="v39-01"></a>
### V39-01 · La consultation élève ouvrait les commandes du moniteur

**Nature : contradiction de navigation reproduite dans le prototype. Importance : élevée pour la fidélité du design.**

Dans l’agenda élève, « Consulter la leçon » ouvrait `seance`, dont la composition expose les commandes de démarrage GPS du personnel. Des liens de gestion web pouvaient aussi conduire aux offres/achats personnels de l’élève. Cela contredit la séparation de rôle de l’architecture de l’information ; ce n’est pas la preuve d’un contournement de permissions serveur.

**Correction :** VIS15 représente E14/E04 dans une projection élève : engagement confirmé, moniteur de la leçon, informations autorisées et dernier bilan publié. Aucun objectif préparatoire privé n’est affiché comme partagé. Le bilan/replay publié reste accessible sans outil de capture. Dans les vues de gestion, un écran encore non dessiné est indiqué comme tel plutôt que remplacé par l’interface d’un autre rôle.

Le sélecteur extérieur de la galerie reste un outil de revue permettant de comparer plusieurs rôles/supports. Il ne représente pas un sélecteur donnant arbitrairement des droits dans Drivy.

**Références :** [architecture de l’information](../02-experience/architecture-information.md), [E04/E14](../02-experience/ecrans.md), [VIS15 et couverture](../DESIGN/04-ecrans-reference.md), I01 dans le [contrat d’interactions](../DESIGN/contrat-interactions.json). **Recette réelle : UX21/UX22, non exécutées.**

<a id="v39-02"></a>
### V39-02 · Revenir sur la leçon pouvait réinitialiser la capture fictive

**Nature : contradiction d’état reproduite dans le prototype. Importance : élevée.**

Une capture active contenant des points était fermée visuellement, puis le retour proposait un nouveau démarrage. Le parcours de démonstration remettait l’état à `waiting` et effaçait l’indicateur de points. La spécification demande pourtant un collecteur hors des vues.

**Correction :** la séance expose « Retrouver la capture » lorsque celle-ci est déjà ouverte ; le retour garde le même état et les mesures fictives acquises. Une deuxième demande de démarrage ne recrée pas ce contexte. Une transition normale vers la séance sans GPS demande de retrouver puis d’arrêter la capture existante, sans effacer ses points. L’arrêt lui-même reste immédiat localement, distinct de la fin de leçon et de l’envoi.

Les sélecteurs de scénario externes peuvent volontairement préparer une autre fiction pour la revue. Cette opération de laboratoire n’est pas confondue avec une navigation interne. La collecte réelle sous verrouillage, après interruption système ou révocation n’est pas testée par ces boutons.

**Références :** [cartographie](../DESIGN/03-cartographie.md), [architecture Swift](../04-technique/architecture-client-swift.md), I02. **Recette réelle : UX23 et scénarios GPS existants, non exécutés.**

<a id="v39-03"></a>
### V39-03 · Le bilan illustré ne représentait pas tout le contrat

**Nature : champs manquants et prévisualisation incomplète ; perte de saisie reproduite. Importance : élevée.**

La V3.8 montrait travail et prochaine étape, sans champ de constat (`observationText`). Un niveau pouvait être sélectionné sans son contexte ; il n’existait pas d’action explicite de retour à « Non observé ». La prévisualisation affichait une explication générique plutôt que les textes saisis. Le changement de vue recréait les valeurs d’exemple.

**Correction :** trois textes distincts, contexte requis lorsqu’une compétence est observée, retrait du niveau par absence d’entrée dans `observations`, et aperçu des valeurs courantes rendu comme texte. Le brouillon reste incomplet tant que nécessaire ; les exigences de publication ne sont pas un prétexte pour supprimer la saisie. Les contrôles d’aperçu signalent les champs manquants sans publication implicite.

Cinq commandes fictives issues de la maquette sont vérifiées contre **SaveDraftCommand existant**, dont une forme trop longue attendue invalide et une chaîne Unicode vérifiant la convention de longueur. Aucun enum `NOT_OBSERVED` n’est ajouté. La maquette ne remplace pas les contrôles de version, d’auteur, de pièce jointe ou la transaction PublishCommand.

La saisie de bilan, de profil et de configuration demeure en mémoire pendant la visite. Recharger la page la réinitialise explicitement : cela **ne prétend pas fournir la persistance native** demandée pour le produit. Une future bascule de compte devra purger les projections incompatibles au lieu de partager ce brouillon.

**Références :** [F08](../03-fonctionnel/bilans-documents.md#f08), [DS03/DS07](../DESIGN/02-composants.md), [client Swift](../04-technique/architecture-client-swift.md), I03/I07. **Recette réelle : UX24/UX25/UX32, non exécutées.**

<a id="v39-04"></a>
### V39-04 · Le curseur du replay suivait la distance dessinée, pas les temps

**Nature : incohérence visuelle reproduite. Importance : élevée pour la pédagogie.**

La position était calculée par fraction de longueur totale du chemin. En sélectionnant l’observation 2 à 24:50, le curseur se trouvait vers `(575, 320.4)` alors que son repère fictif était à `(575, 230)`. Une lacune était masquée visuellement au-dessus d’un chemin continu ; le point continuait à se déplacer. La première observation était affichée même avant son instant.

**Correction :** jeu synthétique de points horodatés, correspondance curseur/annotation, chemins réellement séparés et absence de position dans la lacune. Les limites des segments restent consultables. Avant la première observation, le panneau n’affirme pas qu’elle est déjà atteinte. La vitesse x1 utilise le temps écoulé, pas le nombre d’événements de rendu ; la lecture de la galerie se suspend lorsque le document est masqué.

La [fixture](../DESIGN/replay-fictif.json) utilise des coordonnées de dessin, pas de latitude/longitude, et ne sera pas embarquée comme vraie carte. Les points API, la caméra MapKit, le suivi manuel et les capacités d’appareil gardent leurs propres essais à réaliser.

**Références :** [DS18 et cartographie](../DESIGN/03-cartographie.md), [E24](../02-experience/ecrans.md#e24), I04. **Recette réelle : UX27/UX28, non exécutées.**

<a id="v39-05"></a>
### V39-05 · La confirmation de cours ne démontrait que l’issue favorable

**Nature : scénario de démonstration incomplet, pas défaut serveur constaté. Importance : moyenne à élevée.**

L’état en attente existait, mais « Vérifier le résultat » confirmait systématiquement l’inscription. Cela ne permettait pas d’examiner les conséquences d’un résultat inconnu ou d’une dernière place prise entre-temps.

**Complément :** la revue peut choisir confirmation, refus Complet ou résultat inconnu. Un résultat inconnu garde la même intention fictive et la commande de vérification ; il ne réactive pas un bouton créant une seconde inscription. Le refus n’ajoute ni engagement ni droit réservé. La confirmation seule déplace le cours vers les engagements.

Ce sélecteur de résultat appartient à la galerie. Le vrai client ne choisit pas sa réponse : il la lit dans l’API. Les détails de débit, d’idempotence, de requête abandonnée et de verrous restent dans les contrats déjà présents et ne sont pas déclarés exécutés.

**Références :** [F18](../03-fonctionnel/cours-collectifs.md#f18), [contenu et états](../DESIGN/05-contenu-etats.md), I05. **Recette réelle : UX26 et T existants, non exécutés.**

<a id="v39-06"></a>
### V39-06 · L’archivage perdait le filtre et la liste gardait un détail périmé

**Nature : défauts de continuité reproduits dans le prototype. Importance : moyenne.**

Après l’archivage de Noé dans une recherche filtrée, la recherche et le filtre revenaient à leurs valeurs initiales, et le focus au document. Un filtre ne trouvant personne pouvait laisser le dossier Emma et son action d’archive affichés à côté d’un compteur de zéro résultat.

**Correction :** conservation de la recherche/du filtre, suppression de la sélection lorsqu’elle ne fait plus partie des résultats, panneau neutre sans anciennes actions et focus sur la recherche après retrait de la ligne. La consultation de l’état archivé reste possible après sélection explicite dans un filtre adapté. Effacer une recherche fonctionne réellement et ne réemploie pas la précédente valeur non vide.

Cette correction de maquette ne change ni les droits d’archivage, ni les blocages par engagements ou dettes. La restauration et les résultats de lots ne sont pas soudainement simulés ; leurs critères de rendu et essais à réaliser sont précisés.

**Références :** [F22](../03-fonctionnel/gestion-web-archivage.md), [DS22/tables](../DESIGN/02-composants.md), I06. **Recette réelle : UX29/UX30, non exécutées.**

<a id="v39-07"></a>
### V39-07 · Les contrôles de rendu étaient moins exigeants que le dossier

**Nature : couverture incomplète des tests et complément clavier. Importance : moyenne.**

La V3.8 testait 150 % de texte sur une seule largeur, alors que le système de design visait 200 % et 320 CSS px. Ce n’était pas la preuve d’une impossibilité à 200 %, mais une différence entre exigence et contrôle. Certains changements de vue/état pouvaient aussi perdre le focus.

**Correction :** 128 cas de rendu normal et 120 cas à texte 200 %, dans quatre largeurs et deux thèmes. Les formulaires, textes de choix, boutons et titres concernés grandissent ; le contrôle ne se limite plus à quelques paragraphes. Le reflow ne réduit pas la police pour faire disparaître un dépassement. Les tableaux bidimensionnels peuvent défiler dans leur conteneur ; le document et ses commandes ne débordent pas horizontalement dans les cas mesurés.

Les dialogues web ont un titre accessible, un parcours Tab/Maj+Tab contenu et un retour de focus utile. Les transitions Pause/Reprendre retrouvent le bouton correspondant ; une nouvelle destination reçoit un focus de contenu. Les scripts vérifient aussi les erreurs JavaScript et l’absence d’appels externes du prototype. La relecture des images a conduit à inclure les libellés des niveaux, auparavant non agrandis dans une première correction intermédiaire.

**Références :** [système de design](../02-experience/design-system.md), [recette UX](../DESIGN/06-livraison-validation.md), [S126/S127](sources.md#s126). **Limite :** pas de qualification Dynamic Type, VoiceOver, Safari, TalkBack ou conformité globale WCAG.

## Vérifications et artefacts cohérents

La [comparaison](../annexes/comparaison-prototype-v3-8-v3-9.json) montre **12 observations améliorées** sur les mêmes intentions. Ce ne sont pas 12 bugs indépendants : plusieurs observations relèvent du même ensemble et l’agrandissement est une extension explicite de couverture.

Le [rapport du prototype](../annexes/verification-prototype-v3-9.json) contient 72 assertions, 128 rendus normaux, 120 rendus à texte agrandi et cinq cas de commande. Les couleurs restent les mêmes et les 36 contrastes opaques sont recalculés. Les contrôles du contrat hérité conservent 201 opérations, 374 schémas et 229 cas de validation. Les [scripts courants](revue-coherence.md) indiquent leurs dépendances et leurs limites.

La synthèse et le catalogue ne présentent plus une ancienne version comme la référence courante ; les apports historiques détaillés restent dans leurs journaux, au lieu d’être empilés dans la synthèse produit. Le lecteur est régénéré depuis les textes corrigés, puis ses documents, liens profonds, recherche et tailles de fenêtre sont vérifiés. Le [diff](../annexes/corrections-v3-8-vers-v3-9.patch) distingue les sources modifiées des images/rapports générés. La provenance et les empreintes conservent l’archive reçue et les versions antérieures.

**382 scénarios métier et 60 scénarios mobiles restent NON EXÉCUTÉS.** Les critères de design UX01–UX32 incluent des essais utilisateur et natifs futurs. Un test de DTO dans Chromium ne démontre ni une publication autorisée ni une conservation de données sur iPhone. Le validateur intégral du méta-schéma OpenAPI n’a pas pu être installé ; les validations de schémas/références disponibles sont séparées de ce manque.

<a id="decisions"></a>
## Ce qui reste à compléter ou décider

| Point | État honnête après cette passe | Prochaine preuve utile |
|---|---|---|
| 33 références d’écrans non dessinées | Composants/familles affectés, pas de maquette livrée pour ces écrans | Décliner selon les tranches, notamment publication collective, preuves et suppression |
| Détails visuels et densité | Direction A décidée ; pas tous les détails validés par utilisateurs | Essais avec moniteurs/élèves, fenêtre iPad, grand texte et conditions de séance |
| Première capture hors réseau | Autorisation initiale en ligne conservée, pas limite universelle de Swift | Arbitrage de périmètre puis conception/test de préautorisation si retenue |
| Une capture par bilan | Limite actuelle du contrat inchangée | Décider l’assemblage avant de le promettre |
| Régularisation des droits et tarification | Politiques proposées, pas conditions commerciales universelles | Validation de l’école et essais transactionnels |
| Suppression globale / dernier administrateur | Contrats présents, exploitation non qualifiée | Responsabilités, délais, rétentions, succession/clôture et fournisseur à valider avant publication |
| Swift, GPS et intégrations système | Architecture écrite, pas build ou appareil qualifié | Tranche native bout en bout et tests réels de fond, stockage, permissions et synchronisation |
| Android | Client futur distinct conservé | Ressources et qualification GA0 avant disponibilité |

La V3.9 réduit le décalage entre le design et les règles existantes. Elle ne remplace pas les arbitrages restants par des valeurs inventées, ne revendique pas de conformité totale et ne prétend pas qu’une nouvelle couleur ou une liste de tests rende l’application prête à publier.
