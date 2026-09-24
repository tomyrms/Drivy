# Spécifications des 49 écrans et de leurs états

> Drivy · Dossier de conception 3.17 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Conventions d’écran

Les variantes par rôle sont des vues du même objet avec des autorisations serveur différentes. Une information masquée visuellement ne doit pas avoir été chargée sans droit. Les composants DS sont définis dans [Design system](design-system.md). Les critères fonctionnels F et tests T complètent ces spécifications ; les limites chiffrées se trouvent uniquement dans les [règles](../03-fonctionnel/regles-etats.md).

Sur chaque écran : titre explicite, retour cohérent, focus visible, contenu adaptable et libellé textuel des états. Les informations sensibles ne sont pas utilisées dans les traces techniques. Les petits écrans utilisent une page dédiée pour les formulaires longs ; les panneaux larges ne changent pas les conséquences des actions.


## Conventions communes aux écrans

Après 202/PENDING, ne pas afficher « Terminé » : conserver l’intention et sa clé, proposer une reprise/actualisation et attendre le résultat confirmé. Chaque écran passe la [revue AS](qualite-ui-ux-anti-slop.md) et la [qualification mobile](../05-realisation/qualification-mobile-ui-ux.md). La couverture neutre du sélecteur d’apps masque le privé sans changer l’état métier ou arrêter la capture.

Les [patterns](patterns-mobile-parcours.md) et la [matrice visuelle](../DESIGN/04-ecrans-reference.md) complètent les fiches. L’[atelier unifié](../DESIGN/APPLICATION.html) illustre 17 fiches dans 20 compositions courantes, avec une bibliothèque commune ; la galerie antérieure porte le total illustré à 23 fiches, 26 non dessinées. Les [composants affectés aux 49 écrans](../DESIGN/composants-usage.json) ne constituent pas 49 vues réalisées. Les variantes n’ajoutent ni écran E ni capacité serveur ; aucune maquette ne prouve les permissions réelles.

<a id="intégration-v2-aux-écrans-conservés"></a>
<a id="adaptation-des-écrans-e01e32"></a>
<a id="ajustements-transversaux-v32-sans-nouveau-parcours-principal"></a>
<a id="complément-dintégration-uiux-v34"></a>
<a id="compléments-des-écrans-existants-v35"></a>
<a id="déclinaison-visuelle-de-référence-38"></a>
<a id="cohérence-des-variantes-illustrées-v39"></a>
<a id="précisions-transversales-v310"></a>

## Socle d’accessibilité de toutes les fiches

Chaque écran E01–E49 hérite de ce socle ; ses précisions peuvent le renforcer, pas le désactiver implicitement. Fournir noms, rôles et états accessibles ; statuts textuels sans couleur seule ; cibles proposées d’au moins 44 × 44 pt sur Apple ; Dynamic Type jusqu’aux tailles d’accessibilité avec reflow, sans réduction forcée de police. Ordre VoiceOver/clavier cohérent, focus contenu et restitué à la fermeture des feuilles, erreur associée au champ. Respecter Réduire les animations, Réduire la transparence et Augmenter le contraste avec une présentation lisible et opaque au besoin. Les contrôles HTML ne sont ni un test VoiceOver ni une certification native. Les fiches suivantes conservent leurs exigences particulières.

<a id="e01"></a>
## E01 · Connexion

**Entrées :** Ouverture sans session, lien protégé, session expirée. **Public :** Tous.

**Fonction et hiérarchie :** Marque Drivy, explication courte, action Se connecter, information sur le compte ; aucune donnée scolaire avant autorisation.

**Actions et sorties :** Connexion système ; annuler ; accéder aux informations de confidentialité. Le retour du fournisseur ouvre E02 ou la destination autorisée.

| État | Comportement attendu |
|---|---|
| Chargement | Échange de session annoncé, action non soumise deux fois. |
| Vide | Pas de compte autorisé : invitation ou contact de l’école. |
| Erreur | Fournisseur indisponible ou retour invalide, possibilité de réessayer. |
| Hors ligne | Pas de nouvelle connexion ; accès natif existant uniquement selon lease. |
| Permission | Mauvais compte pour une invitation : changer de compte sans afficher les données visées. |
| Succès | Session confirmée avant toute donnée métier. |

**Traçabilité :** F01 F02 J11.

<a id="e02"></a>
## E02 · Choix d’école et acceptation

**Entrées :** Retour connexion, ouverture invitation, changement d’école via compte. **Public :** Tous selon appartenances.

**Fonction et hiérarchie :** Nom de chaque école autorisée, rôle dans celle-ci ; pour invitation, école, rôle proposé, information de collecte et conséquences.

**Actions et sorties :** Choisir école ; accepter ou refuser invitation ; changer de compte. Acceptation explicite, pas déclenchée par simple ouverture de lien.

| État | Comportement attendu |
|---|---|
| Chargement | Liste d’appartenances neutre, sans ancien nom provenant du cache d’un autre compte. |
| Vide | Aucune école : invitation nécessaire et contact. |
| Erreur | Invitation expirée ou révoquée, demander renvoi. |
| Hors ligne | Changement de contexte non préparé indisponible. |
| Permission | Refus d’accès sans révéler la liste des autres membres. |
| Succès | Nom de l’école choisi visible dans l’en-tête suivant. |

**Traçabilité :** F01 F02 J01.

<a id="e03"></a>
## E03 · Agenda du personnel

**Référence visuelle courante :** [APP02](../DESIGN/APPLICATION.html?screen=agenda). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Entrée de l’espace de travail, retour de leçon, lien de changement. **Public :** ADMIN, INSTRUCTOR.

**Fonction et hiérarchie :** Date et école ; actions prioritaires contextualisées ; liste chronologique heure/élève/formation/lieu/état. L’argent et les statistiques ne dominent pas.

**Actions et sorties :** Changer de jour ; ouvrir semaine sur écran adapté ; planifier ; ouvrir E04 ; filtrer son planning ou planning école autorisé.

| État | Comportement attendu |
|---|---|
| Chargement | Squelette de lignes sans noms fictifs. |
| Vide | Aucune leçon ce jour, action Planifier et accès au jour suivant. Filtre vide distingué. |
| Erreur | Échec de rafraîchissement avec dernière projection datée si autorisée. |
| Hors ligne | Liste préparée en lecture seule et lien vers brouillons locaux. |
| Permission | Planning école non autorisé absent ; occupations d’autres ressources anonymisées. |
| Succès | Nouvelle leçon insérée à sa place et confirmation explicite. |

**Traçabilité :** F05 F11 J02 J04.

<a id="e04"></a>
## E04 · Leçon de référence

**Référence visuelle courante :** [APP05](../DESIGN/APPLICATION.html?screen=lesson). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Planning, formation, prochaine leçon élève, notification. **Public :** Selon matrice ; contenu adapté au rôle.

**Fonction et hiérarchie :** Élève/formation, état métier, heure prévue, lieu, moniteur ; contrôle permis pour équipe ; objectifs ; bilan publié ou brouillon pour auteur ; solde secondaire.

**Actions et sorties :** Équipe : préparer, déplacer, annuler, ajouter/relire des observations pendant la leçon (thème/statut, même sans GPS), faire bilan, journal. Élève : souhait, lire bilan, contacter école. Actions fermées expliquées selon état.

| État | Comportement attendu |
|---|---|
| Chargement | Conserver le contexte non sensible du lien sans inventer l’état. |
| Vide | Objet introuvable ou retiré : retour sûr au planning, pas fiche vide modifiable. |
| Erreur | Données non actualisées, pas de confirmation optimiste d’un changement. |
| Hors ligne | Lecture autorisée et brouillon natif, actions d’engagement désactivées. |
| Permission | Ressource non autorisée renvoie une page sûre sans nom d’élève. |
| Succès | Résultat confirmé et état d’envoi distinct, avis de modification visible. |

**Traçabilité :** F05 F06 F07 F10 J03.

**Précisions de comportement :** Les repères manuels de préparation sont privés et distincts des observations vécues et de la trace mesurée ; ordre/liste accessibles et modifications versionnées. Variante élève : lecture de ses engagements/publications uniquement, aucune note préparatoire privée ni commande GPS.

<a id="e05"></a>
## E05 · Planifier ou déplacer

**Référence visuelle courante :** [APP06](../DESIGN/APPLICATION.html?screen=planning). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Depuis Planifier, formation, commande déplacer dans E04. **Public :** ADMIN ou INSTRUCTOR dans son périmètre.

**Fonction et hiérarchie :** Formation explicite, moniteur, jour, durée, lieu, prix convenu, propositions de créneaux puis récapitulatif. En déplacement, avant/après côte à côte ou empilés.

