# Validation finale : manifeste de vague (#84)

Vague ouverte le 21 octobre 2026. Les tests sont écrits avec le code. Leur exécution complète a lieu à la fin.

## Mode vague (IPA seulement)

- Aucun workflow modifié.
- Les push de `refonte-checks`, `school-opening-e2e` et `ipa-essai` ne se déclenchent que sur `master`, `codex/**` et `claude/**`.
- Les branches de vague `vague/**` et `openai/**` ne lancent donc aucune suite au push.
- IPA à la demande : `gh workflow run ipa-essai.yml --ref <branche>`.
- Pas de PR vers `master` avant la campagne finale. Un `pull_request` lancerait `refonte-checks` et l'e2e.
- Pas de `[skip ci]`.
- Restauration : rien à restaurer. Les déclencheurs normaux sont intacts.

Une IPA compilée prouve la construction. Elle ne prouve ni le fonctionnement ni les tests.

## Matrice

États : `PASS`, `FAIL`, `BLOCKED`, `NOT_EXECUTED`, `DEFERRED`.

| Issue | Critère | Commits | Preuve | Résultat | Point restant |
| --- | --- | --- | --- | --- | --- |
| #37 | Epic cours collectifs | | | NOT_EXECUTED | Campagne finale |
| #38 | Création et publication de séries | 7c3bcef, efc6a85 | API : 11 tests ciblés en local ; web : typage + 35 tests ; IPA compilée run 39940836151 | NOT_EXECUTED | Campagne finale |
| #39 | Inscription à toute la série | 3d911b8, af10b48, 4d9c4ae, 9109b74 | API : tests ciblés en local ; web : typage + 40 tests ; IPA run 40039016177 | NOT_EXECUTED | Campagne finale |
| #40 | Liste d'attente prioritaire | idem #39 | idem #39 | NOT_EXECUTED | Valeurs 2 h / 30 min / 12 h provisoires ; campagne finale |
| #41 | Annulation et délai | idem #39 | idem #39 | NOT_EXECUTED | Changement d'heure à tester ; campagne finale |
| #42 | Présences | 3056515, a419e90, f1f726f | API : tests ciblés en local ; web : typage + 47 tests ; IPA run 40118350531 | NOT_EXECUTED | Campagne finale |
| #43 | Rappels et alerte minimum | | | NOT_EXECUTED | Campagne finale |
| #44 | Préférences push | | | NOT_EXECUTED | Campagne finale |
| #45 | Finance future | | | DEFERRED | Différée par sa description |
| #63 | Audio IA premium | | | DEFERRED | Différée par sa description |
| #79 | Cadrage cours | | `docs/implementation/cours-collectifs-cadrage-79.md` | NOT_EXECUTED | Revue du porteur |
| #80 | Socle cours (migration 042) | 7c3bcef | Migrations 001 à 042 appliquées en local par le harnais | NOT_EXECUTED | Tests PostgreSQL |
| #81 | Règlement sur place | idem #42 | idem #42 | NOT_EXECUTED | Campagne finale |
| #82 | Validation finale explicite | idem #42 | idem #42 | NOT_EXECUTED | Campagne finale |
| #83 | Recette cours collectifs | | | NOT_EXECUTED | Campagne finale |
| #85 | Attribution Apple Plans visible (fermée, reste couverte) | | | NOT_EXECUTED | Campagne finale |
| #86 | Temps de démarrage par étape (fermée, reste couverte) | | | NOT_EXECUTED | Campagne finale |
| #87 | Départ en attente d'une autre leçon sans blocage (fermée, reste couverte) | | | NOT_EXECUTED | Campagne finale |
| #88 | Epic tracés GPS/OSRM | | | NOT_EXECUTED | Campagne finale |
| #89 | Diagnostic capture et moteur privé (fermée, reste couverte) | | | NOT_EXECUTED | Campagne finale |
| #90 | Recalage direct ligne et marqueur (fermée, reste couverte) | | | NOT_EXECUTED | Campagne finale |
| #91 | Replay OSRM fiable, portions brutes explicites | | | NOT_EXECUTED | Campagne finale |
| #95 | Démarrage compact, choix GPS réutilisé (fermée, reste couverte) | ce7e3a8, 1826c04 | UI iPhone/iPad réussie sur ce7e3a8 | NOT_EXECUTED | Échec métier corrigé dans 1826c04, non rejoué |

## Résultats exécutés (25 octobre 2026)

