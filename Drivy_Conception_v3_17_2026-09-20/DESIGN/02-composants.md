# Composants · Anatomie et comportement

> Référence visuelle 3.17 · [Accueil design](README.md) · [Valeurs canoniques](../02-experience/design-system.md).

**Atelier de référence E23/E24 :** [LECON.html](LECON.html). Les spécifications ci-dessous restent applicables ; pour la leçon, la carte et les feuilles courtes remplacent les grands formulaires permanents. Catégories sans cadre individuel, statut en lignes séparées sans chevron de navigation, une instruction commune, aucune perte de libellé accessible. Catégories et statut restent dans le même panneau ; contenu et hauteur évoluent ensemble, sans nouvelle ancre ni changement de cadrage. Le mouvement est interrompable et supprimable sans bloquer les commandes. La valeur de 200 ms de l’atelier est une proposition CSS/WAAPI, pas une cible native qualifiée. Les variantes grand texte changent la disposition au lieu de réduire les cibles.


## Source de fabrication commune

**[APPLICATION.html](APPLICATION.html)** et **[LECON.html](LECON.html)** sont deux entrées du **même code**, pas deux systèmes de composants. `atelier/ui.js` contient les primitives partagées, `atelier/workspace.js` compose les parcours hors carte et `atelier/app.js` conserve les interactions cartographiques. `workspace.css` étend les mêmes tokens, sans palette d’écran. Le [registre machine](composants-usage.json) relie tous les écrans E aux composants prévus et distingue code HTML présent, illustration antérieure et usage restant à réaliser.

Même fonction et même contexte : même renderer. Une variante se justifie par une différence de conséquence ou d’espace, jamais uniquement par le nom de la page. Les champs longs de la carte et du bilan utilisent DS03.multiline ; les champs structurés restent DS03.single/choice ; la recherche DS03.search possède un nom accessible même si son label visuel est compact.

La liste privée de la carte, les observations à inclure dans un bilan et la lecture partagée passent toutes par `UI.observationRow`. Chevron = ouvrir ; case cochée = inclure ; aucun accessoire = lire. `UI.statusAction` enregistre directement un statut LIVE, sans chevron. Une appréciation de compétence n’utilise pas ce geste : elle garde sa propre échelle et sa source.

`UI.sheetHeader` et `UI.dialog` fabriquent aussi bien le panneau cartographique que les feuilles de filtre, document et confirmation. Le contexte, le titre accessible et la fermeture sont paramétrés ; ils ne sont pas recopiés par écran. Les règles d’inertie, de focus et de conservation des données restent à traduire et qualifier nativement.

## Construire par rôle, pas par écran

Les identifiants DS01–DS16 sont conservés. DS17–DS24 donnent une forme concrète aux groupes cartographiques et métier déjà décrits ; ce ne sont pas de nouvelles fonctions. Les variantes doivent utiliser les mêmes tokens dans les mêmes rôles. Chaque composant est une projection de données autorisées, jamais un moyen de contourner le serveur.

Un composant n’obtient pas une hauteur fixe parce que sa maquette n’a qu’une ligne. Tester textes longs, grand texte, traduction future et erreurs. Au-delà de la largeur utile, empiler les contrôles plutôt que réduire leur cible tactile. Les surfaces sont opaques par défaut ; ombre uniquement pour superposition.

## Répertoire des composants

