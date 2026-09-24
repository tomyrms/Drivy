# Migration éventuelle, conservation et transition

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

<a id="transition-code"></a>
## Refonte du code, distincte de la migration des données

Le dossier décrit la cible d’une **refonte demandée par le porteur**. Il ne constitue pas une liste de renommages à appliquer au dépôt actuel et ne garantit pas que 33 modèles existants deviennent mécaniquement le modèle cible. Un ancien test prouve au mieux un comportement de sa version, pas celui des nouveaux contrats.

| Élément existant | Traitement proposé | Preuve avant réutilisation |
|---|---|---|
| Navigation, écrans et identité visuelle | Ne pas reprendre automatiquement ; redessiner selon DA A et les parcours actuels | Correspondance écran/besoin et revue iPhone/iPad ; pas de parité écran par écran |
| Capture et événements pédagogiques live | Conserver le besoin ; examiner les composants Swift comme candidats, pas comme architecture imposée | Tests d’interruption, permissions, isolation du service et mapping explicite vers R46 |
| Modèles Prisma/DTO et endpoints | Construire le contrat cible sans renommage aveugle ; adapter seulement les composants compatibles | Matrice ancien champ → concept cible, clés d’école, états, autorisations et tests contractuels |
| Fonctions de calcul et helpers | Réutilisation sélective possible | Tests unitaires reproduits et revue des hypothèses métier |
| Tests existants | Réemployer les cas utiles, réécrire les fixtures/attendus divergents | Test lié à une règle actuelle, exécuté sur le nouveau composant ; pas de compteur hérité déclaré vert |
| Données, traces et bilans | Aucune suppression automatique au motif d’une refonte | Choix M0/M1/M2 ci-dessous, sauvegarde, mapping et restauration validés |

**Stratégie de transition proposée :** branche/dépôt de refonte et environnements isolés ; première tranche verticale à données fictives ; contrats et migrations versionnés ; répétition de la reprise sur copie autorisée ; décision de bascule par école avec sauvegarde/restauration testées. Aucun dual-write, basculement de production, reset de base ou import réel n’est autorisé par la livraison de ce ZIP. Ne pas faire pointer les deux clients sur des mutations incompatibles sans versionnement/adaptateur explicite.

Un registre de disposition doit nommer les composants réutilisés, remplacés ou abandonnés, avec justification et tests. Il reste **à produire sur le code réel au moment du développement** : cette archive contient de la documentation et un audit historique, pas les sources applicatives à modifier. L’ancien audit ne vaut pas examen d’un nouveau commit.

### Évolution du contrat de saisie pédagogique

Les observations LIVE utilisent les routes/entité existantes ; `draft_id` peut être nul avant constat, et auteur/provenance/instant/type/statut sont explicités. Les anciennes observations restent de provenance REVIEW si ces champs sont absents ; ne pas leur attribuer rétrospectivement un instant de saisie live. Avant une migration réelle, ajouter les champs, reprendre l’auteur depuis le brouillon de manière vérifiée, accepter les lectures transitoires nécessaires, puis déployer les producteurs et contraintes conditionnelles. Les snapshots publiés restent intacts et les niveaux de compétence ne sont pas convertis en statuts d’événement. Aucun SQL de migration n’a été exécuté ici.


## Ce qui est connu et inconnu

Le ZIP contient du code, des modèles et de la documentation, **pas un export exploitable et validé d’une base de production accompagné de ses fichiers et règles de conservation**. L’existence d’utilisateurs actifs, de données à conserver, d’un usage scolaire réel et d’une obligation de continuité n’a pas été vérifiée. Concevoir à neuf ne signifie donc ni « tout jeter » ni « migration forcément nécessaire ».

L’arbitrage Q02 décide entre : aucun utilisateur/donnée réelle à migrer, migration limitée de données utiles, ou transition de service actif. Aucune suppression de l’archive fournie n’est prévue. L’archive source reste intacte ; le nouveau dossier n’en redistribue pas les données ni le code comme s’ils étaient la nouvelle application.

## Trois scénarios de transition

**M0, expérimentation sans données réelles.** Conserver le dépôt ancien en lecture seule et son historique. Démarrer une base nouvelle avec fixtures ; ne pas importer des noms ou documents de démonstration comme des clients. Faire valider explicitement l’absence de besoin de migration, plutôt que la déduire de la petite taille du projet.

**M1, reprise utile sans service quotidien actif.** Exporter dossiers et fichiers autorisés, classer données connues et ambiguës, importer uniquement celles dont la correspondance est fiable, garder une archive privée consultable selon droits et rétention. Le nouveau système affiche la provenance et ne transforme pas des scores historiques en observations nouvellement validées.

