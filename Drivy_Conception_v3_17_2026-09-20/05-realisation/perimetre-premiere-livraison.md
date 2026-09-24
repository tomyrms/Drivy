# Périmètre de la première livraison : objets et justification

> Référence 3.13 · Proposition de découpage, pas schéma physique validé. [Roadmap](roadmap-backlog.md) · [Modèle courant](../04-technique/modele-donnees.md).

## Règle d’admission

Le premier incrément interne G1/G2 sert un parcours pédagogique complet sur données fictives. Il n’implémente pas d’avance les objets de G3/G4 ; le pilote complet les inclut quand leurs parcours sont prêts. Les objets d’identité, d’isolation, de reprise et de conservation restent nécessaires dès que les données correspondantes existent. Les politiques de données et la suppression ne sont pas facultatives à l’ouverture réelle parce que leur orchestration complète est testée plus tard.

Le registre recense les **101 libellés distincts présentés dans les tableaux du modèle**, avec 113 lignes avant regroupement. Il inclut des vues, DTO, attributs et groupes ; ce n’est pas un nombre d’entités à coder. Il ne crée aucun nouvel objet pour Android ou pour la saisie live. Une proposition de table sans commande, lecture, droit et cycle de vie identifiés est à refuser ou différer, pas à générer par habitude.

Les justifications ci-dessous proviennent des contraintes décrites, pas d’entretiens utilisateurs. Elles doivent être éprouvées au moment d’implémenter chaque tranche. Un groupe de concepts n’a pas d’allocation physique implicite ; une projection calculable ne doit pas devenir une seconde source de vérité.

<a id="profil-dimplementation-g1g2"></a>
## Profil d’implémentation G1/G2 : ne pas matérialiser le registre d’un coup

Le tableau exhaustif plus bas reste utile pour vérifier qu’aucun besoin ou invariant n’est oublié. **Il n’est pas un plan de migrations.** La première implémentation doit avancer par tranches verticales et choisir la représentation physique la plus simple qui préserve les invariants connus.

### Ordre recommandé des tranches

| Tranche | Parcours démontrable | Concepts qui doivent exister logiquement | Ce qui peut rester regroupé ou différé |
|---|---|---|---|
| G1A · Accès et école | Se connecter, entrer dans une école, voir son rôle, ouvrir un dossier élève/formation autorisé | Person, IdentityLink, School, SchoolMembership, LearnerProfile, Training, InstructorAssignment, OfferingVersion | Role/Grant peuvent appartenir à l’agrégat d’appartenance si leurs contraintes et requêtes restent simples ; invitation uniquement quand le parcours d’invitation est réellement livré. |
| G1B · Configuration minimale | Configurer ce qui est nécessaire au premier parcours, joindre une pièce réellement utilisée | paramètres/version d’école nécessaires, Operation/Audit pour effets critiques, Document si un écran G1 l’exige | curriculum détaillé, push, campagnes, pipeline média avancé et politiques non utilisées ne sont pas créés préventivement. |
| G2A · Leçon sans GPS | Planifier, préparer, démarrer, constater, rédiger et publier un bilan sans dépendre de la géolocalisation | AvailabilityRule/Closure selon besoin, Lesson, Reservation, LessonPreparation, LessonOutcome, rapport versionné, observations pédagogiques | brouillon/révision/pointeur de publication peuvent partager un même agrégat physique si immutabilité et concurrence restent garanties ; projection de progression reste dérivée. |
| G2B · Capture et observation live | Autoriser/refuser la capture, enregistrer une trace partielle, créer une observation, la retrouver au bilan | RecordingChoice, CaptureSession, données de trace, GeoObservation, publication de capture | segments/chunks/manifeste/snapshot ne nécessitent pas chacun une table SQL : stockage objet, métadonnées et manifestes peuvent porter ces concepts tant que reprise, hash, purge et lacunes restent démontrables. |
| G2C · Continuité | Couper le réseau, reprendre sans doublon, perdre un droit, resynchroniser | Operation/idempotence, Outbox si événement asynchrone réel, horloge/curseur de synchronisation, invalidation | ProjectionEvent et BootstrapSnapshot sont d’abord des contrats de lecture ; aucune table dédiée sans besoin de conservation/requête. |

Les packs, droits commerciaux, cours collectifs, campagnes, métriques, archivage en lot et orchestration complète de suppression appartiennent à G3/G4 sauf dépendance explicite d’un parcours antérieur. Leur présence dans le modèle cible ne justifie pas leur création pendant G1/G2.

### Quand séparer physiquement un concept

Créer une table, collection ou objet persistant indépendant seulement si au moins un critère est réel :