**Actions et sorties :** Choisir des valeurs ; vérifier les suggestions ; confirmer ; abandonner. Aucun maintien de créneau implicite.

| État | Comportement attendu |
|---|---|
| Chargement | Calcul de créneaux seul bloqué, reste du formulaire conservé. |
| Vide | Aucun créneau : expliquer plages fermées/occupées de façon non privée. |
| Erreur | Conflit de réservation à côté du choix horaire, proposer d’autres heures. |
| Hors ligne | Réservation interdite avec explication ; pas de bouton confirmant localement. |
| Permission | Moniteur ou formation retiré : rafraîchir les choix autorisés. |
| Succès | Ouvrir E04 avec date confirmée, pas simplement fermer le formulaire. |

**Traçabilité :** F04 F05 J02 J04.

**Précisions de comportement :** Le déplacement affiche durée, financement, droits et prix avant/après ; un changement commercial est explicite selon R13, identique sur web et tablette. Aucun tarif calculé depuis la trace.

<a id="e06"></a>
## E06 · Rechercher une personne à accompagner

**Référence visuelle courante :** [APP03](../DESIGN/APPLICATION.html?screen=students). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Destination Accompagner. **Public :** Équipe selon périmètre.

**Fonction et hiérarchie :** Recherche, filtres actifs et lignes nom/formations actives/prochaine étape administrative utile. Pas de score global ni adresse complète.

**Actions et sorties :** Rechercher ; effacer filtres ; ouvrir dossier E07 ; inviter si habilité.

| État | Comportement attendu |
|---|---|
| Chargement | Chargement de résultats annoncé sans déplacer le focus du champ. |
| Vide | Aucun élève autorisé ou aucun résultat de filtre, textes distincts. |
| Erreur | Échec recherche, conserver terme et possibilité de reprise. |
| Hors ligne | Recherche limitée à la projection préparée, clairement indiquée. |
| Permission | Résultats filtrés serveur ; aucun aperçu d’un dossier hors périmètre. |
| Succès | Liste stable, homonymes distingués par information autorisée. |

**Traçabilité :** F02 F03 J01 J06.

<a id="e07"></a>
## E07 · Dossier et formation

**Référence visuelle courante :** [APP04](../DESIGN/APPLICATION.html?screen=student). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Résultat de recherche, lien de leçon, Mon parcours. **Public :** Équipe affectée, élève concerné ; ADMIN avec contenu administratif limité.

**Fonction et hiérarchie :** Nom de la personne puis sélection de formation ; prochaine leçon, prochaine étape, contrôle du permis, bilans, documents et accès au journal.

**Actions et sorties :** Équipe : créer formation, affecter, planifier, gérer pièces. Élève : changer formation, consulter, saisir souhait. Archiver avec aperçu : ADMIN, ou délégation MANAGE_LEARNER_ARCHIVES dans le périmètre affecté ; aucun droit obtenu par le simple accès au web.

| État | Comportement attendu |
|---|---|
| Chargement | La catégorie choisie reste visible, pas de données provenant d’une autre formation. |
| Vide | Dossier sans formation : créer si habilité ; élève voit attente de l’école. |
| Erreur | Section en erreur isolée, pas affichage de zéro progression. |
| Hors ligne | Formation préparée lisible avec date ; aucun changement de catégorie non disponible. |
| Permission | Notes et bilans absents pour ADMIN seul, pas simplement masqués en CSS. |
| Succès | Nouvelle formation apparaît séparément, sélection explicite. |

**Traçabilité :** F03 F06 F08 F14 J06.

**Cas particulier :** une exigence dont la preuve est corrigée affiche « À vérifier de nouveau », son motif accessible et le contrôle requis. Ne pas la présenter « Non suivie » ni la rétablir dès qu’un crédit est réglé. L’archive tient compte des suivis de droit ouverts.

<a id="e08"></a>
## E08 · Rédiger et prévisualiser un bilan

**Référence visuelle courante :** [APP07](../DESIGN/APPLICATION.html?screen=report) · [APP08](../DESIGN/APPLICATION.html?screen=preview). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Faire le bilan depuis E04, reprendre brouillon E17. **Public :** Auteur habilité / moniteur désigné.

**Fonction et hiérarchie :** Contexte leçon et formation, heures réelles, travaillé/constat/prochaine étape ; observations de la leçon à relire (repères non qualifiés, thèmes/statuts, instant, état d’envoi), compétences finales distinctes ; pièces ; statut local/serveur.

**Actions et sorties :** Sauvegarder brouillon ; prévisualiser version élève ; publier connecté ; créer correction motivée. Aucun slider global. Un repère non qualifié ne peut pas être publié ; aucune sélection ni note automatique à la clôture.

| État | Comportement attendu |
|---|---|
| Chargement | Charger référentiel et brouillon sans initialiser des notes à zéro. |
| Vide | Premier brouillon : instructions courtes sur ce qui est nécessaire, pas texte prérempli factuel. |
| Erreur | Erreur de champ ou sauvegarde, texte conservé ; conflit vers E21. |
| Hors ligne | Sauvegarde locale native, publication désactivée et état précis. |
| Permission | Droit retiré : verrouiller et proposer contact/réconciliation encadrée, pas exporter librement. |
| Succès | Publication confirmée : lien vers E09 et nouvelle révision visible. |

**Traçabilité :** F07 F08 F12 J03 J05.

**Cas particulier :** deux sélections distinctes, annotations textuelles et trajet. Prévisualiser `textObservations` même sans capture ; liste vide signifie aucune annotation séparée. Conflit de version : revue à refaire sans publication partielle.

<a id="e09"></a>
## E09 · Lire un bilan partagé

**Référence visuelle courante :** [APP09](../DESIGN/APPLICATION.html?screen=shared). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Notification, E04, historique de formation. **Public :** Élève concerné et moniteurs affectés.

**Fonction et hiérarchie :** Date réelle, formation, auteur, point travaillé, constat, prochaine étape ; observations et contexte ; pièces READY ; mention de correction.

**Actions et sorties :** Ouvrir source et pièces ; consulter version actuelle et historique autorisé ; revenir formation ; contacter école pour question.

| État | Comportement attendu |
|---|---|
| Chargement | Structure textuelle, aucune note provisoire. |
| Vide | Pas de bilan partagé : l’expliquer sans montrer le brouillon. |
| Erreur | Lien de révision retirée : expliquer retrait et afficher version actuelle autorisée. |
| Hors ligne | Dernière révision préparée datée ; aucune certitude qu’elle est encore actuelle. |
| Permission | Aucun contenu avant contrôle de la formation. |
| Succès | Lecture cohérente avec progression, source de chaque observation disponible. |

**Traçabilité :** F08 F09 J03.

**Cas particulier :** les annotations autonomes du snapshot se lisent sans carte ni permission GPS. Un texte libre peut contenir un lieu ; ne pas afficher « anonyme » du seul fait de l’absence de coordonnées.

**Précisions de comportement :** En cas de retrait du trajet, démonter la carte et purger les caches géographiques autorisés ; ne pas masquer des coordonnées toujours reçues. Le bilan autonome conserve seulement le contenu autorisé (R48).

<a id="e10"></a>
## E10 · Documents utiles

**Référence visuelle courante :** [APP10](../DESIGN/APPLICATION.html?screen=documents). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Formation, contrôle de permis, bilan. **Public :** Selon audience et finalité.

**Fonction et hiérarchie :** Liste par finalité avec état reçu/analyse/prêt/rejeté ; date et rattachement. Le statut de pièce est distinct du contrôle humain de permis.

**Actions et sorties :** Ajouter ; choisir audience ; ouvrir seulement si READY ; remplacer avec nouvel objet ; demander suppression.

| État | Comportement attendu |
|---|---|
| Chargement | Métadonnées puis aperçu à la demande. |
| Vide | Aucune pièce ; expliquer celles réellement nécessaires. |
| Erreur | Dépôt/contrôle échoué avec action de remplacement ; pas de pièce cassée faussement prête. |
| Hors ligne | Binaire de permis non disponible par défaut ; transfert local en attente visible. |
| Permission | Sélecteur fichier si caméra refusée ; aucun blocage général. |
| Succès | READY puis retour au contexte, sans approbation automatique du permis. |

**Traçabilité :** F09 J07.

**Précisions de comportement :** Distinguer intention expirée, transport reçu, quarantaine et READY ; la reprise R22 ne réaffecte jamais une pièce à une autre école.

<a id="e11"></a>
## E11 · Journal d’un compte de prestation

**Entrées :** Détail leçon, liste de règlements autorisée. **Public :** ADMIN, moniteur habilité, élève en lecture.

**Fonction et hiérarchie :** Prix prévu, charge due, encaissé net, reste ; liste des mouvements typés avec date/auteur et liens de correction.

