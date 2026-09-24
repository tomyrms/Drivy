# Audit et consolidation : Drivy V3.5 vers V3.6

> **19 septembre 2026 · Référence 3.6** · [Index](../README.md) · [Fonctionnalités prévues](../01-fonctionnalites-prevues.md)
> Audit de documentation et de contrats. Aucun code applicatif modifié ; aucun build, trajet réel ou test de base de données exécuté.

<a id="apports"></a>
## Résultat

La V3.6 remplace la V3.5. Elle corrige ou complète **huit ensembles de constats**, dont certains portent sur plusieurs documents. Ce ne sont ni huit bugs reproduits dans l’ancienne application, ni un certificat d’absence de défauts. Les références fonctionnelles, les contrats, les modèles, les transactions, les écrans, le catalogue et les scénarios concernés ont été modifiés ensemble.

**Décisions conservées :** Drivy sans e, Swift natif iPhone/iPad, GPS et exploitation pédagogique centraux mais capture facultative, tablette à part entière, gestion web détaillée, Android futur distinct, offres configurables, onboarding progressif et cours collectifs avec inscription volontaire. Le nouveau contrat ne reconduit aucune dépendance mobile à un runtime JavaScript.

## Base, méthode et limites de couverture

Le ZIP source complet est `Drivy_Dossier_Conception_v3_5_2026-09-19.zip`, identifié par son empreinte dans la [provenance](../annexes/provenance-v3-6.json). L’archive a été extraite dans une source conservée, puis copiée pour modification. Les **cinq vérificateurs antérieurs ont réellement été exécutés sur la V3.5 et ont réussi** : [résultats initiaux](../annexes/controle-v3-5-avant-correction.json). Ils ne vérifiaient donc pas les lacunes exposées ci-dessous.

Le contrôle structurel parcourt tous les Markdown, liens et artefacts référencés ; la revue sémantique croise les domaines et leurs jonctions, notamment : publication sans GPS, arrêt sans mesure, clôture de cours/droits, prix/remise de service, identité/révocation et états initiaux. L’[inventaire de couverture](../annexes/inventaire-audit-v3-6.json) distingue références actives, historiques, données de contrôle et fichiers dérivés. Il n’affirme pas une nouvelle validation de chaque phrase commerciale ou juridique historique.

Les trois parcours de référence sont relus comme des suites d’états et de contrats : **leçon individuelle**, **cours collectif**, **gestion/archivage/suppression**. Les scénarios ajoutés couvrent reprises, conflits, absence de réseau, absence de droits et absence de données. Les scénarios écrits ne sont pas des simulations d’application exécutées.

Les sources externes reconsultées portent sur les exigences Apple de suppression, les verrous PostgreSQL et les versions Apple. Les tarifs des dix écoles et les profils réglementaires scolaires restent des observations datées : pas de nouvelle enquête commerciale, pas de délais légaux inventés. Les références historiques à d’anciens frameworks restent comme provenance, pas comme pile actuelle.

Les [preuves avant correction](../annexes/preuves-audit-v3-6.json) contiennent les chemins, lignes, extraits et empreintes **de la V3.5**. Ces numéros ne doivent pas être utilisés comme les lignes du document corrigé. Le [diff de référence](../annexes/corrections-v3-5-vers-v3-6.patch) permet de comparer les textes et le contrat sans confondre documents générés et sources.

## Constats et corrections

### V36-01 · Publier les observations d’une leçon sans GPS

**Nature :** fonctionnalité promise mais incomplètement contractée. **Importance : élevée**, car la leçon sans enregistrement doit conserver sa valeur pédagogique.

**Preuve V3.5 :** `bilans-documents.md`, ligne 94, autorise une annotation textuelle sans géolocalisation. `PublishCommand` et `ReportRevision` ne matérialisent pourtant la sélection d’observations que via `CaptureSelection` et une capture. La présence d’un commentaire libre dans un bilan ne résout pas le devenir des observations distinctes déjà saisies dans le brouillon.