| ID | Anatomie et géométrie de référence | Variantes et adaptations | Contrat d’interaction |
|---|---|---|---|
| DS01 · En-tête objet | Retour 44 minimum, titre, sous-titre école/formation, action secondaire | Compact pendant capture ; titre 28 et sous-titre 14 hors capture ; large avec contexte iPad | Le retour conserve le contexte et ne termine pas une leçon. Nom long lisible au détail. |
| DS02 · Action | Label 16–17 semibold, icône facultative 20, hauteur custom 48 minimum | Primaire bleu ; secondaire neutre ; destructive rouge ; version compacte web sans réduire la cible | Normal, pressé, focus, en cours, indisponible avec raison. Conserver le label pendant chargement. Une mutation en attente n’autorise pas un deuxième clic. |
| DS03 · Champ | Label permanent 14–17, contrôle >=48 haut, padding 12, aide et erreur sous champ | Texte, montant, multiligne, date ; conteneur mobile pleine largeur | Erreur associée au champ ; saisie conservée. Le placeholder donne un exemple, jamais l’unique label. Montant formaté à l’affichage seulement. |
| DS04 · Ligne de rendez-vous | Heure tabulaire 16, titre 17, catégorie et lieu 14, statut lisible | Hauteur de contenu >=64 ; rangée dense web >=52 ; aucune hauteur maximale | Action Ouvrir nommée. Leçons confirmées, cours proposés et engagements inscrits sont distingués. |
| DS05 · État | Texte 14 medium, symbole facultatif, padding horizontal 8, espace 6 | Neutre, informatif, succès, vigilance, erreur | Un état n’est pas un bouton sans indice d’action. « Complet » reste un état de capacité neutre, pas une faute de l’élève. |
| DS06 · Formation | Catégorie, libellé du parcours, état validé/à vérifier | Menu natif s’il y en a plusieurs ; texte si une seule | Changer de formation relit les bonnes données ; ne fusionne pas les compétences. |
| DS07 · Observation qualitative | Compétence, niveau textuel, contexte, auteur/version | Lecture en ligne ; édition avec choix explicites, dont Non observé | Aucun curseur de note inventé. Séparer progression pédagogique et état de partage. |
| DS08 · Synchronisation | Icône, message concret, action utile si disponible | Local, transfert en attente, conflit, accès retiré | Distinguer « sur cet appareil », « reçu au serveur » et « partagé ». Ni bandeau permanent sans utilité ni succès global trompeur. |
| DS09 · État vide | Titre 21, une phrase utile, action contextuelle | Premier usage, aucun résultat filtré, absence normale de trace | Une erreur de réseau n’est pas affichée comme zéro dossier. Pas de pourcentage de progression à zéro faute de données. |
| DS10 · Erreur | Message, conséquence, données conservées, reprise possible | Champ, section, page, information sensible masquée | Une erreur locale n’efface pas une saisie. Identifiant technique copiable séparément. |
| DS11 · Confirmation | Objet, avant/après ou toutes les dates, coût/droits, conséquence, action nommée | Inscription, déplacement, archive, publication, suppression | Pour une action importante, expliciter la portée sans popup après chaque saisie. Le bouton nomme ce qu’il fait. |
| DS12 · Pièce | Nom, finalité, état technique puis humain, date, action | Transfert, vérification technique, disponible, rejeté, contrôle métier | Une pièce reçue n’est pas un permis validé. Aucune vignette d’un document interdit ou en quarantaine. |
| DS13 · Journal financier | Montant signé/typé, date, moyen déclaré, auteur, lien de correction | Liste mobile, tableau web | Encaissement, contre-écriture et remboursement distincts. Aucun total en flottants ni statut de présence modifié ici. |
| DS14 · Agenda | En-têtes dates, heures, engagements et offres ; alternative liste | Jour/liste en compact ; semaine en grand ; pas de scroll bidimensionnel imposé aux formulaires | Ouvrir/modifier via boutons ; drag facultatif seulement. Les offres ne bloquent pas un créneau personnel. |
| DS15 · Présentation | Titre, corps, fermeture/annulation, action contextuelle | Page pour long formulaire ; feuille/détail ancré pour court ; panneau latéral iPad | Focus entré/restitué, clavier non piégé ; action fixe ne masque ni champ actif ni fin de contenu. |
| DS16 · Révisions | Version, date, auteur, état courant, différences | Liste et comparaison | Ancienne publication clairement datée ; modification du brouillon ne la change pas. |
| DS17 · Panneau de capture | État local, temps de capture, objectif bref, pause/arrêt, transfert séparé | Bas sur téléphone ; panneau 320–400 sur iPad large ; sans trace = fiche normale | Arrêt local toujours accessible et indépendant du réseau. Quitter la carte n’arrête pas. Temps GPS jamais prix de leçon. |
| DS18 · Carte et chronologie | Trace mesurée, repères compacts, thème du seul repère sélectionné, curseur temps, statut écrit | Panneau compact, côte à côte, liste accessible sans carte ; anciennes pastilles numérotées dans la galerie complémentaire uniquement | Caméra et lecture indépendantes. Même identifiant entre repère/liste ; événements simultanés accessibles séparément. Une lacune reste une lacune. |
| DS19 · Offre / engagement | Intitulé, dates, statut personnel, lieu, capacité datée | Offre blanche à contour pointillé ; engagement plein avec bord gauche + texte | Offre « Disponible · Non inscrit » ; engagement « Inscrit ». La capacité ne prouve pas la place de la personne. |
| DS20 · Récapitulatif de série | Toutes les occurrences, lieu, langue, conditions, droits/coût, action | Pleine page sur téléphone ; largeur de lecture bornée ailleurs | Aucun regroupement des dates dans une infobulle. Une reconfirmation ne vaut pas acceptation d’un nouveau tarif caché. |
| DS21 · Droits de pack | Libellé de prestation, unités disponibles/réservées/consommées, paiement séparé | Lignes plutôt que jauge globale ; compteur utilisable si financement bloque | Dix leçons et une sensibilisation ne deviennent pas onze unités interchangeables. Ne pas afficher disponible=utilisable systématiquement. |
| DS22 · Navigation | Destinations nommées, sélection, accès au compte et aux avis | Tab bar mobile, rail iPad, sidebar web | Destinations par rôle déjà définies. La capture contextuelle peut masquer les onglets mais possède une sortie ; une capture active reste retrouvable. |
| DS23 · Étape d’accueil | Titre, raison des champs, progression de tâche, Continuer/Plus tard si applicable | Élève simple ; école par capacités ; moniteur invité séparé | Pas de pourcentage de profil ni pénalité pour photo absente. GPS, notifications et identité séparés. |
| DS24 · Indicateur | Nom, valeur/unité, période, fraîcheur et définition accessibles | Petit résumé ou ligne/tableau ; placeholder non chiffré si indisponible | Indicateur non autorisé omis, pas remplacé par zéro. Pas de flèche de tendance sans données comparables. |
| DS25 · Ligne d’objet | Icône ou identité, titre, métadonnée utile et accessoire sémantique ; contenu flexible | Navigation, sélection ou lecture ; nom long et grand texte permis | `UI.row` unique pour élèves, documents, compte et notifications. Un chevron ouvre un détail ; une sélection affiche son état ; une lecture ne feint pas une action. |

