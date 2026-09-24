# Audit fonctionnel de l’archive et limites de preuve

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Périmètre réellement accessible

**VER.** Archive `Drivy-master.zip`, empreinte SHA-256 `017fe85938e393a503f03b10681967ff001c4cca0b32fe60c33a0153e775d5e3`. L’archive comporte 609 entrées ZIP, dont des répertoires : ce nombre n’est pas un nombre de fichiers source. Le repérage a identifié **140 fichiers Swift, 53 fichiers de tests TypeScript, 23 migrations SQL et 51 documents Markdown dans `docs/`**. Le schéma Prisma déclare **33 modèles**. Les comptages sont reproductibles dans la copie d’audit.

L’examen a combiné inventaire des chemins, lecture du schéma entier, lecture des routes enregistrées et lectures ciblées des services, dépôts de données, synchronisation et documents. **Ce n’est pas une revue ligne par ligne de tout le logiciel.** La matrice indique la solidité variable des preuves. Les sous-domaines observés par leurs contrats et modèles ne sont pas présentés comme testés en fonctionnement.

Ni l’app iOS, ni une app Android, ni un client web n’ont été lancés. Les tests existants n’ont pas été exécutés. Aucun compte réel, base de production, serveur, secret, statistique d’usage ou témoignage utilisateur n’a été consulté. Les scripts et tests du dépôt peuvent réinitialiser des tables : ils n’ont pas été lancés sur une base inconnue. Aucune donnée utilisateur n’a été migrée. Le code, sa configuration et les deux fichiers fournis n’ont pas été modifiés.

## Ce que l’existant apprend réellement

