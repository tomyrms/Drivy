# Audit et corrections : Drivy V3 vers V3.1

> **Historique conservé, non normatif pour la technologie mobile.** La décision Swift de la [V3.4](changements-v3-4.md) remplace les recommandations mobiles antérieures ; les constats et résultats ci-dessous restent ceux de leur version d’origine.
> **19 septembre 2026 · Référence corrigée 3.1.** [Index](../README.md). Revue de conception, pas audit d’une application exécutée.

## Résultat

La V3.1 remplace la V3 dans son ensemble. Elle corrige **19 ensembles d’écarts**, sans changer le positionnement décidé : GPS et apprentissage au centre, enregistrement volontaire, cours collectifs avec inscription explicite, offres et packs configurables, tablette de premier plan, web et onboarding progressif. Les originaux sont conservés. Aucune modification du code de Drivy n’est comprise dans cette livraison.

Les défauts relevés sont des contradictions, insuffisances ou ambiguïtés **dans la spécification**. Ils peuvent entraîner une implémentation erronée ; cela ne prouve pas qu’une vulnérabilité ou un dysfonctionnement a été reproduit dans l’ancienne application. Les précisions de conception choisies pour résoudre un manque sont signalées et restent révisables avant développement.

## Base et méthode

La référence est le ZIP V3 complet reçu dans cette conversation, pas seulement les fichiers Markdown liés dans les réponses précédentes. Son inventaire comporte 48 fichiers Markdown, le contrat OpenAPI et les annexes. La demande de conception initiale et les décisions produit de la conversation cadrent la revue ; l’ancien code n’est pas pris pour architecture à reproduire.

La revue croise les domaines fonctionnels, les règles et états, les parcours, les permissions, les compositions d’écran, les modèles, les contrats, les transactions, les tests et la roadmap. L’intégralité des fichiers Markdown entre dans le contrôle des liens et identifiants. Les vérifications sémantiques portent particulièrement sur les jonctions à risque : identité/école, capture/publication, pack/inscription/paiement, préparation/activation, archivage/droits et statistiques/sources. La recherche et le design sont conservés, avec leurs niveaux de preuve et arbitrages.

Cette revue n’est pas une nouvelle enquête sur les dix écoles. Les prix et descriptions externes restent le relevé daté déjà présent, non des devis reconfirmés. Aucun entretien, build, essai routier, test de concurrence SQL ou audit juridique n’a été réalisé dans cette passe. Les décisions encore ouvertes ne sont pas transformées artificiellement en paramètres validés.

Les [preuves de repérage](../annexes/preuves-audit-v3-1.json) donnent les chemins, lignes et empreintes de la V3. Le [diff documentaire](../annexes/corrections-v3-vers-v3-1.patch) montre les changements textuels des références existantes, hors dérivés générés. Les lignes citées dans ces preuves sont celles du fichier source avant correction, pas celles du document courant.

## Registre des corrections

<a id="aud-01"></a>
### AUD-01 · Activation initiale de l’école

**Nature :** Bloquant de conception. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** La définition de CAN_USE_WORKSPACE exigeait une école ACTIVE, tandis que l’activation utilisait cette capacité comme préalable. La création d’une école DRAFT pouvait donc être spécifiée sans chemin d’activation cohérent.

**Correction V3.1 :** SchoolReadiness expose activationReady et activationBlockers calculés avant la transition ; l’accès courant au workspace reste conditionné à ACTIVE. La préparation globale n’est pas une autorisation de transaction pour un élève ou appareil donné.