**M2, service existant actif.** Inventaire complet, répétition en environnement isolé, rapprochement, plan de gel court des écritures ou passage par école, responsable d’autorité, support et repli. Ne pas faire de double écriture improvisée. Les rendez-vous futurs et règlements doivent être rapprochés avec l’école avant bascule.

## Inventaire à obtenir avant chiffrage

Demander propriétaire et emplacement de la base et du stockage, versions de schéma, nombres par école, utilisateurs réellement actifs, prochains rendez-vous, pièces orphelines, taille et checksum des objets, identités d’authentification, clés nécessaires, politique de données et source comptable officielle. L’accès doit être autorisé et limité ; pas de secrets dans ce dossier.

Produire un rapport à blanc par école : volume, qualité, doublons, formations manquantes, catégories inconnues, dates incohérentes, rôles, paiements sans montant et objets absents. Un comptage global ne révèle pas une mauvaise affectation de document entre élèves.

## Correspondances proposées, jamais conversion aveugle

| Source ancienne observée | Destination nouvelle | Transformation et condition | Valeur ambiguë |
|---|---|---|---|
| User / appartenance avec rôle unique | Person + IdentityLink + SchoolMembership + MembershipRole | Préserver liens scolaires, vérifier identité et correspondance OIDC | Ne pas fusionner deux personnes uniquement sur nom ou email ressemblant. |
| StudentProfile | LearnerProfile scolaire | Champs utiles minimaux ; conserver source id dans table de migration privée | Pas de données globales copiées dans toutes les écoles. |
| StudentLicenseEnrollment / SchoolLicenseOffering | Training + OfferingVersion | Catégorie et contexte confirmés ; offeringKey stable | Champs de permis globaux ne déterminent pas automatiquement la formation. |
| Lesson SCHEDULED | Lesson PLANNED | Vérifier formation, moniteur, instants et fuseau | Conflits listés et arbitrés, pas supprimés. |
| Lesson COMPLETED | Lesson COMPLETED + résultat importé | Conserver provenance, dates et author si fiables | Ne pas inventer heures réelles si seule durée prévue connue. |
| Lesson IN_PROGRESS / SYNCING | Cas de reprise à instruire | Consulter source/école, identifier données locales éventuelles | Ne pas convertir automatiquement en COMPLETED. |
| Évaluations, couleurs, notes /10 | Archive historique contextualisée | Conserver forme d’origine et interprétation connue | Aucune équivalence automatique vers DISCOVERING/GUIDED/INDEPENDENT. |
| Données pédagogiques validées explicitement | Révision de bilan importée ou archive liée | Approbation métier, auteur/provenance, marquage importé | Un texte absent n’est pas remplacé par un constat inventé. |
| `paid: true/false` | Statut historique à rapprocher | Conserver indication source ; rapprocher montant/charge avec preuve externe | `true` ne permet pas d’inventer encaissement, date ou mode ; `false` ne prouve pas une dette. |
| Documents et LessonAttachment | Document / référence de pièce | Autorisation, propriétaire, catégorie, checksum, recontrôle de fichier | Fichiers introuvables signalés, pas marqués READY. |
| Route / TrackPoint / itinéraires | Capture historique distincte si qualité et finalité vérifiées ; sinon archive privée limitée | Finalité, publication et conservation approuvées | Pas de consentement ou de précision inventés ; le cœur V2 traite les traces mais ne rend pas les anciennes automatiquement publiables. |
| Messages et indicateur staffReadAt | Archive de conversation si justifiée | Conserver portée et participants connus | Pas de fabrication de lectures individuelles. |
| Badges et anciens fonds | Archive, pas nouvelle fonctionnalité | Justification X consultable | Ne pas réintroduire via migration un écran écarté du produit. |
| Mots de passe / refresh tokens | Aucun transfert de secret client | Reprise OIDC validée ou réinvitation | Invalider anciennes sessions selon plan ; aucune copie de token vers la nouvelle app. |

La table décrit une intention de mapping, pas un script déjà compatible avec une base réelle. Les écarts du schéma exact exporté exigent un mapping versionné et une nouvelle revue.

## Préserver les inconnues au lieu de fabriquer des faits

Une ancienne leçon réalisée sans heure réelle connue peut être conservée dans une archive d’historique avec champs source et mention « heure réelle non renseignée ». Elle n’est pas forcée dans un endpoint CompleteLesson qui exige des heures réelles. De même, un ancien bilan sans les trois champs du nouveau modèle ne reçoit pas un texte générique présenté comme observation du moniteur.

