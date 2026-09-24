# Identités, formations et administration

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Mode d’emploi

Les règles ne sont pas redéfinies ici : les identifiants R renvoient à leur [référence principale](regles-etats.md). Les séquences suivantes spécifient les fonctions du cœur proposé, avec préconditions, variantes, données et critères observables. L’[autorisation](roles-permissions.md) s’applique à tous les appels, même lorsqu’un bouton n’est pas affiché.

<a id="f01"></a>
## F01 · Identité, école et session

**Besoins :** B05. **Parcours :** [J01](../02-experience/parcours.md#j01), [J09](../02-experience/parcours.md#j09), [J11](../02-experience/parcours.md#j11). **Écrans :** [E01](../02-experience/ecrans.md#e01), [E02](../02-experience/ecrans.md#e02), [E19](../02-experience/ecrans.md#e19).

**Règles et dépendances :** [R01](regles-etats.md#r01), [R02](regles-etats.md#r02), [R03](regles-etats.md#r03), [R04](regles-etats.md#r04), [R34](regles-etats.md#r34), [R37](regles-etats.md#r37). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Entrer dans le bon espace sans dupliquer la personne ni conserver des droits retirés. Le fournisseur authentifie ; Drivy décide des droits métier.

### Rôles, autorisations et préconditions

Compte OIDC vérifié, client enregistré et appartenance valide ; école ACTIVE pour les mutations courantes ; école DRAFT accessible aux seules commandes de configuration F20 autorisées (R73). Une école archivée peut rester consultable en lecture selon les droits et la conservation, sans nouvelle réservation. Sans appartenance, seul le parcours d’invitation ou un message de contact est disponible. Pas d’inscription publique permettant de créer librement une école en production.

### Parcours nominal et conséquences

Connexion dans le navigateur système, retour validé, échange de code puis récupération des appartenances. Une seule école ouvre directement son espace ; plusieurs présentent un choix explicite. Le contexte conserve schoolId et accessEpoch. La déconnexion informe d’un éventuel brouillon, propose sa synchronisation si les droits sont encore valides, puis verrouille/purge la projection selon la politique locale. Elle invalide la session serveur et tente la révocation chez le fournisseur.

### Variantes, interruptions et cas limites

Annulation de la connexion : retour sans écran bloqué. Email non vérifié : parcours fournisseur, aucune invitation consommée. Fournisseur indisponible : pas de nouveau login ; un appareil natif peut lire sa projection dans la durée autorisée. Changement de compte : clé locale distincte et aucun aperçu du compte précédent. Retrait du dernier ADMIN refusé sous verrou.

### Données, validations et cycle de vie

Person, IdentityLink(issuer,subject), SchoolMembership, MembershipRole, grants, session, accessEpoch et lease native. Le nom public peut être modifié séparément du nom légal éventuellement nécessaire. Aucun mot de passe dans la base Drivy.

### Erreurs, événements et reprise

401 SESSION_REQUIRED, 403 MEMBERSHIP_REVOKED, 409 LAST_ADMIN, 503 IDENTITY_UNAVAILABLE. Un code OIDC invalide ne révèle pas de compte existant. Événements : MembershipChanged, SessionRevoked ; audit sans token.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T001](../05-realisation/tests-recette.md#t001) | Compte membre de A et B ; choisir A. | Les listes, URLs et cache n’exposent que A ; le passage à B remplace la projection. |
| [T002](../05-realisation/tests-recette.md#t002) | Un ADMIN retire un moniteur alors qu’un token est encore valide. | La commande suivante est refusée ; aucun événement métier ni écriture n’est créé. |
| [T003](../05-realisation/tests-recette.md#t003) | Deux administrateurs essaient simultanément de retirer l’autre. | Au moins un ADMIN actif subsiste ; la seconde transaction est refusée. |
| [T004](../05-realisation/tests-recette.md#t004) | Un compte avec cache se déconnecte puis un autre se connecte. | Aucun nom, document ou brouillon du premier n’est visible au second. |

<a id="f02"></a>
## F02 · Invitation et dossier élève

**Besoins :** B03 B05. **Parcours :** [J01](../02-experience/parcours.md#j01). **Écrans :** [E02](../02-experience/ecrans.md#e02), [E06](../02-experience/ecrans.md#e06), [E16](../02-experience/ecrans.md#e16).

**Règles et dépendances :** [R01](regles-etats.md#r01), [R03](regles-etats.md#r03), [R05](regles-etats.md#r05), [R11](regles-etats.md#r11), [R12](regles-etats.md#r12). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Créer une relation école-personne maîtrisée, avec un dossier minimal et sans double saisie inutile.

### Rôles, autorisations et préconditions

ADMIN ou moniteur habilité dans l’école. Email du destinataire connu ; le moniteur ne peut inviter qu’un élève. Les noms et coordonnées saisis avant acceptation doivent rester minimaux et la notice d’information être disponible.

### Parcours nominal et conséquences

L’émetteur renseigne adresse et rôle, confirme l’école et envoie. L’API crée une invitation et un envoi transactionnel. Le destinataire ouvre le lien, s’authentifie et voit clairement école, rôle et information sur les données. Il accepte ; l’appartenance et le dossier élève sont créés ou réutilisés dans la transaction. L’élève poursuit l’onboarding F21 et peut soumettre une TrainingRequest. L’ADMIN approuve cette demande ou crée explicitement la formation et affecte le moniteur dans F03 ; accepter l’invitation ou cocher un permis ne crée pas une formation validée. Un INSTRUCTOR seul peut émettre l’invitation mais attend cette affectation avant de lire le dossier ; l’acceptation informe aussi l’administration. Un indépendant cumulant ADMIN et INSTRUCTOR réalise les deux étapes.

### Variantes, interruptions et cas limites

Adresse déjà liée à cette école : retour vers le dossier existant pour personnel autorisé, pas de second profil. Invitation expirée : proposer une demande de renvoi sans dévoiler le contenu. Mauvaise adresse authentifiée : expliquer que l’invitation vise une autre adresse, sans la révéler intégralement. Un élève sans email utilisable est hors parcours pilote : l’école garde son processus actuel jusqu’à une procédure d’identité assistée validée.

### Données, validations et cycle de vie

Invitation, hash du jeton, expiresAt, email normalisé, roleSet autorisé, inviterMembershipId, acceptedByPersonId ; LearnerProfile créé sans formation implicite, profil administratif à confirmer et OnboardingProgress initialisé pour le rôle concerné. La recherche combine nom/prénom et filtre de formation ; les homonymes sont distingués par un renseignement autorisé, pas une date complète affichée partout.

### Erreurs, événements et reprise

409 ALREADY_MEMBER, 410 INVITATION_EXPIRED, 409 INVITATION_USED, 403 INVITATION_IDENTITY_MISMATCH. Les réponses publiques sont neutralisées contre l’énumération. InvitationAccepted et notification à l’émetteur après commit.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T005](../05-realisation/tests-recette.md#t005) | Une invitation valide vise le compte authentifié. | Une appartenance et un dossier sont créés, aucune formation fictive. |
| [T006](../05-realisation/tests-recette.md#t006) | Le même compte soumet deux fois la même opération. | Même résultat, un seul dossier et un seul effet métier. |
| [T007](../05-realisation/tests-recette.md#t007) | Une autre adresse vérifiée tente de consommer le lien. | Refus, invitation non consommée, aucune donnée privée retournée. |
| [T008](../05-realisation/tests-recette.md#t008) | Le personnel renvoie une invitation. | L’ancien lien ne fonctionne plus ; le nouveau garde les rôles autorisés. |

<a id="f03"></a>
## F03 · Formations, affectations et contrôle de permis

**Besoins :** B01 B03 B05. **Parcours :** [J01](../02-experience/parcours.md#j01), [J06](../02-experience/parcours.md#j06), [J09](../02-experience/parcours.md#j09). **Écrans :** [E07](../02-experience/ecrans.md#e07), [E20](../02-experience/ecrans.md#e20), [E13](../02-experience/ecrans.md#e13).

**Règles et dépendances :** [R02](regles-etats.md#r02), [R06](regles-etats.md#r06), [R07](regles-etats.md#r07), [R11](regles-etats.md#r11), [R35](regles-etats.md#r35), [R36](regles-etats.md#r36). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Séparer les parcours de permis et fournir une vérification humaine dont on connaît l’auteur, la pièce et la portée.

### Rôles, autorisations et préconditions

Dossier élève actif, offre scolaire activée avec référentiel validé, personnel autorisé. Le contrôle de permis exige le grant permit_review. Aucune valeur issue d’un ancien champ global ne devient automatiquement valable pour une autre catégorie.

### Parcours nominal et conséquences

Choisir le dossier, l’offre et le moniteur référent. Créer la formation ACTIVE, puis affecter les moniteurs nécessaires. L’élève ou l’équipe dépose la pièce ou le contrôleur atteste avoir vu l’original. Le contrôleur sélectionne catégorie, date de validité et décision. Un rejet comprend un motif compréhensible et un moyen de fournir une nouvelle pièce. L’écran élève affiche cette action au niveau de la formation concernée.

### Variantes, interruptions et cas limites

Même personne en B et A : séparation visible dans le dossier, la préparation, les documents et le bilan. Même catégorie après un cycle terminé : nouvelle formation, ancien historique conservé. Changement de moniteur : prévisualiser accès et leçons affectées. Formation PAUSED : aucune nouvelle réservation ; les leçons existantes doivent être traitées avant la pause. Vérification expirée : avertissement avant la leçon, pas effacement de l’historique ni certification automatique.

### Données, validations et cycle de vie

Training(id,learnerProfileId,offeringVersionId,status,startedOn,closedOn), InstructorAssignment, PermitCheck, DocumentRef. Statuts formation ACTIVE, PAUSED, COMPLETED, CANCELLED. L’issue de formation est déclarée par l’école ; une réussite à l’examen n’est pas déduite de compétences.

### Erreurs, événements et reprise

409 ACTIVE_TRAINING_EXISTS, 409 OFFERING_NOT_READY, 403 PERMIT_REVIEW_REQUIRED, 412 VERSION_CONFLICT, 409 FUTURE_LESSONS_EXIST. Événements : TrainingCreated, AssignmentChanged, PermitReviewed. Échec de dépôt laisse PENDING, pas APPROVED.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T009](../05-realisation/tests-recette.md#t009) | Un élève suit deux catégories activées. | Chaque leçon et observation conserve sa formation ; aucune progression croisée. |
| [T010](../05-realisation/tests-recette.md#t010) | Une pièce approuvée est remplacée. | Nouveau contrôle PENDING, ancien contrôle conservé en historique restreint. |
| [T011](../05-realisation/tests-recette.md#t011) | Une formation a encore des leçons futures. | La mise en pause exige un traitement explicite de ces leçons ; aucune suppression silencieuse. |
| [T012](../05-realisation/tests-recette.md#t012) | Un moniteur perd une formation. | Accès et synchronisation sont révoqués ; aucun bilan ancien ne devient modifiable par son token. |

<a id="f13"></a>
## F13 · Administration du périmètre scolaire

**Besoins :** B01 B04 B05. **Parcours :** [J01](../02-experience/parcours.md#j01), [J09](../02-experience/parcours.md#j09). **Écrans :** [E13](../02-experience/ecrans.md#e13), [E16](../02-experience/ecrans.md#e16), [E19](../02-experience/ecrans.md#e19).

**Règles et dépendances :** [R02](regles-etats.md#r02), [R04](regles-etats.md#r04), [R06](regles-etats.md#r06), [R35](regles-etats.md#r35), [R36](regles-etats.md#r36), [R38](regles-etats.md#r38). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Permettre au responsable de configurer un produit cohérent sans altérer les règles communes ni la lisibilité.

### Rôles, autorisations et préconditions

ADMIN actif et identité réauthentifiée pour les changements sensibles. Une école pilote est créée par onboarding contrôlé, pas par un formulaire SaaS de souscription non spécifié.

### Parcours nominal et conséquences

Renseigner nom, contacts professionnels, fuseau et logo ; sélectionner les offres réellement disponibles, confirmer référentiels et politique de pièces. Inviter l’équipe, attribuer rôles et grants, affecter des formations. Définir durée proposée et prix par offre avec validation explicite. Prévisualiser les effets des changements sur les nouveaux rendez-vous, sans réécrire les anciens.

### Variantes, interruptions et cas limites

Logo absent : nom de l’école dans un bloc typographique. Couleur scolaire non libre au pilote, pour préserver contrastes et statuts. Changement de fuseau après des réservations : analyser l’impact, maintenir les instants déjà fixés ; décision explicite avant application aux horaires récurrents. Catégorie désactivée : aucune nouvelle formation, historiques lisibles. Traductions manquantes : pilote FR ; aucune bascule vers une interface partiellement traduite promise comme complète.

### Données, validations et cycle de vie

SchoolSettingsVersion, OfferingVersion, CurriculumVersion, SchoolAsset et grants. Le logo suit un dépôt distinct des pièces élève : JPEG/PNG, au plus 2 Mio, analyse puis READY ; seul ADMIN change le pointeur scolaire avec If-Match. Un ancien logo reste affiché pendant le contrôle du nouveau et est retiré selon politique après remplacement. La configuration expose l’auteur et la date d’effet. Les secrets fournisseur et de base ne sont jamais administrables depuis l’interface métier.

### Erreurs, événements et reprise

409 LAST_ADMIN, 409 OFFERING_IN_USE, 422 INVALID_TIME_ZONE, 409 CONFIG_IMPACT_REVIEW_REQUIRED. L’école ne peut désactiver audit, contrôle des droits ou validation des pièces pour contourner une contrainte.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T049](../05-realisation/tests-recette.md#t049) | Le prix par défaut change après une réservation. | La réservation conserve son prix photographié ; les suivantes utilisent le nouveau. |
| [T050](../05-realisation/tests-recette.md#t050) | L’ADMIN active une catégorie sans contenu validé. | Activation refusée avec éléments manquants, pas fausse prise en charge. |
| [T051](../05-realisation/tests-recette.md#t051) | Le logo est absent ou rejeté. | L’interface reste lisible avec le nom, sans casser la navigation. |
| [T052](../05-realisation/tests-recette.md#t052) | Un rôle ou grant est modifié. | Réauthentification si nécessaire, audit et epoch actualisée. |

## Exigences communes et configuration d’école V2

RequirementRecord porte learnerId et requirementType dans une école ; RequirementTrainingLink relie l’exigence aux formations concernées après validation du profil. Le statut UNKNOWN ne signifie ni accompli ni non accompli. L’élève fournit une déclaration/preuve, le personnel habilité valide. Une exigence commune approuvée peut satisfaire deux formations sans doubler une inscription ou une campagne. Aucun partage d’une preuve avec une autre école n’est implicite.

F13 configure les modules, sites, salles et produits ; l’offre de permis historique Offering représente la possibilité d’ouvrir une formation et son référentiel. ServiceProductVersion représente une prestation vendue ; PackOfferVersion rassemble des droits. Ces concepts ne deviennent pas synonymes du fait qu’ils concernent tous une catégorie B.

Les nouveaux grants de [la matrice](roles-permissions.md) permettent de gérer les cours et présences sans habilitation globale aux traces. Avant suppression d’une appartenance, traiter inscriptions, captures en transfert, achats et obligations selon R29. La conservation des preuves d’un cours n’est pas déduite de celle d’un bilan ou d’un paiement.


## Intégration V3 : accueillir sans dupliquer

[F20/F21](onboarding.md) complètent F01/F02/F03/F13, sans second système d’identité. L’adresse de connexion appartient au fournisseur ; le contact scolaire et le profil administratif ont leur propre finalité. Les déclarations de permis attendent validation F03. Une photo de profil réutilise le pipeline F09, purpose PROFILE_PHOTO, et ne devient jamais une preuve de permis.

Le wizard école publie la configuration par les services F13/F17/F18 ; le wizard élève écrit un profil versionné et des demandes contrôlées. Un moniteur invité ne reçoit pas les questions de propriétaire de l’école. L’ADMIN d’un indépendant peut cumuler les deux parcours sans saisir deux fois les données déjà pertinentes.

La liste web détaillée, l’archivage et la restauration sont définis dans [F22](gestion-web-archivage.md), les agrégats d’activité dans [F23](statistiques.md). L’accès à ces écrans n’accorde aucun droit supplémentaire aux données pédagogiques.


<a id="vérification-de-permis-cohérence-du-contrat-v35"></a>
## Décisions du contrôle de permis
[R07](regles-etats.md#r07) demeure la règle : une approbation doit être fondée sur une pièce effectivement examinée et accessible dans le scope, ou sur un contrôle physique explicitement attesté. Un UUID de document ne vaut pas examen humain. PermitCommand refuse APPROVED sans preuve et REJECTED sans motif non blanc ; le serveur renseigne le contrôleur habilité et la date. L’envoi d’un document n’approuve jamais le permis. La validité réglementaire n’est pas calculée avec une durée universelle inventée.

F01 inclut désormais l’accès global « Supprimer mon compte Drivy », même sans école active, via [R103/R104](compte-suppression-globale.md). Il ne s’agit ni de l’archive F22 ni d’une action ADMIN sur autrui.

## Accomplissement fondé sur des preuves versionnées

Pour F03, [R110](regles-etats.md#r110) précise la validation déjà prévue : une source interne est un cycle d’inscription exact, une source externe un document vérifié. AP122 matérialise ce cycle ; le serveur fige les versions effectivement contrôlées dans `RequirementDecisionBasis`. Une exemption doit correspondre au profil approuvé et à un motif, avec justificatifs selon le cas. Le téléchargement d’une pièce n’est pas une preuve de validité administrative.

Le dossier élève affiche « À vérifier de nouveau » lorsqu’une preuve ayant fondé l’accomplissement est corrigée ou invalidée. La dernière décision reste auditable sans être affichée comme valable aujourd’hui. L’élève ne devient pas automatiquement destinataire d’une campagne « Vous devez suivre ce cours ». Les engagements existants restent visibles avec un suivi personnel habilité ; les nouveaux actes dépendant d’un préalable valide utilisent l’état recontrôlé. Toute ouverture d’une autre école conserve ses propres preuves et permissions.