**Actions et sorties :** Encaisser ; contre-écriture/remboursement pour ADMIN ; consulter justificatif interne ; contacter école en lecture.

| État | Comportement attendu |
|---|---|
| Chargement | Montants masqués jusqu’à réponse, pas 0 CHF par défaut. |
| Vide | Aucun mouvement : solde calculé depuis la charge ; pas confondu avec gratuit. |
| Erreur | Solde périmé ou opération refusée, actualiser avant confirmer. |
| Hors ligne | Lecture de dernier solde daté seulement, aucune saisie d’encaissement confirmée. |
| Permission | Données financières d’autres élèves absentes. |
| Succès | Mouvement ajouté une fois, nouveau solde et référence affichés. |

**Traçabilité :** F10 J08.

<a id="e12"></a>
## E12 · Disponibilités

**Entrées :** Planifier puis paramètres de planning, École pour gestion autorisée. **Public :** Moniteur sur son planning, ADMIN selon habilitation.

**Fonction et hiérarchie :** Semaine type, périodes d’application, fermetures, durée et tampon ; aperçu des effets.

**Actions et sorties :** Ajouter plage/fermeture ; modifier ; prévisualiser impacts ; enregistrer avec version.

| État | Comportement attendu |
|---|---|
| Chargement | Réglages actuels prioritaires, aucune semaine fictive enregistrée. |
| Vide | Pas de plage ouverte : aucune réservation proposée ; guider la configuration. |
| Erreur | Chevauchement ou impact sur leçons, liens vers objets autorisés. |
| Hors ligne | Lecture possible de réglages préparés, sauvegarde interdite. |
| Permission | Pas de modification du planning d’un autre moniteur sans droit. |
| Succès | Version de réglage affichée, anciennes réservations inchangées. |

**Traçabilité :** F04 J02 J04.

<a id="e13"></a>
## E13 · École et responsabilités

**Référence visuelle courante :** [APP13](../DESIGN/APPLICATION.html?screen=school). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Destination École, demande nécessitant ADMIN. **Public :** ADMIN.

**Fonction et hiérarchie :** Coordonnées, équipe, offres activées, décisions à traiter, échecs d’avis persistants, demandes de données. Pas de contenu de bilan sans rôle pédagogique.

**Actions et sorties :** Inviter personnel ; modifier grants ; configurer offres ; traiter dossiers ; examiner impacts avant retrait.

| État | Comportement attendu |
|---|---|
| Chargement | Sections indépendantes, pas de faux zéro demande. |
| Vide | École non configurée : checklist de préparation au pilote. |
| Erreur | Changement refusé avec conséquence explicite, paramètres conservés. |
| Hors ligne | Pas de changement sensible ; dernier état purement indicatif. |
| Permission | ADMIN perdu : sortie sûre, requêtes ultérieures refusées. |
| Succès | Modification auditée, epoch et version visibles dans l’historique autorisé. |

**Traçabilité :** F13 F14 J01 J09 J10.

**Précisions de comportement :** Identité scolaire : nom/logo/contact, pas de sélecteur d’accent scolaire fictif. L’ancien logo validé reste visible pendant le contrôle du suivant.

<a id="e14"></a>
## E14 · Mes leçons, élève

**Référence visuelle courante :** [APP14](../DESIGN/APPLICATION.html?screen=learner). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Entrée espace élève. **Public :** LEARNER.

**Fonction et hiérarchie :** Prochain rendez-vous avec école/catégorie/heure/lieu ; une préparation nécessaire ; souhait personnel ; derniers changements secondaires.

**Actions et sorties :** Ouvrir leçon ; changer formation ; écrire souhait ; contacter école ; lire dernier bilan.

| État | Comportement attendu |
|---|---|
| Chargement | Pas de rendez-vous inventé ni compte à rebours avant données. |
| Vide | Aucune leçon prévue : contact et dernière prochaine étape, pas écran inutile. |
| Erreur | Dernière donnée datée si autorisée ; ne pas dire aucune leçon quand serveur échoue. |
| Hors ligne | Rendez-vous préparé clairement daté, pas de modification. |
| Permission | Formation fermée : accès historique autorisé ou contact, sans erreur mystérieuse. |
| Succès | Changement de rendez-vous mis en évidence avec état courant. |

**Traçabilité :** F05 F06 F11 J03.

**Précisions de comportement :** Variante élève en lecture seule ; ne pas afficher des actions de moniteur, de capture ou des notes privées.

<a id="e15"></a>
## E15 · Mon parcours

**Référence visuelle courante :** [APP16](../DESIGN/APPLICATION.html?screen=progress). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Destination élève, formation équipe. **Public :** Élève et moniteur affecté.

**Fonction et hiérarchie :** Sélecteur de formation ; prochaine étape ; compétences observées avec date/contexte/source ; bilans chronologiques. Aucune moyenne.

**Actions et sorties :** Ouvrir bilan source ; filtrer observations sans les agréger ; consulter historique et pièces utiles.

| État | Comportement attendu |
|---|---|
| Chargement | Pas de jauge 0 %. |
| Vide | Aucune observation partagée ; texte pédagogique neutre. |
| Erreur | Impossible de charger une projection, lien aux bilans si disponibles. |
| Hors ligne | Projection préparée datée, pas de nouvelle certification. |
| Permission | Chaque formation contrôlée séparément. |
| Succès | Nouvelle révision change la projection selon date réelle, pas ordre d’arrivée. |

**Traçabilité :** F08 J06.

<a id="e16"></a>
## E16 · Invitations et équipe

**Entrées :** École, inviter depuis Accompagner. **Public :** ADMIN ; moniteur limité aux élèves.

**Fonction et hiérarchie :** Destinataire, rôle, école, état en attente/acceptée/expirée/révoquée et émetteur.

**Actions et sorties :** Inviter ; renvoyer en révoquant ancien lien ; retirer ; ouvrir membre autorisé. Pas d’affichage du jeton après usage.

| État | Comportement attendu |
|---|---|
| Chargement | État de la requête explicite. |
| Vide | Aucune invitation en attente, pas besoin d’en créer pour terminer l’onboarding. |
| Erreur | Email invalide ou envoi en échec, invitation et livraison distinctes. |
| Hors ligne | Pas d’envoi ni consommation de jeton. |
| Permission | Moniteur ne peut choisir ADMIN même par API. |
| Succès | Confirmation avec échéance et moyen de suivre l’avis. |

**Traçabilité :** F02 F13 J01.

<a id="e17"></a>
## E17 · Brouillons et opérations en attente

**Entrées :** Bandeau local, compte, retour réseau. **Public :** Auteur sur appareil natif.

**Fonction et hiérarchie :** École et leçon, dernière sauvegarde, statut local/envoi/conflit/verrouillé, action nécessaire. Aucun mélange inter-comptes.

**Actions et sorties :** Reprendre ; envoyer après reconnexion ; ouvrir conflit ; supprimer un brouillon local avec confirmation si autorisé.

| État | Comportement attendu |
|---|---|
| Chargement | Lecture locale sans réseau ; si coffre indisponible, état technique explicite. |
| Vide | Aucun brouillon en attente, pas liste d’anciennes données privées. |
| Erreur | Stockage plein ou corruption détectée, ne pas prétendre récupérer un contenu non lisible. |
| Hors ligne | Gestion du brouillon autorisée dans lease, pas publication. |
| Permission | Lease ou droits expirés : verrouiller les aperçus et attendre connexion. |
| Succès | Opération acquittée avec lien serveur, pas suppression avant preuve de commit. |

**Traçabilité :** F12 J05.

<a id="e18"></a>
## E18 · Demandes concernant mes données

**Entrées :** Compte et École selon rôle. **Public :** Personne concernée et responsables habilités.

**Fonction et hiérarchie :** Types de demande, portée de l’école, conséquences et état d’instruction ; contact responsable.

**Actions et sorties :** Créer demande ; répondre à vérification ; consulter décision ; accéder export autorisé ; retirer demande si possible.

| État | Comportement attendu |
|---|---|
| Chargement | Statut de demande, pas durée légale fictive. |
| Vide | Aucune demande ; information et choix d’action. |
| Erreur | Export expiré ou identité à revérifier, demande d’un nouveau lien. |
| Hors ligne | Notice préchargée seulement, soumission connectée. |
| Permission | Un parent sans habilitation n’accède pas automatiquement aux données. |
| Succès | Numéro de demande, responsable et prochaines étapes explicites. |

**Traçabilité :** F14 J10.

<a id="e19"></a>
## E19 · Compte et préférences

**Référence visuelle courante :** [APP11](../DESIGN/APPLICATION.html?screen=account). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Entrées :** Avatar dans tous les espaces. **Public :** Utilisateur connecté.