## Variantes obligatoires avant intégration

Pour DS02/03/15 : normal, focus clavier, pression, erreur, en cours, indisponible, texte long et grande taille. Pour DS04/19/20 : cours disponible, dernière place indicative, complet, demande en cours, inscrit, changement à reconfirmer, annulé et dernière mise à jour ancienne. Pour DS17/18 : préparation, attente de première mesure, capture, pause, fin locale, transfert différé, partiel, privé/publié, retiré et sans trace.

Ces combinaisons sont un répertoire à développer et tester, pas une explosion de composants dupliqués. Les [maquettes](MAQUETTES.html) illustrent une sélection ; les états métier restent dans les documents fonctionnels.

## Icônes et marqueurs

Dans le replay privé, la sélection reprend le pictogramme du thème dans le point et le panneau. Le statut reste lisible par un symbole distinct et un texte, jamais seulement une couleur. Les autres points gardent leurs symboles de statut. L’épaisseur SVG commune est conservée ; la variante de giratoire est itérable, pas un pictogramme officiel certifié. Le thème « Observation » n’est pas renommé « Contrôles visuels » sans confirmation de son périmètre pédagogique. Le raccourci de repère conserve sa forme de position et se distingue du signe + de Signaler.

Pour Apple, utiliser des symboles système lorsque le sens est établi : retour/fermer, calendrier, personnes, pause, arrêt, document, recentrage. Vérifier nom, disponibilité, poids et rendu dans le SDK effectivement retenu. Un nom de symbole n’est pas une garantie de compatibilité. L’icône et le texte suivent la même sémantique d’état ; une icône seule reçoit un label accessible.

