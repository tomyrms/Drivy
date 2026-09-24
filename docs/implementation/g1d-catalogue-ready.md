# G1D2 — catalogue approuvé, équipe et formation affectée

Préparation du 24 septembre 2026, après le gel API G1D1. Ce document ne crée ni migration 005 ni API supplémentaire. Il précise le sous-ensemble du [READY formation](g1d-formation-ready.md) à réaliser ensuite ; [G1D1](g1d-profils.md) fournit déjà politique de champs, profil et accueil minimal.

Références : [F03/F13](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/identites-formations.md#f03), [permissions](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/roles-permissions.md), [R02/R06/R07/R11/R12/R35/R36](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/regles-etats.md), [OpenAPI 3.11](../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml), [modèle](../../Drivy_Conception_v3_17_2026-09-20/04-technique/modele-donnees.md), [ordre transactionnel](../../Drivy_Conception_v3_17_2026-09-20/04-technique/transactions-v2.md#autorisation-et-commit), [définition READY](../../Drivy_Conception_v3_17_2026-09-20/05-realisation/roadmap-backlog.md#definition-ready).

## Les six critères READY

1. **Action utilisateur.** ADMIN saisit et approuve une procédure de catégorie et un référentiel, confirme une offre avec sa durée et son prix, puis crée la formation d'un élève. Il affecte ensuite explicitement un INSTRUCTOR actif de l'école. S'il enseigne lui-même, il ajoute d'abord INSTRUCTOR à sa propre appartenance par une modification de rôles réauthentifiée ; aucun cumul n'est déduit de « indépendant ».
2. **Source de vérité.** Versions immuables de procédure, référentiel et offre ; la formation conserve son offeringId exact. Une seule formation ACTIVE/PAUSED par école, élève et offeringKey, même après nouvelle version de l'offre. Les dates d'affectation et rôles actuels donnent les droits ; ni l'auteur d'une invitation ni celui d'une formation ne reçoit automatiquement une affectation.
3. **Échec et concurrence.** Commandes durables et audit atomique ; reprise AP72 avec même intention. AP08 compare Member.version et protège le dernier ADMIN. AP19/AP21/AP23/AP27/AP95 créent de nouveaux objets sans If-Match canonique ; sérialisation serveur, unicité et contrôle des références restent requis. AP23 et AP27 sont deux commits distincts : échec d'affectation laisse « formation créée, moniteur à affecter », sans annuler ni refaire la création.
4. **Persistance minimale.** Ajouter curriculum_version, competency_definition et school_policy_version ; compléter offering_version et instructor_assignment existantes. Réutiliser membership, training, operation, audit_event et school_settings_version. Conserver les références historiques inactives sans fabriquer d'approbations ni de contenus pour satisfaire une FK.
5. **Contrat et UI.** Parcours ADMIN « Référentiel → Procédure → Offre → Formation → Affectation » avec états vides, prix/durée explicites, revue et approbation décochée. AP07 alimente le sélecteur administratif de moniteurs ; il reste interdit aux élèves/moniteurs ordinaires. Offrir la reprise d'une demande incertaine avant une nouvelle commande. Afficher contrôle de permis restant à faire, sans déclarer une autorisation de conduire.
6. **Preuve attendue.** PostgreSQL16.14 et17.11, propriétaire de migration non privilégié, RLS forcée, contrats canoniques et recette navigateur/natif avec données synthétiques déclarées. Vérifier versions d'offres, références non approuvées, double création, séparation AP23/AP27, affectation/role perdus pendant attente, dernier ADMIN concurrent, réauthentification véritable, AP72/replay et rollback provoqué. T003/T009/T012/T049/T050/T052 sont les scénarios de référence ; leurs étapes encore dépendantes de leçons/bilans ne seront pas déclarées réussies par ces seuls tests.

## Routes et préconditions HTTP exactes

Tous les chemins sont relatifs à `/v1/schools/{schoolId}`. Toutes les commandes exigent `operationId` UUID et `Idempotency-Key` identique. En session cookie, Origin et CSRF sont vérifiés au BFF. Une réponse contient `data`, `requestId`, `serverTime`. Les pages ont `items` et `nextCursor` nullable ; seules options canoniques de ces listes : `limit` 1–100 (défaut50) et `cursor`. Aucun filtre `categoryCode`, `status` ou `enabled` n'est ajouté implicitement.

| AP | Méthode et chemin | Commande → réponse | Succès | If-Match |
|---|---|---|---|---|
| 07 | GET `/members` | sans corps → MemberPage | 200 | Non |
| 08 | PATCH `/members/{membershipId}` | UpdateMemberCommand → Member | 200 | Member.version |
| 18 | GET `/offerings` | sans corps → OfferingPage | 200 | Non |
| 19 | POST `/offerings` | OfferingCommand → Offering | 201 | Non |
| 20 | GET `/curricula` | sans corps → CurriculumPage | 200 | Non |
| 21 | POST `/curricula` | CurriculumCommand → Curriculum | 201 | Non |
| 94 | GET `/policy-versions` | sans corps → SchoolPolicyPage | 200 | Non |
| 95 | POST `/policy-versions` | SchoolPolicyCommand → SchoolPolicy | 201 | Non |
| 23 | POST `/trainings` | CreateTrainingCommand → Training | 201 | Non |
| 26 | GET `/trainings/{trainingId}/assignments` | sans corps → AssignmentPage | 200 | Non |
| 27 | POST `/trainings/{trainingId}/assignments` | AssignCommand → Assignment | 201 | Non |

Le canon autorise aussi 202 pour les écritures ; cela n'impose pas un job pour ces transactions courtes et ne vaut pas succès métier. Préserver les lectures AP22/AP24 existantes. AP28 (fin d'affectation), AP09 (révocation d'appartenance), AP25 (état de formation), AP29/30 (permis) et AP178–181 (demandes élève) restent distincts ; aucun champ caché de ces commandes n'est intégré à AP08/AP23/AP27.

## DTO exacts à raccorder

Dans les descriptions suivantes, tous les champs sont requis sauf `?` ; `null` n'est admis que s'il est indiqué. Tous les objets canoniques refusent les propriétés inconnues.

**Membres.** UpdateMemberCommand contient `{operationId, roles, grants, reason}` : roles = tableau non vide et unique de ADMIN/INSTRUCTOR/LEARNER ; grants = tableau unique, éventuellement vide ; reason = texte non vide. Ce n'est pas un PATCH partiel de rôles. Member contient `{id, schoolId, version, personId, displayName, status, roles, grants, accessEpoch}` ; status ACTIVE/REVOKED. `status` n'est pas modifiable via AP08.

Les grants autorisés sont exactement `permit_review`, `cash_record`, `CONFIGURE_CATALOG`, `SELL_SERVICES`, `MANAGE_COURSES`, `TAKE_ATTENDANCE`, `VALIDATE_REQUIREMENT`, `REVIEW_REGULATORY_PROFILE`, `MANAGE_LEARNER_ARCHIVES`, `VIEW_SCHOOL_METRICS`, `VIEW_FINANCIAL_METRICS`, `EXPORT_MANAGEMENT`. Les attribuer ne livre pas les fonctions correspondantes ; aucun grant ne donne une affectation pédagogique globale.

**Référentiel.** CurriculumCommand contient `{operationId, categoryCode, approved, approvalReason, competencies}`. `competencies` a au moins un élément `{key,label,description,sortOrder}` ; sortOrder entier ≥0. Curriculum contient `{id,schoolId,version,categoryCode,revision,approved,competencies}` ; chaque compétence devient `{id,schoolId,version,curriculumVersionId,key,label,description,sortOrder}`. Le canon ne fournit ni route de modification d'une version ni commande séparée d'approbation : modifier ou approuver un brouillon crée une nouvelle version par AP21.

`revision` numérote le référentiel de catégorie ; `version` est la version de l'objet immuable (initialement1). Identifiant de compétence propre à une version ; une même key ou un même libellé ne transfère pas silencieusement une progression vers un autre référentiel. Auteur, date et motif d'approbation sont conservés côté serveur, bien qu'ils ne figurent pas tous dans Curriculum.

**Politique de catégorie.** SchoolPolicyCommand contient `{operationId,categoryCode,procedureText,cancellationPolicyText,sourceUrls,approved,approvalReason}`. procedureText et cancellationPolicyText : 1–4000 caractères ; approvalReason : 1–1000 ; sourceUrls : tableau d'URI, éventuellement vide selon le schéma. SchoolPolicy contient `{id,schoolId,version,categoryCode,procedureText,cancellationPolicyText,sourceUrls,approved,approvedAt}` ; approvedAt date-heure serveur ou null. Aucun téléchargement des URL n'est nécessaire pour enregistrer la décision ; des liens sont rendus uniquement avec un protocole web admis, sans exécuter une URI fournie par un utilisateur.

Cette politique est une procédure déclarée/approuvée par l'école, pas la notice de données G1B, la politique de champs G1D1 ni un RegulatoryProfileVersion de cours. Une chaîne `sourceUrls` ne vaut pas vérification de sa validité juridique.

**Offre.** OfferingCommand contient `{operationId,offeringKey,categoryCode,curriculumVersionId,enabled,defaultDurationMinutes,defaultPriceCents,policyVersionId}`. offeringKey : 1–80 caractères ; durée : entier1–480 ; prix : entier0–9007199254740991 centimes CHF, sans arrondi via flottant. Offering contient les mêmes champs sans operationId, avec `{id,schoolId,version}`. Les deux UUID référencent respectivement CurriculumVersion et SchoolPolicyVersion de la même école/catégorie. Les valeurs null ne sont pas permises dans cette projection, même pour une offre désactivée.

Le prix0 est un choix explicite possible, jamais une valeur de formulaire inventée. La durée/prix proposés de l'offre ne créent ni ServiceProductVersion, ni conditions commerciales acceptées, ni droit de pack.

**Formation.** CreateTrainingCommand contient `{operationId,learnerId,offeringId,startedOn?}` ; startedOn est une date civile ou null. Training conserve la projection déjà livrée : `{id,schoolId,version,learnerId,offeringId,categoryCode,status,startedOn,closedOn}` ; statut ACTIVE/PAUSED/COMPLETED/CANCELLED, dates civiles nullables. Création explicite ACTIVE avec closedOn null ; ne pas convertir une date civile en instant UTC ni inventer une date de début si le client la laisse absente.

**Affectation.** AssignCommand contient `{operationId,instructorMembershipId,validFrom,validUntil?}` ; validFrom date-heure, validUntil date-heure ou null. Assignment contient `{id,schoolId,version,trainingId,instructorMembershipId,validFrom,validUntil}`. Intervalle `[validFrom,validUntil)` non vide, sans fin si null. trainingId est dans la route, pas le corps ; AP23 n'accepte aucun instructorMembershipId.

AP26 n'expose pas de nom du moniteur. L'ADMIN peut joindre les Member qu'il est autorisé à lire ; ne pas ouvrir AP07 à un élève pour remplir ce libellé. Un futur contact élève exige une projection autorisée appropriée, distincte d'un annuaire administratif.

## Persistance et transitions justifiées

| Élément | Ajout minimal et invariant |
|---|---|
| curriculum_version | UUID, school/category, revision unique par école/catégorie, approved, auteur/date/motif, created_at. Version immuable et RLS. |
| competency_definition | UUID, school/curriculum, key unique dans cette version, label/description/sortOrder, version1 ; FK composite. |
| school_policy_version | UUID, school/category, version séquentielle proposée par catégorie, textes/sources, auteur/date/motif d'approbation et created_at ; immuable. |
| offering_version existante | Ajouter curriculum_version_id, policy_version_id, durée/prix et created_at. Même offeringKey conserve sa chaîne de versions ; références complètes avant projection AP18/activation. Prix stocké en bigint compatible entier JSON sûr. |
| training existante | Réutiliser FK school/learner/offeringKey et index unique partiel ACTIVE/PAUSED ; aucun second agrégat Training. Insérer sous droits courants, sans permis APPROVED ni affectation implicite. |
| instructor_assignment existante | Ajouter version et created_at ; contraintes de scope, rôle actuel, intervalle et doublon/chevauchement pour même membre/formation. Plusieurs moniteurs distincts restent possibles. |
| membership existante | Réutiliser rôles/grants/version/access_epoch ; AP08 est audité avec motif. Si LEARNER est ajouté, préparer le dossier minimal manquant par service commun, sans noms déduits, formation ou consentement. |
| operation/audit/settings | Ajouter les types d'effet et leurs règles RLS ; révision de configuration pour publication de catalogue, aucune réponse avant commit. |

La migration ne peut pas rendre les anciennes références de fixtures conformes en générant une procédure « approuvée ». Garder leurs nouvelles colonnes null et enabled=false comme état interne historique, exclu de la projection Offering canonique ; leurs formations historiques restent lisibles par AP22/AP24. Les recettes créent elles-mêmes des versions synthétiques complètes par le parcours de commande. Aucune formation de fixture n'est ajoutée en production.

Le serveur refuse enabled=true si référentiel/politique absents, non approuvés ou incohérents. Une version disabled avec références complètes peut être préparée sans rendre le parcours actif. Les versions référencées par une formation restent immuables. L'application ne transforme jamais approved=false en true depuis la sélection d'une offre ou la création d'une formation.

## Droits, locks et reprise

AP07/AP08 : ADMIN actif seulement. AP19/AP21/AP95 relèvent ici de l'administration F13 ; le grant CONFIGURE_CATALOG décrit dans la matrice V2 les produits/packs et ne doit pas être étendu tacitement à l'approbation de procédures ou de référentiels de conduite. Les périmètres de lecture des listes AP18/AP20/AP94 pour les non-ADMIN doivent être fixés explicitement avant code : proposition bornée ci-dessous.

AP23 : ADMIN, ou INSTRUCTOR déjà autorisé sur ce dossier par une affectation actuelle ; LEARNER interdit. L'invitation seule ne suffit pas. Le cas INSTRUCTOR crée une nouvelle formation sans lui donner sa lecture pédagogique : la réponse de création ne doit pas devenir une auto-affectation. Le parcours initial ADMIN peut être livré d'abord, mais ne sera pas présenté comme la totalité de cette permission canonique.

AP27 : ADMIN ; cible INSTRUCTOR active de même école et Person active. Pas d'affectation d'un ADMIN seul ni d'acceptation d'un identifiant d'une autre école. L'epoch des appartenances dont la portée change doit être incrémentée dans la transaction, même si le rôle ne change pas. AP08 incrémente version et accessEpoch et ne modifie jamais Person ou une appartenance d'une autre école.

Résoudre provisoirement les Person concernées (acteur, élève et moniteur suivant la commande), les verrouiller par UUID, puis école, appartenances par UUID avec leur mode final, puis ressources. Pour AP08 sur soi, prendre dès le départ le verrou d'écriture de la ligne cible au lieu de promouvoir FOR SHARE après un autre verrou. Relire tous les liens/droits après attente ; tous les futurs retraits d'affectation reprennent cette coordination scolaire. Aucun appel OIDC ou SMTP sous verrou.

Types AP72 proposés, à figer avec les clients avant implementation : `UPDATE_MEMBER → Member`, `CREATE_CURRICULUM_VERSION → Curriculum`, `CREATE_SCHOOL_POLICY → SchoolPolicy`, `CREATE_OFFERING_VERSION → Offering`, `CREATE_TRAINING → Training`, `CREATE_ASSIGNMENT → Assignment`. resourceId est l'UUID de l'objet créé/modifié ; resourceVersion sa version réelle. Le client garde séparément schoolId, learnerId/trainingId de route, version cible AP08 et contexte d'accès. Une lecture de preuve ne restitue aucun payload protégé ; refus ultérieur de droits ne démontre pas qu'une ancienne opération n'avait pas commité.

## Décisions à fixer avant le code, sans interrompre la préparation

1. **Réauthentification prouvée AP08.** Le canon impose un contrôle pour les modifications sensibles mais ne fixe pas de fenêtre numérique. `Identity` actuel conserve issuer/subject/email, pas auth_time vérifié. Proposition d'implémentation : AP08 exige un auth_time fournisseur récent avec fenêtre configurée et bornée ; le client lance le vrai flux système/BFF avec max_age adapté et revient au même compte. Absence/ancienneté → REAUTH_REQUIRED, sans utiliser iat ou un refresh comme preuve. Il reste à fixer la durée et qualifier la claim Keycloak pour les deux clients ; ce n'est pas un simple bouton de confirmation.
2. **Version applicable d'offre.** AP19 n'a ni expectedVersion, ni effectiveFrom, ni route de désactivation en place. Proposition : chaque création ajoute la prochaine version sous verrou scolaire ; seule la dernière version de chaque offeringKey décide des nouvelles formations. Une dernière version disabled ferme les nouveaux actes même si une ancienne était enabled. AP23 refuse une ancienne version devenue non applicable et demande relecture ; les anciennes formations gardent leur référence. Une offeringKey ne change pas silencieusement de catégorie. Ce choix doit figurer dans le contrat d'implémentation, sans ajouter un If-Match absent du canon.
3. **Lecture du catalogue.** Proposition : ADMIN voit toutes versions complètes, y compris non approuvées ; membres ordinaires voient les offres applicables activées et leurs contenus approuvés, plus les versions référencées par leurs formations autorisées. Aucun brouillon d'une autre école. Cette précision manque aux descriptions génériques AP18/AP20/AP94 et mérite des tests distincts ; ne pas la faire passer pour une règle littérale déjà écrite.
4. **Retrait d'un rôle avec relations existantes.** AP08 ne révoque pas une appartenance et ne remplace pas AP28. Avant retrait INSTRUCTOR, traiter les affectations/engagements ; avant retrait LEARNER, traiter le parcours élève. Proposition pour la tranche sans outil de fin d'affectation : refus métier explicite si une relation active/future exige revue, aucun effacement/fin automatique. Le dernier ADMIN reste toujours protégé. Pour rendre ces retraits utilisables, AP28 sera une dépendance supplémentaire à planifier, pas une mutation cachée.
5. **Bornes de contenu.** OpenAPI laisse categoryCode, certains champs de compétence et certains tableaux sans maximum. Définir des limites techniques documentées (taille totale, nombre de compétences/sources, chaînes non blanches et unicité des keys), sans présenter ces limites comme réglementation. Les champs et motifs de publication doivent rester réellement révisables par ADMIN ; aucune liste de catégories, durée, prix ou compétence issue de l'ancien projet n'est adoptée automatiquement.

Le contenu réel — catégories effectivement proposées, curriculum, procédure, annulation, prix et durée — reste à saisir et approuver par l'école. Cela ne bloque pas la construction des formulaires ni les tests synthétiques. Ces approbations ne certifient pas une réglementation cantonale ni un profil de cours collectif ; les qualifications correspondantes restent distinctes.

## Recettes minimales de sortie

- Migration sous propriétaire sans SUPERUSER/BYPASSRLS/CREATEROLE ; anciennes fixtures restent désactivées/non approuvées, aucune FK orpheline, toutes nouvelles tables sous FORCE RLS.
- Référentiel/politique brouillons puis version approuvée explicite : auteur/date/motif réels, corps vide/doublons/URL dangereuse refusés selon bornes documentées ; aucun fetch externe implicite.
- Offre étrangère, références de catégories différentes, référence non approuvée ou ancienne offre désactivée refusées. Deux versions concurrentes restent deux objets cohérents ; aucune formation existante ne change de prix/référentiel par cette écriture.
- Double AP23 même clé : un effet ; deux clés simultanées même offeringKey : une seule ACTIVE/PAUSED ; nouvelle version de l'offre ne contourne pas l'unicité. Plusieurs catégories restent possibles. Erreur d'audit annule aussi création/preuve.
- AP23 réussi puis AP27 refusé : formation conservée, zéro affectation ; relance AP27 ne recrée pas la formation. Moniteur d'autre école, REVOKED, sans rôle ou Person inactive refusé ; doublon/intervalle incohérent refusés sans artefacts.
- AP08 exige vraie réauthentification et bonne version ; deux retraits réciproques ne retirent pas le dernier ADMIN. Changement de rôle/grant et epoch atomiques, droits réduits immédiatement malgré un token OIDC encore valable. Rôle retiré pendant attente AP27/AP23 correctement sérialisé.
- RLS et lecture par clients : pas d'annuaire AP07 aux non-ADMIN ; aucune lecture pédagogique par ADMIN seul ; preuve AP72 limitée à son auteur/contexte/portée, reprise conservant l'intention après perte de réponse ou changement d'accès.
- Recette web et native complète avec compte synthétique : saisir/approuver contenu, activer offre, choisir élève/moniteur, créer puis affecter ; noms, contrôle à faire et erreurs compréhensibles. Aucune promesse de leçon réservable sans produits commerciaux/disponibilités/conditions G2.

## Preuve de parité préalable exécutée

Le 24 septembre 2026, le gel API G1D1 a été exécuté sans modification sur PostgreSQL **16.14**, conteneur local existant `drivy-refonte-pg16-check`, port55433. Seules bases présentes : postgres et drivy_test ; aucune connexion applicative active avant recette. La base drivy_test, exclusivement réservée aux tests, a été remise à zéro par la suite G1B puis migrée sous propriétaire non privilégié : **23/23 G1B PASS**. La suite entière a ensuite donné **113/113 PASS**, en25,28s. Le cluster n'a pas été recréé et aucun service distant n'a été touché.

La même révision avait déjà obtenu113/113 sur PostgreSQL17.11, ainsi que typecheck/build. Cette preuve porte sur G1D1 ; elle ne qualifie pas les routes catalogue et formation décrites ici, encore à implémenter.