- E2e navigateur : PASS sur `a8a0729` (run 40184333047).
- IPA d'essai avec `aps-environment=development` : compilée sur `6744408` (run 40184742677). Signature et installation iLoader : NOT_EXECUTED.
- Campagne iOS sur `495f97b` : 29/30 tests UI PASS. FAIL : `FieldFlowTests.testLeavingLiveThroughTheExitButtonKeepsTheStartedLessonWithoutCancellingIt` (requête de l'accessoire capture-return sous iOS 26), corrigé dans `c169a7f`, relance ciblée en cours (run 40184805111).
- Reste à qualifier : campagne iOS complète ; livraison APNs réelle (clés `APNS_*` et script `prepare-course-worker.sql` non exécutés).

Les contrôles physiques (GPS réel, arrière-plan, autonomie, VoiceOver sur appareil) restent manuels. Le simulateur ne les valide pas.

## Historique de qualification messagerie du 23 octobre (non applicable au candidat intégré)

# Validation finale de la vague du 21 octobre 2026 (#84)

## Conclusion de cette intervention

**BLOCKED pour la qualification globale. PASS uniquement pour quatre scénarios synthétiques du prototype SDK. Messages n'est pas qualifié pour activation par cette preuve.**

Relevé le 23 octobre 2026 à 22:11 UTC (24 octobre à 00:11 en UTC+02). Branche partagée `openai/65-messagerie`, HEAD observé `e2657c493029153d46f2ca4ae034ebe8d01304bd`. Les autres intervenants modifient l'arbre partagé : ce relevé ne prétend pas qualifier leurs modifications ultérieures ni un futur SHA intégré.

Mandat limité à `prototypes/messaging-crypto/**` et aux deux fichiers `docs/qa/validation-finale-20261021.{json,md}`. Aucun commit, push, fusion, déploiement, lancement CI, modification d'app, workflow, STATUS ou matrice messaging-78 par cette intervention. Aucun défaut du prototype démontré, aucun correctif de code nécessaire.

## Inventaire immuable et sources

Source : `tomyrms/Drivy#84`, corps et six commentaires relus via `gh issue view 84 --repo tomyrms/Drivy --json title,body,comments`. Instantané initial : **47 issues, #37 à #83 incluses**, au 21 octobre, référence `master@f82889494fde230cda5b3d7ae3c81d6626a4ef0c`. Les fermetures GitHub ne retirent aucun critère. Le JSON compagnon porte les numéros individuels, critères, références de tests, décisions et points restants.

| Extension | Preuve de rattachement |
|---|---|
| #85, #86 | Commentaire #84 `6316206922` |
| #87 | Commentaire #84 `6317144698` |
| #88, #89, #90, #91 | Commentaire #84 `6318422983` |
| #95 | Commentaire #84 `6351049517`, limites de qualification rappelées dans `6353993500` |
| #94 | Dépendance/régression de #64 déjà intégrée, identité unique et migration 041 décrites dans commentaire #94 `6348862817`, pas une extension fonctionnelle indépendante |
| #97 | Description #97 et décisions messagerie du 23 octobre : report explicite des pièces jointes #75 après la base |

#93 n'est pas ajouté automatiquement : absent des extensions explicites #84 inspectées. Réexaminer son rôle d'infrastructure si nécessaire à la campagne. #84 est l'orchestration, pas un 48e élément de l'instantané initial. Les URL précises des commentaires sont conservées dans `sources` du JSON.

`DEFERRED` n'est jamais un succès : #45 finance future et #63 audio IA restent différés. #75 est reporté vers #97 par décision explicite. Les options #76 (réactions, citations, épinglage, recherche locale, accusés visibles) sont **retenues**, pas optionnellement retirées. Indicateur de saisie non demandé.

## Preuve exécutée : SDK local

Commande depuis la racine :

```text
cargo test --locked --offline --manifest-path prototypes/messaging-crypto/Cargo.toml
```

- Début outil : `2026-10-23T22:11:28.678Z`, fin : `2026-10-23T22:11:58.142Z`.
- Code retour **0**, **4 passés, 0 échoué, 0 ignoré, 0 filtré**.
- Scénarios : **8,09 s**. Durée murale mesurée par Stopwatch : **29,017546 s**. Cargo annonce **11,23 s** de préparation. Ces mesures portent sur des périmètres différents, pas sur trois suites à additionner.
- Bibliothèque : 0 test. Doctests : 0 test. Ces cibles vides ne constituent pas des preuves supplémentaires.
- Windows x86_64, cargo `1.99.0 (5f94df478)`, rustc `1.99.0 (b940084d7)`. Dépendances disponibles localement, aucun téléchargement nécessaire.
- Dernier commit du prototype : `60e845f5275fcab822bb9ce335892dda9be5702b`. Code et Cargo.lock inchangés avant/après exécution. Seul le README est actualisé pour éviter de laisser croire que les scénarios n'ont jamais été exécutés.
- Pas de run CI ni d'artefact distant pour ce résultat. Preuve : sortie locale de commande, transcrite ci-dessous et dans le JSON. Aucun message réel, position, jeton, clé ou export cryptographique enregistré.

| Test dans `prototypes/messaging-crypto/tests/scenarios.rs` | Critère démontré | Résultat |
|---|---|---|
| `group_rotation_excludes_removed_member_but_does_not_erase_received_history` | Rotation change la session, retiré sans nouvelle clé même avec ciphertext, ancien historique encore lisible | PASS |
| `second_device_is_excluded_until_explicit_trust_and_excluded_again_after_revocation` | Appareil non approuvé exclu, approbation de fixture puis admission sans ancien historique, révocation + rotation excluent le futur | PASS |
| `replacement_device_with_same_user_id_does_not_recover_historical_keys` | Nouveau terminal du même compte sans secrets ne déchiffre pas l'ancien historique | PASS |
| `recovery_requires_the_user_secret_for_a_standard_encrypted_key_export` | Mauvaise phrase refusée, import officiel avec bonne phrase rend l'historique accessible | PASS |

Limites : magasin en mémoire, annuaire/to-device simulés, confiance locale attribuée par fixture, déchiffrement permissif pour étude des primitives, un seul expéditeur. Aucune preuve SAS/QR, OIDC, droits scolaires, persistance durable chiffrée, protection rollback, rotation concurrente de tous les expéditeurs, sauvegarde serveur, résidence ou intégration Swift. **Le prototype utilise matrix-sdk-crypto 0.19.1, le client Apple documenté utilise FFI 0.17.0 : aucun transfert automatique de qualification.**

## Messagerie candidate et cours non intégrés

### Complément des autres intervenants, relevé à 22:15 UTC

Ces runs ont été lancés par le coordinateur, pas par cette intervention. Leurs SHA, états et étapes ont été vérifiés en lecture seule avec `gh run view`. Tous portent sur le baseline `e2657c493029153d46f2ca4ae034ebe8d01304bd`, pas sur les corrections locales en cours.

| Preuve | État observé | Portée et limites |
|---|---|---|
| Navigateur run `40031985954` | PASS | Job Chromium/OIDC/BFF/API/PostgreSQL de 22:11:32 à 22:13:31 UTC, étape parcours synthétique de 22:12:20 à 22:13:28. Ne prouve pas les nouveaux parcours messagerie/cours. |
| API run `40031983397` | FAIL | Job Contrats/droits/PostgreSQL de 22:11:30 à 22:14:32, étape `npm test` échouée. Coordinateur rapporte 596 passés, 21 échoués, 617 tests, 4 fichiers en échec. Comptes rapportés, non relus dans les logs par cet agent. Correction API en cours, premier échec conservé. |
| Intégrité documentaire du même run | PASS documentaire | Ne qualifie pas le produit. |
| Apple run `40031925552` | FAIL compilation, tests NOT_EXECUTED | Mise à jour vérifiée à 22:16:08 UTC : compilation application/cibles échouée, tests iPhone/iPad, captures et IPA sautés. Aucun XCTest/UI exécuté. Coordinateur rapporte ciphertext optionnel et captures MainActor dans `@Sendable`, correction iOS en cours. Diagnostic rapporté, non relu ici. |

Le coordinateur rapporte également : web local 320 tests/typecheck/build PASS sous Node26 (hors cible Node24), sélection de tests 14 PASS, captures 11 PASS **après correction** d'un premier échec de listes Swift. Ces preuves locales n'ont pas été exécutées ni relues par cet agent, et ne couvrent pas automatiquement un futur SHA final. Les URL des runs sont conservées dans `externalRuns` du JSON. Les statuts individuels de la matrice restent des qualifications de critères, non des déductions à partir du vert d'une suite historique. La qualification globale demeure bloquée et l'échec API est explicite.

Les commits candidats messagerie incluent `17855da`, `5ceeac2`, `b182bc0`, `3307833`, `e4fc5c8`, `9db614e`, `6623eea`, `2b3221e`, `b39fce4`, avec bilan `e2657c4`. Ils fournissent des références d'implémentation, pas des résultats de tests. La liste des fichiers API/Swift/UI candidats est conservée dans `testReferences.MSG_API` et `MSG_IOS` du JSON. Ces suites ne sont pas exécutées par cette intervention.

La lecture de `docs/implementation/decisions-messaging-20261023.md` fixe les bornes d'arrivée/départ, la réintégration, la modération, les sondages, la recherche locale et l'absence de contenu APNs. `messaging-e2ee-ios-20261023.md` distingue le store et le relais Apple, la confiance au premier usage, l'UI de vérification encore à réaliser et l'activation de développement. Rien ici ne remplace la recette réelle de ces éléments.

`git log --oneline HEAD..vague/cours-collectifs` montre **cinq commits non intégrés** :

| Commit | Lot |
|---|---|
| `7c3bcef` | Socle cours, migration 042, API création/publication (#80/#38) |
| `6877eea` | Cadrage #79, socle #80 et manifeste |
| `efc6a85` | Agenda web et iOS/iPadOS, brouillon/publication (#38) |
| `50d4640` | Documentation STATUS et manifeste #84 |
| `3d911b8` | Inscription, file prioritaire, annulations, migration 043 (#39/#40/#41) |

La ref locale `origin/vague/cours-collectifs` ne montre que les quatre premiers. Le mandat signale aussi du travail local cours en cours. Aucun travail ni commit de cette branche n'a été fusionné, copié ou modifié. Les migrations cours et messagerie devront être confrontées lors d'une intégration autorisée, pas supposées compatibles.

Le commentaire #84 `6363165534` rapporte seulement une **IPA** réussie sur `efc6a85`, run `39940836151`. Cela ne valide aucun scénario. Il annonce `apps/api/test/courses.integration.test.ts`, `apps/web/test/course-model.test.ts`, `apps/web/test/school-bff.test.ts`, `apps/ios/DrivyTests/SchoolCourseClientTests.swift` et une UI agenda vers cours. Les trois fichiers spécifiques cours ne sont pas présents sur ce candidat messagerie. `school-bff.test.ts` existe mais sa présence ne prouve pas les scénarios de la branche cours.

Règles cours à conserver : annulation autonome jusqu'à 24 h avant première séance par défaut, configurable/versionnée, refus tardif sans libérer de place avant décision manuelle auditée. File FIFO, offre exclusive à durée limitée, acceptation explicite, expiration/refus puis suivant. La durée de réponse n'est **pas** le délai d'annulation de 24 h et reste à confirmer. Couvrir plusieurs places, capacité diminuée, doubles appuis et concurrence inscription/acceptation/expiration. Un e-mail volontaire au responsable ne devient pas une notification automatique.

## Matrice des 47 issues initiales

Les identifiants de tests ci-dessous désignent les fichiers exacts de `testReferences` du JSON. Hors SDK, ce sont des **références candidates**, non une certification que toutes les assertions requises existent. `GAP` signifie qu'une référence précise manque. Pour les autres lots que messagerie/cours/#94/#95, les commits individuels restent à rattacher, sans les inventer depuis l'état fermé d'une issue.

| Issue | Critère à conserver | Références | Résultat / point restant |
|---|---|---|---|
| #37 | Parcours complet cours, conflits leçons et progression | COURSES, MANUAL | BLOCKED : lot non intégré |
| #38 | Créer/gérer/publier séries iOS/web | COURSES | BLOCKED : branche cours |
| #39 | Offres agenda, inscription série entière, capacité | COURSES | BLOCKED : branche cours |
| #40 | File FIFO, proposition exclusive, expiration et concurrence | COURSES | BLOCKED : intégration et durée réponse |
| #41 | Annulation 24 h configurable, refus tardif, décision auditée | COURSES | BLOCKED : branche cours |
| #42 | Appel/correction par séance, indépendant paiement | COURSES, GAP | BLOCKED : scénario spécifique à intégrer |
| #43 | Annonces/confirmations/rappels sans e-mail automatique | COURSES, MANUAL | BLOCKED : cours et notification réelle |
| #44 | Préférences personnelles par rôle | COURSES, GAP | BLOCKED : couverture cours |
| #45 | Finance future | Aucun | DEFERRED : décision initiale |
| #46 | Positions valides après perte GPS | GPS, MANUAL | NOT_EXECUTED : régression et physique |
| #47 | Abandon clôture sans impasse | LESSON | NOT_EXECUTED : reprise durable |
| #48 | Isolation captures corrompues sans perte récupérable | GPS, LESSON | NOT_EXECUTED : corruption/persistance |
| #49 | Agenda actualisé après autre appareil | AGENDA | NOT_EXECUTED : navigateur multi-session |
| #50 | Récupération d'accès OIDC | ACCOUNT, GAP | BLOCKED : scénario spécifique à identifier |
| #51 | Gestion leçons individuelles agenda web | AGENDA | NOT_EXECUTED : droits/conflits/navigateur |
| #52 | Demande élève déplacement/annulation selon politique | AGENDA, GAP | BLOCKED : preuve spécifique manquante |
| #53 | Homonymes distincts avant action compte | ACCOUNT | NOT_EXECUTED : identité et rôles |
| #54 | Examens, tentatives, résultats | GAP | BLOCKED : implémentation/test non établis |
| #55 | Thèmes et campagne métier/UI iPhone/iPad entière | SIGNALS, UI, MANUAL | NOT_EXECUTED : runner Apple et terrain |
| #56 | Signaler découplé compétences UI/API/base | SIGNALS | NOT_EXECUTED : PostgreSQL et UI |
| #57 | Toutes compétences au bilan sans filtre signalement | SIGNALS, LESSON | NOT_EXECUTED : interaction #56/#57 |
| #58 | Confirmation rétablissement cohérente | SIGNALS, UI | NOT_EXECUTED : annulation/accessibilité |
| #59 | Centrage/suivi/vue trajet distincts | GPS, UI, MANUAL | NOT_EXECUTED : capteurs réels |
| #60 | Sortie GPS sans arrêter leçon, onglets masqués | UI, LESSON | NOT_EXECUTED : continuité/navigation |
| #61 | Annuler/interrompre depuis GPS actif | LESSON, UI | NOT_EXECUTED : commandes concurrentes |
| #62 | Nom fiche leçon ouvre dossier autorisé | UI, LESSON | NOT_EXECUTED : navigation et droits |
| #63 | Audio IA premium | Aucun | DEFERRED : très long terme |
| #64 | Profil/photo, rôles et identité cohérente | ACCOUNT, UI | NOT_EXECUTED : régression #94 |
| #65 | Messagerie complète E2EE/Suisse/leçons | SDK, MSG_API, MSG_IOS, MANUAL | BLOCKED : PASS SDK partiel seulement |
| #66 | Messages secondaire, fiche élève, décisions produit | MSG_IOS, UI | NOT_EXECUTED : UI finale |
| #67 | Clés, rotation, perte, récupération | SDK, MSG_IOS | BLOCKED : primitives PASS, produit non qualifié |
| #68 | Suisse, sauvegardes, cycle de vie | MANUAL, MSG_API | BLOCKED : preuves infrastructure |
| #69 | Contacts affectés, bornes, retrait/réintégration | MSG_API, MSG_IOS, SDK | NOT_EXECUTED : droits serveur/RLS |
| #70 | Envoi durable, historique, hors-ligne protégé | MSG_API, MSG_IOS | NOT_EXECUTED : transport réel/persistance |
| #71 | Espace Messages et privés depuis dossiers | MSG_IOS, UI | NOT_EXECUTED : UI et appareil |
| #72 | Général, mentions, nom/photo, bornes membres | MSG_API, MSG_IOS | NOT_EXECUTED : métadonnées et droits |
| #73 | Sondages unique/multiple, vote modifiable, clôture | MSG_API, MSG_IOS | NOT_EXECUTED : concurrence/UI |
| #74 | Notifications sans texte, non-lus, silence | MSG_API, MSG_IOS, MANUAL | NOT_EXECUTED : APNs/arrière-plan |
| #75 | Images/fichiers | Aucun | DEFERRED : report explicite #97 |
| #76 | Réactions, citations, épinglage, recherche locale, lectures | MSG_API, MSG_IOS | NOT_EXECUTED : fonctions retenues |
| #77 | Modération et signalement rechiffré choisi | MSG_API, MSG_IOS | NOT_EXECUTED : preuve conservée et privé protégé |
| #78 | Sécurité, multi-appareils et interaction leçons | SDK, MSG_API, MSG_IOS, MANUAL | BLOCKED : recette produit à effectuer |
| #79 | Cadrage cours et durées distinctes | COURSES | BLOCKED : branche et paramètre |
| #80 | Schéma, contrats, droits, migrations/RLS | COURSES | BLOCKED : intégration et migrations |
| #81 | Règlement indépendant présence/accomplissement | COURSES, GAP | BLOCKED : pas assimilé à #45 |
| #82 | Accomplissement/progression dossier | COURSES, GAP | BLOCKED : intégration et métier |
| #83 | Cours bout en bout, concurrence, non-régression | COURSES, UI, MANUAL | BLOCKED : IPA seule insuffisante |

## Matrice des extensions

| Issue | Critère | Références | Résultat / point restant |
|---|---|---|---|
| #85 | Attribution Plans visible, hauteurs et iPhone/iPad, replay | UI, GPS | NOT_EXECUTED |
| #86 | Mesures avant/après chaque étape démarrage et requêtes/pages | START, LESSON, MANUAL | NOT_EXECUTED : aucune saturation supposée |
| #87 | A/B, non envoyé/refus/en vol/réponse perdue, actif/clôturé, réseau/retrait | LESSON, START, UI | NOT_EXECUTED : bouton stable, aucun double départ, points conservés |
| #88 | Chaîne GPS/OSRM complète sur référence indépendante | GPS, MANUAL | NOT_EXECUTED |
| #89 | Diagnostic acquisition/sync/moteur privé/couverture | GPS, MANUAL | NOT_EXECUTED : état moteur actuel non mesuré |
| #90 | Ligne ET marqueur live, lenteur/arrêt/manœuvre/marche/latence | GPS, UI, MANUAL | NOT_EXECUTED : originaux préservés, pas de repli public |
| #91 | Replay partiel/brut/en attente explicite, chronologie/cache versionné | GPS, UI, MANUAL | NOT_EXECUTED : réseau/OSRM indisponible |
| #95 | Fenêtre compacte, accord/refus réutilisés sans réécriture, notice/erreur/changement contexte | START, UI, MANUAL | NOT_EXECUTED : qualification de ce SHA absente |
| #94 | Profil/identité uniques, rôles, migration 041, photo | ACCOUNT, UI, MANUAL | NOT_EXECUTED : régression #64 au SHA final |
| #97 | Pièces jointes E2EE, formats/tailles/stockage suisse | Aucun | DEFERRED : après messagerie de base |

#95 : `26297dd` annoncé intégré par le commentaire #84. Une UI iPhone/iPad sur commit antérieur et un échec métier corrigé mais non rejoué ne deviennent pas un PASS sur ce candidat. Inclure clavier, rotation, Dynamic Type, VoiceOver, permissions iOS distinctes, refus/révocation et absence de création résiduelle/double action.

#94 : les commentaires rapportent des preuves historiques API/web/navigateur et déploiement. Elles ne sont pas réexécutées ni transférées à ce HEAD. La décision ultérieure d'identité unique remplace la première solution à deux formulaires/sources affichées. La régression doit conserver droits par rôle et école, photo et confirmation des modifications administratives.

## Conditions pour la campagne intégrée et l'affichage Messages

1. Rassembler les développements retenus sur décision explicite, sans fusion implicite de la branche cours. Résoudre les références de commits manquantes et les `GAP`.
2. Figer un SHA unique transmis à tous jobs et artefacts. Les modifications locales concurrentes observées ne sont pas couvertes par ce résultat SDK.
3. Exécuter API/contrats/droits/concurrence sur **vraie PostgreSQL isolée**, migrations base vierge et évolution synthétique, Web/BFF/navigateur, scripts/contrats, Swift métier complet et UI iPhone **et** iPad. Ne pas laisser un filtre GPS seul ou visuel seul réduire silencieusement le périmètre.
4. Réutiliser les mêmes preuves pertinentes pour #55/#78/#83, sans trois campagnes redondantes. Rapport des jobs échoués, annulés, ignorés ou sans tests attendus : jamais PASS global.
5. Qualifier les parcours messagerie réels : transport, clés, store protégé, multi-appareils, rotation, récupération, bornes serveur, notifications, réseau dégradé et commandes de leçon non bloquées. Le seul SDK synthétique ne permet pas d'afficher Messages en Release.
6. Garder les limites physiques/infrastructure : GPS arrière-plan, batterie, fluidité, VoiceOver appareil, APNs et preuves de résidence/restauration. Aucun résultat inventé depuis compilation ou simulateur.
7. L'IPA doit correspondre au SHA qualifié mais reste une preuve de construction distincte. Retrait du mode temporaire, déploiement et clôtures sont des décisions séparées. Cette intervention n'en effectue aucun.

Les contrôles de cohérence JSON/références documentaires servent à fiabiliser cet inventaire, **pas à qualifier le produit**.