**Fonction et hiérarchie :** Identité, école active, langue disponible, thème système/clair/sombre, sessions, informations de confidentialité.

**Actions et sorties :** Changer école ; gérer identité via fournisseur ; déconnecter ; préférences ; demandes de données. Aucun module métier enfoui ici.

| État | Comportement attendu |
|---|---|
| Chargement | Ne pas afficher les coordonnées d’un ancien compte. |
| Vide | Préférence non définie : système utilisé sans erreur. |
| Erreur | Échec de révocation distante distingué de verrouillage local. |
| Hors ligne | Préférences locales accessibles, changements d’identité refusés. |
| Permission | Biométrie optionnelle différée, pas exigée pour accéder au compte. |
| Succès | Préférences appliquées sans modifier les couleurs de statut. |

**Traçabilité :** F01 F13 J11.

**Précisions de comportement :** L’action « Supprimer mon compte » ouvre E49, y compris sans école active ; le contrat R103/AP193–AP198 existe déjà. Les demandes scolaires E18 sont distinctes.

<a id="e20"></a>
## E20 · Contrôle d’une pièce de permis

**Entrées :** Action de formation, file de contrôles autorisée. **Public :** Élève pour dépôt/lecture ; personnel permit_review pour décision.

**Fonction et hiérarchie :** Formation, pièce ou attestation d’original, catégorie, validité, état humain, dernier motif et contrôleur.

**Actions et sorties :** Déposer/remplacer ; approuver ou rejeter si habilité ; corriger par nouveau contrôle ; ouvrir source officielle. Aucun OCR décisionnaire.

| État | Comportement attendu |
|---|---|
| Chargement | Pièce chargée uniquement après autorisation et READY. |
| Vide | Pas de pièce ni attestation : expliquer voie disponible. |
| Erreur | Document technique rejeté distinct de permis humain refusé. |
| Hors ligne | Aucune décision, pas de cache binaire par défaut. |
| Permission | Grant manquant : pas d’approbation possible ni via API. |
| Succès | Décision datée et portée catégorie visibles ; pas message d’autorisation légale. |

**Traçabilité :** F03 F09 J01 J07.

<a id="e21"></a>
## E21 · Conflit à résoudre

**Entrées :** Échec de commande de version ou opération offline. **Public :** Auteur encore autorisé, administration si arbitrage.

**Fonction et hiérarchie :** Objet, raison métier, version courante autorisée, contenu local permis, conséquences de chaque option.

**Actions et sorties :** Recharger ; conserver notes dans nouveau brouillon ; demander arbitrage ; abandonner copie après confirmation. Aucun bouton Forcer global.

| État | Comportement attendu |
|---|---|
| Chargement | Récupérer version actuelle avant proposer une fusion. |
| Vide | Objet retiré : expliquer qu’un arbitrage est nécessaire, pas créer nouvel objet automatiquement. |
| Erreur | Impossible d’obtenir serveur : conflit reste ouvert. |
| Hors ligne | Notes autorisées conservées, résolution serveur indisponible. |
| Permission | Droit retiré : masquer comparatif sensible et bloquer export. |
| Succès | Nouvelle opération et audit de résolution ; ancienne opération reste traçable. |

**Traçabilité :** F12 J05 J09.

<a id="e22"></a>
## E22 · Séance, accueil du personnel

**Référence visuelle courante :** [APP01](../DESIGN/APPLICATION.html?screen=home). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Fonctions :** F06 F07 F15. **Entrées :** Onglet Séance ; reprise d’une capture en cours.

**Hiérarchie :** Prochaine leçon ou occurrence, élève/formation, objectifs et action principale ; statut serveur/local clairement distinct.

**Actions et conséquences :** Préparer, démarrer avec enregistrement, démarrer sans enregistrement, reprendre le bilan.

| État | Comportement |
|---|---|
| Chargement | Squelette sans valeur ni confirmation inventée ; commandes de confirmation attendent le contexte serveur. |
| Vide | Aucune séance : planning et dernier bilan à compléter, sans carte vide. |
| Erreur | Contexte non chargé : ne pas proposer une capture pour l’ancien élève. |
| Hors ligne | Hors réseau : objectifs préparés ; nouvelle capture non autorisée au pilote, mode sans enregistrement disponible. |
| Permission | Moniteur non affecté : pas de données privées ; capacité de cours donne seulement la prochaine occurrence. |
| Succès | Capture autorisée : E23 ; sans GPS : E04 puis E08. |

**Accessibilité :** libellé textuel du statut, zones tactiles du design system, lecture au clavier/lecteur d’écran et réduction des animations ; focus restitué après confirmation ou erreur. [Règles](../03-fonctionnel/regles-etats.md), [tests](../05-realisation/tests-recette.md).

**Précisions de comportement :** Retrouver une capture en cours ne crée ni nouvelle autorisation ni nouveau captureId ; arrêt GPS et constat restent séparés.

<a id="e23"></a>
## E23 · Carte de séance et capture

**Référence visuelle courante :** [APP17](../DESIGN/LECON.html?view=capture) · [APP18](../DESIGN/LECON.html?view=categories) · [APP19](../DESIGN/LECON.html?view=status). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Fonctions :** F15 F16. **Entrées :** E22/E04 après action explicite et autorisation.

**Hiérarchie :** Carte dominante ; identité compacte de l’élève, état réel du collecteur et temps distincts ; bulle « Signaler » visible en permanence hors défilement ; accès aux observations et commandes GPS séparées. Les objectifs détaillés restent dans le contexte secondaire.

**Actions et conséquences :** « Signaler » fige l’instant et l’ancre disponible, ouvre les catégories et ne crée pas d’événement avant confirmation. Thème puis statut explicitement choisi, commentaire facultatif ; « Marquer un moment » conserve seulement un repère privé. « Observations privées » ouvre la liste et le replay privé. Pause/reprise/arrêt restent accessibles sans confirmer le panneau. Sortie en haut à gauche ; aucun bouton photo ni saisie obligatoire en mouvement. R46 permet une observation LIVE sans brouillon avant constat.

**Géométrie :** déclencheur hors conteneur défilant, entièrement dans la zone sûre à toute taille qualifiée ; le contenu secondaire et la carte cèdent avant la commande. Le panneau peut défiler, pas le déclencheur. Les cibles restent au moins celles du design system. Le bouton principal de l’atelier est haut de 56 unités CSS ; une cible de 60 × 60 pt demeure une hypothèse native à qualifier, pas une équivalence CSS/points ; aucune dimension ne valide la sûreté en déplacement. Classes de taille et largeur/hauteur utiles pilotent la composition, y compris Split View. Redimensionner conserve l’intention et l’ancre, sans nouvelle écriture.

