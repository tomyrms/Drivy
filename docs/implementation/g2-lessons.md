# G2 — planification des leçons

Tranche serveur du 24 septembre 2026. Références : F04/F05, R08–R14, contrats AP31–AP43 et AP100/101 de la conception. La migration006 ajoute les disponibilités, fermetures, leçons, occupations, révisions commerciales et événements à livrer. Elle ne crée aucune donnée scolaire ni approbation.

## Parcours livré

L’administration, ou un moniteur pour ses propres formations actuellement affectées, peut planifier une leçon, la consulter, la déplacer et l’annuler. L’élève consulte ses leçons. Les listes paginées sont limitées au périmètre scolaire courant ; les curseurs conservent la précision temporelle PostgreSQL et sont liés à la personne et à son époque d’accès.

La création exige une école ACTIVE, un élève actif, une formation ACTIVE non archivée, une offre active avec procédure approuvée, les champs administratifs requis pour JOIN/BEFORE_LESSON et une affectation couvrant le rendez-vous. Le moniteur doit avoir une ouverture explicite couvrant la leçon et son tampon, sans fermeture. Les instants portent un décalage UTC et le fuseau doit être celui de l’école. Aucun horaire, prix, consentement, permis ou temps de trajet n’est déduit.

AP177 PLAN_LESSON vérifie les prérequis généraux de formation, affectation, ouverture et prestation, ainsi que les champs déjà contrôlés par le profil. Cette réponse permet d’ouvrir le formulaire : elle ne promet pas qu’un créneau précis est libre. AP40 recontrôle le contexte complet lors de l’écriture.

Les occupations sont enregistrées par personne (élève et moniteur) dans des intervalles `[début, fin)`, avec exclusion PostgreSQL des chevauchements. Le tampon concerne le moniteur. L’effet, les occupations, la révision commerciale éventuelle, la preuve d’opération, l’audit et l’événement sont dans la même transaction. Les commandes scolaires prennent le verrou de l’école avant de modifier les ressources ; aucun appel réseau n’est effectué sous verrou.

Le déplacement exige If-Match et `agreementConfirmed:true`. Une variation de durée exige `commercialChange`, son motif et une sélection commerciale cohérente. Une dérogation de prix exige le rôle ADMIN. Les occupations précédentes restent intactes si la nouvelle réservation échoue. Cette tranche refuse de déplacer une leçon dont le début prévu est passé (`LESSON_STARTED`) : il faut renseigner son constat. L’annulation garde les occupations écoulées et libère seulement la partie future ; elle ne calcule pas de pénalité et ne crée pas un paiement.

## Contrats pour les clients

Toutes les routes suivantes sont sous `/v1/schools/{schoolId}`. Toutes les mutations portent `operationId` et `Idempotency-Key` identiques. Les réponses utilisent l’enveloppe habituelle `data/requestId/serverTime` ; les ressources versionnées ont un ETag fort.

| Routes | Corps / résultat |
| --- | --- |
| GET/POST `/lessons` | AP39/40 canoniques ; création201 `Lesson` |
| GET `/lessons/{lessonId}` | AP41 `Lesson` |
| POST `/lessons/{lessonId}/move` | AP42 `MoveLessonCommand`, If-Match de Lesson |
| POST `/lessons/{lessonId}/cancel` | AP43 motif canonique et commentaire facultatif, If-Match de Lesson |
| GET/POST `/availability-rules` | AP31/32, jours ISO1–7 et heures locales HH:mm |
| PUT `/availability-rules/{id}` | AP33, If-Match ; le moniteur de la plage ne change pas |
| POST `/availability-rules/{id}/remove` | AP34 ReasonCommand, If-Match, résultat Ack |
| GET/POST `/closures` | AP35/36 ; des rendez-vous existants incompatibles bloquent la fermeture |
| POST `/closures/{id}/remove` | AP37 ReasonCommand, If-Match, résultat Ack |
| GET/POST `/service-products` | AP100/101, véritables ServiceProductVersion immuables |
| GET/POST `/commercial-terms` | Extension explicite ci-dessous |

