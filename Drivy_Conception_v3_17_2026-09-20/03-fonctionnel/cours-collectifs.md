# F18 : cours collectifs, inscription volontaire et présences

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

<a id="f18"></a>

## Objectif et origine

Remplacer, lorsqu’une école le souhaite, l’annonce informelle d’un cours puis les échanges individuels pour connaître les dates et les places. Le porteur décrit ce fonctionnement sur WhatsApp chez Luc’s ; cette description est un **témoignage utilisateur**, pas une observation indépendante du fonctionnement de l’école. Drivy propose un agenda d’offres, sans imposer ce workflow à toutes les écoles.

**Résultat attendu :** un cours publié, une inscription explicite confirmée sans surréservation, puis un suivi des présences et de l’exigence réellement accomplie. Le module complète le cœur GPS ; un cours en salle ne collecte aucune position GPS.

**Références normatives :** [R55–R69](regles-etats.md#r55), [R06](regles-etats.md#r06), [R10–R12](regles-etats.md#r10), [R23–R26](regles-etats.md#r23), [R53–R54](regles-etats.md#r53). Les choix chiffrés restent dans ces règles ou le profil approuvé, pas dupliqués dans chaque écran.

## Objets métier

| Objet | Responsabilité | Ne doit pas être confondu avec |
|---|---|---|
| CourseTemplate | Type de cours, exigence visée et produit associé | Une série de dates vendue. |
| RegulatoryProfileVersion | Contraintes datées approuvées, preuves et critères | Un prix librement modifiable par l’école. |
| CourseSession | Une série complète, capacité, audience, conditions et version | Une leçon individuelle. |
| CourseOccurrence | Un bloc daté, salle, formateur et objectifs | Une place supplémentaire à vendre au même élève. |
| CourseEnrollment | Une place pour un élève sur la série entière | Un paiement ou une attestation. |
| AttendanceRecord | Présence de cet élève à ce bloc | Le fait d’avoir cliqué « S’inscrire ». |
| RequirementRecord | Accomplissement ou dispense documenté d’une exigence | Le solde d’un pack. |

## Rôles autorisés et préconditions

**MANAGE_COURSES** autorise préparation, publication, modification et annulation d’une série dans l’école. L’administrateur peut détenir cette capacité ou la déléguer ; ce n’est pas un accès aux trajets. **TAKE_ATTENDANCE** autorise les présences de ses occurrences. **VALIDATE_REQUIREMENT** autorise la validation d’un accomplissement ou d’une preuve externe. Ces capacités peuvent être cumulées, mais sont contrôlées distinctement.

L’élève actif consulte les offres de son audience, voit uniquement ses inscriptions, s’inscrit et se désinscrit selon les conditions acceptées. Le personnel peut saisir à sa place une demande réellement reçue, avec origine tracée. L’inscription d’un mineur et l’acceptation contractuelle exigent une politique validée avant données réelles ; ne pas supposer que l’autorisation GPS du téléphone vaut autorisation contractuelle.

Une école sans ce module n’a ni section vide ni notification collective. Désactivation avec inscriptions futures : refus et liste de résolution, pas disparition des cours.

## Parcours de publication

1. Le personnel choisit la prestation et le profil réglementaire applicable. Il saisit le titre, le lieu, la salle, le formateur, les blocs, la capacité et les conditions commerciales.
2. L’aperçu affiche toutes les dates, la place consommée dans un pack compatible ou le prix unitaire, les délais de désinscription et l’audience. Les capacités réglementaires et matérielles contraignent le maximum.
3. À « Publier », le serveur revalide profil, horaires, disponibilité des ressources et version. Une erreur laisse le brouillon intact, sans annonce partielle.
4. La série devient PUBLISHED et ses occurrences apparaissent dans la couche des offres des élèves actifs concernés par l’audience d’école. Les inscrits n’existent pas encore.
5. Une campagne unique de notification est créée. Les destinataires réellement admissibles aux annonces sont sélectionnés selon [F19](calendrier-notifications.md), indépendamment de la visibilité générale de l’offre.

L’école peut proposer des cours de sensibilisation, de premiers secours ou d’autres formations. Les exigences réglementaires d’un type ne sont jamais appliquées par défaut aux autres.

## Parcours élève et confirmation

L’élève voit « Sensibilisation · Disponible · Non inscrit ». La fiche détaille la série et précise « Cette inscription réserve une place pour toutes les dates ci-dessous ». Il voit la capacité restante indicative, le lieu, le prix ou le droit compatible, les conditions et les critères de participation.

Le bouton « S’inscrire » ouvre une confirmation avec toutes les dates et la version commerciale. Le serveur ne fait pas confiance au compteur affiché. Il verrouille les ressources nécessaires, recontrôle le besoin et les conditions, puis confirme dans une transaction l’inscription, les occupations et le droit réservé ou compte de prestation. Une seule confirmation crée un droit à la place.

Après succès, toutes les occurrences passent visuellement dans « Mes rendez-vous » avec « Inscrit ». La confirmation in-app persiste même si la notification push échoue. L’élève peut rouvrir l’app ou répéter une requête perdue sans créer deux inscriptions.

À COURSE_FULL, la fiche devient « Complet » ; aucun droit n’est retiré, aucun montant n’est dû et aucun rendez-vous n’apparaît. Une place libérée redevient accessible, mais personne n’est inscrit automatiquement.

## Formation déjà suivie ou situation inconnue

Une personne inscrite pour deux permis possède un dossier d’exigences reliées explicitement. Une même sensibilisation validée ne génère pas deux demandes de suivi. COMPLETED ou EXEMPT supprime les annonces de nouvelle offre liées à ce besoin ; l’offre peut rester visible dans le calendrier général de l’école.

L’élève peut choisir « J’ai déjà suivi ce cours » et joindre une preuve ou demander une vérification physique. Cela crée EVIDENCE_PENDING ; le personnel valide ou refuse avec motif. Aucun pack n’est consommé pour une formation suivie ailleurs. Un statut UNKNOWN ne constitue pas une preuve de non-accomplissement : le calendrier invite à préciser la situation ; l’auto-inscription reste bloquée tant que les critères nécessaires ne sont pas validés.

Les inscrits reçoivent toujours les avis concernant leur cours (déplacement, annulation), même si leur statut pédagogique a changé. Pour un élève reconnu dispensé après réservation, proposer l’annulation explicite et traiter la place et les droits ; ne pas le retirer silencieusement.

## Modifications, annulations et absences

| Situation | Comportement proposé |
|---|---|
| Correction d’une faute dans le titre | AP192 EDITORIAL : nouvelle version technique, même offerRevision ; pas une nouvelle campagne générale. |
| Changement de prix | AP192 COMMERCIAL : nouvelle offerRevision avant début, pour futures inscriptions ; les cycles déjà inscrits gardent leur snapshot commercial. |
| Changement de date ou lieu | Contrôle de tous les conflits, puis RECONFIRMATION_REQUIRED ; comparaison ancien/nouveau, place maintenue. |
| Nouvelle date incompatible avec un inscrit | Refus de la mutation globale ; le personnel résout le cas avec l’élève avant nouvelle tentative. |
| Élève ne répond pas au changement | Place conservée, état visible au personnel ; pas de facture ni désinscription supplémentaire automatique. |
| Annulation élève dans les conditions | Libérer la place et le droit encore réservé ; ajuster le compte sans inventer un remboursement. |
| Annulation hors délai ou cours commencé | Contact du personnel ; décisions et compensations tracées. |
| École annule toute la série | Tous les inscrits avertis ; occupations futures libérées, droits et montants traités explicitement. |
| Absence à un bloc | Marquer ABSENT, garder le parcours PARTIAL si nécessaire ; ne pas valider le cours. |
| Rattrapage | Traitement par le personnel et preuve de blocs ; la réservation autonome d’un seul bloc est différée. |

Une capacité réduite sous le nombre de places actives est refusée. Un cours commencé n’est pas réutilisé comme nouvelle série. Une suppression dure ne remplace jamais une annulation d’un cours déjà réservé.

## Présence, droit acheté et validation finale

Le formateur ouvre la liste de ses inscrits par occurrence. Il marque présence ou absence avec date et auteur. Les preuves requises par le profil sont conservées dans le circuit de documents, à accès limité. Une correction de présence crée un événement d’audit, pas une réécriture introuvable.

La proposition commerciale du pilote consomme le droit de série à la première présence confirmée (R54), tandis que la validation pédagogique exige tous les blocs requis et une décision habilitée (R63). Cette politique doit être acceptée par chaque école ; elle n’est pas présentée comme une règle de droit universelle. Une annulation d’école après une présence nécessite un arbitrage de compensation explicite, pas une restitution aveugle ou un abandon du droit.

La fiche élève affiche séparément « Inscrit », « Présence : 2 blocs sur 4 », « Exigence : partiellement accomplie », « Paiement : réglé ». Les exports sont internes ; aucun envoi automatique à une autorité ni intégration SARI n’est affirmé.

## Contraintes réglementaires et transition 2027

La sensibilisation n’est pas un événement libre quelconque. Les instructions OFROU applicables à partir de 2021 décrivent une structure de cours et des exigences de contrôle. Elles sont utilisées comme source datée pour le profil de référence 2026, pas comme justification éternelle de toutes les sessions [S44](../06-gouvernance/sources.md#s44).

L’OFROU annonce au 1er janvier 2027 un changement de contenu et de place du CTC dans le parcours d’accès à l’examen théorique [S45](../06-gouvernance/sources.md#s45). Le profil 2027 reste **DRAFT_REQUIRES_REVIEW** tant que les textes complets, cas transitoires et exigences cantonales n’ont pas été validés. L’app ne bloque donc pas arbitrairement toute personne sans permis élève selon une constante héritée de 2026. Une publication dépendant d’un profil non approuvé est refusée avec « Paramétrage réglementaire à valider ».

## Contrat, erreurs et données

Le contrat [OpenAPI](../04-technique/openapi.yaml) expose création/édition/publication de sessions, lecture des offres, création/annulation/reconfirmation d’inscriptions, présence et exigences. Les transactions détaillées sont dans [transactions GPS, packs et cours](../04-technique/transactions-v2.md).

Erreurs à distinguer : COURSE_FULL (409), ALREADY_ENROLLED (409 ou résultat idempotent de la même commande), SCHEDULE_CONFLICT (409), INELIGIBLE (422), REQUIREMENT_UNVERIFIED (422), PROFILE_NOT_APPROVED (422), OFFER_CHANGED (412), INSUFFICIENT_ENTITLEMENT (409), CANCELLATION_REQUIRES_STAFF (409), OUTSIDE_SCHOOL (404), OPERATION_PENDING (202 si résultat encore indéterminé). Aucune erreur ne divulgue les noms d’autres élèves.

## Critères d’acceptation essentiels

Deux élèves visent une dernière place : un succès et un refus sans débit. Une publication ne crée aucune inscription. Une série de plusieurs dates n’immobilise qu’une place mais occupe tous ses horaires. Un élève ayant déjà satisfait l’exigence ne reçoit pas l’annonce ciblée. Refus de push : calendrier et inscription utilisables. Une présence manquante interdit la validation finale. Un achat de pack ne préinscrit pas à une session. Une inscription manuelle et autonome concurrentes restent uniques.

Tous ces cas sont détaillés dans la [recette](../05-realisation/tests-recette.md) ; ils sont spécifiés, pas exécutés.


## Composition web et adaptation tablette

Le formulaire multi-dates peut être rempli dans le workspace web, avec aperçu des occurrences, participants et capacités. Sur tablette, calendrier et liste de présences se disposent côte à côte si la largeur suffit. Les invariants de réservation, reconfirmation et présence sont les mêmes : pas de deuxième moteur de cours selon la plateforme.

L’onboarding école ne rend ce module prêt qu’avec un profil de cours approuvé et les paramètres requis. L’onboarding élève peut demander un complément limité avant une inscription, selon la politique et la finalité applicables, sans transformer ce complément en validation de cours. La déclaration « déjà suivi ailleurs » attend une vérification distincte. Le retour d’onboarding ne consomme pas la dernière place sans un nouveau clic S’inscrire et une confirmation serveur.

Les listes et compteurs web suivent les grants. La capacité M05 compte une inscription par série même si plusieurs blocs sont planifiés. Un élève déjà inscrit à une série future ne peut pas être archivé sans résoudre cet engagement explicitement.

## Réinscription après annulation

[R59](regles-etats.md#r59) distingue la relation unique élève/série de ses cycles. Une nouvelle demande n’efface pas le cycle annulé. L’API renvoie `enrollmentCycle`, incrémenté seulement à la réinscription effectivement confirmée. Les mouvements de place et de droits sont liés à ce cycle et à l’opération ; le compte conserve ses écritures passées. Un remboursement encore dû bloque la réinscription avec `ENROLLMENT_FINANCIAL_REVIEW_REQUIRED` jusqu’à traitement ; rien n’est annoncé comme remboursé automatiquement.

<a id="coherence-cycle-offre"></a>
## Séries, cycles et informations acceptées

Les corrections de titre/prix passent par AP192 ; une série DRAFT reste éditée par AP132. Les champs d’exigence/profil/produit d’une série publiée ne sont pas retargetés par un changement de modèle. Voir [R51](regles-etats.md#r51), [R59](regles-etats.md#r59) et [R62](regles-etats.md#r62).

Le formulaire de déplacement affiche, en plus de toutes les dates, les deux échéances avant/après. Le serveur vérifie leur cohérence avant de notifier quiconque. La confirmation de nouvelles dates ne fait pas accepter un nouveau prix. Le cycle stocke aussi `acceptedSelfCancellationDeadline` : AP144 fait confirmer explicitement l’échéance proposée avec les dates ; une échéance raccourcie ne prive pas silencieusement un inscrit de son droit antérieur avant cette acceptation. Le prix antérieur reste intact.

La feuille de présence est liée au cycle visible dans le roster. Premier relevé conditionnel, correction versionnée, blocage d’une saisie provenant d’un ancien cycle et absence de consommation avant un fait constaté suivent [R63](regles-etats.md#r63). La sélection des justificatifs ne peut pas contenir deux fois le même document.

Une commande en cours affiche « Confirmation en cours », sans ticket d’inscription acquis. Fermer l’app n’autorise pas la création d’une seconde intention : le statut se retrouve avec la même opération.


## Langue du cours, offre et engagement

La V3.5 matérialise la langue annoncée dans CourseSession/Command et CalendarOffer, selon [R105](regles-etats.md#r105). La projection de l’engagement collectif la restitue. Elle est choisie avant publication et figée ensuite, comme une condition importante de participation. Le changement de titre AP192 n’autorise pas une traduction silencieuse du cours déjà accepté. Les catégories de permis et l’état d’accomplissement continuent de déterminer l’éligibilité ; la langue n’ajoute aucun ciblage caché.

## Clôture d’une série et droits jamais consommés

En E28, la revue de clôture distingue : droits consommés à une première présence, droits encore immobilisés sans aucune présence, inscriptions sans pack et suivis financiers ouverts. La commande CloseCourseCommand remplace la simple raison de clôture ; elle confirme la liste et les versions des droits à libérer selon [R106](regles-etats.md#r106). Il n’existe ni bouton « clôturer malgré tout » ni saisie PRESENT utilisée pour débloquer le registre.

Une présence concurrente ou un changement de cycle invalide la revue ; aucun des droits n’est libéré partiellement avant le refus. Après confirmation, les absences restent visibles, le cours est CLOSED et une éventuelle décision financière reste à traiter séparément. L’archivage voit le nouveau reliquat sans HOLD, mais continue de vérifier les obligations. Une correction tardive ABSENT→PRESENT suit R109 : enregistrer le fait autorisé, ouvrir la régularisation du droit si nécessaire, sans reprendre en secret une unité déjà employée ailleurs. La validation pédagogique reste distincte de cette régularisation.

<a id="correction-presence-tardive"></a>
## Présence corrigée après clôture : parcours complet

**F18, R63/R109/R110.** Le formateur habilité ouvre le relevé du cycle courant, corrige le statut avec son motif et la version affichée, puis le serveur confirme le fait. L’écran distingue « Présence corrigée » de « Droit du pack à régulariser ». Un manque de crédit ne doit plus obliger à garder ABSENT. La série reste CLOSED : la correction ne rouvre ni les inscriptions ni une place. Une saisie issue d’un ancien cycle reste un conflit explicite, non une modification de la réinscription actuelle.

L’inscription expose `rightSettlement` et sa version quand un droit rendu n’a plus de consommation active. Le responsable ouvre ce dossier, voit le mouvement source et le reliquat utilisable du lot d’origine. Il confirme soit le décompte autorisé sur ce lot, soit la renonciation à consommer ce droit. La résolution AP201 demande ADMIN et contrôle de nouveau toutes les versions. Une unité manquante, un lot suspendu ou une présence rétractée entraîne refus sans effet commercial ; la présence exacte déjà saisie reste conservée.

La fiche sépare désormais présence, accomplissement, argent et régularisation des droits. Une attente de droit n’interdit pas au personnel habilité de valider une formation réellement accomplie. Une régularisation ne valide jamais la formation. Les décisions d’accomplissement touchées par une correction sont à réexaminer selon R110, sans retirer automatiquement les futurs rendez-vous.

**Échecs à présenter :** `RIGHT_SETTLEMENT_CHANGED` (409), `INSUFFICIENT_ENTITLEMENT` (409), `ENTITLEMENT_NOT_USABLE` (409), version périmée (412), absence de grant (403). L’aperçu n’est pas un reçu de consommation. Le refus ne donne pas les données d’un autre élève. La politique de renonciation et son habilitation ADMIN sont proposées au pilote, pas validées par la recherche des tarifs.

## Vérification de la confirmation depuis la maquette

L’interface d’inscription distingue trois issues après une demande : confirmation durable, refus explicite tel que Complet, ou absence de résultat fiable. La troisième n’autorise pas une seconde intention automatique : conserver la clé et reprendre la réconciliation décrite par [Synchronisation](../04-technique/synchronisation.md). Aucune place ni droit réservé n’est ajouté à la seule fin d’une animation. Une reprise qui retrouve une confirmation met à jour les engagements ; un refus explicite laisse l’offre consultable sans inscription.

Le contrôle de galerie illustre ces issues sur une même demande fictive. Il ne simule ni le verrou SQL de capacité, ni un paiement, ni un délai contractuel. Les réponses finales et leurs effets restent ceux des règles F18/R existantes.