**Référence corrigée :** [03-fonctionnel/onboarding.md](../03-fonctionnel/onboarding.md). **Recette prévue :** [T233–T235](../05-realisation/tests-recette.md#t233).

<a id="aud-02"></a>
### AUD-02 · Archivage et délégation

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** La matrice générale et E07 réservaient l’archivage à ADMIN, alors que F22, les règles et les contrats prévoient MANAGE_LEARNER_ARCHIVES. Terminer une formation et archiver le dossier étaient également regroupés.

**Correction V3.1 :** Les deux opérations sont séparées ; un moniteur délégué peut archiver uniquement dans son périmètre affecté, avec prévisualisation et vérification au commit. L’accès au web ne donne aucun droit supplémentaire.

**Référence corrigée :** [03-fonctionnel/roles-permissions.md](../03-fonctionnel/roles-permissions.md). **Recette prévue :** [T236](../05-realisation/tests-recette.md#t236).

<a id="aud-03"></a>
### AUD-03 · Validation d’une formation et projection de l’équipe

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Les formulations de rôle laissaient confondre création de formation pour un élève connu et approbation d’une TrainingRequest. La liste administrative Member, comprenant rôles et délégations, n’était pas distinguée assez fermement d’un contact d’école.

**Correction V3.1 :** Approbation de TrainingRequest par ADMIN ; vérification des affectations conservée pour les opérations du moniteur. AP07 expose la liste administrative uniquement à ADMIN. Les autres utilisateurs voient le contact de l’école et les intervenants via leurs engagements autorisés, pas le roster administratif.

**Référence corrigée :** [03-fonctionnel/roles-permissions.md](../03-fonctionnel/roles-permissions.md). **Recette prévue :** [T242, T247](../05-realisation/tests-recette.md#t242).

<a id="aud-04"></a>
### AUD-04 · Archivage et remboursement non terminé

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** La vérification des obligations mettait en avant dette, engagements et droits réservés, mais ne rendait pas explicite le blocage d’une inscription annulée dont le remboursement restait à traiter alors que le solde courant était nul.

**Correction V3.1 :** Le suivi financier REFUND_REQUIRED bloque l’archivage avec ARCHIVE_FINANCIAL_FOLLOW_UP_REQUIRED dans ARCHIVE_BLOCKED. Une capture arrêtée avec transfert incomplet est un avertissement, pas une collecte encore active.

**Référence corrigée :** [03-fonctionnel/gestion-web-archivage.md](../03-fonctionnel/gestion-web-archivage.md). **Recette prévue :** [T237–T238](../05-realisation/tests-recette.md#t237).

<a id="aud-05"></a>
### AUD-05 · Profil partiel et versions concurrentes

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** AdministrativeProfileCommand exigeait les noms même pour une modification de contact. Deux voies de modification Learner/profil n’expliquaient pas suffisamment leur versionnement commun, ni l’omission des champs privés dans les projections.

**Correction V3.1 :** PATCH partiel avec au moins un champ modifié ; autorisation par champ côté service. AP16 et AP176 portent le même agrégat et invalident ensemble leurs versions de projection. Les champs non autorisés sont omis ; null signifie absence de valeur pour un champ autorisé.

**Référence corrigée :** [04-technique/api.md](../04-technique/api.md). **Recette prévue :** [T239–T240](../05-realisation/tests-recette.md#t239).

<a id="aud-06"></a>
### AUD-06 · Photo facultative jusque dans le contrat

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** L’onboarding promettait une photo facultative, mais la règle générique de politique permettait de déclarer ce champ obligatoire à l’entrée. Les noms de champs et étapes de politique différaient aussi entre prose et schéma.

**Correction V3.1 :** ProfileFieldRule contraint la photo à OPTIONAL/OPTIONAL/PERSONALISATION. Les noms exigés pour l’identité et les champs conditionnels sont séparés. Les clés et étapes de politique sont alignées sur le contrat. La photo n’est pas un préalable de capacité.

**Référence corrigée :** [03-fonctionnel/onboarding.md](../03-fonctionnel/onboarding.md). **Recette prévue :** [T241](../05-realisation/tests-recette.md#t241).

<a id="aud-07"></a>
### AUD-07 · Publication GPS réellement immuable

**Nature :** Bloquant de conception. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Le bilan publié référençait une sélection de capture et d’observations alors que celles-ci restaient des objets privés modifiables ; ni la version des observations sélectionnées ni le manifeste des points publiés n’étaient matérialisés assez précisément.

**Correction V3.1 :** CaptureSelection exige les versions contrôlées au commit ; CapturePublication et PublishedGeoObservation matérialisent le snapshot publié, avec geometrySnapshotId et sans draftId. Une arrivée tardive de points ne modifie pas un ancien bilan. Purge et révocation restent prioritaires sur l’accès aux snapshots.

**Référence corrigée :** [03-fonctionnel/gps-replay.md](../03-fonctionnel/gps-replay.md). **Recette prévue :** [T246–T248](../05-realisation/tests-recette.md#t246).

<a id="aud-08"></a>
### AUD-08 · Autorisation de collecte et transfert différé

**Nature :** Bloquant de conception. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** La preuve temporaire utilisée pour collecter se retrouvait dans la commande d’envoi alors que l’envoi différé pouvait dépasser la borne de collecte. L’origine de la durée maximale et la distinction entre états serveur et collecteur local restaient ambiguës.

**Correction V3.1 :** Deux preuves de portée différente : signedCaptureAuthorization et signedUploadAuthorization. L’expiration de collecte part de authorizedAt, pas d’un lancement local tardif. Le serveur connaît AUTHORIZED/STOPPED/REVOKED/EXPIRED ; RECORDING/PAUSED sont locaux. Session et droits courants sont toujours contrôlés à l’envoi.

**Référence corrigée :** [04-technique/synchronisation.md](../04-technique/synchronisation.md). **Recette prévue :** [T250–T251](../05-realisation/tests-recette.md#t250).

<a id="aud-09"></a>
### AUD-09 · Pagination du replay sans perte de segment

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Les limites de page et de points par segment ne définissaient pas comment lire un long segment dépassant la borne du schéma. Un développeur aurait pu couper un trajet ou fabriquer des ruptures pour paginer.

**Correction V3.1 :** Le budget est de 1 000 points au total par page ; chaque fragment conserve son segment logique et indique ses continuations. Le curseur est lié au scope, aux droits et à la révision/snapshot. La limite de transport ne crée aucune pause GPS.

**Référence corrigée :** [04-technique/api.md](../04-technique/api.md). **Recette prévue :** [T253](../05-realisation/tests-recette.md#t253).

<a id="aud-10"></a>
### AUD-10 · Inscription et réinscription sans effet financier caché

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Le contrat pouvait accepter RECORDED_REQUEST sans justificatif de demande, et ne rejetait pas les identifiants d’occurrences dupliqués. La réutilisation d’une relation annulée ne distinguait pas assez clairement un nouveau cycle et l’ancien compte financier.

**Correction V3.1 :** Une note accompagne la saisie de demande par le personnel, sans remplacer ses droits ; SELF reste distinct. Occurrences uniques, ensemble validé côté service. Réinscription explicite avec enrollmentCycle, obligations antérieures résolues et aucun INITIAL ou encaissement dupliqué.

**Référence corrigée :** [03-fonctionnel/cours-collectifs.md](../03-fonctionnel/cours-collectifs.md). **Recette prévue :** [T243–T245](../05-realisation/tests-recette.md#t243).

<a id="aud-11"></a>
### AUD-11 · Audience de cours et données réellement disponibles

**Nature :** Arbitrage conservateur explicite. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Des filtres d’audience par site/langue étaient proposés sans modèle de rattachement de l’élève à un site ni préférence de langue de cours permettant de les calculer. L’adresse ou le GPS ne constituent pas une telle préférence.

**Correction V3.1 :** Au pilote, audience globale ou catégories de Training actives et validées. Les tableaux siteIds/languages d’audience restent réservés mais vides ; site et langue restent des caractéristiques consultables de l’offre. Un ciblage futur exige une préférence/règle explicitement modélisée et acceptée, pas une inférence cachée.

**Référence corrigée :** [03-fonctionnel/calendrier-notifications.md](../03-fonctionnel/calendrier-notifications.md). **Recette prévue :** [T257](../05-realisation/tests-recette.md#t257).

<a id="aud-12"></a>
### AUD-12 · Droits financiers distincts des statistiques d’école

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Les règles de portée ne rendaient pas uniforme le cas d’une personne possédant VIEW_FINANCIAL_METRICS sans VIEW_SCHOOL_METRICS. Des libellés laissaient également imaginer des séries temporelles pour tous les indicateurs.

**Correction V3.1 :** Les deux délégations sont indépendantes. Au scope SCHOOL, les mesures interdites sont omises, non nulles ou remplacées par zéro. Les séries couvrent M01/M02/M03/M04/M06 ; M05/M07/M08 sont des instantanés, M09 reste un compteur de suivi avec période de référence.

**Référence corrigée :** [03-fonctionnel/statistiques.md](../03-fonctionnel/statistiques.md). **Recette prévue :** [T254–T255](../05-realisation/tests-recette.md#t254).

<a id="aud-13"></a>
### AUD-13 · Unités et termes canoniques

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Deux textes parlaient de montants entiers CHF alors que le contrat manipule des centimes. Plusieurs alias d’export, de préparation ou d’accomplissement ne correspondaient pas aux enums. Les unités des indicateurs étaient permissives.

**Correction V3.1 :** Centimes CHF partout ; STUDENT_LIST/METRICS distincts de PRIVACY ; SETUP_INCOMPLETE, PROFILE_ACTION_REQUIRED, EXPORT_TOO_LARGE et definitionsVersion alignés. UNKNOWN/EVIDENCE_PENDING/COMPLETED concernent le bon agrégat. Les types, unités et bornes M01–M09 sont contraints par schéma.

**Référence corrigée :** [04-technique/fichiers-temps-communications.md](../04-technique/fichiers-temps-communications.md). **Recette prévue :** [T255–T256, T260](../05-realisation/tests-recette.md#t255).

<a id="aud-14"></a>
### AUD-14 · Modèle relationnel et occupation historique

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Le modèle School ne présentait pas DRAFT partout et des noms d’entités d’onboarding différaient des DTO. La formulation « réservation active » pouvait être comprise comme future seulement, contrairement au maintien d’un historique de leçons réalisées.

**Correction V3.1 :** School, SchoolSetup, OnboardingProgress, AdministrativeProfile et ProfileFieldPolicyVersion sont alignés. Les occupations effectives historiques sont conservées ; la date passée ne désactive pas automatiquement une contrainte. L’API School expose modules et configurationVersion.

**Référence corrigée :** [04-technique/modele-donnees.md](../04-technique/modele-donnees.md). **Recette prévue :** [T258–T259](../05-realisation/tests-recette.md#t258).

<a id="aud-15"></a>
### AUD-15 · Diagnostic appareil indépendant des notifications

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Le diagnostic et la création de l’installation n’étaient pas reliés explicitement ; l’inscription aux notifications pouvait être prise, à tort, comme seule voie d’enregistrement de l’appareil.

**Correction V3.1 :** assessCaptureDevice crée ou retrouve l’installation authentifiée dans la transaction de diagnostic, sans jeton push requis. Le diagnostic est une donnée versionnée, pas une preuve de qualification physique universelle.

**Référence corrigée :** [04-technique/transactions-v3.md](../04-technique/transactions-v3.md). **Recette prévue :** [T252](../05-realisation/tests-recette.md#t252).

<a id="aud-16"></a>
### AUD-16 · Catalogue API et exemples effectivement vérifiés

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Le tableau AP17 décrivait encore une commande générique ReasonCommand au lieu d’ArchiveCommitCommand ; d’autres lignes additionnelles n’avaient pas leurs types précis. Le vérificateur ignorait les exemples au niveau media type. Celui d’AP154 omettait deviceAssessmentId, pourtant obligatoire.

**Correction V3.1 :** Les 191 lignes sont réalignées sur OpenAPI. Les exemples de schémas, d’annexe et des requêtes/réponses media type sont tous pris en compte : 27 occurrences positives, dont 6 auparavant hors contrôle. L’exemple d’AP154 est complété.

**Référence corrigée :** [04-technique/api.md](../04-technique/api.md). **Recette prévue :** [Contrôles automatisés + T252](../05-realisation/tests-recette.md#t252).

<a id="aud-17"></a>
### AUD-17 · Dépendances de la roadmap

**Nature :** Importante. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Le bloc de tests demandé au premier gate couvrait aussi des inscriptions concurrentes à des cours, alors que la tranche collective n’était pas encore réalisée. Des périmètres de recette risquaient d’être annoncés avant leurs sources de données.

**Correction V3.1 :** G1 ne dépend plus implicitement de T188/T189 ; ces cas suivent le collectif. Les 28 nouveaux scénarios sont rattachés à la première tranche implémentant leur capacité, jamais tous à l’activation initiale. Les indicateurs attendent leurs sources métier.

**Référence corrigée :** [05-realisation/roadmap-backlog.md](../05-realisation/roadmap-backlog.md). **Recette prévue :** [T233–T260 selon tranche](../05-realisation/tests-recette.md#t233).

<a id="aud-18"></a>
### AUD-18 · Expérience et vocabulaire de preuve

**Nature :** Cohérence. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Un écran réservait encore l’archivage à ADMIN, une tablette secondaire pouvait prétendre qu’une autre enregistrait en direct, et une fixture photo évoquait un deuxième élève dans l’image au lieu d’un deuxième compte. Le titre annonçait trois actions pour quatre opérations de cycle de vie.

**Correction V3.1 :** Écrans et compositions alignés sur les autorisations et la connaissance serveur ; fixtures fictives sans promesse de reconnaissance de visage. Archivage, fin de formation, révocation et effacement restent quatre actions distinctes.

**Référence corrigée :** [02-experience/ecrans.md](../02-experience/ecrans.md). **Recette prévue :** [T236, T249–T250](../05-realisation/tests-recette.md#t236).

<a id="aud-19"></a>
### AUD-19 · Portée du contrôle et traçabilité

**Nature :** Qualité documentaire. **État :** corrigé dans la documentation, vérification métier future requise.

**Constat V3 :** Les liens et exemples existants passaient sans détecter plusieurs contradictions sémantiques. Les rapports et le lecteur étaient ceux de la V3 ; les conserver aurait présenté des vérifications anciennes comme résultats du dossier corrigé.

**Correction V3.1 :** Vérificateur étendu avec 47 cas JSON Schema positifs/négatifs, contrôle catalogue API/registre/prose et relations fonctions-tests réciproques. 28 tests métier supplémentaires restent NOT_EXECUTED. Rapports, index, lecteur, empreintes et archive sont régénérés ; le contrôle documentaire n’est jamais une recette produit.

**Référence corrigée :** [annexes/verifier-documentation.py](../annexes/verifier-documentation.py). **Recette prévue :** [T233–T260 et SC001–SC047](../05-realisation/tests-recette.md#t233).

## Arbitrages de résolution à connaître

**Projection de l’équipe et approbation des demandes.** Le dossier choisit la portée la plus limitée cohérente avec les droits existants : roster administratif et validation de TrainingRequest réservés à ADMIN. Cela ne retire ni les contacts nécessaires au rendez-vous, ni la gestion autorisée de l’élève affecté. Une délégation d’approbation plus large pourra être ajoutée explicitement, avec règles et tests, pas déduite du mot « moniteur ».

**Ciblage de cours.** Les filtres site/langue d’audience ne sont pas opérationnels au pilote faute de données de rattachement spécifiées. Cela ne retire pas le lieu ou la langue de la fiche de cours et n’empêche pas de publier pour tous les élèves. L’extension devra décider comment une préférence est saisie et mise à jour. Aucune classification n’est déduite des trajets.

**Publication de trajet.** Le choix retenu est un snapshot versionné au moment du bilan. Il rend le contrat concret sans promettre la conservation indéfinie des positions : les procédures d’effacement restent applicables à toutes les copies et dérivés.

**Capture et page de replay.** Les bornes proposées restent des paramètres de pilote à qualifier. Leur définition est maintenant sans ambiguïté ; cela ne vaut pas mesure de batterie, performance ou capacité matérielle. Les jetons séparés et curseurs décrivent une architecture à implémenter et à tester, pas des mécanismes déjà exécutés.

## Vérifications documentaires et non-régression

Le [rapport reproductible](../annexes/verification-documentaire.json) indique les résultats exacts du dernier passage. Il valide les références locales, les identifiants, 191 opérations et leurs routes, 323 schémas JSON, les références internes et 27 occurrences d’exemples positifs. Les **47 cas de contrat**, dont 20 positifs et 27 négatifs, vérifient aussi que certaines formes incohérentes sont refusées. Ils ne vérifient ni une signature réelle ni l’autorisation d’une personne ni une transaction en base.

Les **260 scénarios métier**, dont 28 ajoutés par cette passe, demeurent **NOT_EXECUTED**. L’ancien vérificateur avait laissé passer l’exemple AP154 incomplet : il inspectait les exemples de schémas et d’annexe mais pas les media types. Le [contrôle de référence avant correction](../annexes/controle-v3-avant-correction.json) garde cette différence de couverture visible, au lieu de réécrire l’historique comme si elle n’avait jamais existé.

Le lecteur est régénéré à partir des documents corrigés. Ses essais de navigation et de taille de fenêtre concernent uniquement **la lecture du dossier**, pas les futures interfaces de Drivy. L’intégrité du ZIP et la conservation des originaux sont contrôlées séparément.

## Ce qui reste à valider

Les [questions ouvertes](glossaire-decisions-questions.md) restent la référence : appareils et OS réels, ressources, critères de qualification GPS, choix des fournisseurs et coûts, règles commerciales applicables, profils réglementaires, responsabilités et durées de conservation, accès après la relation scolaire, migration des données utiles. La documentation ne remplace ni ces décisions ni leur recette.

Une relecture humaine contradictoire et un premier parcours vertical exécuté restent nécessaires avant de considérer le système prêt. Un rapport documentaire sans erreur signifie **aucune erreur détectée par ces contrôles**, pas absence démontrée de toute incohérence imaginable.