`Lesson` expose les champs canoniques, dont `publicationVersion`, `currentPublishedRevisionId`, `commercialSelection` et `commercialRevisionVersion`. Le contrôle de permis reste à livrer : `permitWarning:true`. Aucune capture scolaire n’est revendiquée (`captureSummary.hasCapture:false`) ; les trajets locaux du téléphone ne deviennent pas implicitement une capture serveur.

Les types AP72 sont CREATE/MOVE/CANCEL_LESSON → Lesson ; CREATE_SERVICE_PRODUCT → ServiceProductVersion ; CREATE_COMMERCIAL_TERMS → CommercialTermsVersion ; CREATE/UPDATE/REMOVE_AVAILABILITY_RULE → AvailabilityRule ; CREATE/REMOVE_CLOSURE → Closure. La preuve est propre à l’auteur et son périmètre actuel est revérifié, sans restitution du corps historique.

## Conditions commerciales : extension nécessaire

Le canon référence `ServiceProductVersion.termsVersionId` et `CommercialSelection.acceptedTermsVersionId` sans fournir de route de création des conditions commerciales. La tranche ajoute donc un véritable objet `CommercialTermsVersion` ; elle n’utilise **pas** SchoolPolicyVersion à sa place. Le texte de procédure scolaire et les conditions commerciales restent deux objets distincts.

POST `/commercial-terms` exige `operationId`, `label`, `termsText`, `validFrom`, `validUntil` nullable, `approved` explicite et `approvalReason`. La réponse contient `id`, `schoolId`, `version` et ces données, plus `approvedByMembershipId`/`approvedAt` nullable. Une nouvelle création produit une nouvelle version immuable ; aucune approbation n’est fabriquée. GET renvoie une page items/nextCursor ; les brouillons ne sont lisibles qu’avec CONFIGURE_CATALOG. POST des conditions et des prestations exige ce grant explicite, même pour ADMIN.

La planification livrée accepte `UNIT_PRICE` : produit individuel de la catégorie, durée × quantité égale à la leçon, prix catalogue × quantité, conditions approuvées et applicables à la date du rendez-vous. Le client doit présenter et faire accepter ces conditions avant de transmettre leur référence. Une révision commerciale fournit un nouvel accord et un motif ; `expectedAccountVersion` reste null tant qu’aucun compte n’existe avant le constat. Les versions historiques demeurent consultables selon les droits courants.

## État et limites

Livré côté serveur : routes ci-dessus, persistance, RLS, conflits d’occupation, idempotence, audit, prérequis AP177. L’application complète et le gateG2 ne sont pas qualifiés par cette tranche.

Restent à raccorder : suggestions de créneaux AP38, préférences de planning AP29/30, archives de prestations AP106, prestations par site, droits de packs ENTITLEMENT, occupations partagées avec les cours, calcul des frais d’annulation, livraison des notifications et protocole de capture scolaire. L’événement dans l’outbox n’équivaut pas à une notification envoyée. Le constat, la charge réellement due et la publication du bilan relèvent de007. Une ouverture unique doit couvrir l’intervalle ; les plages adjacentes ne sont pas fusionnées. Le rendez-vous et son tampon restent dans une même journée locale.

Contrôles exécutés : migration001–006 appliquée dans la base isolée vide `drivy_lessons_migration_test`, PostgreSQL local port55434, sous propriétaire NOSUPERUSER/NOBYPASSRLS/NOCREATEROLE/NOCREATEDB/NOINHERIT. Les28 tables sont toutes ENABLE+FORCE RLS ; l’extension btree_gist a été créée par ce propriétaire. Aucun autre jeu de données n’a été réinitialisé. Typecheck et build TypeScript sont vérifiés avant livraison. Aucun parcours HTTP nominal, campagne de concurrence ou essai natif de cette tranche n’est déclaré passé ici ; le porteur a demandé de concentrer cette étape sur la construction.