Les vecteurs simples des maquettes sont des substituts documentaires originaux, pas une extraction de SF Symbols. Aucun fichier de police ni bibliothèque de symboles propriétaire n’est distribué. Le futur Android et le web utilisent leurs ressources autorisées ; aucun personnage décoratif ni série d’emojis ne remplace l’iconographie métier.

## Densité et surfaces

Lecture mobile : padding 16–20, espaces 12 dans un groupe et 24 entre sujets. Capture : réduire le contenu simultané, pas la taille de la commande Arrêter. Web : lignes et tableaux, avec paddings 12–16 et actions >=44. La séparation décorative `border` est volontairement douce ; la bordure interactive est `controlBorder`. Un champ ne repose donc pas sur une ligne trop claire pour être identifié.

Un bouton pressé emploie `accentPressed` et conserve `onAccent`. Le focus utilise un contour 3 unités avec espace de séparation ; il n’est pas coupé par le conteneur. Les séparateurs et contours sont testés sur les vraies surfaces et les préférences système, pas seulement sur une feuille blanche.

## Composition du signalement pédagogique

Réutiliser les composants de carte, commande, panneau et observation existants. La bulle **Signaler** ouvre un choix de thème à icône et libellé ; un statut explicitement actionné confirme l’enregistrement privé. Les exemples « Priorité à droite », « Stationnement », « Signalisation », « Giratoire », « Observation », « Anticipation » viennent du référentiel fictif de la démonstration. Ils ne créent pas six tables.

Le repère et le signalement qualifié sont distincts. Le numéro sur carte sert de repère de lecture, pas de nombre de fautes notées. Toute observation sans ancre reste accessible dans la liste temporelle. Les contrôles de capture sont séparés du formulaire et ne sont jamais désactivés par l’animation. Adaptation au texte agrandi et mouvement réduit obligatoires ; cibles et mouvement précis restent proposés, pas qualifiés en conduite.

## États et transitions communs

Le composant se fonde sur le résultat du service adapté, pas sur un délai choisi pour rendre l’animation agréable. Un `202` ne devient pas « Inscrit » à la fin d’une animation. Le prototype utilise des scénarios synthétiques explicitement annoncés ; l’application devra utiliser les états réels. [Règles](../03-fonctionnel/regles-etats.md), [microtextes](05-contenu-etats.md).

<a id="précisions-dinteraction-v39"></a>
## Comportements des formulaires et de la navigation
**DS03 / DS07 / DS11 :** le formulaire de bilan représente `workedOn`, `observationText`, `nextStep`. Une observation de compétence choisie exige son `context`. L’action « Retirer le niveau : non observé » supprime l’observation transmise, sans envoyer un enum supplémentaire, `null` ou une note zéro. La validation de publication ne bloque pas la conservation d’un brouillon incomplet. [F08](../03-fonctionnel/bilans-documents.md#f08).

**DS15 :** ouvrir le dialogue sur un contenu lisible, garder Tab/Maj+Tab dans ses contrôles et restituer le focus à l’appelant ou à un successeur logique lorsque cet appelant disparaît. Dans la galerie, après une archive qui retire la ligne du filtre courant, ce successeur est la recherche. Ce comportement reprend le pattern web de [S127](../06-gouvernance/sources.md#s127), sans qualifier VoiceOver ou les présentations UIKit.

**DS17 / DS18 :** retrouver une capture n’est pas en démarrer une seconde. L’horloge du replay suit les temps du jeu de points, jamais la longueur totale du tracé. Le curseur n’est pas interpolé à travers une interruption. L’observation future n’est pas décrite comme déjà atteinte. [Grammaire cartographique](03-cartographie.md).

**DS19 / DS21 :** après une demande, distinguer confirmation, refus explicite et résultat inconnu. Un résultat inconnu conserve l’intention en cours et ne libère ni ne réserve fictivement un droit. Le serveur reste la seule autorité ; les trois issues sont des scénarios dans la galerie.

**DS22 / tables :** une navigation conserve le rôle ; une recherche et son filtre persistent après une action locale. Si la sélection n’appartient plus aux résultats, la vue de détail l’indique et retire les actions de l’ancien dossier. Aucun message « zéro résultat » ne doit masquer une erreur de chargement.