Les archives importées restent typées `LegacyRecord` avec type de source, identifiant, école, personne/formation validées, instant d’import, hash et accès autorisé. Elles sont **hors du moteur de progression et du journal financier** tant qu’une réconciliation explicite n’a pas produit un objet nouveau valide. Leur interface de consultation n’entre dans le cœur pilote que si M1/M2 est retenu ; elle reçoit alors ses propres contrats et tests avant bascule. Cette branche n’est pas spécifiée comme déjà développable sans l’export réel.

## Procédure de reprise et validation

Copier export et objets dans une zone d’import chiffrée autorisée ; calculer empreintes ; analyser sans modifier les originaux ; produire mapping et exceptions ; faire approuver les décisions ; importer dans une base neuve ; vérifier clés étrangères et isolation ; rapprocher chiffres et échantillons avec l’école. Les opérations d’import sont idempotentes grâce à `(sourceSystem, sourceId, importVersion, schoolId)` et ne créent pas de doublons lors d’une répétition.

Contrôler tous les comptes par école, nombres de dossiers et de formations, prochains rendez-vous, collisions, références de fichiers et hashes. Sur les règlements, rapprocher chaque montant et absence de montant, pas seulement somme générale. Tester les accès avec comptes des trois rôles et une école distincte. Valider les traces d’import qui permettent d’expliquer l’origine sans exposer un export complet à chaque utilisateur.

Le traitement des données futures et des catégories non activées doit être décidé avant l’import : une leçon déjà fixée pour une offre non prise en charge ne peut pas disparaître. Soit activer cette catégorie après référentiel validé, soit conserver l’ancien outil comme autorité jusqu’à la prise en charge, avec limites annoncées.

## Bascule et retour arrière

Pour M2, convenir d’un instant ou lot scolaire où l’ancien système arrête d’accepter des mutations. Exporter le delta, rapprocher puis activer le nouveau. Tester les liens d’invitation, les accès et les confirmations ; empêcher le renvoi massif de tous les emails historiques. Garder l’ancien en lecture seule selon autorisation et rétention, pas exposé publiquement.

Un repli avant nouvelles écritures peut revenir à l’ancien point d’autorité vérifié. Après nouvelles écritures, le repli exige export/réconciliation des rendez-vous, bilans et règlements ajoutés ; il n’est pas instantané ni sans perte par simple restauration d’un ZIP. Informer l’école et ne pas laisser les deux systèmes prendre des réservations concurrentes sans mécanisme qualifié.

## Critères de passage

Propriétaire des données et scénario validés ; mapping documenté ; exceptions bloquantes résolues ou explicitement maintenues hors bascule ; zéro référence inter-écoles ; tous rendez-vous futurs rapprochés ; paiements sans preuve non transformés en faits ; pièces contrôlées ; droits et retour arrière testés ; export original conservé selon politique et accès restreint. En l’absence de ces preuves, la conception peut continuer, mais la migration réelle ne doit pas être lancée.

## Migration V2 et coexistence

Les données de l’archive ne prouvent pas l’accord à une nouvelle finalité de replay ni la qualité d’un ancien trajet. Les captures importées portent source LEGACY, qualité inconnue explicitement, horodatages originaux et audience restreinte jusqu’à décision. Ne pas reconstruire une précision ou un segment manquant comme une mesure certaine.

Le catalogue peut être initialisé depuis des conditions validées par l’école, pas depuis des tarifs web importés automatiquement. Les anciens marqueurs « payé » exigent rapprochement avant création de comptes/encaissements ; pas de pack supposé à partir d’un nombre de leçons. Les soldes de droits d’ouverture demandent justification et auteur.

Les cours annoncés hors app et leurs participants peuvent être saisis sous demande réelle et même contrôle de capacité. Un export WhatsApp n’est pas un accord GPS, une inscription marketing ni une présence. Vérifier les doublons d’élèves, les confirmations réelles et les dates avant bascule. Pendant coexistence, un seul registre est maître de la capacité ; pas deux stocks de places indépendants.

Répéter la migration sur fixtures et environnement de préparation ; rapprocher nombres de personnes/formations, engagements, inscriptions, droits, comptes et traces autorisées. Le repli doit empêcher des commandes concurrentes entre ancien et nouveau systèmes. Aucun import réel ni modification du ZIP d’origine n’est réalisé par ce dossier.

## Reprise V3 des profils et états

Les données anciennes conservent leur provenance. Ne pas découper automatiquement un displayName en prénom/nom légal sans confirmation ; stocker le nom d’affichage et demander les champs réellement utiles à la personne. Date de naissance inconnue reste null, pas01.01 d’une année inventée ; une photo ancienne ne devient pas pièce de permis.

Un ancien élève marqué inactif peut signifier archive, accès révoqué, formation terminée ou simple filtre : examiner le sens réel avant mapping. Ne pas révoquer Membership à partir d’un seul champ d’archive ; ne pas non plus rendre un accès historiquement révoqué à la restauration. Soldes/achats/droits sont réconciliés explicitement avant archive et statistiques.

