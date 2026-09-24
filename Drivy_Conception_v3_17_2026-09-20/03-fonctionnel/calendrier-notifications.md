# F19 : calendrier d’offres et notifications ciblées

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

<a id="f19"></a>

## Objectif et frontières

L’élève conserve un véritable calendrier. Il y voit ses leçons et cours confirmés, mais aussi les cours que son école propose. La distinction visuelle et métier empêche d’interpréter une publication comme une convocation. F18 gère les places ; F19 projette l’agenda et détermine l’annonce ; F11 transporte les messages.

**Références :** [R55](regles-etats.md#r55), [R58](regles-etats.md#r58), [R64–R65](regles-etats.md#r64), [R26](regles-etats.md#r26), [R70](regles-etats.md#r70).

## Visibilité et occupation

L’API renvoie deux collections pour la même fenêtre : commitments et offers. Les commitments sont personnels et bloquants ; les offers sont des possibilités scolaires non bloquantes. Les occurrences d’une série déjà réservée ne sont pas affichées une seconde fois comme offres : la clé visuelle combine courseSessionId et occurrenceId.

Par défaut, les membres élèves actifs de l’école voient les cours publiés de l’audience scolaire, y compris les personnes déjà formées, avec filtre « Afficher les cours disponibles ». Au pilote, l’école peut borner une audience par catégorie de formation active validée ; cet aperçu précise la règle. Le site reste une information de lieu consultable ; la langue est une information et un filtre d’offres. Le filtre par site n’est pas contractualisé au pilote. Ni site ni langue ne sont des critères de ciblage tant qu’aucune préférence élève n’est définie. Aucune segmentation par trajet ou localisation n’est utilisée.

Le fait d’avoir déjà accompli une sensibilisation influe surtout sur l’annonce et l’admissibilité, pas sur l’existence d’un événement public à l’intérieur de l’école. L’élève peut masquer les offres ; il ne masque pas ainsi ses engagements et ne se désinscrit pas.

## Matrice d’affichage

| Situation personnelle | Libellé et action | Effet sur disponibilité |
|---|---|---|
| Offre ouverte, non inscrit | Disponible · Non inscrit ; consulter puis S’inscrire | Aucun. |
| Offre pleine | Complet ; consulter détails | Aucun. |
| Besoin déjà satisfait | Déjà effectué ; pas de réservation standard | Aucun. |
| Situation inconnue | Situation à confirmer ; mettre à jour le dossier | Aucun. |
| Inscription confirmée | Inscrit ; consulter, annuler si conditions | Toutes les occurrences occupent. |
| Dates changées | À reconfirmer ; comparer et répondre | Place et nouveaux engagements conservés. |
| Annulation enregistrée | Annulé dans historique, non bloquant | Futur libéré. |
| Cache hors ligne | Dernière actualisation visible ; inscription désactivée | Pas de nouvelle promesse. |

Les lecteurs d’écran annoncent le statut textuel. Une bande pointillée pour l’offre et pleine pour l’engagement aide, mais ne remplace pas le texte. Le prix et le nombre de places ne sont jamais exprimés par la couleur seule.

## Ciblage des nouvelles offres

À publication, un CampaignIntent est écrit atomiquement. Le worker parcourt les dossiers par pages, déduplique par élève et type d’exigence, puis relit les critères avant création/envoi du message. Les besoins TO_DO/PARTIAL sont ciblables ; UNKNOWN/EVIDENCE_PENDING ne sont pas transformés en certitude de besoin.

Une notification de nouvelle sensibilisation n’est pas envoyée à une personne qui possède deux formations comme deux annonces identiques. Une personne déjà inscrite à un cours équivalent n’est pas sollicitée comme sans place. Une preuve validée entre publication et envoi supprime l’annonce non encore livrée. Une notification déjà reçue ne peut pas être retirée avec certitude ; son ouverture relit toujours le dossier et la série.

Une mutation d’orthographe du titre n’envoie pas de nouvelle annonce. Les nouvelles places après annulation n’entraînent pas de réservation ou campagne automatique au pilote. Une future liste d’attente possédera son propre opt-in et sa politique de priorité.

## Canaux et messages

| Événement | Destinataires | In-app | Push / email |
|---|---|---|---|
| Nouvelle série publiée | Élèves ciblables non inscrits | Une annonce | Push si autorisé ; email d’annonce selon préférence, pas les deux par défaut. |
| Inscription confirmée | Élève inscrit | Confirmation durable | Push/email selon école + préférence personnelle + capacité technique ; confirmation in-app toujours consultable. |
| Date/lieu modifié | Tous les inscrits concernés | Action de reconfirmation | Push et email opérationnel selon disponibilité. |
| Série annulée | Tous les inscrits concernés | Information persistante | Avis transactionnel ; aucun destinataire en copie visible. |
| Rappel de cours | Inscrits actifs seulement | Rappel | Horaire paramétrable, invalidé sur changement/annulation. |
| Présence ou exigence validée | Élève concerné | Mise à jour du parcours | Pas d’annonce de groupe. |
| Nouveau bilan avec trajet | Élève de la leçon | Bilan disponible | Pas de coordonnées ou observations privées dans le payload. |

Exemple d’annonce : « Un cours de sensibilisation est disponible dans votre école. Consultez les dates et les modalités. » Le nombre de places n’est pas figé dans le push, car il pourrait être obsolète à l’ouverture. Exemple de confirmation : « Votre inscription est confirmée. Retrouvez toutes les dates dans votre agenda. » Les contenus d’écran verrouillé restent minimisés.

## Résilience et préférences

Un token push expiré est invalidé, les tentatives sont limitées avec backoff et état d’erreur consultable par le support habilité. Ne pas confondre permission OS, préférence d’annonce et inscription marketing. Refuser le push n’empêche pas la consultation in-app. Les campagnes marketing ne sont pas activées implicitement par la création d’un compte scolaire.

Une livraison est au mieux dédupliquée par le backend ; un fournisseur peut avoir accepté une requête dont la réponse est perdue. Un message peut arriver deux fois malgré les précautions : les actions métier derrière le lien restent idempotentes et l’in-app n’affiche qu’une entrée logique. Ne pas promettre un transport exactement une fois.

L’ouverture d’un lien passe par authentification et vérification de l’école ; pas de lien portant des données privées ou permettant une inscription automatique par GET. Après sortie d’école, l’accès renvoie introuvable/accès révoqué sans fuite du contenu.

## Scénarios de validation

Un cours publié est visible mais ne bloque pas un créneau personnel. S’inscrire le transforme sans doublon visuel. Un élève COMPLETED ne reçoit pas de campagne de besoin. Une personne UNKNOWN reçoit seulement l’invitation neutre du dossier, pas « Vous devez faire ce cours ». Changement de date : tous les inscrits sont avertis, y compris ceux dont le besoin vient d’être validé ailleurs. Un échec push laisse la confirmation de place et l’in-app intactes.

Les compteurs d’ouvertures ne mesurent pas l’efficacité pédagogique. Les métriques utiles sont la compréhension du statut, les confirmations sans échange supplémentaire, les conflits évités et les réclamations d’inscription indue, sans suivi invasif.


## Continuité onboarding et multi-écrans

Un nouveau destinataire peut terminer son profil dans le navigateur puis revenir au cours. L’inscription n’est jamais précochée ; après le retour, relire la série, le prix, les dates et les places. Le profil incomplet ne réserve pas de siège pendant l’onboarding. Si la place a été prise, afficher Complet.

La tablette affiche offres et engagements selon la même sémantique dans son agenda plus large. Le web de gestion permet de composer/publier une série et de gérer ses présences ; la consultation élève web reste personnelle. Les champs nécessaires dépendent du profil de cours validé et de la finalité (R77/R81), jamais de la photo ou de l’acceptation GPS.

Archiver retire les nouvelles offres/annonces et bloque l’inscription sans révoquer automatiquement les accès à l’historique. Le contrôle de l’audience est relu lors de l’envoi, de l’ouverture et de l’inscription ; R70 précise la distinction avec une révocation réelle.

## Audience déterministe du pilote

Le filtre d’audience scolaire peut porter sur les catégories des Training actives et validées. ALL_ACTIVE_LEARNERS n’applique aucun filtre ; FILTERED exige au moins une catégorie. Les dimensions site et langue n’ont pas de source d’affiliation élève définie dans le modèle actuel : elles ne servent donc pas à exclure un élève ni à cibler un push au pilote. Les champs API `CourseAudience.siteIds` et `languages` restent des tableaux vides réservés, refusés s’ils sont remplis. Le site reste affichable ; la langue du cours est affichable et filtrable dans la consultation des offres. Leur activation comme ciblage exigera une préférence scolaire explicite et documentée, jamais une déduction depuis le GPS, l’adresse ou la langue de l’interface.

## Source d’exigence et révisions sans campagne parasite

Le besoin ciblé vient de `CourseSession.requirementTypeSnapshot`, pas du modèle courant de cours. Une retouche EDITORIAL via AP192 ne recrée pas une campagne générale. La révision COMMERCIAL ne remplace pas les conditions acceptées par les inscrits ; les notifications de changement de dates continuent selon [R62](regles-etats.md#r62). Le flux d’invalidation des offres et engagements empêche qu’une lecture ancienne reste présentée comme une confirmation courante.

## Livraison mobile et ouverture d’un cours

Les [adaptateurs de notification et de liens](../04-technique/integration-mobile-transverse.md) précisent installation/jeton, domaine associé, contenu minimal et ouverture sous droits courants. L’intention outbox n’est pas une preuve de lecture par l’élève ; un push reçu n’est pas une inscription. Notification absente, refusée, retardée ou dupliquée ne modifie pas les règles de disponibilité/confirmation. Les [cas MOB018/MOB019](../05-realisation/qualification-mobile-ui-ux.md#mob018) complètent la recette.


<a id="précisions-v35"></a>
## Langue des offres et préférences de communication
La langue annoncée est teachingLanguage selon [R105](regles-etats.md#r105), et non CourseAudience.languages. Le filtre de consultation ne masque jamais les engagements confirmés. Les canaux suivent la conjonction école + personne + capacité technique définie par [R65](regles-etats.md#r65). Désactiver une campagne n’efface ni l’offre de calendrier ni une inscription. La langue n’est jamais inférée du nom, de l’adresse ou des trajets.

## Création des préférences et absence de choix

**Proposition de défaut explicite à valider au pilote :** la création d’une appartenance initialise NotificationPreferences version 1 avec courseOffersInApp=true et les quatre canaux externes courseOffersPush/courseOffersEmail/transactionalPush/transactionalEmail=false. Le centre interne et le calendrier restent utiles ; l’onboarding propose ensuite de choisir les canaux pertinents. Ce n’est ni un consentement GPS ni une qualification juridique générale de tous les messages. GET lit cet objet sans le créer ; PUT requiert son ETag. Une permission système accordée seule ne transforme pas la préférence en true.

AP152 sans aucun choix enregistré répond 404 RECORDING_CHOICE_NOT_SET après vérification de l’accès au dossier. Le client présente « Choix non renseigné » et ne démarre pas de collecte ; il ne crée pas de RecordingChoice SELF/RECORDED_VERBAL pour satisfaire un schéma. Un refus ou accord réellement saisi garde son acteur, sa notice et son horodatage. Les événements inconnus/droits refusés restent distingués côté serveur sans fuite inter-école.

## Preuve réexaminée et appareil réaffecté

Une exigence invalidée par R110 devient EVIDENCE_PENDING : elle ne remplit pas automatiquement une audience TO_DO/PARTIAL. Les offres restent consultables. Les communications nécessaires à un rendez-vous existant restent possibles selon préférence et droits, sans transformer un incident de preuve en campagne répétée.

Le push natif suit [R112](regles-etats.md#r112). Une acceptation de notification par le téléphone ne rattache pas toutes les écoles d’un ancien compte au compte nouvellement connecté. Le centre interne web n’utilise pas AP148 et ne demande pas d’autorisation navigateur ; une véritable souscription Web Push nécessiterait un futur contrat distinct, non représenté par une simple chaîne token.
