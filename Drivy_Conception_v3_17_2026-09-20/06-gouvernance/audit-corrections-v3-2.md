# Deuxième revue : corrections de Drivy V3.1 vers V3.2

> **Historique conservé, non normatif pour la technologie mobile.** La décision Swift de la [V3.4](changements-v3-4.md) remplace les recommandations mobiles antérieures ; les constats et résultats ci-dessous restent ceux de leur version d’origine.
> **19 septembre 2026 · Référence 3.2**. [Index](../README.md).
> Audit de conception et de contrats, pas essai d’une application exécutée.

## Résultat et périmètre

Cette passe corrige **11 ensembles supplémentaires** de contradictions, lacunes ou précisions nécessaires. Les corrections sont intégrées aux références fonctionnelles, règles, données, contrats, écrans et recettes ; ce rapport ne constitue pas un addendum concurrent. La V3.2 remplace la V3.1 pour développer le futur produit.

Le GPS reste central et facultatif par leçon. Les cours ne créent toujours aucune inscription automatique. Packs configurables, web, tablette et onboarding progressif sont conservés. Le code et les cinq archives sources ne sont pas modifiés. Les ajustements pour résoudre une lacune sont des décisions de conception proposées, distinctes d’un défaut prouvé du logiciel existant.

La base est le ZIP V3.1 complet, contenant 49 Markdown. Le dossier corrigé en contient 50, dont cet audit. Les contrôles transversaux portent sur tous les documents et le contrat. La revue sémantique approfondie porte sur les transitions entre domaines : financement/droits, cours/cycles/conditions, publication/effacement, client/synchronisation et droits/commit. Les documents de recherche, de direction artistique et les décisions de plateformes ont été conservés avec leurs limites ; cette passe n’est pas une nouvelle étude du marché.

## Ce qui est démontré par les contrôles

Le [vérificateur antérieur appliqué à V3.1](../annexes/controle-v3-1-avant-correction.json) passait : les nouvelles corrections ne doivent donc pas être présentées comme des erreurs déjà détectées la dernière fois. Le [contrôle transversal étendu appliqué à V3.1](../annexes/controle-transversal-v3-1.json) relève 192 écarts de clauses/occurrences. **Ce ne sont pas 192 bugs distincts** : la même convention manquante se répète sur plusieurs routes.

62 nouveaux cas JSON s’ajoutent aux 47 cas précédents rejoués, soit **109 contrôles de forme**. Parmi eux, **8 mêmes fixtures non conformes à la nouvelle règle étaient acceptées par le schéma V3.1 et sont refusées par V3.2**. Les cas portant sur de nouveaux DTO sont identifiés comme tels, sans prétendre qu’un DTO auparavant inexistant acceptait quoi que ce soit. [Comparaison détaillée](../annexes/comparaison-contrats-v3-1-v3-2.json).

24 nouveaux scénarios de recette portent la référence à **284 scénarios métier, tous NOT_EXECUTED**. Les 109 contrôles ne prouvent pas leur succès. La forme JSON ne vérifie pas une autorisation humaine, un interblocage SQL, un montant réellement encaissé ou le fonctionnement d’un GPS.

## Registre des corrections

<a id="d01"></a>
### D01 · Pagination et enveloppes des listes

**Nature :** Contradiction de contrat. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** R33 et les conventions annoncent 50 éléments par défaut et 100 au maximum. Plusieurs routes ajoutées autorisent 200, les pages V2 vont jusqu’à 500 et 15 réponses de listes ne sont pas enveloppées comme les autres.

**Correction V3.2 :** Limiter les requêtes ordinaires à 1–100 (50 par défaut), leurs tableaux à 100, et envelopper les 15 réponses. Les budgets spécialisés du replay/snapshot restent distincts de la capacité d’un cours.

**Références modifiées :** [api](../04-technique/api.md), [regles-etats](../03-fonctionnel/regles-etats.md), [openapi](../04-technique/openapi.yaml).