Le domaine est plus riche qu’un agenda : la relation élève-école peut porter plusieurs formations, une leçon a un moniteur et une formation, les observations pédagogiques ont un historique, les documents peuvent être rattachés à une leçon. L’importance de ces liens est étayée par [EV03](#ev03), [EV04](#ev04) et [EV05](#ev05). Cela ne démontre pas qu’il faille conserver la carte en écran principal.

Le README annonce encore une phase de conception alors que routes, migrations, vues et tests sont présents. Ce décalage interdit d’utiliser le README comme preuve unique de maturité [EV01](#ev01), [EV06](#ev06). La future documentation devra séparer état de conception, état d’implémentation et état de disponibilité.

Les appartenances à une école sont distinctes des personnes, mais leur rôle est unique dans le schéma ancien. Une nouvelle conception multi-rôle n’est donc pas un simple renommage de cet objet [EV02](#ev02). Les formations multi-permis existent ; des champs de permis subsistent aussi sur le dossier général [EV03](#ev03). Le nouveau modèle ne doit pas imposer qu’un permis soit un attribut universel d’une personne.

## Incohérences et risques utiles, sans projet de réparation

| Constat statique | Ce qu’il autorise à conclure | Conséquence pour la nouvelle conception |
|---|---|---|
| `SYNCING` figure parmi les statuts de leçon [EV02](#ev02). | Une notion de transport peut être confondue avec la réalité métier ; son utilisation effective partout n’est pas prouvée. | Séparer état de leçon, publication du bilan et état local d’envoi. |
| Plusieurs structures coexistent : `Evaluation`, `CompetencyValidation`, `StudentCompetencyRating`, `LessonCompetencyRating` [EV04](#ev04), [EV05](#ev05). | Les concepts pédagogiques et leurs sources de vérité demandent clarification. Ce n’est pas une preuve d’erreur sur chaque écran. | Un référentiel versionné, des observations datées, une projection de progression définie. |
| `paid` est un booléen de leçon [EV03](#ev03), [EV07](#ev07). | Le schéma ne suffit pas à représenter acomptes, paiements partiels et corrections comptables. | Journal interne de montants, sans prétendre produire des factures. |
| Le dépôt de réservation utilise `Serializable` [EV08](#ev08). | Une protection concurrente existe déjà. Dire « aucun contrôle de réservation » serait faux. | Écrire les invariants et tester aussi élève, pauses, déplacements et double requête. |
| Le calcul d’occupation observé est centré sur moniteur et école [EV09](#ev09). | La preuve examinée ne démontre pas un verrou global pour un élève multi-permis. | Contrainte de capacité par personne et école dans le nouveau périmètre. |
| La synchronisation remplace plusieurs collections de données [EV11](#ev11). | Une transaction existe et un traitement protège certaines évaluations plus récentes ; aucune preuve de résolution universelle. | Versions explicites, correction de bilan par révision, pas de remplacement silencieux. |
| Les exigences de formation sont liées au dossier étudiant, pas à la formation [EV05](#ev05). | Leur portée ne coïncide pas avec celle des compétences multi-permis. | Future exigence explicitement scolaire ou liée à une formation, sans champ ambigu. |
| La conversation est école-élève avec `staffReadAt` partagé [EV02](#ev02). | La notion « lu par l’équipe » n’atteste pas une lecture par chaque moniteur. | Chat différé ; distinguer livraison, lecture individuelle et responsabilité de réponse. |
| Le service push lu enregistre et retire des tokens [EV13](#ev13). | Il ne prouve pas un envoi APNs, un ordonnanceur ni la livraison en production. | Notifications classées partielles ; contrat transactionnel d’envoi à concevoir. |
| Des brouillons JSON et des conflits persistés existent [EV14](#ev14). | La reprise locale n’est pas absente. Le stockage observé ne démontre pas un chiffrement applicatif complet. | Cache natif chiffré et files explicites ; tester arrêt brutal et révocation. |

## Ce qui n’est pas établi

Aucune mesure ne permet d’affirmer qu’une fonction est « inutilisée », que les élèves préfèrent un système de notes ou qu’un écran provoque un taux d’abandon. Les demandes historiques signalent des préoccupations, pas une étude représentative. Les suggestions d’exclusion sont des **REC/HYP**, non un jugement statistique.

Les disponibilités légales des enseignants, leurs autorisations professionnelles, les modalités de vente, l’encaissement réel, l’hébergement effectif et les accords de sous-traitance restent inconnus. Les mentions de stockage suisse, de chiffrement, de Stripe ou de conformité dans une documentation ne prouvent pas une installation réelle ni sa conformité.

## Registre des preuves internes

Les chemins ci-dessous sont relatifs à la racine **de l’archive d’origine**, pas au nouveau dossier. Les plages sont des repères de vérification ; certains fichiers longs ont fait l’objet d’une lecture ciblée, non d’un audit exhaustif. Les empreintes permettent de distinguer cette version d’une évolution ultérieure.

<a id="ev01"></a>
### EV01 · Positionnement ancien, stack annoncée et statut documentaire périmé

`README.md`, lignes **1–78**. SHA-256 : `a4b77284875609b5b3e61f853f552ce332e18670908bd2b316ade6ffd1b8a01c`.

<a id="ev02"></a>
### EV02 · Énumérations, écoles, personnes, appartenances, invitations, conversations

`api/prisma/schema.prisma`, lignes **1–218**. SHA-256 : `a736650afa299c710669edba96d92a45026402fdffd235d7e316f8fb7192f95b`.

<a id="ev03"></a>
### EV03 · Référentiels, dossiers, offres, formations, leçons

`api/prisma/schema.prisma`, lignes **219–368**. SHA-256 : `a736650afa299c710669edba96d92a45026402fdffd235d7e316f8fb7192f95b`.

<a id="ev04"></a>
### EV04 · Traces, évaluations, fautes, documents et médias

`api/prisma/schema.prisma`, lignes **369–473**. SHA-256 : `a736650afa299c710669edba96d92a45026402fdffd235d7e316f8fb7192f95b`.

<a id="ev05"></a>
### EV05 · Itinéraires, plusieurs modèles de compétences, disponibilités, prérequis, badges

`api/prisma/schema.prisma`, lignes **474–707**. SHA-256 : `a736650afa299c710669edba96d92a45026402fdffd235d7e316f8fb7192f95b`.

<a id="ev06"></a>
### EV06 · Routes de domaines effectivement enregistrées

`api/src/index.routes.ts`, lignes **1–49**. SHA-256 : `a2161b42576cd19031ff3cd513cfe5685c272567d6c469532536ff32277dd2a0`.

<a id="ev07"></a>
### EV07 · Création, modification, cycle de leçon, objectifs et indicateur payé

`api/src/services/lesson.service.ts`, lignes **1–319**. SHA-256 : `dab11245e0b51656b4507584e5bcd610d013d58530f9e5d1091a274394e22e2b`.

<a id="ev08"></a>
### EV08 · Recherche de conflits et transactions sérialisables

`api/src/repositories/lesson.repository.ts`, lignes **1–301**. SHA-256 : `56225260a7e2180f5f80b6d380eef506e6092b899807df6ca620cf11e3fb2e58`.

<a id="ev09"></a>
### EV09 · Fuseau fixe Europe/Zurich, intervalles, pauses, créneaux

`api/src/lib/scheduling.ts`, lignes **1–244**. SHA-256 : `e453600642e0253d0b3d611633a2a1d3ac693bef2ca4ecf895653a0f1a6f8282`.

<a id="ev10"></a>
### EV10 · Validation et identifiant de synchronisation

`api/src/services/lesson-sync.service.ts`, lignes **1–136**. SHA-256 : `f5e46db7944156049bbb7420cb448a200d78202d182da3cf54a5040f08ddcda5`.

<a id="ev11"></a>
### EV11 · Remplacement transactionnel de bilan et protection partielle des évaluations récentes

`api/src/repositories/lesson-sync.repository.ts`, lignes **1–200**. SHA-256 : `e0917b77c80b4b0ce2f8f4618953ebfca5c84ca8262adeaf002a9f2d3b35a6d5`.

<a id="ev12"></a>
### EV12 · Niveaux et normalisation du score

`api/src/services/competency-assessment.service.ts`, lignes **1–165**. SHA-256 : `0b7173a4c50d964e74a8c0b3ab824d2be19924d8c7940e63df2225ad58c231b5`.

<a id="ev13"></a>
### EV13 · Enregistrement et retrait de token, pas expédition dans ce service

`api/src/services/push.service.ts`, lignes **1–27**. SHA-256 : `ef09d7ad889f7961e0ea1463613606a1710cf706e179f3a579425948673dce6c`.

<a id="ev14"></a>
### EV14 · Brouillons, file durable, actions, conflits ; écritures JSON

`ios/Drivy/Core/Sync/PendingSyncStore.swift`, lignes **1–331**. SHA-256 : `a4e0b5ed96e0818f50a0f60cb3328760866754e8992c5fd17d10119ad90adc28`.

<a id="ev15"></a>
### EV15 · Navigation actuelle différente selon rôle

`ios/Drivy/Features/Shell/MainTabView.swift`, lignes **400–450**. SHA-256 : `2a9f0dcf7926bc7883be5e8f8ff65191b8010e11741ac16b5573416380f63c99`.

<a id="ev16"></a>
### EV16 · Affirmations de sécurité et questions de conformité à réexaminer

`docs/security-privacy.md`, lignes **1–104**. SHA-256 : `45b5cb896e67ee3970bd3ca1a906eb4fa043f2e6c9e8559213feb7873b8b7b9b`.

<a id="ev17"></a>
### EV17 · Hiérarchie documentaire annoncée et documents historiques

`docs/README.md`, lignes **1–29**. SHA-256 : `7ddfd383157ff5f121eb9ea1885168bae144f282f635d3e2388fdf784041bef2`.

<a id="ev18"></a>
### EV18 · Dépendances et scripts déclarés, non exécutés

`api/package.json`, lignes **1–44**. SHA-256 : `3435597a57f2cf08e3f5708f89fdd0090c21e4933e82ce47a52579ba6df04e3d`.

<a id="ev19"></a>
### EV19 · Accès aux documents et cycle média

`api/src/services/document.service.ts`, lignes **1–392**. SHA-256 : `5af5a0a2b0d5e20942feaa594bb0153989a1410d083ef142ca2e8ce6fa593f2d`.

<a id="ev20"></a>
### EV20 · Disponibilités, pauses et génération de créneaux

`api/src/services/availability.service.ts`, lignes **1–210**. SHA-256 : `9d93de70b5f74a7a7ad8e95dd5a7b5a9c400aed83b8161221f60bf3ea04c8999`.

<a id="ev21"></a>
### EV21 · Gestion des dossiers et permis

`api/src/services/student.service.ts`, lignes **1–400**. SHA-256 : `131f038ecf7bdc6c4183592b5dbba1306be0db7a2e908b61c83cc4df3657ea81`.

<a id="ev22"></a>
### EV22 · Conversation école-élève et messages

`api/src/services/chat.service.ts`, lignes **1–98**. SHA-256 : `ee49594195c6fb5aef4e949151307e4f8a28daae2d27a8e2f045bf197903a75b`.

<a id="ev23"></a>
### EV23 · Agrégations analytiques

`api/src/services/analytics.service.ts`, lignes **1–252**. SHA-256 : `beba806f1846bb46dbde43f75f0e8bea2250c0991f7609c9b095069032de3dae`.

<a id="ev24"></a>
### EV24 · Attribution et consultation des badges

`api/src/services/badge.service.ts`, lignes **1–39**. SHA-256 : `97a86b0c7f8740d055a82717a13f088fbc16a314b50954d233764544aa23bc57`.

<a id="ev25"></a>
### EV25 · Orchestration de la leçon en direct, GPS et évaluations

`ios/Drivy/Features/Instructor/LessonLiveViewModel.swift`, lignes **1–304**. SHA-256 : `5c87e9aa033c74b9a214bbc89f7de4d2521ae99d8e6bba6a471b1208b27289ab`.

<a id="ev26"></a>
### EV26 · Consultation des leçons et représentation de trajet

`ios/Drivy/Features/Lessons/LessonDetailView.swift`, lignes **1–750**. SHA-256 : `c0cf9d069c7c71bb3f9a0b44c98c6be44bba3d7854da54f83b9d174b82f48482`.

<a id="ev27"></a>
### EV27 · Capture et dépôt des pièces jointes

`ios/Drivy/Features/Shared/Attachments/LessonAttachmentsViewModel.swift`, lignes **1–370**. SHA-256 : `7260700523a4cf3e797ec698f2721850845c0fc88a1fa3213cb094d56bbbf87b`.

<a id="ev28"></a>
### EV28 · Paramétrage de marque dans l’ancienne interface

`ios/Drivy/Features/Settings/SchoolBrandingView.swift`, lignes **1–370**. SHA-256 : `b6355667c50618118eef0c0c8a6a66ef6aed69e4e6d1071dcbbe5b567cb888f6`.

<a id="ev29"></a>
### EV29 · Catalogue et statut des exigences de formation

`api/src/services/requirement.service.ts`, lignes **1–257**. SHA-256 : `f59577484031ff13f0437bd20e753cde132e83b8e20431df0c718bb612bca88d`.

<a id="ev30"></a>
### EV30 · Autorisation par appartenance et rôle

`api/src/lib/authz.ts`, lignes **1–17**. SHA-256 : `41c76cd04542de34ffc1cc279594d1d1b30dbfdf55ce7e7f1f1ed2e4cfaca2db`.


## Recommandation de migration de connaissance

Conserver les invariants métier justifiés, les cas limites et les exemples non personnels ; ne transférer automatiquement ni les composants visuels, ni les anciens statuts, ni les modèles de données. Les éventuelles données réelles suivent un processus de [migration séparé](../05-realisation/migration.md). La matrice suivante est l’inventaire raisonné des capacités identifiées, pas une certification d’exhaustivité de chaque chemin d’exécution.