Onboarding peut être initialisé avec étapes déjà vérifiées et manques identifiés, sans marquer consentement ni profil complet par défaut. Une nouvelle politique demande uniquement les compléments nécessaires. Les anciennes captures gardent précision/provenance inconnues lorsqu’elles ne sont pas documentées ; ne pas inventer un diagnostic tablette QUALIFIED pour les rendre compatibles.

Avant métriques, tester dates, statuts terminaux, charge réelle et PaymentEntry unique pour éviter doublons de comptes/pack. Les importations sans horaires réels sont signalées incomplètes, pas remplies depuis trace ou durée annoncée. Les données réelles, utilisateurs existants et migration nécessaire ne sont pas prouvés par la présence de l’archive source.


## Compatibilité documentaire 3.2 vers 3.5

La documentation ne migre aucune base réelle. Pour une éventuelle reprise, plannedWaypoints est initialisé [] si aucun repère structuré n’existe. teachingLanguage ne se déduit pas du canton, du nom ou de l’adresse : l’école confirme la valeur ou la série reste à réviser avant usage des actions qui la requièrent. Les anciens permis dépourvus de preuve ne deviennent pas approuvés pour satisfaire le nouveau schéma. Les demandes globales de suppression sont de nouvelles entités, distinctes des demandes scolaires ; ne pas fusionner leur portée par simple égalité d’email. Le plan de migration reste soumis aux données réellement présentes et aux obligations de conservation.

## Adaptation documentaire V3.6, sans migration exécutée

Les anciens bilans sans `textObservations` peuvent être lus comme liste absente historiquement, puis [] dans une projection compatible ; ne pas extraire automatiquement les textes de snapshots GPS privés. Les segments historiques à zéro point doivent être examinés : une séquence zéro ne prouve pas un point. Ne corriger que sous manifeste vérifié.

Pour une nouvelle version d’offre, saisir les lignes de prix et les suppléments d’options. Une ancienne vente garde son total et son snapshot ; ne pas inventer des montants d’options historiques. L’absence de décomposition peut être affichée comme « historique non détaillé », pas reconstruite depuis la grille courante. Les exemples de lignes tarifaires du dossier sont fictifs, jamais une preuve de décomposition commerciale historique. Les adaptations SC107/SC108 concernent uniquement des manifestes de test, pas des captures réelles.

Initialiser les préférences absentes par migration explicitement versionnée et conserver les choix existants ; jamais par un GET créant une acceptation. Les séries déjà closes avec HOLD non résolu nécessitent une revue administrative, pas une consommation automatique. Aucune migration SQL ni modification des utilisateurs réels n’a été exécutée.

## Migration éventuelle du contrat V3.6 vers V3.7

Aucun serveur n’est migré par ce dossier. Si des données réelles existent lors de l’implémentation : ajouter `rightSettlement=null` aux inscriptions sans événement de régularisation identifié, ne pas créer des débits rétroactifs. Les anciens cycles/prix/consommations restent intacts. Reconstituer une basis de validation uniquement à partir de preuves effectivement identifiées ; faute de source/cycle/contrôleur, classer à revoir plutôt qu’inventer une attestation. Les décisions historiques sont conservées sous leur niveau de preuve original, avec validation humaine avant conversion en décision actuelle.

Les anciennes registrations sans environnement fiable ne reçoivent pas arbitrairement APNS_PRODUCTION : désactiver leur routage jusqu’à réinscription native explicite ou migration prouvée depuis la configuration de déploiement. Le centre interne continue de fonctionner. La nouvelle exigence `sourceEnrollmentCycle` et les champs de projection imposent un client cohérent avec le contrat complet 3.10.0, pas un mélange d’anciens DTO.

## Compatibilité documentaire V3.10

Le contrat 3.10.0 complète les tickets (méthode et en-têtes contraints), les READY de pièces/logos et les métadonnées de l’export. Aucun serveur n’est prétendu migré. Un ancien READY dont les octets exacts, le type ou le contrôle ne sont pas prouvés ne reçoit pas ces preuves par défaut : requalification/reconstruction documentée ou indisponibilité explicite jusqu’à contrôle, avec information des références affectées. Ne pas utiliser un nom de fichier ou l’extension pour inventer detectedMime.

Les anciens exports sont régénérés avant d’offrir les métadonnées obligatoires ; ne pas inventer taille/hash. Une intention existante sans scellement démontré est drainée/refusée avant adoption du nouveau profil ; aucun nouveau ticket écrasable ne doit viser un READY. Évaluer impacts et conserver les preuves utiles sans prolonger arbitrairement leur conservation.