**Recettes à exécuter :** [T261](../05-realisation/tests-recette.md#t261), [T262](../05-realisation/tests-recette.md#t262).

<a id="d02"></a>
### D02 · Résultat encore en cours, sans fausse confirmation

**Nature :** Contrat incomplet. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** La fonction de cours mentionne OPERATION_PENDING/202. Le contrat de recherche d’opération et beaucoup de mutations scolaires ne définissent que le résultat commité, sans DTO de résultat encore en cours.

**Correction V3.2 :** Ajouter PendingOperationEnvelope aux réponses concernées et à AP72. Le client conserve l’intention et sa clé ; 202 ne confirme aucune place ni prestation. Distinguer un Job accepté de la commande encore en cours. Préciser le crash, la preuve durable et le rejeu à clé inchangée.

**Références modifiées :** [cours-collectifs](../03-fonctionnel/cours-collectifs.md), [synchronisation](../04-technique/synchronisation.md), [openapi](../04-technique/openapi.yaml).

**Recettes à exécuter :** [T263](../05-realisation/tests-recette.md#t263), [T264](../05-realisation/tests-recette.md#t264), [T284](../05-realisation/tests-recette.md#t284).

<a id="d03"></a>
### D03 · Présence conditionnelle et cycle de réinscription

**Nature :** Contradiction et lacune de cycle. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** AP146 accepte une « version 0 » pour la première présence via If-Match alors que la convention parle d’ETag d’une ressource existante. Le relevé ne porte pas enrollmentCycle malgré les cycles de réinscription introduits en V3.1.

**Correction V3.2 :** Identifier le cycle dans l’URI et le relevé ; création If-None-Match: *, correction If-Match. Une seule précondition, version initiale 1. Rejeter une commande d’un cycle antérieur et empêcher une présence définitive avant la fin du bloc. Ce dernier choix est une proposition conservatrice de pilote, explicitement soumise à validation.

**Références modifiées :** [api](../04-technique/api.md), [cours-collectifs](../03-fonctionnel/cours-collectifs.md), [regles-etats](../03-fonctionnel/regles-etats.md), [openapi](../04-technique/openapi.yaml).

**Recettes à exécuter :** [T265](../05-realisation/tests-recette.md#t265), [T266](../05-realisation/tests-recette.md#t266), [T267](../05-realisation/tests-recette.md#t267).

<a id="d04"></a>
### D04 · Déplacement de cours et échéances

**Nature :** Paramètres manquants et effet de bord commercial. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** RescheduleCourseCommand contient les occurrences et le motif, mais pas les échéances stockées sur la série. Avancer ou reporter les dates ne définit pas comment revalider inscription et désinscription.

**Correction V3.2 :** Soumettre et contrôler les deux échéances avec les dates. Conserver la date d’annulation acceptée par chaque cycle ; ne pas la raccourcir implicitement. Le déplacement et ses avis restent atomiques ; une comparaison temporelle relève du service, pas du seul JSON Schema.

**Références modifiées :** [cours-collectifs](../03-fonctionnel/cours-collectifs.md), [regles-etats](../03-fonctionnel/regles-etats.md), [openapi](../04-technique/openapi.yaml).

**Recettes à exécuter :** [T268](../05-realisation/tests-recette.md#t268), [T271](../05-realisation/tests-recette.md#t271).

<a id="d05"></a>
### D05 · Modèle de cours, offre publiée et conditions acceptées

**Nature :** Lacune de versionnement et action promise non contractée. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** CourseTemplate est mutable et porte requirementType, mais CourseSession ne fige pas cette valeur. Le document prévoit des corrections éditoriales et changements de prix ; le PUT existant est DRAFT seulement et les commandes publiées n’incluent pas cette édition ciblée.

**Correction V3.2 :** Figer requirementTypeSnapshot sur la série et acceptedCommercialSnapshot par cycle. AP192 concrétise les deux actions déjà promises : titre seul ou nouvelles conditions pour futurs inscrits. Une reconfirmation de dates ne transforme pas le tarif accepté en prix courant.

**Références modifiées :** [cours-collectifs](../03-fonctionnel/cours-collectifs.md), [calendrier-notifications](../03-fonctionnel/calendrier-notifications.md), [openapi](../04-technique/openapi.yaml).

**Recettes à exécuter :** [T269](../05-realisation/tests-recette.md#t269), [T270](../05-realisation/tests-recette.md#t270), [T271](../05-realisation/tests-recette.md#t271).

<a id="d06"></a>
### D06 · Durée de leçon et financement synchronisés

**Nature :** Transition insuffisamment spécifiée. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** MoveLessonCommand peut modifier début et fin, mais ne propose ni sélection commerciale révisée ni prix/quantité de droits. Une séance passant de 45 à 90 minutes pouvait être décrite sans traitement explicite de son HOLD et de son compte.

**Correction V3.2 :** Ajouter commercialChange pour la révision explicite avant capture/constat sur PLANNED. Conserver LessonCommercialRevision et appliquer horaire, occupations, droits et compte au même commit. Sans révision requise ou avec un solde invalide, préserver entièrement l’ancienne leçon. Aucune règle tarifaire universelle basée sur le GPS.

**Références modifiées :** [planning-lecons](../03-fonctionnel/planning-lecons.md), [catalogue-packs](../03-fonctionnel/catalogue-packs.md), [openapi](../04-technique/openapi.yaml).

**Recettes à exécuter :** [T272](../05-realisation/tests-recette.md#t272), [T273](../05-realisation/tests-recette.md#t273), [T274](../05-realisation/tests-recette.md#t274).

<a id="d07"></a>
### D07 · Droits de pack après correction d’un prépaiement

**Nature :** Transition retour non définie. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** La documentation décrit l’activation après paiement intégral et les contre-écritures, mais ne rend pas explicite le retour à un financement insuffisant. Les états de lot n’exposent pas cette suspension ni l’utilisabilité distincte du reliquat.

**Correction V3.2 :** Séparer availableQuantity et usableQuantity ; ajouter SUSPENDED_PAYMENT et DISABLED. Recontrôler finance et droits atomiquement lors d’une correction sur achat. Proposition du pilote : pas d’annulation automatique des engagements acquis ; honorer/traiter explicitement les HOLD existants et bloquer leur augmentation nette tant que nécessaire.

**Références modifiées :** [catalogue-packs](../03-fonctionnel/catalogue-packs.md), [transactions-v2](../04-technique/transactions-v2.md), [openapi](../04-technique/openapi.yaml).

**Recettes à exécuter :** [T275](../05-realisation/tests-recette.md#t275), [T276](../05-realisation/tests-recette.md#t276), [T277](../05-realisation/tests-recette.md#t277).

<a id="d08"></a>
### D08 · Flux de synchronisation des domaines ajoutés

**Nature :** Écart entre périmètre fonctionnel et contrat incrémental. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** SyncChange énumère les domaines initiaux, mais ne peut pas nommer cours, inscriptions, achats, droits, exigences et captures. Les nouvelles règles parlent pourtant d’invalidation de ces données.

**Correction V3.2 :** Compléter les types et l’action INVALIDATE. Définir la matrice entre snapshot initial et caches enrichis, leur relecture autorisée et leur nettoyage à changement d’epoch/snapshot. Les points GPS gardent leur circuit spécialisé, sans promesse nouvelle de tout fonctionner hors ligne.

**Références modifiées :** [synchronisation](../04-technique/synchronisation.md), [hors-ligne-vie-privee](../03-fonctionnel/hors-ligne-vie-privee.md), [openapi](../04-technique/openapi.yaml).

**Recettes à exécuter :** [T278](../05-realisation/tests-recette.md#t278), [T279](../05-realisation/tests-recette.md#t279).

<a id="d09"></a>
### D09 · Effacement GPS représentable sans coordonnées

**Nature :** Contradiction de projection et de confidentialité. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** ReplayPage accepte WITHDRAWN/DELETED mais impose un geometrySnapshotId pour tout état non privé et ne contraint pas les segments à être vides. CapturePublication ne décrit que le snapshot disponible. Cela contredit l’effacement géographique documenté.

**Correction V3.2 :** Distinguer le snapshot conservé à titre de preuve de sa projection d’accès courante. Un objet retiré/effacé expose une géométrie nulle, sans observations, segments ni curseur de données. Les bilans autonomes autorisés restent séparés ; retirer un partage n’ouvre pas la vue privée. Purge des dérivés et limites hors ligne conservées.

**Références modifiées :** [gps-replay](../03-fonctionnel/gps-replay.md), [regles-etats](../03-fonctionnel/regles-etats.md), [openapi](../04-technique/openapi.yaml).

**Recettes à exécuter :** [T280](../05-realisation/tests-recette.md#t280), [T281](../05-realisation/tests-recette.md#t281).

<a id="d10"></a>
### D10 · Sélections uniques plutôt que tableaux dupliqués

**Nature :** Validation de forme manquante. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** Les options d’achat et les indices de chunks attendus acceptent des doublons dans les schémas. Les justificatifs de présence et les occurrences reconfirmées avaient le même problème de liste répétée.

**Correction V3.2 :** Imposer uniqueItems sur ces ensembles. Les références, sommes et compatibilités restent vérifiées au service ; cette restriction ne prouve ni le calcul commercial ni la complétude d’un trajet.

**Références modifiées :** [openapi](../04-technique/openapi.yaml), [catalogue-packs](../03-fonctionnel/catalogue-packs.md), [gps-replay](../03-fonctionnel/gps-replay.md).

**Recettes à exécuter :** [T282](../05-realisation/tests-recette.md#t282).

<a id="d11"></a>
### D11 · Autorisation courante à la frontière du commit

**Nature :** Précision d’architecture à tester. **État :** corrigé dans la conception ; recette produit à réaliser.

**Constat V3.1 :** Les permissions courantes sont exigées et l’ordre des verrous métier est décrit, mais la coordination d’une révocation avec une commande ayant déjà lu ses droits puis attendu un verrou n’est pas matérialisée.

**Correction V3.2 :** Inclure l’appartenance et ses délégations dans l’ordre de verrouillage et relire la portée en transaction ; la révocation prend le verrou incompatible. Spécifier les deux ordres de commit et la reprise bornée. Cela décrit une stratégie, pas une vulnérabilité reproduite ni un test de concurrence exécuté.

**Références modifiées :** [roles-permissions](../03-fonctionnel/roles-permissions.md), [regles-etats](../03-fonctionnel/regles-etats.md), [transactions-v2](../04-technique/transactions-v2.md).

**Recettes à exécuter :** [T283](../05-realisation/tests-recette.md#t283).

## Précisions et conséquences de conception

**Le contrat change avant implémentation.** AP146 acquiert un cycle dans son URI ; les réponses des listes concernées sont enveloppées ; certains DTO exigent de nouveaux champs et AP192 matérialise une action déjà décrite. Un futur client doit utiliser le contrat V3.2 complet, pas mélanger des types V3.1 et des routes V3.2. La version de conception ne simule pas un déploiement ou une migration effective.

**Prépayé corrigé.** Le choix de maintenir les engagements déjà confirmés évite une annulation cachée. L’école doit approuver cette politique et la manière de résoudre les dettes ; la documentation ne fixe pas une règle de remboursement légale universelle.

**Présence.** L’interdiction de validation définitive avant fin de bloc est une proposition de pilote à confronter au travail du formateur. Le formulaire peut être préparé sans transformer sa saisie en attestation.

**Échéance de désinscription.** La date acceptée appartient au cycle et n’est pas remplacée par un simple changement de paramètre global. Le traitement d’une échéance défavorable doit être explicitement accepté ou résolu ; aucun code ne doit inventer une retenue parce que l’administrateur a changé une date.

**Autorisation transactionnelle.** Les mécanismes HTTP et de verrouillage ont été confrontés à leurs sources primaires [S59](sources.md#s59), [S60](sources.md#s60). Cela n’atteste ni d’un middleware ni d’un schéma SQL existants. Les invariants de concurrence doivent être reproduits sur deux connexions réelles.

## Traçabilité et preuves

Les [preuves avant correction](../annexes/preuves-audit-v3-2.json) donnent chemins, lignes et empreintes du dossier V3.1. Les lignes sont celles de cette version source, pas celles du document corrigé. Le [diff](../annexes/corrections-v3-1-vers-v3-2.patch) compare les références existantes, hors fichiers dérivés et rapports historiques. Les [contrôles documentaires courants](../annexes/verification-documentaire.json) sont séparés de la [vérification du lecteur](../annexes/verification-lecteur.json) et de [l’intégrité des sources](../annexes/verification-originaux.json).

Le vérificateur est étendu : enveloppes de réponses, limites de pages et paramètres, déclarations de résultats provisoires, cycles et préconditions, domaines de sync, ensembles uniques et champs de projection. Il conserve aussi références, liens, schémas, exemples, registres et relations réciproques tests/fonctions. Son utilisation de JSON Schema n’exige plus RefResolver déprécié. Il ne s’agit toujours pas d’un validateur intégral du méta-schéma OpenAPI.

## Reste à exécuter ou à décider

Aucun build, essai routier, diagnostic d’appareil réel, test de concurrence contre PostgreSQL, restauration de sauvegarde avec purge, audit de sécurité ou validation juridique n’est réalisé dans cette passe. Les fournisseurs et tarifs des écoles n’ont pas été reconfirmés. Les profils réglementaires, responsabilités, durées de conservation, politiques commerciales et moyens de développement restent au [registre des décisions](glossaire-decisions-questions.md).

Un dossier sans erreur détectée par ces vérificateurs n’est pas une démonstration d’absence totale de défauts. Le prochain niveau de preuve est l’exécution d’un parcours vertical réel et de ses cas de refus, pas une augmentation artificielle du nombre de documents.