**Scénario :** le moniteur termine une leçon sans GPS, ajoute deux observations liées à des compétences, puis publie le bilan. Un client ne doit ni supprimer ces observations ni créer une fausse capture pour les transmettre.

**Correction :** `PublishCommand.textObservationSelection` explicite les identifiants et versions, y compris une liste vide. `ReportRevision.textObservations` contient les copies autonomes. Le serveur vérifie auteur, droits, leçon, brouillon, version et absence d’ancrage. Un doublon d’identifiant reste interdit même lorsque les versions diffèrent. Les ancrages ne sont jamais retirés silencieusement pour contourner un refus de partage.

La sélection GPS reste séparée. L’ensemble est publié atomiquement. Retirer le trajet n’efface pas automatiquement le bilan textuel autonome autorisé ; une demande de suppression des données du bilan reste applicable. Un texte peut mentionner un lieu : il n’est pas réputé anonyme pour autant.

**Références :** [F08](../03-fonctionnel/bilans-documents.md#f08), [R46](../03-fonctionnel/regles-etats.md#r46), [transaction textuelle](../04-technique/transactions-v2.md#publication-textuelle), API, modèle, E08/E09, J13 et client Swift.

**Vérification :** T311–T315 et T349 à exécuter ; SC143–SC149 contrôlent uniquement la forme du contrat. Aucun test de publication sur serveur n’est revendiqué.

### V36-02 · Arrêter une capture avant le premier point

**Nature :** contradiction d’état et de schéma. **Importance : élevée** pour représenter honnêtement une interruption ou un signal absent.

**Preuve V3.5 :** `SegmentManifest` autorise `expectedPointCount=0`, mais impose un entier positif ou nul à `lastSequence`, sans préciser le sens d’une séquence sur un segment vide. La même forme permet d’annoncer des points sans chunk.

**Scénario :** le moniteur démarre puis arrête avant la première position exploitable. Forcer `lastSequence=0` ferait croire qu’un point de séquence zéro existe.

**Correction :** zéro point implique `lastSequence=null` et aucun chunk attendu. Un segment contenant des points exige un entier de séquence et au moins un chunk. Aucune ouverture de segment donne une liste de segments vide. Un manifeste sans point peut être transféré intégralement ; cela ne qualifie pas un trajet comme enregistré avec succès. Les sommes, ordres et identités restent des validations du service.

**Références :** [GPS](../03-fonctionnel/gps-replay.md), [R43](../03-fonctionnel/regles-etats.md#r43), synchronisation, modèle, architecture Swift, E23 et OpenAPI.

**Vérification :** T316–T318 et T346 à exécuter ; SC150–SC155 rejouent les cas vides et non vides. Le GPS physique n’est pas testé.

### V36-03 · Clôturer un cours où un droit n’a jamais été consommé

**Nature :** transition incomplète entre présence, droit réservé et clôture. **Importance : élevée** : un HOLD résiduel peut empêcher l’usage du pack ou l’archivage.

**Preuve V3.5 :** la consommation du cours est déclenchée au premier PRESENT ; la clôture AP138 ne reçoit qu’un motif. Le cas où toutes les présences ont été renseignées sans aucun PRESENT ne dispose pas d’une décision explicite sur le HOLD restant.

**Scénario :** l’élève a réservé avec son pack mais est absent à tous les blocs. La série se termine. Elle ne doit ni fabriquer une présence pour solder le droit ni rester indéfiniment liée à un crédit réservé sans issue.

**Correction proposée R106 :** la clôture expose les HOLD non consommés ; le personnel choisit explicitement leur libération. `CloseCourseCommand` transmet la liste exacte avec cycles, versions, motif et mouvement source. Le commit vérifie qu’aucune présence n’a changé, que toutes les occurrences sont terminées et que les droits supplémentaires de libération sont présents. Série et mouvements changent ensemble, ou pas du tout.

La libération du droit n’est ni un remboursement ni une exonération automatique de frais : les obligations financières gardent leur processus. **Cette politique est une proposition de résolution, à approuver par les écoles.** Une règle différente exige un parcours commercial explicite, pas un autre libellé de présence.

**Limite rendue visible :** corriger ensuite une absence en présence, après libération, nécessite de réconcilier les droits. Le service refuse de recréer silencieusement une consommation. Le parcours exceptionnel complet reste à décider avant d’autoriser cette correction dans cette situation ; il n’est pas présenté comme résolu par un simple changement de champ.

**Références :** [F18](../03-fonctionnel/cours-collectifs.md#f18), [R106](../03-fonctionnel/regles-etats.md#r106), [packs](../03-fonctionnel/catalogue-packs.md), transactions, permissions, archivage, E28/J17.

**Vérification :** T319–T323 et T350 à exécuter, SC163–SC169 pour les commandes. Aucun essai concurrent de présence/clôture effectué.

### V36-04 · Remettre un accès théorique ou constater l’accompagnement à l’examen

**Nature :** fonction commerciale annoncée sans opération complète. **Importance : élevée** pour les packs composites étudiés.

**Preuve V3.5 :** `catalogue-packs.md`, lignes 24 et 42, décrit un service externe à remettre et la consommation d’un droit d’examen au constat réel. Les opérations de droits ne fournissent pas la remise directe de ces deux types indépendamment d’une leçon ou d’une présence de cours.

**Scénario :** une école remet l’accès théorique inclus dans le pack. Elle doit pouvoir l’indiquer sans inventer un rendez-vous de conduite, un paiement supplémentaire ou un résultat pédagogique.

**Correction :** AP199 constate une remise manuelle pour `EXTERNAL_SERVICE` ou `EXAM_SUPPORT`. La quantité, date réelle et confirmation sont contrôlées ; le serveur déduit acteur, élève et école du lot et de la session. Le journal conserve une preuve minimale de consommation, sans mot de passe ni code d’accès externe. Une répétition de la même commande ne débite pas deux fois. La restauration motivée utilise AP114 avec ses bornes.

Cela complète le décompte du droit, **pas la réservation d’un examen officiel ni l’intégration automatique du fournisseur théorique**. Aucune leçon n’est ajoutée aux statistiques ; aucun encaissement n’est créé.

**Références :** [F17](../03-fonctionnel/catalogue-packs.md#f17), [R107](../03-fonctionnel/regles-etats.md#r107), AP199, modèle, permissions, transactions, E30/J18 et statistiques.

**Vérification :** T324–T328 à exécuter et SC156–SC162. L’envoi d’un accès réel ou une prestation d’examen n’ont pas été exécutés.

### V36-05 · Expliquer le prix d’un pack et ses options

**Nature :** prix accepté insuffisamment représenté. **Importance : élevée** pour éviter qu’un développeur invente la tarification.

**Preuve V3.5 :** le catalogue annonce options, frais ponctuels et prix exceptionnel motivé (lignes 18 et 67). Le contrat contient des composants et un total, sans prix par groupe d’option, décomposition de base ni dérogation explicite à l’achat.

**Scénario :** deux prestations optionnelles appartiennent au même supplément « premiers secours ». Le supplément doit être appliqué une fois, pas une fois par composant ; une inscription offerte ne doit pas donner une leçon supplémentaire.

**Correction proposée R108 :** prix de base détaillé en lignes signées ; un supplément non négatif par clé d’option, éventuellement nul ; calcul serveur du prix catalogue sélectionné ; dérogation motivée réservée à ADMIN dans le profil proposé. L’achat fige lignes de base, prix d’options choisies, total catalogue et total convenu. Les remises informatives ne sont pas recomptées. Les droits naissent des composants, pas des lignes de prix.

La cohérence des sommes et des clés relève du serveur. Les tableaux uniques en JSON ne suffisent pas à détecter deux objets de même clé et de montants différents. Les versions historiques de prix ne sont pas recomposées depuis le catalogue courant.

**Limite :** les frais automatiques dépendant d’un événement tel que la deuxième leçon ne sont pas un moteur implémenté dans ce contrat. Une école peut définir une offre explicite ou traiter un ajustement autorisé, mais l’onboarding ne doit pas promettre une automatisation absente.

**Références :** [R108](../03-fonctionnel/regles-etats.md#r108), catalogue/paiements/onboarding, AP103/AP109/AP110, modèle, E29, migration et roadmap.

**Vérification :** T329–T333 et T347 à exécuter ; SC170–SC175 ; **14 cas de calcul documentaire isolé**, avec sommes attendues et refus indépendants. Ce modèle Python n’est pas le code du serveur ni un test d’encaissement.

### V36-06 · Demander la suppression globale sans blocage caché

**Nature :** lacune d’échelle, contradiction de procédure et précision de concurrence. **Importance : élevée** pour l’accès à la suppression et l’administration de l’école.

**Preuve V3.5 :** l’aperçu est borné à 100 appartenances et le texte renvoie les cas plus grands vers une assistance ; les garde-fous du dernier ADMIN étaient formulés trop tardivement par rapport à PROCESSING. Plusieurs descriptions abrégées des verrous commençaient à l’école alors que la clôture globale nécessite une porte d’accès d’identité.

**Scénarios :** une personne liée à 101 écoles souhaite déposer sa demande ; un dernier ADMIN passe en traitement et perd sa session avant que la continuité scolaire soit résolue ; une inscription lit les droits puis attend tandis que la suppression les révoque.

**Corrections :**

- L’aperçu donne un total et un curseur ; AP200 permet sa lecture paginée. La confirmation porte sur le manifeste complet côté serveur, pas seulement sur la page visible. Aucun appel au support n’est imposé pour dépasser 100 écoles.
- Le cas du dernier ADMIN se résout **avant PROCESSING** : maintien en revue, information de suivi, succession acceptée ou clôture scolaire dûment autorisée. Une demande reste possible ; le support n’est pas promu propriétaire et un blocage indéfini non expliqué n’est pas une politique.
- L’ordre commun commence par les personnes concernées, puis écoles, appartenances et agrégats. Les commandes ordinaires et le passage ACTIVE→CLOSING se coordonnent par des modes de verrou incompatibles. Les modes d’écriture nécessaires sont acquis d’emblée, sans promotion tardive. Les tâches internes ont un mandat restreint, pas une session ordinaire de la personne supprimée.

Apple distingue une demande dans l’app d’un traitement manuel interne : la confirmation de suppression peut prendre du temps, mais une procédure générale ne doit pas imposer un appel ou un email au support. Aucune exemption sectorielle de Drivy n’a été établie. [S110](sources.md#s110). Les verrous décrivent une stratégie à vérifier sur PostgreSQL, pas une garantie obtenue par lecture de documentation. [S108](sources.md#s108).

**Références :** [suppression globale](../03-fonctionnel/compte-suppression-globale.md), [ordre de commit](../04-technique/transactions-v2.md#autorisation-et-commit), modèle, transactions V3, E49/J29 et guide mobile.

**Vérification :** T334–T340 et T348 à exécuter, SC176–SC182. La procédure DM06, les délais et les rétentions restent à approuver avant publication.

### V36-07 · Définir un état initial sans inventer un consentement

**Nature :** initialisation incomplète. **Importance : moyenne à élevée** selon la portée des notifications et de la capture.

**Preuve V3.5 :** la modification des préférences est versionnée, sans création initiale suffisamment explicite ; un RecordingChoice complet exige une source alors qu’aucune déclaration n’a nécessairement été recueillie.

**Correction :** une nouvelle appartenance initialise ses préférences en version 1 ; les lectures n’en créent pas implicitement. Proposition initiale : offres visibles dans le centre interne, quatre préférences externes désactivées, modification explicite à l’onboarding. Les choix existants à migrer ne sont pas écrasés par ces valeurs.

Sans choix GPS enregistré, AP152 renvoie un état d’absence `RECORDING_CHOICE_NOT_SET` après vérification des droits. Aucun événement SELF ou VERBAL n’est fabriqué. L’autorisation système du téléphone ne vaut toujours pas accord pédagogique. Une phrase résiduelle promettant un filtre de site a également été alignée : site affichable ; filtre de langue réellement contracté ; aucun ciblage privé déduit des trajets.

**Références :** onboarding, calendrier/notifications, modèle, R70/R101, AP152, transaction initiale et E42.

**Vérification :** T341–T344 à exécuter. Les valeurs initiales sont une recommandation de produit, pas une exigence légale présentée comme universelle.

### V36-08 · Faire correspondre la référence active aux contrôles

**Nature :** cohérence documentaire et provenance. **Importance : moyenne**, mais le risque d’implémenter une instruction abandonnée est réel.

**Preuve V3.5 :** le registre structuré de traçabilité portait encore une version 3.4 ; une formulation active de synchronisation citait le runtime JS en arrière-plan alors que Swift était confirmé. Le guide mobile conservait aussi deux sections successives de suppression : l’une décrivait les routes globales, l’autre disait encore que le contrat était absent. Les scripts antérieurs ne détectaient pas ces contradictions.

**Correction :** versions document/contrat explicites, registre 3.6, description du processus Swift natif, une seule section mobile de suppression indiquant les routes existantes et les validations encore manquantes, catalogue enrichi de ses dépendances et limites, contrôles courants séparés des anciens, lecteur régénéré avec indication d’historique pour les journaux antérieurs. Les contenus historiques ne sont pas réécrits comme s’ils avaient toujours décrit Swift.

Les nouvelles données et commandes ne créent pas artificiellement de fonctionnalités de haut niveau : F01–F23 restent les mêmes. R106–R108, AP199–AP200 et T311–T350 sont ajoutés aux registres avec liens réciproques. Le nombre de liens n’est jamais présenté comme une mesure de qualité produit.

**Vérification :** contrôles de fichiers et registre, T345 à exécuter côté intégration. Aucun compilateur Swift n’est invoqué.

## Fidélité à l’intention et statut des fonctionnalités

Le [catalogue](../01-fonctionnalites-prevues.md) conserve les rôles, supports, phases et limites de F01–F23 et distingue cœur, extensions et exclusions. Il ajoute les dépendances et les propositions qui restent à approuver. Le besoin d’adaptation des écoles est conservé sans affirmer que toutes les offres observées disposent d’un moteur automatique sur mesure.

Le GPS n’est ni retiré du cœur ni imposé à chaque leçon. Les observations textuelles autonomes rendent la voie sans capture plus cohérente. La publication d’un cours, sa notification et son inscription restent trois étapes distinctes. Les nouvelles remises et libérations de droits ne produisent pas de présences, d’encaissements ou de compétences fictives.

Les écrans existants sont complétés plutôt que multipliés. Aucun chatbot, classement d’aptitude automatique, navigation guidée ou surveillance continue n’a été ajouté. Les noms de technologies ne servent pas de preuve de fluidité ou de qualité d’interface.

<a id="decisions"></a>
## Arbitrages et incomplétudes restant visibles

| Point | Qualification | Conséquence avant réalisation ou disponibilité |
|---|---|---|
| Swift natif Apple | **Décision utilisateur acceptée** | Ne pas rouvrir le choix d’un framework partagé. Les outils et bibliothèques précis restent à qualifier. |
| GPS démarré avec autorisation en ligne | Choix d’architecture proposé, pas limitation matérielle universelle | Valider les lieux de départ et l’accès réseau. Préautorisation hors ligne éventuelle à concevoir séparément. |
| Une capture par bilan publié | Limite actuelle du contrat | Plusieurs captures séquentielles ne sont pas fusionnées automatiquement. Décider si le premier pilote doit couvrir cet assemblage. |
| Palette commune, français initial, collecte individuelle voiture | Périmètre proposé, non exigence nouvelle du porteur | Vérifier les attentes des écoles ; aucune couleur configurable ou trace de groupe n’est promise implicitement. |
| R106 : libération après absence totale | Politique commerciale proposée | Faire approuver la règle. Après libération, une correction tardive de présence exige une résolution explicite des droits ; parcours exceptionnel encore incomplet. |
| R107 : remise manuelle | Complément de la fonction de pack | La consommation du droit est définie ; réservation d’examen officiel et accès fournisseur automatiques ne le sont pas. |
| R108 : base/options/dérogation ADMIN | Modèle tarifaire proposé | Validation des conventions de prix et des habilitations ; frais conditionnels automatiques et promotions complexes restent hors moteur courant. |
| Préférences externes initialement désactivées | Proposition prudente, pas règle légale alléguée | Tester la compréhension de l’onboarding et le choix des canaux sans forcer le GPS ou une inscription. |
| DM06 : suppression globale et dernier ADMIN | Contrats complétés, exploitation non qualifiée | Désigner responsables, délais, rétentions justifiées, mandat de clôture scolaire et fournisseur. Ne pas publier tant que ce parcours est impraticable. |
| iOS/iPadOS 26 et 27 | Versions étudiées, aucune combinaison Drivy qualifiée | Relevé Apple S109 : publication 27 distincte des bêtas ; SDK, Xcode, hôte et minimum utilisateurs restent séparés. Binaire et appareils à éprouver. |
| Android | Client futur distinct | Ressources et qualification GA0 avant son lancement ; aucune compilation Apple ne prouve le support Android. |
| Tests natifs, concurrence, sauvegarde et sécurité | Preuves manquantes, pas simples choix documentaires | Exécuter la tranche verticale et les cas de refus sur appareils/services réels. |

Les garanties réglementaires et commerciales ne sont pas établies par un schéma. En particulier, aucun délai de rétention universel, aucune politique de remboursement ou performance batterie n’a été inventé pour fermer un point ouvert.

## Contrat, données et migration

Le contrat passe à **3.6.0 avant implémentation**. Les clients doivent prendre le fichier complet : PublishCommand, SegmentManifest, CloseCourseCommand, PackOffer/Purchase et AccountDeletionPreview changent. Les nouvelles AP199/AP200 ne remplacent aucune route historique existante.

Une migration ne peut pas déduire d’anciennes options tarifaires ou une source d’accord GPS absente. Les règles de migration conservent les prix effectivement connus et exigent une validation des offres nouvelles plutôt qu’une reconstitution fictive. Une liste vide d’observations autonomes signifie « aucun snapshot autonome migré », pas « aucune observation n’avait jamais existé ».

Les données de test sont fictives. Les anciens rapports et schémas restent comme comparaison, non comme contrats de compatibilité automatique. La génération Swift devra notamment préserver null/absence/valeur et les cas de confirmation en cours.

## Contrôles exécutés et limites de preuve

La [revue de cohérence](revue-coherence.md) donne les commandes reproductibles et résultats courants. Le contrôle de forme couvre **182 cas de schéma**, dont 40 nouveaux. Dans la [comparaison](../annexes/comparaison-contrats-v3-5-v3-6.json), **six mêmes exemples indésirables acceptés par le contrat V3.5 sont refusés par le contrat V3.6**. Les objets nouvellement créés sont distingués : un type inexistant auparavant n’est pas présenté comme une donnée auparavant autorisée.

Les **14 cas de modèle de prix** exécutent une interprétation isolée de R108, pas l’application. Les contrôles structuraux et comparaisons n’exercent ni un middleware d’autorisation, ni une transaction, ni le GPS, ni un fournisseur de compte.

Les **350 scénarios métier et 52 scénarios mobile/UX** restent **NOT_EXECUTED**. Six lignes de matrice appareil/build restent **NOT_QUALIFIED**. Le lecteur HTML est vérifié dans Chromium avec des tailles de fenêtre simulées, distinctement de la future UI native.

Un validateur intégral du méta-schéma OpenAPI n’a pas pu être installé dans cet environnement. Les contrôles JSON Schema, références, routes, paramètres et exemples disponibles sont exécutés ; ils ne doivent pas être décrits comme une certification complète OpenAPI ou une compatibilité Swift démontrée.

**Conclusion de revue :** les écarts établis sont corrigés dans la référence et plusieurs fonctions ont désormais une transition concrète. Le produit exige encore des arbitrages précis et des essais réels. Cette version n’est pas déclarée parfaite ou prête à publier sur la seule base des contrôles documentaires.