- cycle de vie ou autorisation indépendante ;
- unicité, clé étrangère ou contrainte transactionnelle qui doit être garantie par le stockage ;
- verrouillage/concurrence ou idempotence indépendante ;
- rétention, purge ou restauration indépendante ;
- relation plusieurs-à-plusieurs ou cardinalité non raisonnable à embarquer ;
- volume append-only ou indexation/recherche qui justifie un stockage séparé ;
- preuve de performance montrant que l’agrégat actuel n’est plus adapté.

À l’inverse, un DTO, un état calculé, une vue, une projection recalculable, une configuration versionnée de petite taille ou un sous-objet sans cycle propre **ne reçoit pas une table par défaut**. Une séparation future motivée par une mesure est préférable à une architecture spéculative au premier commit.

### Revue obligatoire avant chaque migration

Pour chaque nouvelle persistance indépendante, la PR ou l’ADR courte doit nommer : **commande créatrice**, **lectures qui l’utilisent**, **invariant non garanti autrement**, **rétention/suppression**, **index/contrainte**, et **scénario de preuve**. Si un de ces éléments manque, la création est différée ou le concept reste embarqué/dérivé.

| Objet ou groupe | Nature | Première tranche | Raison de le prévoir / contrainte à défendre |
|---|---|---|---|
| Person | concept de données | G1 | Identité humaine globale ; données scolaires hors de cette table. [R104](../03-fonctionnel/regles-etats.md#r104) et [ordre](../04-technique/transactions-v2.md#autorisation-et-commit) |
| IdentityLink | concept de données | G1 | Unique `(issuer, subject)` ; email vérifié est un attribut, pas une clé métier universelle de dossier. |
| School | concept de données | G1 | DRAFT/ACTIVE/ARCHIVED ; fuseau IANA. |
| SchoolMembership | concept de données | G1 | Unique `(school_id, person_id)` ; ACTIVE/REVOKED. |
| MembershipRole | concept de données | G1 | Unique rôle par appartenance ; ADMIN/INSTRUCTOR/LEARNER. |
| MembershipGrant | concept de données | G1 | `permit_review`, `cash_record`, CONFIGURE_CATALOG, SELL_SERVICES, MANAGE_COURSES, TAKE_ATTENDANCE, VALIDATE_REQUIREMENT, REVIEW_REGULATORY_PROFILE, MANAGE_LEARNER_ARCHIVES, VIEW_SCHOOL_METRICS, VIEW_FINANCIAL_METRICS, EXPORT_MANAGEMENT ; portées détaillées dans les permissions. |
| LearnerProfile | concept de données | G1 | Unique profil scolaire par personne ; rattachement LEARNER actif pour parcours courant. |
| Invitation | concept de données | G1 | Jeton haché unique ; états PENDING/ACCEPTED/REVOKED/EXPIRED. |
| SchoolPolicyVersion | concept de données | G1 | Procédure relue et approuvée avant activation de l’offre ; pas de moteur automatisé de droit cantonal. |
| SchoolSettingsVersion | concept de données | G1 | Version immuable des paramètres applicables. |
| OfferingVersion | concept de données | G1 | Clé logique stable `offering_key`, numéro de version distinct ; référentiel et politique documentaire valides avant activation. |
| Training | concept de données | G1 | Index unique partiel `(school_id, learner_profile_id, offering_key)` pour ACTIVE/PAUSED ; une nouvelle version de l’offre ne contourne pas cette contrainte. Plusieurs catégories admises. |
| InstructorAssignment | concept de données | G1 | Formation et membre de même école ; rôle INSTRUCTOR actif. |
| PermitCheck | concept de données | G1 | Pièce READY ou attestation physique explicite ; décision humaine. |
| AvailabilityRule | concept de données | G2 | Intervalles locaux valides, dates d’application cohérentes, calendrier de l’école. |
| Closure | concept de données | G2 | Début < fin ; motif privé non exposé à l’élève. |
| Lesson | concept de données | G2 | Formation et moniteur compatibles ; personne élève dérivée de formation. |
| Reservation | concept de données | G2 | Origine explicite ; moniteur/salle pour occurrence, élève pour inscription ; contraintes d’exclusion communes. |
| LessonOutcome | concept de données | G2 | Historique des constats/corrections ; heures réelles différentes des heures prévues. |
| LessonPreparation | concept de données | G2 | 0 à 3 objectifs ; IDs de compétences versionnées facultatifs. |
| LearnerWish | concept de données | G2 | Auteur élève concerné ; formation explicite. |
| CurriculumVersion | concept de données | G1 | Version immuable ; aucun catalogue présenté comme standard légal sans validation. |
| CompetencyDefinition | concept de données | G1 | Identifiant stable pour une version ; correspondance inter-versions explicite, jamais par simple texte égal. |
| OutcomeApproval | concept de données | G2 | Approbateur affecté, validité courte, contenu et versions immuables ; consommation atomique avec correction. |
| ReportDraft | concept de données | G2 | Un brouillon courant par auteur/leçon ; privé ; transitions contrôlées. |
| ReportRevision | concept de données | G2 | Immuable après publication ; numéro unique par leçon. [R46](../03-fonctionnel/regles-etats.md#r46) |
| ReportPublication | concept de données | G2 | Pointeur atomique, retrait motivé possible ; ne détruit pas révisions. |
| CompetencyObservation | concept de données | G2 | Révision et formation cohérentes ; seule la révision publiée courante participe à la projection. |
| TrainingProgressProjection | projection ou contrat | G2 | Dérivée, supprimable/recalculable ; pas source primaire de vérité. |
| Document | concept de données | G1 | Portée cohérente ; READY ne vise que la génération contrôlée ; tombstone empêche une promotion tardive. Mime/taille projetés depuis le contenu canonique. |
| SchoolAsset | concept de données | G1 | Pas de propriétaire élève. Logo READY courant seulement ; image JPEG/PNG admissible, nom scolaire en repli. |
| UploadIntent | concept de données | G1 | Exactement un propriétaire Document ou SchoolAsset de même école ; clé jamais réaffectée. État interne OPEN/SEALED/ABANDONED ; aucune réouverture implicite. Expiration d’URL distincte du nettoyage. |
| FileGeneration | concept de données | G1 | Identifie les octets originaux figés, non écrasables via URL client ; une génération scellée par intention. La stratégie stockage/version/copie est qualifiée avant lancement. |
| FileArtifact | concept de données | G1 | Original/aperçu/canonique distingués. Chaque sortie est immuable. La promotion CAS de l’objet propriétaire et de sa génération interdit les résultats de scan obsolètes. |
| ReportAttachment | concept de données | G2 | READY et même élève/formation ; relation explicite au moment de publication. |
| Account (vue contextuelle LessonAccount) | concept de données | G2 | Un propriétaire exactement, FK scolaires et unicité par propriétaire. Les routes de leçon sont une vue du même compte ; soldes dérivés du journal commun. |
| ChargeEntry | concept de données | G2 | Total de charge jamais négatif ; écriture initiale unique par événement de réalisation/vente/inscription, corrections explicites. |
| PaymentEntry | concept de données | G2 | Montant positif, remboursements bornés et référence non inversée deux fois. |
| Operation | concept de données | G1 | Unique `(actor_person_id, operation_id)` ; contexte scolaire ou global et type de commande vérifiés avant lecture du résultat. Preuve de non-double-effet, sans contenu sensible inutile. Le marqueur en cours ne prouve pas le commit ; récupération de crash contrôlée avant reprise. |
| AuditEvent | concept de données | G1 | Append-only pour rôles applicatifs ; accès dédié ; limites de rétention. |
| OutboxEvent | concept de données | G1 | Créé dans transaction métier ; charge utile minimale ; réessais idempotents. |
| InAppNotification | concept de données | G1 | Unicité événement/destinataire ; lecture recalculée selon droits. |
| DeliveryAttempt | concept de données | G1 | Livraison séparée de l’état métier ; ne pas journaliser le texte du bilan. |
| SchoolSyncClock | concept de données | G1 | Compteur verrouillé transactionnel, garantit ordre de publication des mutations scolaires. |
| ProjectionEvent | projection ou contrat | G1 | Flux minimal ; données filtrées par droits au moment de lecture. Invalidation scoped/epoch ; ni points bruts ni permission transportée. |
| BootstrapSnapshot | projection ou contrat | G1 | Vue cohérente paginée, temporaire et privée. |
| PrivacyRequest | concept de données | G1 | Instruction et portée explicites, pas effacement aveugle. |
| RetentionPolicyVersion | concept de données | G1 | Approuvée avant pilote ; l’app n’invente pas le droit applicable. |
| DeletionTombstone | concept de données | G1 | Réappliqué après restauration et propagation aux projections. |
| RecordingChoice | concept de données | G2 | ALLOWED / REFUSED / UNKNOWN ; un accord ne dépasse pas la finalité/version ; source SELF ou RECORDED_VERBAL. |
| CaptureSession | concept de données | G2 | Une active par leçon et moniteur ; autorisation explicite ; pas de création en mode sans GPS. |
| TrackSegment | concept de données | G2 | Index unique par capture ; rupture explicite, pas interpolation entre segments. |
| TrackChunk | concept de données | G2 | Unicité capture/segment/chunk ; hash stable, stockage privé ; pas de coordonnées dans outbox générale. |
| CaptureManifest | concept de données | G2 | Réconciliation explicite ; incomplet reste PARTIAL. |
| GeoObservation | concept de données | G2 | Pendant la leçon : origin LIVE, draft_id nul ; après R15, rattachement au brouillon du même auteur sous verrou. Ancre facultative complète ; repère non qualifié non publiable ; thème/statut distincts des notes finales. |
| GeometrySnapshot | projection ou contrat | G2 | Ensemble immuable des chunks/segments publiés et lacunes ; soumis aux retraits et à la purge. |
| CapturePublication | concept de données | G2 | Au plus une capture par révision au pilote ; versions/textes/ancrages figés, droits courants et purge des dérivés. Les vues WITHDRAWN/DELETED ne contiennent plus de coordonnées ou ancrages ; purge des objets associés suivant R48. |
| SchoolSite / Room | groupe de concepts | G1 | Salle et site dans la même école ; ne pas confondre capacité matérielle avec plafond de profil. |
| ServiceProductVersion | concept de données | G1 | Version immuable après vente ; unité explicite ; référence à Offering distincte. |
| PackOfferVersion / PackComponent | groupe de concepts | G2 | Pas de packs récursifs ; composants référencés et total explicite. |
| Purchase | concept de données | G2 | Prix/conditions immuables ; compte unique ; corrections tracées. |
| EntitlementLot | concept de données | G2 | Bénéficiaire et service compatibles ; pas d’équivalence implicite de durées. Recalcul avec finance ; au service, `0 <= usable <= available`. Ne pas matérialiser une valeur périmée comme autorisation. |
| EntitlementMovement | concept de données | G2 | Append-only ; mouvements liés ; RESTORE ne duplique pas la restauration. [R107](../03-fonctionnel/regles-etats.md#r107) |
| EntitlementHold | concept de données | G2 | Un propriétaire ; consommation/libération atomique ; les mouvements font foi. |
| RegulatoryProfileVersion (API : RegulatoryProfile) | concept de données | G1 | Référence approuvée et datée par école ; profils 2027 non qualifiés restent DRAFT_REQUIRES_REVIEW. Sources publiques communes possibles ; adoption d’école explicite. |
| CourseTemplate | concept de données | G3 | Modèle configurable, pas un horaire ni une présence. |
| CourseSession | concept de données | G3 | Séries et capacité validées ; offre_version stable face aux simples changements de places. Figé à publication ; un PUT du modèle n’a aucun effet transitif. [R105](../03-fonctionnel/regles-etats.md#r105) |
| CourseOccurrence | concept de données | G3 | Une occurrence réservée par série ; ressources non chevauchantes ; structure de profil respectée. |
| CourseEnrollment | concept de données | G3 | Unicité élève/série, même pour concurrence manuel/app. Réinscription après annulation réutilise la relation avec nouvel événement et accord. |
| AttendanceRecord | concept de données | G3 | Un état courant par école/occurrence/inscription/cycle, révisions auditées ; pas de suppression d’un passé tenu. Pas de relevé fictif version 0. Création version 1 ; corrections versionnées sur cycle courant. |
| RequirementRecord | concept de données | G1 | Un état courant par exigence ; preuve requise pour COMPLETED/EXEMPT. |
| RequirementTrainingLink | concept de données | G1 | Plusieurs formations couvertes seulement par règle validée, pas par correspondance de libellé. |
| CampaignIntent / NotificationRecipient | groupe de concepts | G3 | Unique campagne/élève/type ; ciblage relu et identité minimale. |
| DevicePushRegistration | concept de données | G1 | Token secret révocable, accès du compte courant, jamais utilisé comme droit d’accès. Plusieurs écoles autorisées du même propriétaire, jamais deux propriétaires actifs pour un même tuple. Une révocation scolaire ne supprime pas les routes d’autres écoles du même compte. |
| SchoolSetup | concept de données | G1 | Un par école ; pas copie des offres. Créé avec provision ; mutations réservées ADMIN. |
| School.configuration_version | attribut | G1 | Incrémentée par configuration ayant effet sur readiness ; activation vérifie la valeur. School DRAFT ajouté explicitement. |
| OnboardingProgress | concept de données | G1 | Unique par appartenance/kind. Généré lors d’acceptation ; pas par GET. Le statut READY est dérivé des prérequis présents. |
| LearnerAdministrativeProfile | concept de données | G1 | Un par dossier scolaire. Noms null autorisés tant que profil non confirmé ; complétion exige valeurs. Lecture détaillée distincte des listes. |
| ProfileFieldPolicyVersion | concept de données | G1 | Champs/finalités/stades bornés ; version publiée immuable. Pas de champs arbitraires ni photo obligatoire. |
| TrainingRequest | concept de données | G1 | Au plus une PENDING par offre/dossier ; décision et création Training atomiques. |
| ArchivePreview | projection ou contrat | G4 | Éphémère15min proposée ; ne réserve ni dossier ni place. Aucun secret/bilan dans impacts non autorisés. |
| ArchiveJob / ArchiveJobRow | groupe de concepts | G4 | Maximum50 ; effet idempotent par job/ligne ; droits relus ; résultats mixtes autorisés. |
| DeviceAssessment | concept de données | G1 | Lié au compte et appareil ; pas coordonnées requises pour diagnostic. Non transposable via partage de connexion. |
| ManagementExportRequest | concept de données | G4 | Réutilise Export privé, distingue PRIVACY/STUDENT_LIST/METRICS. Aucun lien public ; revalidation des droits. |
| MetricsSnapshot | projection ou contrat | G4 | Dérivé et temporaire, jamais source financière primaire ; purge avec export. |
| CourseEnrollment / EnrollmentCycle | groupe de concepts | G3 | Reconfirmation de dates ne change pas le prix accepté. Historique de cycle conservé même si la relation courante est réutilisée. |
| LessonCommercialRevision | concept de données | G2 | Append-only ; projection Lesson expose `commercialRevisionVersion`. |
| LessonPreparation / Preparation | groupe de concepts | G2 | [R102](../03-fonctionnel/regles-etats.md#r102) |
| CalendarOffer / engagement collectif | projection ou contrat | G3 | [R105](../03-fonctionnel/regles-etats.md#r105) |
| AccountDeletionPreview | projection ou contrat | G4 | [Contrat global](../03-fonctionnel/compte-suppression-globale.md) [Suppression](../03-fonctionnel/compte-suppression-globale.md) |
| AccountDeletionRequest | concept de données | G4 | [R103/R104](../03-fonctionnel/regles-etats.md#r103) |
| AccountDeletionSchoolTask | concept de données | G4 | [Orchestration](../03-fonctionnel/compte-suppression-globale.md) |
| AccountDeletionReceipt | concept de données | G4 | [Reçu](../03-fonctionnel/compte-suppression-globale.md) |
| SegmentManifest | projection ou contrat | G2 | [R43](../03-fonctionnel/regles-etats.md#r43) |
| CourseSession / EnrollmentCycle | groupe de concepts | G3 | [R106](../03-fonctionnel/regles-etats.md#r106) |
| PackOfferVersion / Purchase | groupe de concepts | G2 | [R108](../03-fonctionnel/regles-etats.md#r108) |
| NotificationPreferences | concept de données | G1 | [Notifications](../03-fonctionnel/calendrier-notifications.md) |
| CourseRightSettlement | concept de données | G3 | Au plus un suivi REVIEW_REQUIRED par cycle ; historique par mouvement source conservé. Aucun mouvement nouveau par simple lecture. CourseEnrollment expose le dernier suivi, null si jamais requis. |
| RequirementDecision | concept de données | G1 | Index inverses sur les sources ; décision courante nulle lorsque le statut n’est plus final. L’historique restreint n’est pas un accès permanent aux pièces purgées. |
| RequirementDecisionBasis | concept de données | G1 | Source interne exacte, ou preuves externes, ou règle d’exemption. Unicité par identifiant dans les listes, pas seulement égalité JSON entière. Auteur/profil conservés par la décision englobante. |
| PushInstallationBinding | concept de données | G1 | Un routage global par tuple technique ; chiffrement du token, pas exposition au client dans la lecture. Le serveur authentifie séparément le compte. |

## Revue avant création physique

Pour chaque table proposée, compléter propriétaire/source de vérité, commande créatrice, index/contraintes, suppression/rétention et test réel. Les objets « attribut », « projection ou contrat » et « groupe de concepts » demandent un choix explicite avant génération de migration. Réutiliser une projection existante lorsque le parcours ne nécessite pas un état indépendant ; ne pas dupliquer la même autorisation entre clients.

La suppression globale a déjà son contrat. L’inscrire G4 pour les recettes complètes ne permet pas d’ouvrir un produit à données réelles sans son dispositif conforme et ses procédures qualifiées. Les tests de ce dossier restent NOT_EXECUTED.