**Libellés canoniques :** « Signaler », « Marquer un moment », « Compléter l’observation », « Observations privées », « Attention », « À retravailler », « Point positif », instruction commune « Le choix enregistre. ». La couleur ne remplace pas ces libellés. [Instant et annulation](../03-fonctionnel/gps-replay.md#instant-signalement), [mouvement](../03-fonctionnel/gps-replay.md#mouvement-signalement).

| État | Comportement |
|---|---|
| Chargement | Squelette sans valeur ni confirmation inventée ; commandes de confirmation attendent le contexte serveur. |
| Vide | Mode sans capture n’ouvre pas cette vue ; zéro point initial : attente clairement affichée. |
| Erreur | Permission perdue ou interruption : arrêt/gap, conservation des points acquis et alternative sans GPS. |
| Hors ligne | Points et intentions d’observation chiffrés sous autorisation/lease ; accusé seulement après persistance, même operationId à la reprise. Arrêt local indépendant du réseau. |
| Permission | Refus élève bloque la capture ; aucun bouton permettant de le contourner. |
| Succès | Arrêt GPS confirmé localement, leçon non terminée ; observations privées conservées, transfert distinct de publication. |

**Accessibilité :** libellé textuel du statut, zones tactiles du design system, lecture au clavier/lecteur d’écran et réduction des animations ; focus restitué après confirmation ou erreur. [Règles](../03-fonctionnel/regles-etats.md), [tests](../05-realisation/tests-recette.md).

**Référence visuelle :** [atelier de leçon](../DESIGN/LECON.html). Le signalement n’est pas un formulaire détaillé permanent. Six catégories stables avec libellé ; trois lignes de statut sans chevron de navigation ni sous-texte « Enregistrer l’observation » répété. La ligne agit directement après le choix explicite ; « Le choix enregistre. » reste une instruction commune. Catégories et statut sont deux contenus d’un même panneau, avec transition interrompable ; le retour conserve l’instant et l’ancre et replace le focus sur la catégorie précédente. Aucun délai d’animation ne conditionne le prochain geste. « 3 observations » avec cadenas est un libellé compact, annoncé « 3 observations privées » par le lecteur d’écran. L’aide complète reste dans le menu de séance.

**Commandes de séance proposées :** la réduction de texte regroupe pause/reprise, « Arrêter le GPS » et « Terminer la leçon » dans un menu nommé pour l’accessibilité. Une feuille ouverte se ferme sans validation avant d’ouvrir ce menu. Ce coût d’accès supplémentaire par rapport à une commande visible en continu doit être éprouvé ; il n’est pas considéré comme ergonomiquement validé. L’implémentation doit préserver le point figé et ne jamais enregistrer un statut pour simplement fermer la feuille.

**Cas particulier :** arrêt sans premier point : « Aucun point enregistré ». Pas de marqueur inventé, ni de succès de qualité déduit d’un transfert vide.

**Cas particulier :** avant le premier point admissible sauvegardé : « En attente de position ». Une dernière position de cache ne déplace pas le départ de la leçon. Les interruptions et mesures anciennes restent distinguées, sans trajectoire fictive.

<a id="e24"></a>
<!-- La variante privée de E24 est illustrée dans DESIGN/LECON.html ; le parcours élève reste en lecture publiée. -->

## E24 · Replay et observations

**Référence visuelle courante :** [APP20](../DESIGN/LECON.html?view=replay). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Fonctions :** F16 F08. **Entrées :** Leçon terminée ou bilan publié ; accès privé/public selon rôle.

**Hiérarchie :** Carte, état complet/partiel, chronologie et observations prises pendant la leçon ou en revue, avec thème/statut et instant ; objectifs, dernière prochaine étape.

**Actions et conséquences :** Lecture/pause, x1/x2/x4, scrubber, zoom manuel, recentrage ; sélectionner une observation relie explicitement sa ligne, son repère admissible et son instant. À x1, une seconde de replay correspond à une seconde enregistrée. Exploration manuelle de la carte suspend le suivi de caméra, pas la lecture ; le recentrage reste explicite. Le replay privé du moniteur retrouve les observations LIVE de la séance, y compris les non localisées dans la liste. Le replay élève reste lié à sa révision publiée et n’expose aucun événement privé. Compléter/qualifier conserve la provenance et l’instant sauf correction explicite ; aucune publication antérieure n’est réécrite.

| État | Comportement |
|---|---|
| Chargement | Squelette sans valeur ni confirmation inventée ; commandes de confirmation attendent le contexte serveur. |
| Vide | Trajet non enregistré : bilan textuel normal ; trace supprimée : « Trajet retiré » sans carte cassée. |
| Erreur | Chunk/tuile indisponible : lacune visible ; texte des observations toujours disponible si autorisé. |
| Hors ligne | Lecture de données préparées autorisées ; fond de carte non garanti sans licence/cache approuvés. |
| Permission | Élève : seulement captures et annotations publiées propres ; admin seul : aucune trace. |
| Succès | Nouvelle observation reste brouillon jusqu’à publication ; zoom ne stoppe pas la lecture. |

**Accessibilité :** libellé textuel du statut, zones tactiles du design system, lecture au clavier/lecteur d’écran et réduction des animations ; focus restitué après confirmation ou erreur. [Règles](../03-fonctionnel/regles-etats.md), [tests](../05-realisation/tests-recette.md).

**Précisions de comportement :** Dans le replay privé courant, le seul repère sélectionné montre le pictogramme du thème, avec un symbole de statut distinct ; le panneau reprend le thème et écrit le statut. Les autres points restent compacts. Aucun libellé permanent sur chaque point ni couleur par thème. La liste et précédent/suivant conservent chaque identifiant, même pour des événements au même instant. Choisir un point dans le replay ne réinitialise ni le cadrage manuel ni la vitesse ou l’état de lecture. Le curseur suit le temps et les segments, pas un pourcentage de distance. Pendant une lacune, aucune position interpolée n’est présentée comme mesure.

<a id="e25"></a>
## E25 · Agenda élève, engagements et offres

**Référence visuelle courante :** [APP15](../DESIGN/APPLICATION.html?screen=learner-agenda). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Fonctions :** F19 F18. **Entrées :** Onglet Agenda et liens de calendrier internes.

**Hiérarchie :** Jour/semaine/liste, fuseau, engagements personnels et offres non inscrites distinctes ; filtre offres.

**Actions et conséquences :** Consulter une leçon, ouvrir une série ; masquer offres sans annuler.

| État | Comportement |
|---|---|
| Chargement | Squelette sans valeur ni confirmation inventée ; commandes de confirmation attendent le contexte serveur. |
| Vide | Aucun engagement n’est pas absence d’offres ; absence d’offres n’est pas erreur serveur. |
| Erreur | Serveur indisponible : dernière actualisation, pas « aucun cours ». |
| Hors ligne | Affichage daté, inscription désactivée ; aucune occupation locale créée. |
| Permission | Seulement audience d’école active ; noms d’autres élèves jamais renvoyés. |
| Succès | Inscription transforme les occurrences sans doublon et place « Inscrit ». |

**Accessibilité :** libellé textuel du statut, zones tactiles du design system, lecture au clavier/lecteur d’écran et réduction des animations ; focus restitué après confirmation ou erreur. [Règles](../03-fonctionnel/regles-etats.md), [tests](../05-realisation/tests-recette.md).

**Précisions de comportement :** Le filtre de langue porte sur les offres, pas sur la langue de l’app ni les engagements déjà confirmés.

<a id="e26"></a>
## E26 · Fiche d’une série et inscription

**Fonctions :** F18 F17. **Entrées :** Offre E25, notification ou exigence Mon parcours.

**Hiérarchie :** Titre, toutes les dates/blocs, lieu, conditions, prix ou droit utilisable, capacité indicative et état personnel.

**Actions et conséquences :** S’inscrire puis confirmer toutes dates ; annuler selon conditions ; signaler formation déjà faite.

| État | Comportement |
|---|---|
| Chargement | Squelette sans valeur ni confirmation inventée ; commandes de confirmation attendent le contexte serveur. |
| Vide | Complet : bouton désactivé ; pas d’attente implicite. |
| Erreur | Dernière place perdue : COURSE_FULL ; version commerciale changée : relecture et nouvel accord. |
| Hors ligne | Consulter cache ; aucune confirmation possible hors connexion. |
| Permission | Inadmissibilité ou preuve en attente : explication et accès au dossier ; pas d’accès aux inscrits. |
| Succès | Confirmation durable, détails de série et compte/droit associés. |

**Accessibilité :** libellé textuel du statut, zones tactiles du design system, lecture au clavier/lecteur d’écran et réduction des animations ; focus restitué après confirmation ou erreur. [Règles](../03-fonctionnel/regles-etats.md), [tests](../05-realisation/tests-recette.md).

**Précisions de comportement :** Une réponse d’inscription inconnue reste en attente ; aucune nouvelle intention n’est créée automatiquement. teachingLanguage et échéances sont visibles avec les dates.

<a id="e27"></a>
## E27 · Composer et publier un cours

**Fonctions :** F18 F13. **Entrées :** Agenda personnel/École, capacité MANAGE_COURSES.

**Hiérarchie :** Type/profil approuvé, occurrences, intervenants/salle, capacité, prix/conditions, audience et aperçu élève.

**Actions et conséquences :** Ajouter/ordonner blocs, sauvegarder brouillon, publier, modifier avec aperçu des impacts, annuler.

| État | Comportement |
|---|---|
| Chargement | Squelette sans valeur ni confirmation inventée ; commandes de confirmation attendent le contexte serveur. |
| Vide | Aucun modèle configuré : lien au catalogue/profil, pas valeurs légales inventées. |
| Erreur | Profil non approuvé ou conflit : cibler le champ, garder le brouillon, aucune notification. |
| Hors ligne | Brouillon local personnel possible comme notes uniquement ; publication exclusivement serveur. |
| Permission | Seul responsable habilité ; capacité ne donne pas accès aux GPS. |
| Succès | Série publiée ; retour fiche, aucune inscription automatique ni remplissage fictif. |

**Accessibilité :** libellé textuel du statut, zones tactiles du design system, lecture au clavier/lecteur d’écran et réduction des animations ; focus restitué après confirmation ou erreur. [Règles](../03-fonctionnel/regles-etats.md), [tests](../05-realisation/tests-recette.md).

**Précisions de comportement :** Titre, calendrier et révision de tarif futur sont des actions distinctes. Les inscrits gardent leurs conditions. teachingLanguage est visible et figé après publication.

<a id="e28"></a>
## E28 · Inscrits et présences

**Fonctions :** F18 F03 F09. **Entrées :** Série du formateur ou gestion habilitée.

**Hiérarchie :** Date du bloc, compte places, élèves résolus, état inscription et présence ; exigence distincte.

**Actions et conséquences :** Marquer présence, joindre preuve, corriger avec motif, valider le cours si tous critères réunis.

| État | Comportement |
|---|---|
| Chargement | Squelette sans valeur ni confirmation inventée ; commandes de confirmation attendent le contexte serveur. |
| Vide | Aucun inscrit : liste vide réelle, pas colonne de noms d’exemple. |
| Erreur | Conflit de version : comparer auteur et état actuel sans écraser. |
| Hors ligne | Liste préparée si autorisée ; saisie de présence finale non confirmée hors réseau au pilote. |
| Permission | TAKE_ATTENDANCE pour sa séance ; VALIDATE_REQUIREMENT pour conclusion, pas les élèves. |
| Succès | Présences enregistrées, consommation selon politique et exigence mise à jour après validation. |

**Accessibilité :** libellé textuel du statut, zones tactiles du design system, lecture au clavier/lecteur d’écran et réduction des animations ; focus restitué après confirmation ou erreur. [Règles](../03-fonctionnel/regles-etats.md), [tests](../05-realisation/tests-recette.md).

**Cas particulier :** avant clôture, afficher les HOLD jamais utilisés et leurs versions, expliquer RELEASE sans remboursement et vérifier les habilitations. Une présence concurrente impose une nouvelle revue. La correction tardive vers PRESENT d’un droit libéré reste à traiter explicitement.

**Cas particulier :** « Présence corrigée » est un résultat factuel, distinct du badge « Droit à régulariser ». Montrer cette alerte à la relecture de l’inscription, et l’action de règlement uniquement à ADMIN. Présenter lot/source/effet avant AP201 ; afficher confirmation en cours si 202. La formation n’est jamais bloquée uniquement par un règlement financier.

**Précisions de comportement :** Le roster et la présence portent le cycle courant d’inscription ; ne jamais écrire sur un ancien cycle.

<a id="e29"></a>
## E29 · Catalogue et formules d’école

**Fonctions :** F17 F13. **Entrées :** École, capacité CONFIGURE_CATALOG.

**Hiérarchie :** Prestations par catégorie/site, durée/unité, dates d’effet, versions et packs composés.

**Actions et conséquences :** Créer nouvelle version, activer, composer pack et options, archiver sans effacer les ventes.

| État | Comportement |
|---|---|
| Chargement | Squelette sans valeur ni confirmation inventée ; commandes de confirmation attendent le contexte serveur. |
| Vide | École sans packs : liste de tarifs simples et commande optionnelle d’activation. |
| Erreur | Total incohérent, produit périmé ou conditions absentes : erreur ciblée. |
| Hors ligne | Lecture datée seulement, changements serveur requis. |
| Permission | Personnel habilité ; pas de paramètre commercial pouvant dépasser le profil réglementaire. |
| Succès | Nouvelle version disponible aux achats futurs, anciennes ventes inchangées. |

**Accessibilité :** libellé textuel du statut, zones tactiles du design system, lecture au clavier/lecteur d’écran et réduction des animations ; focus restitué après confirmation ou erreur. [Règles](../03-fonctionnel/regles-etats.md), [tests](../05-realisation/tests-recette.md).

**Cas particulier :** séparer lignes de base, frais/remises inclus et supplément par option. Afficher le total recalculé ; une ligne à zéro ne crée pas un droit. ADMIN peut convenir d’un total exceptionnel avec motif, sans modifier les quantités.

<a id="e30"></a>
## E30 · Mes achats et droits

**Fonctions :** F17 F10. **Entrées :** Mon parcours ou dossier d’un élève autorisé.

**Hiérarchie :** Achat, composants, disponibles/réservés/utilisés, paiement séparé et conditions acceptées.

**Actions et conséquences :** Voir mouvements, rejoindre une prestation compatible ; personnel : créer achat et saisir paiement.

| État | Comportement |
|---|---|
| Chargement | Squelette sans valeur ni confirmation inventée ; commandes de confirmation attendent le contexte serveur. |
| Vide | Aucun pack : prestations à la séance ; jamais « gratuit » par défaut. |
| Erreur | Solde périmé : rafraîchir ; dernier droit indisponible expliqué sans débit. |
| Hors ligne | Soldes datés, aucune vente ni consommation confirmée localement. |
| Permission | Élève : ses comptes ; moniteur : périmètre et habilitation ; admin selon mission. |
| Succès | Compte de pack payé une fois ; droits indépendants clairement affichés. |

**Accessibilité :** libellé textuel du statut, zones tactiles du design system, lecture au clavier/lecteur d’écran et réduction des animations ; focus restitué après confirmation ou erreur. [Règles](../03-fonctionnel/regles-etats.md), [tests](../05-realisation/tests-recette.md).

**Cas particulier :** montrer total catalogue et total convenu si différents, composants effectivement choisis et remises consignées. Le personnel habilité ouvre « Consigner une prestation remise » ; l’élève consulte seulement, sans boutons de consommation.

**Cas particulier :** afficher séparément le reliquat, le suivi de droit, le suivi d’argent et les justificatifs de remise. Renoncer au décompte n’est pas « Remboursé ». Après conflit de version, conserver l’intention en brouillon mais relire avant toute nouvelle confirmation.

**Précisions de comportement :** Distinguer reliquat et utilisabilité : un règlement à vérifier peut suspendre de nouvelles réservations sans supprimer les droits ni les engagements existants.

<a id="e31"></a>
## E31 · Reconfirmer une série modifiée

**Fonctions :** F18 F19. **Entrées :** Avis de changement ou inscription marquée à reconfirmer.

**Hiérarchie :** Anciennes/nouvelles dates et lieu, raison, conservation de la place, conséquences contractuelles.

**Actions et conséquences :** Accepter nouvelle version, demander annulation/assistance, revenir sans perdre sa place.

| État | Comportement |
|---|---|
| Chargement | Squelette sans valeur ni confirmation inventée ; commandes de confirmation attendent le contexte serveur. |
| Vide | Aucune réponse demandée si correction purement éditoriale. |
| Erreur | Nouvelle modification pendant lecture : version périmée et nouveau comparatif. |
| Hors ligne | Lecture possible, réponse nécessite serveur. |
| Permission | Uniquement participant de la série ou agent habilité saisissant son accord réel. |
| Succès | Acceptation remet CONFIRMED ; absence de réponse ne désinscrit pas automatiquement. |

**Accessibilité :** libellé textuel du statut, zones tactiles du design system, lecture au clavier/lecteur d’écran et réduction des animations ; focus restitué après confirmation ou erreur. [Règles](../03-fonctionnel/regles-etats.md), [tests](../05-realisation/tests-recette.md).

<a id="e32"></a>
## E32 · Centre de notifications

**Référence visuelle courante :** [APP12](../DESIGN/APPLICATION.html?screen=notifications). Variante illustrée seulement ; mêmes [composants DS](../DESIGN/02-composants.md).

**Fonctions :** F11/F19. **Entrées :** cloche de l’en-tête, retour d’un push. **Hiérarchie :** confirmations et actions à traiter, puis nouvelles offres ciblées ; date et école visibles. Une annonce n’utilise pas le même libellé qu’une confirmation d’inscription.

**Actions :** ouvrir la ressource courante, marquer lu, accéder aux préférences E19. Cliquer une offre ne réserve rien. Un message d’annulation reste consultable, même si l’offre n’est plus réservable.

| État | Comportement |
|---|---|
| Chargement | Liste neutre, sans annonces fictives. |
| Vide | Aucune nouvelle information, accès à l’agenda toujours disponible. |
| Erreur | Réessayer sans faire disparaître une confirmation déjà acquise. |
| Hors ligne | Liste préparée datée, action de confirmation nécessitant serveur désactivée. |
| Permission | Ancienne école ou accès révoqué : pas de contenu privé derrière le lien. |
| Succès | Ouverture du cours/bilan actuel et état de lecture distinct de livraison. |

Accessibilité : annoncer le type (offre, confirmation, changement), pas seulement badge couleur ; liste triée stable et focus conservé. Les préférences de canaux ne deviennent pas une autorisation de collecte GPS.

<a id="e33"></a>
## E33 · Vue d’ensemble web

**Entrées :** Entrée du workspace personnel, retour depuis la navigation. **Public :** Personnel selon grants.

**Fonction et hiérarchie :** École/contexte ; prochaine action et alertes traitables ; agenda du jour ; métriques autorisées avec période et mise à jour. Pas de carte de surveillance.

**Actions et sorties :** Ouvrir le dossier ou cours nécessitant action, changer période, ouvrir Activité E45. Aucun encaissement créé depuis une carte KPI.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Première école sans activité : tâches de configuration, pas graphiques à valeurs fictives. Filtre sans résultats distinct d’absence de données. |
| Erreur | Indicateurs incomplets ou financiers non autorisés : explication/périmètre, aucune requête globale exposée. Connexion perdue : plus de rafraîchissement ni mutation, état daté. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F20 F22 F23 J19 J26.

<a id="e34"></a>
## E34 · Liste détaillée des élèves

**Entrées :** Navigation Élèves du web, lien depuis une action de gestion. **Public :** ADMIN et moniteur avec scope courant.

**Fonction et hiérarchie :** Recherche locale au scope, filtres actifs/archivés, formation, moniteur ; colonnes nom, formation, référent, prochaine leçon, actions requises. Aucun anniversaire ou adresse complète en liste.

**Actions et sorties :** Ouvrir E35 ; sélectionner explicitement un lot ; E36 pour aperçu d’archivage ; E46 pour export autorisé. Pagination conserve filtre, sélection explicite et taille de lot.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Aucun dossier : inviter. Aucun résultat de filtre : effacer filtre, sans prétendre aucun élève dans l’école. |
| Erreur | Retrait d’accès vide les sélections. Changement de page ne sélectionne pas toutes les lignes cachées. Pas de filtre personnel sérialisé dans URL publique ni localStorage. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F02 F22 J24 J25.

**Précisions de comportement :** Recherche et filtre sont conservés au retour ; une sélection hors résultats est retirée et le focus revient à un élément visible.

<a id="e35"></a>
## E35 · Dossier élève sur bureau

**Entrées :** Ligne E34, recherche autorisée, dossier depuis agenda. **Public :** Personnel selon droits administratifs et pédagogiques.

**Fonction et hiérarchie :** En-tête avec statut du dossier ; rubriques Identité, Formations, Agenda, Cours, Packs, Comptes, Documents ; Bilans/Trajets seulement selon droits. Actions secondaires de cycle de vie séparées.

**Actions et sorties :** Modifier les champs autorisés par version ; terminer une formation via F03 ; voir compte F10 ; ouvrir archivage E36, restauration E37 ou demande de droits F14.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Historique sans trace : bilan textuel. Dossier archivé : bandeau et lecture historique ; pas bouton nouvelle leçon. |
| Erreur | Conflit d’édition : préserver saisie autorisée et montrer différences. Date de naissance conditionnelle validée en date civile. Suppression ne se cache pas dans Archiver. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F03 F09 F10 F14 F21 F22 J24.

<a id="e36"></a>
## E36 · Prévisualisation et résultat d’archivage

**Entrées :** E34 lot ou E35 individuel. **Public :** ADMIN ou grant MANAGE_LEARNER_ARCHIVES avec scope.

**Fonction et hiérarchie :** Identités sélectionnées, état/version, blocages et avertissements par ligne ; conséquences explicites et aperçu expirant. En lot : nombre éligible sur nombre choisi.

**Actions et sorties :** Traiter un blocage en ouvrant sa source ; confirmer les lignes éligibles cochées ; accepter explicitement l’avertissement de droits disponibles. Suivre job et résultats individuels.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Zéro ligne éligible : aucun bouton Forcer. Dossier déjà archivé : état explicite non effacé. |
| Erreur | Aperçu périmé : recalcul. Nouveau conflit : ligne BLOCKED/VERSION_CONFLICT, aucune opération financière implicite. PARTIAL ne se présente pas comme succès global. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F14 F22 J24 J25.

**Précisions de comportement :** Après archivage, conserver le filtre/recherche et traiter explicitement les résultats partiels ; ne pas laisser le focus sur une ligne retirée.

<a id="e37"></a>
## E37 · Restauration du dossier

**Entrées :** Bandeau du dossier archivé. **Public :** Personnel habilité.

**Fonction et hiérarchie :** Résumé du dossier, date/motif d’archivage, accès actuel et droits contractuels restants ; ce qui ne sera pas réactivé.

**Actions et sorties :** Saisir motif et restaurer avec If-Match ; revenir au dossier. Nouvelle formation ou nouvelle invitation ensuite via leur parcours séparé.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Dossier déjà actif : résultat idempotent ou actualisé, pas nouvelle formation. |
| Erreur | Membership révoquée : message Accès non rétabli. Données purgées non récupérables ; ne pas montrer un aperçu promis inexistant. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F14 F22 J24.

<a id="e38"></a>
## E38 · Configuration guidée de l’école

**Entrées :** Invitation opérateur responsable, reprise depuis workspace DRAFT. **Public :** ADMIN.

**Fonction et hiérarchie :** Progression courte, étape courante, raison des champs, sauvegarde confirmée ; identité puis organisation, catégories, offres, options de cours, politique et revue.

**Actions et sorties :** Précédent/Suivant, sauvegarder, ignorer les modules facultatifs, reprendre plus tard. Chaque section appelle son domaine, pas un gros blob scolaire concurrent.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | École partiellement configurée : éléments déjà validés conservés ; pas besoin de remplir logo ou packs. |
| Erreur | Prix manquant non converti en zéro ; changement d’onglet avant réponse : état non enregistré explicite. Conflit 412 avec champ et valeur serveur. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F13 F17 F18 F20 J19 J28.

<a id="e39"></a>
## E39 · Préparation et activation de l’école

**Entrées :** Fin E38, onglet École. **Public :** ADMIN.

**Fonction et hiérarchie :** Résumé de ce qui sera visible et quatre capacités : workspace, planifier, capturer, publier cours. Blocages rattachés à leur raison, responsable et étape.

**Actions et sorties :** Activer le workspace après revalidation ; ouvrir le paramètre manquant ; continuer une configuration facultative plus tard.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | École sans cours : pas d’alerte trompeuse de configuration inachevée pour ce module désactivé. |
| Erreur | État changé depuis le résumé : relecture sans activer à partir d’un cache ; catégorie approuvée par l’école seule ne devient pas habilitation légale. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F13 F20 J19.

<a id="e40"></a>
## E40 · Identité et coordonnées élève

**Entrées :** Invitation acceptée, compléter un profil, demande liée à action. **Public :** Élève ; saisie assistée autorisée identifiée.

**Fonction et hiérarchie :** École destinataire, prénom/nom ; champs conditionnels expliqués ; photo facultative ; information sur finalité et réutilisation. Libellés persistants.

**Actions et sorties :** Sauvegarder ; passer la photo ; ajouter image via pipeline ; vérifier données existantes ; retour à action d’origine autorisée.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Coordonnées déjà disponibles et pertinentes préremplies après confirmation du destinataire ; aucun formulaire vierge forcé. |
| Erreur | Nom Unicode valide sans alphabet occidental imposé ; date future refusée ; pas d’âge minimum universel inventé. Profil en cours d’image ne bloque pas entrée. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F02 F09 F21 J21 J22 J27.

**Précisions de comportement :** Photo facultative ; reprise du dépôt sans perte des champs ; les états de transport, quarantaine et disponibilité restent distincts.

<a id="e41"></a>
## E41 · Formations souhaitées et acquis déclarés

**Entrées :** Après profil minimum, ajout d’une demande. **Public :** Élève.

**Fonction et hiérarchie :** Catégories réellement proposées, formation déjà existante, intention d’inscription et attestations éventuelles ; statuts Déclaré/À vérifier distincts.

**Actions et sorties :** Soumettre TrainingRequest ; retirer demande encore PENDING ; déposer une preuve ou demander examen physique selon procédure.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Pas encore de catégorie prête : contacter école, garder accès à son dossier ; pas liste de catégories inventées. |
| Erreur | Double demande pour même offre : retrouver la demande active. Déclaration du cours suivi n’entraîne pas VERIFIED ni annulation des inscriptions réelles. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F03 F18 F21 J21 J22 J27.

<a id="e42"></a>
## E42 · Comprendre le GPS et les notifications

**Entrées :** Onboarding, aide ou réglage personnel. **Public :** Tous avec contenu adapté à rôle.

**Fonction et hiérarchie :** Finalité du replay, qui peut voir quoi, alternative sans enregistrement ; information sur notifications de cours. Texte court, accès notice complète.

**Actions et sorties :** Continuer sans autoriser maintenant ; consulter notice ; paramètres adaptés. La permission OS est demandée uniquement lors de l’action native pertinente.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Navigateur élève sans localisation : expérience normale, aucune alerte d’installation obligatoire. |
| Erreur | Refus de push ou GPS ne devient pas une erreur du profil. Ne pas confondre J’ai lu et consentement contractuel/juridique. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F11 F15 F21 J20 J21.

**Cas particulier :** absence de choix GPS = « Choix non renseigné », sans événement fictif. Les préférences externes proposées à false sont modifiables volontairement et restent distinctes de la permission système.

<a id="e43"></a>
## E43 · Prochaines étapes personnelles

**Entrées :** Fin ou reprise onboarding, compte. **Public :** Élève et personnel selon contexte.

**Fonction et hiérarchie :** Données minimales confirmées ; demandes en attente ; action suivante réelle, par exemple vérifier une attestation ou consulter cours disponible. Facultatifs séparés.

**Actions et sorties :** Accéder à agenda, à formation, à action initiale ; reprendre uniquement le complément utile.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Aucune leçon ni cours : explication de contact, pas fausse formation complétée. |
| Erreur | Fin wizard ne réserve aucune place ; lien expiré affiché sans remplacer par un autre cours. Une politique modifiée n’efface pas acquis passés. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F20 F21 J21 J27 J28.

<a id="e44"></a>
## E44 · Préparation de l’appareil GPS

**Entrées :** Premier démarrage, changement technique, reprise diagnostic. **Public :** INSTRUCTOR sur téléphone/tablette natif.

**Fonction et hiérarchie :** Appareil/build courant ; statut qualification ; permission, localisation récente, précision et limite explicite ; réseau affiché séparément.

**Actions et sorties :** Démarrer contrôle à l’arrêt ; ouvrir réglages système ; utiliser sans capture ; revenir à Séance. Aucun transfert live implicite depuis téléphone.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Modèle non qualifié : autres modules disponibles ; alternative expliquée sans prétendre qu’une carte visible suffit. |
| Erreur | Permission retirée ou dernier diagnostic ancien/invalide : NEEDS_CHECK ; mesure indisponible distingue matériel, signal et serveur. Pas de faux voyant vert après mise à jour OS. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F15 F21 J20 J23.

<a id="e45"></a>
## E45 · Activité et indicateurs détaillés

**Entrées :** Navigation Activité, carte E33. **Public :** Personnel autorisé.

**Fonction et hiérarchie :** Période civile, scope, filtres applicables ; cartes et tables des M01–M09 ; définition accessible, date de calcul, données manquantes et unité.

**Actions et sorties :** Changer filtre, afficher détail autorisé, exporter E46 ; lecteur d’écran dispose des valeurs textuelles.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Zéro réel ≠ données absentes ≠ droit non attribué ; pas graphique rempli d’exemples en production. |
| Erreur | Filtre incompatible sur financier : indicateur non applicable, pas attribution par moniteur fictive. Erreur réseau garde date ancienne visible seulement si accès encore valide. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F22 F23 J26.

<a id="e46"></a>
## E46 · Export de gestion

**Entrées :** E34 ou E45. **Public :** EXPORT_MANAGEMENT et droit au jeu.

**Fonction et hiérarchie :** Type de jeu, colonnes minimales, scope, filtres, taille et avertissement sur le fichier téléchargé ; job et expiration.

**Actions et sorties :** Confirmer export, retrouver son état, télécharger avec autorisation renouvelée. Export personnel légal renvoie F14, pas ce formulaire.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Résultat de filtre vide : export avec en-têtes et nombre zéro explicite ; pas fichier d’une ancienne recherche. |
| Erreur | Trop de lignes : restreindre. Droit retiré : téléchargement bloqué même si READY. Expiré : nouvelle demande explicite ; aucune URL publique permanente. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F14 F22 F23 J26.

**Précisions de comportement :** Afficher les métadonnées des octets réellement disponibles et le refus si les droits ont changé. Régénérer crée une nouvelle intention explicite, pas un contenu changé sous le même téléchargement.

<a id="e47"></a>
## E47 · Accueil personnel du moniteur

**Entrées :** Acceptation invitation personnel. **Public :** INSTRUCTOR et ADMIN qui enseigne.

**Fonction et hiérarchie :** École, rôles et périmètre, nom public, contact utile, première action et aide appareil ; pas le wizard de propriétaire.

**Actions et sorties :** Confirmer profil propre ; consulter affectations ; préparer appareil E44 ou entrer dans Séance.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Aucune affectation : explication de l’organisation, pas liste complète d’élèves. |
| Erreur | Compte partagé interdit ; refus permission ne retire pas les tâches administratives autorisées. Aucun choix d’élève signé par le moniteur lors de cet accueil. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F01 F21 J20.

<a id="e48"></a>
## E48 · Politique de profil et paramètres détaillés

**Entrées :** École/Paramètres web, édition autorisée tablette. **Public :** ADMIN.

**Fonction et hiérarchie :** Réglages groupés par organisation, formations/offres, données, accès. Tableau borné champ/finalité/étape/statut/version ; aperçu effet élèves et date d’entrée en vigueur.

**Actions et sorties :** Publier version après contrôle ; choisir les champs autorisés et les stades ; consulter impacts. Photo ne peut jamais être obligatoire.

| État | Comportement attendu |
|---|---|
| Chargement | Zone de contenu annoncée, ancienne école jamais exposée, commande non soumise deux fois. |
| Vide | Aucun champ conditionnel requis : onboarding minimum assumé, non une configuration défectueuse. |
| Erreur | Champ arbitraire ou finalité absente refusé. Conflit de version ne modifie aucun achat passé. Interface indique les futures actions concernées sans invalider l’historique. |
| Hors ligne | Web : pas de mutation prétendue enregistrée. App : seulement les capacités locales documentées ; nouvelle décision serveur indisponible. |
| Permission | Accès absent, expiré ou révoqué : aucune donnée hors droits ; expliquer la restriction, conserver une sortie sûre et appliquer les précisions de la ligne Erreur. |
| Succès | État/version confirmé, message textuel contextualisé et focus rendu à une destination utile. |

**Adaptation :** web large et tablette : panneaux selon largeur utile ; fenêtre étroite : étapes/pages empilées, actions essentielles accessibles, ordre de focus logique. Ne jamais exiger le survol pour une fonction.

**Traçabilité :** F13 F20 F21 F22 J19 J28.

<a id="e49"></a>
## E49 · Supprimer mon compte Drivy et suivre la demande

**Fonctions :** F01/F14. **Entrée :** Compte E19, même sans école active ; app iPhone/iPad et web. **Parcours :** J29. **Données :** aperçu et demande de suppression, jamais autres dossiers scolaires.

**Hiérarchie :** titre précis ; conséquences et rétentions ; engagements à traiter ; délai/prochain suivi ; action de réauthentification puis confirmation. L’export est proposé sans détour obligatoire. Un avertissement local distingue données non transférées connues et données serveur. Ne pas mettre l’action dans un écran de réglages réservé à ADMIN.

**Actions :** demander aperçu ; confirmer explicitement ; consulter reçu ; retirer avant PROCESSING sous version ; contacter l’assistance à identité vérifiée. « Demande reçue » est distinct de « Suppression terminée ». Au passage PROCESSING, la session métier est révoquée et l’app conserve uniquement le suivi limité autorisé. Le reçu ne figure dans aucun lien copié ou paramètre analytique.

| État | Comportement attendu |
|---|---|
| Chargement | Aperçu annoncé, confirmation inactive tant que les conséquences actuelles ne sont pas connues. |
| Vide | Aucune école active n’empêche de demander la suppression du compte ; aucune demande existante ne vaut suppression déjà faite. |
| Erreur | Aperçu périmé, conflit de rôles ou retrait devenu irréversible : actualiser l’état avant une nouvelle décision. |
| Hors ligne | Aucune demande prétendue envoyée ; conserver au plus une intention non destructive puis refaire authentification et aperçu. |
| Permission | Réauthentification refusée ou reçu expiré : conserver seulement les possibilités de suivi autorisées, sans retour vers les dossiers métier. |
| Succès | Distinguer demande reçue, en traitement et terminée ; afficher le prochain suivi et les rétentions applicables. |

**Précisions des états :** chargement, aperçu périmé, réauthentification refusée, réseau indisponible, plus d’école, liste de rôles modifiée, demande déjà existante, retrait devenu irréversible, traitement long avec prochain suivi, reçu expiré, terminé avec explication des rétentions. Hors ligne, ne pas afficher demande envoyée tant qu’elle n’est pas reçue ; conserver au plus une intention non destructive et refaire authentification/aperçu avant confirmation.

**Accessibilité :** texte explicite, aucune couleur seule, confirmation clavier/VoiceOver, Retour sans lancer la suppression, surface stable sur tablette. La suppression n’est pas déclenchée par lien profond ni notification. [R103/R104](../03-fonctionnel/regles-etats.md#r103).

**Précisions de comportement :** L’aperçu affiche le nombre total d’écoles et des pages du même manifeste. Confirmer l’ensemble n’exige ni chargement de chaque page ni appel au support. Dernier ADMIN : IN_REVIEW puis suivi interne avant PROCESSING, sans fermeture automatique d’école. Les délais et rétentions restent à qualifier au titre de DM06.
