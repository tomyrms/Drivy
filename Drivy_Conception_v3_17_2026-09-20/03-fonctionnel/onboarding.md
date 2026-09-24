# Accueil progressif : école, moniteur et élève

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; choix détaillés proposés, à valider. [Index](../README.md).

## Intention et périmètre

L’onboarding met une personne en mesure d’accomplir sa première tâche. Ce n’est ni un tutoriel obligatoire de toutes les fonctions, ni un formulaire qui recueille par défaut toutes les données possibles. Il comprend trois parcours partageant les mêmes données entre app et web : configurer l’école, accueillir un membre du personnel et accueillir un élève dans une école.

**Exigence du porteur :** prévoir l’accueil, l’identité et les coordonnées utiles, une photo facultative et la configuration des permis/services. **Proposition :** collecte progressive, champs justifiés et blocages limités à l’action qui nécessite l’information. Le minimum ne signifie pas renoncer aux pièces utiles ; il signifie les demander au bon moment.

Les règles canoniques sont [R73–R81](regles-etats.md#r73), [R97–R100](regles-etats.md#r97). F01/F02 conservent l’identité et l’invitation ; F13 les paramètres ; F03 la validation de formation. F20/F21 les orchestrent sans dupliquer leurs règles.

<a id="f20"></a>
## F20 · Mettre une école en service

**Besoins :** B12 B14 B05. **Parcours :** J19, J28. **Écrans :** E38, E39, E48 ; E13/E29 pour compléter après activation. **Données :** SchoolSetup, School.configurationVersion, OfferingVersion, ProfileFieldPolicyVersion. **Tests :** T163–T174.

### Autorisation et préconditions

Au pilote, un opérateur provisionne une école DRAFT et une invitation d’administrateur par le processus contrôlé F01/F13. La configuration dans Drivy est ensuite autonome. Aucun visiteur ne crée une école ACTIVE ou ne se donne ADMIN en choisissant « Je suis moniteur ». L’activation self-service publique et la facturation SaaS restent distinctes et différées.

L’administrateur authentifié peut reprendre le brouillon dans l’app ou sur le web. Un moniteur invité rejoint l’école existante : il ne refait pas sa configuration et ne crée pas un doublon.

### Étapes de configuration

| Étape | Informations et choix | Obligatoire pour quoi ? | Résultat |
|---|---|---|---|
| 1. Votre école | Nom, contact professionnel, pays/canton pertinent, langue d’interface disponible, fuseau proposé Europe/Zurich à confirmer ; logo facultatif. | Identité et contact avant activation. | Contexte scolaire explicite ; aucune géolocalisation demandée. |
| 2. Votre organisation | Indépendant ou équipe comme aide de configuration ; sites, lieu de rendez-vous habituel, disponibilités initiales ; équipe à inviter maintenant ou plus tard. | Un responsable actif ; ressources réelles avant leurs réservations. | Preset modifiable, pas un rôle de sécurité automatique. |
| 3. Vos formations | Catégories réellement proposées, manuel/automatique lorsque pertinent, référentiel pédagogique et politique de vérification. | Au moins une offre prête pour le parcours activé. | Offre scolaire, pas attestation d’autorisation professionnelle. |
| 4. Vos prestations | Durées et prix confirmés, règlement à la leçon, packs optionnels, frais identifiés ; sites si tarifs différents. | Prix/durée connus avant publication de la prestation ; pas de zéro implicite. | Versions commerciales explicites, réutilisées par F17. |
| 5. Vos cours collectifs | Activer ou ignorer ; modèles, salles, capacité, formateurs, profils approuvés. | Seulement avant publication d’une série. | Un cours non prêt n’empêche pas le parcours individuel. |
| 6. Votre cadre de données | Informations nécessaires par action, notices, accès, conservation, module GPS proposé sans imposer la capture ; contact pour les demandes. | Politiques nécessaires au module avant données réelles. | Politique versionnée et refus GPS protégé. |
| 7. Vérifier et démarrer | Récapitulatif, éléments bloquants et facultatifs, aperçu élève, confirmation de l’administrateur. | Contrôles serveur d’activation. | School ACTIVE et versions de configuration, sans cours publié ni inscription automatique. |

Ces étapes peuvent regrouper plusieurs petits écrans ; le nombre s’adapte aux modules choisis. Un indépendant n’a pas de pages obligatoires sur plusieurs sites ou une grande équipe. Une école sans packs peut sauter toute la composition de forfaits.

### Readiness par capacité

`SchoolReadiness.activationReady` évalue les prérequis de configuration (responsable et contact, notice et politique de données validées) sans exiger que l’école soit déjà ACTIVE ; `activationBlockers` explique les manques. C’est la précondition de DRAFT→ACTIVE. `CAN_USE_WORKSPACE` exige ensuite école ACTIVE et ces prérequis. Le responsable peut lire et corriger la configuration DRAFT sans avoir encore ce droit d’usage courant. `CAN_PLAN_LESSON` ajoute une offre/durée/prix/référentiel cohérents et une affectation. `CAN_CAPTURE` ajoute les conditions GPS et un appareil qualifié ; il reste faux lorsque le module est désactivé. `CAN_PUBLISH_COURSE` ajoute série, profil, formateur, salle et règles de capacité. Aucune coche d’interface ne remplace ces contrôles.

La validation de configuration retourne des éléments `{code, fieldPath, severity, capability, message}`. Les avertissements facultatifs ne bloquent pas. Les erreurs sont rapprochées des champs, avec navigation vers l’étape concernée. Les politiques juridiques non qualifiées ne sont pas approuvées par une simple valeur par défaut générée par Drivy.

### Sauvegarde, activation et variantes

Le brouillon est sauvegardé au serveur avec version ; état visible « Enregistré » seulement après accusé. Revenir le lendemain ou changer d’appareil reprend cette version. Hors réseau, le web conserve au plus la saisie en mémoire de l’onglet et l’indique ; fermer l’onglet peut la perdre. L’app peut stocker un brouillon local chiffré sous les règles F12, sans l’annoncer disponible ailleurs.

L’activation est une transaction : relecture des droits, du brouillon et des références, publication des seules versions validées, changement de statut, audit. Un renvoi ne duplique pas les offres. Deux administrateurs qui modifient le même brouillon obtiennent un conflit de version, pas une fusion de tarifs implicite.

Après activation, les modifications passent par F13/F17 et leurs dates d’effet ; l’assistant reste consultable comme checklist mais n’écrase pas l’école en relançant l’activation. Désactiver une catégorie ou un module conserve les achats, formations et engagements existants selon leurs règles. Changer la politique de champs ne redemande pas des données facultatives à tous les élèves.

### Erreurs et événements

`SETUP_ACCESS_REQUIRED`, `SCHOOL_ALREADY_ACTIVE`, `SETUP_INCOMPLETE`, `POLICY_REVIEW_REQUIRED`, `VERSION_CONFLICT`, `MODULE_NOT_READY`. Événements : SchoolSetupSaved, SchoolActivated, SchoolSettingsVersionPublished. Les journaux portent identifiants et champs modifiés, pas les coordonnées intégrales.

<a id="f21"></a>
## F21 · Accueillir un élève ou un moniteur

**Besoins :** B03 B05 B14. **Parcours :** J20, J21, J22, J27, J28. **Écrans :** E40–E43, E47, E02/E16/E44. **Données :** OnboardingProgress (kind STUDENT ou STAFF), LearnerAdministrativeProfile (DTO AdministrativeProfile), TrainingRequest, RecordingChoice. **Tests :** T175–T191.

### Élève : entrée et rattachement

Le lien d’invitation ouvre une page accessible ; l’app installée peut recevoir le même parcours. Sans app, le navigateur permet de le terminer et d’utiliser les fonctions personnelles web. Authentification et identité visée sont vérifiées selon F02. Le nom de l’école et les informations sur la relation sont visibles avant acceptation.

Acceptation crée ou retrouve la relation scolaire ; elle ne signifie ni achat, ni inscription à un cours, ni autorisation GPS. Le profil et les documents préparés par l’école sont présentés pour correction selon les droits, pas présentés comme déjà confirmés par l’élève.

### Étapes élève

| Étape | Présentation et action | Effet réel |
|---|---|---|
| 1. Rejoindre l’école | École, contact, compte utilisé, notice et confirmation de rattachement. | Une relation scolaire ; le refus quitte sans consommation du lien. |
| 2. Vous connaître | Prénom/nom, nom d’affichage si utile, contact vérifié déjà connu ; champs supplémentaires justifiés et repérables. | Profil administratif de **cette** école, distinct de l’identité de connexion. |
| 3. Votre parcours | Permis souhaité parmi les offres, besoins déclarés, documents déjà disponibles et cours suivis ailleurs. | Demande de formation et déclarations à examiner, pas habilitation automatique. |
| 4. Comprendre Drivy | Revoir les leçons, agenda, offres non réservées ; explication du GPS avec « Décider plus tard », « Je refuse » et choix éclairé. | RecordingChoice distinct de la relation et des notifications ; aucun point collecté. |
| 5. Votre prochaine action | Contact du moniteur, premier rendez-vous s’il existe, documents utiles à compléter et offres de cours. | Checklist contextualisée ; aucun rendez-vous ou achat inventé pour remplir l’écran. |

La photo se propose dans le profil, sans étape bloquante. « Plus tard » n’affiche pas un profil en échec. L’élève peut consulter son agenda même si l’adresse n’est pas nécessaire à ce stade. L’accès à l’aide, aux annulations existantes et à ses droits sur les données n’est pas conditionné à la complétude administrative.

### Catalogue des champs et finalités proposées

| Champ | Niveau recommandé | Quand le demander | Validation et accès |
|---|---|---|---|
| Prénom / nom | Base de la relation | Entrée dans l’école ; valeurs préremplies à confirmer. | Unicode accepté, pas de rejet d’accents/traits d’union ; 150 caractères par champ. Cas d’état civil particulier traité sans faux nom imposé. |
| Nom d’affichage | Facultatif | Profil | Ne remplace pas le nom administratif sur une preuve. |
| Email de connexion | Vérifié par le fournisseur | Connexion/invitation | Pas éditable comme simple champ de contact ; changement via parcours vérifié F01. |
| Email / téléphone de contact | Email connu réutilisé ; téléphone conditionnel | Coordination justifiée par l’école | Format international pour téléphone ; école ne déclare pas le numéro vérifié sans procédure. |
| Date de naissance | Conditionnelle | Avant une action nécessitant âge/admissibilité ou pièce officielle | Date civile, pas d’heure ni de fuseau ; pas dans le futur ; contrôle de catégorie séparé. Ne pas imposer arbitrairement 18 ans pour créer un compte. |
| Adresse postale | Conditionnelle | Finalité administrative explicitée et configurée | Pays + champs postaux ; ne remplace pas un rendez-vous et ne devient pas un point GPS partagé. |
| Photo de profil | Toujours facultative | Après l’accueil ou depuis le profil | JPEG/PNG ≤ 2 Mio après conversion éventuelle, pipeline F09, EXIF retirés ; visible seulement aux personnes autorisées de l’école. |
| Permis souhaités | Déclaration | Orientation du parcours | Offres actives de l’école ; décision de formation par personnel autorisé. |
| Pièce du permis / validité | Selon la formation | Avant la leçon qui l’exige | F03/F09, vérification humaine ; un upload ne vaut pas approbation. |
| Cours déjà suivis | Déclaration facultative puis preuve utile | Éviter de proposer inutilement une formation | UNKNOWN sans déclaration, EVIDENCE_PENDING après dépôt non encore vérifié (RequirementRecord). |
| Préférence de notification | Facultative | Après explication d’une utilité concrète | Refuser les push ne bloque ni agenda ni place de cours. |
| Choix GPS | Facultatif, refus possible | Information initiale puis contrôle lors de la séance | UNKNOWN n’est jamais ALLOWED ; pas de permission de localisation sur le téléphone élève si le moniteur enregistre. |

Le catalogue ne prévoit pas AVS, santé, religion, nationalité obligatoire, document d’identité complet ni accès parent par défaut. Toute extension exige un besoin, une finalité, un accès et une conservation documentés. Les exigences liées aux mineurs et aux représentants seront qualifiées avant le pilote ; une simple date de naissance ne les résout pas.

### Profil de données configurable mais borné

L’école choisit parmi des champs définis, pas un générateur de formulaires arbitraire. Le contrat ProfileFieldRule contient `field`, `requirement`, `stage`, `purposeCode` et `explanation`. `requirement` vaut REQUIRED, CONDITIONAL ou OPTIONAL ; `stage` vaut JOIN, BEFORE_LESSON, BEFORE_COURSE ou OPTIONAL. La visibilité découle des droits par champ et n’est pas un réglage libre. CONDITIONAL dépend des prérequis du produit/profil réglementaire sélectionné, calculés au serveur, jamais d’une formule arbitraire du client. Une naissance peut être exigée par le profil d’admissibilité même si la politique d’accueil la laissait facultative.

Impossible de rendre la photo, l’acceptation GPS, le marketing ou le push obligatoires. L’école ne peut demander une adresse pour simplement lire un bilan publié. Le serveur recalcule les exigences de l’action ; il n’accepte pas un booléen client `profileComplete=true`.

### Plusieurs écoles et compte existant

La personne conserve son identité de connexion. Rejoindre B crée une relation séparée et affiche ce qui sera transmis. Les informations que la personne a elle-même enregistrées dans son profil global peuvent être proposées à la saisie ; les pièces, coordonnées propres à A, choix GPS de A et formations de A ne sont pas copiés silencieusement. Une concordance de nom/date ne fusionne pas deux personnes.

Le statut « sensibilisation suivie ailleurs » crée une déclaration avec provenance et contrôle. Il ne marque pas automatiquement l’exigence COMPLETED ni ne reproduit une attestation privée d’une autre école.

### Formation souhaitée et décision de l’école

L’élève soumet une ou plusieurs TrainingRequest liées aux OfferingVersion proposées. ADMIN approuve ou refuse avec motif, conformément à R79. La création directe F03 par un moniteur déjà habilité ne lui confère pas le droit de décider une TrainingRequest. L’approbation utilise F03 dans la même transaction : vérifie la catégorie, la politique et l’unicité, puis crée ou référence une formation correspondante. Une formation active préexistante n’est jamais dupliquée par une nouvelle demande.

La décision est visible à l’élève. L’achèvement de l’onboarding ne donne pas à un élève le droit de créer sa propre formation ACTIVE. Une formation peut ensuite être confirmée mais rester non prête à conduire tant que son permis doit être examiné. R07 autorise la planification avec avertissement ; le contrôle reste requis avant la conduite.

### Accueil du moniteur

L’invitation définit l’école et les rôles. Le moniteur confirme son identité, ses coordonnées professionnelles utiles, son contexte de travail et ses disponibilités proposées. Les catégories enseignées sont déclaratives jusqu’à configuration/validation par l’école ; l’interface ne lui attribue pas automatiquement une habilitation.

L’écran explique les données qui lui seront accessibles, la publication du bilan et la distinction entre capture et facturation. Il propose « Préparer cet appareil » pour le diagnostic GPS sur téléphone ou tablette. Le consentement d’un élève n’est pas recueilli lors de cet accueil du personnel.

Aucune modification des packs, des tarifs globaux, des droits ou des politiques n’est accordée par l’onboarding moniteur. Un indépendant qui est ADMIN + INSTRUCTOR peut ouvrir le parcours école correspondant, sans changer de compte.

### Reprise, conflits et parcours interrompus

Chaque progression scolaire a un identifiant et une version serveur. Terminer une étape sauvegarde ses champs autorisés ; la progression de l’assistant n’est pas la source de vérité pour l’admissibilité. Passer de web à app reprend le dernier état confirmé, pas les frappes non envoyées dans un onglet fermé.

Si l’école modifie la politique entre deux étapes, la nouvelle exigence s’affiche avec sa raison et seulement pour les prochaines actions concernées. En cas de conflit, montrer les champs différant et demander une confirmation autorisée ; ne pas effacer les coordonnées corrigées par le personnel. Si l’accès est révoqué, cesser l’accueil et ne pas conserver une copie ouverte dans le navigateur.

Un deep link vers une sensibilisation est conservé comme intention non sensible. Après accueil suffisant, la fiche est relue : dates, place disponible, prix et profil peuvent avoir changé. Il faut toujours cliquer « S’inscrire » et accepter l’offre courante. La connexion ne transforme pas l’intention en inscription.

### Assistance et limites

Le personnel peut assister la saisie sur son propre écran avec provenance STAFF_ASSISTED ; il ne coche pas « accepté par l’élève », ne signe pas à sa place et ne choisit ALLOWED pour gagner du temps. Un choix oral, lorsque la politique le permet, utilise explicitement RECORDED_VERBAL et les règles F15. Un élève sans email utilisable reste hors du parcours d’identité autonome du pilote ; aucun faux email ni compte partagé n’est recommandé.

Les notices/conditions, choix de collecte, préférences de notification et permission OS ont des identifiants et événements distincts. Un accusé de présentation de notice n’est pas déclaré comme consentement juridique universel.

### Erreurs et critères d’acceptation

Erreurs : INVITATION_EXPIRED, INVITATION_IDENTITY_MISMATCH, PROFILE_ACTION_REQUIRED, OFFERING_NOT_READY, VERSION_CONFLICT, TRAINING_REQUEST_ALREADY_DECIDED, PHOTO_NOT_READY, ACCESS_REVOKED. Les données saisies non sensibles sont conservées quand la reprise est autorisée ; les données d’autrui ne servent jamais à expliquer un refus.

La recette couvre reprise inter-appareils, refus GPS, photo absente, mineur sans règle d’âge inventée, deux écoles, déclaration externe non validée, refus des notifications, champ nouvellement requis, doublon de formation et deep link devenu complet. Référence : [T175–T191](../05-realisation/tests-recette.md#t175).

## Précisions de contrat

Un profil tout juste créé peut avoir les noms administratifs null tant qu’ils n’ont pas été confirmés ; firstName/lastName sont exigés pour sauvegarder le profil confirmé et terminer l’étape utile. Le displayName existant n’est pas découpé automatiquement. Les noms d’API et tables sont explicitement rapprochés dans le modèle.

SchoolReadiness calcule les capacités pour le contexte du responsable ; sans appareil préparé, CAN_CAPTURE indique DEVICE_REQUIRED sans bloquer l’activation de gestion. Le diagnostic individuel sera demandé au moniteur au moment utile. Les versions/politiques publiées sont partagées, mais aucune permission OS n’est supposée valable sur tous ses appareils.

<a id="permissions-et-continuité-mobile-v34"></a>
## Permissions et continuité mobile
L’accueil n’obtient pas toutes les permissions au lancement. Les demandes sont liées à une action utile et aux exigences réelles du profil natif : [iOS/iPadOS](../04-technique/integration-ios-ipados.md), [Android](../04-technique/preparation-android.md). Consulter un replay, rejoindre une école ou s’inscrire à un cours ne nécessite pas le GPS de l’élève. Les annonces push restent facultatives ; la photo ne devient pas obligatoire pour rendre le parcours visuellement « complet ».

La reprise app/web promet seulement les données effectivement persistées et synchronisées. Le lien d’invitation relit identité, école et validité ; il ne contourne pas les préalables. Les interactions et variantes accessibles sont dans [PX04](../02-experience/patterns-mobile-parcours.md#px04).

L’entrée initialise les préférences de notification selon le [cycle de création documenté](calendrier-notifications.md#création-des-préférences-et-absence-de-choix) ; les canaux externes ne sont pas déduits d’un jeton push. Aucun événement de choix GPS n’est créé automatiquement. Le premier parcours peut continuer sans GPS et sans notifications externes.

