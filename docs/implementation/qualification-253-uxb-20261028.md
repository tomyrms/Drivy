# Qualification après essai — #253 et 15 corrections UX B

Le porteur a accepté l'essai livré, puis demandé de lancer les tests, corriger leurs échecs et fermer l'épic avec ses issues. Ce retour ne constitue pas une qualification physique du GPS, de la batterie ou de VoiceOver. Les contributions de `claude/replay-audit-b42-b44-20261028` sont conservées dans l'historique de `codex/simplification-253`.

## Corrections après essai

- Le départ préparatoire GPS avait une action d'audit distincte sans permission SQL correspondante : la transaction échouait, sans démarrer la leçon. La migration additive `20261028b_lesson_gps_preparation_audit.sql` autorise précisément `LessonPreparedForGPS` pour un membre de l'école. Les droits sur les leçons, le choix personnel et les protections de départ sont inchangés. Le test vérifie aussi un seul audit après rejeu.
- Les prérequis du dossier réutilisent désormais les faits de cours autorisés : présences et validation interne FIRST_AID/AWARENESS. Les droits sont relus ; une panne, un refus et une lecture vide sont distincts. Aucune attestation, dispense ou date de cours n'est déduite de ces faits. [Contrat et limites](regles-suisses-20261028.md).
- L'échéance d'une offre de cours s'appuie sur l'heure serveur et une horloge monotone, y compris lorsque la confirmation est ouverte ou que la relecture échoue. Le serveur reste l'autorité lors de la commande. Le test de lecture du replay exerce le vrai lecteur : sélection, pause, observation conservée, puis reprise du suivi.
- Les recettes ont été adaptées aux trois étapes du guide et aux détails repliés. Les données historiques de test, la migration datée et la personnalisation du texte de conservation ont été corrigées ; les contrôles métier n'ont pas été retirés.

## Preuves d'exécution

| Exécution | SHA | Résultat et portée |
|---|---|---|
| [Vérifications corrigées 40740971311](https://github.com/tomyrms/Drivy/actions/runs/40740971311) | `502351abf395cb1bde8d42a5759ec63acd890638` | PASS : 791 tests API sur PostgreSQL réel, 416 tests web/BFF, typage/compilation et intégrité documentaire. Précède le raccord S10. |
| [Swift initial 40739178690](https://github.com/tomyrms/Drivy/actions/runs/40739178690) | `36d75142af3ef9de7e8568f42e66feacfcf07b8e` | PASS : 1 087 tests, aucun échec ni test ignoré ; 1 161 exécutions en comptant les cas paramétrés. Précède la correction d'horloge et le nouveau test de lecture. |
| [API, web et contrats 40742565492](https://github.com/tomyrms/Drivy/actions/runs/40742565492) | `4a1a68854933668e58c940205258ff6f217ebfc8` | PASS : 73 fichiers / 796 tests API PostgreSQL et 37 fichiers / 423 tests web, aucun échec, ignoré ou todo. S10 : 4 cas PostgreSQL, 1 test de contrat, 7 tests web réussis. Typage, compilation et intégrité documentaire réussis. |
| [Navigateur 40743521660](https://github.com/tomyrms/Drivy/actions/runs/40743521660) | `83aadc37fa02af5420a08e1f0e52178bfdf27ff7` | PASS : 162 contrôles, Chromium 153.0.8010.12. Ouverture, OIDC, réponse perdue, reprise, configuration, premier élève et rendez-vous, formations et conservation de l'historique sur données synthétiques isolées. |
| [Swift corrigé 40742298060](https://github.com/tomyrms/Drivy/actions/runs/40742298060) | `94348f6f4b32c9e92c6e91843e40cf28aebd454a` | PASS : 1 091 tests, aucun échec, ignoré ou échec attendu. Les deux décalages de ±2 jours, la confirmation reçue après l'échéance, l'horloge monotone et la sélection manuelle du replay passent. |
| [UI initiale 40739185025](https://github.com/tomyrms/Drivy/actions/runs/40739185025) | `36d75142af3ef9de7e8568f42e66feacfcf07b8e` | PASS : 16/16 sur iPhone 17 Pro et 16/16 sur iPad Air 11 pouces (M4), simulateurs iOS 26.4.1 ; aucun échec ou test ignoré. Cours, accueil, bilan, protection du formulaire, confidentialité, sondage, recherche et protection indisponible sans faux reçu. Précède le correctif d'horloge. |
| [Cours UI corrigés 40745176299](https://github.com/tomyrms/Drivy/actions/runs/40745176299) | `94348f6f4b32c9e92c6e91843e40cf28aebd454a` | PASS : 7/7 sur iPhone 17 Pro et 7/7 sur iPad Air 11 pouces (M4), simulateurs iOS 26.4.1 ; aucun échec, ignoré ou échec attendu. Les 14 résultats et l'identité du run ont été relus. |

Les artefacts JSON, identités et journaux ont été téléchargés et relus. Le job cours `40742355593`, encore en attente sans aucun job démarré, a été annulé puis remplacé par `40745176299` sur une branche de qualification au même SHA : aucun test n'est revendiqué pour l'exécution annulée. Aucune configuration CI n'a été modifiée.

Comparaison exécutée avant fusion : `apps/ios` est identique à `94348f6f`, et `apps/api`/`apps/web` à `4a1a6885`. Les recettes finales correspondent à `83aadc37` ; les derniers changements portent uniquement sur les reçus documentaires. L'intégrité des 556 fichiers de conception et le contrôle documentaire passent aussi localement, avec les dépendances verrouillées dans un environnement isolé. `git diff --check` passe. Les premiers échecs ont été corrigés puis rejoués ; aucun run initial en échec n'est transformé en succès dans ce reçu.

## IPA corrigée

[Run 40742302908](https://github.com/tomyrms/Drivy/actions/runs/40742302908) : compilation réussie du SHA `94348f6f4b32c9e92c6e91843e40cf28aebd454a`, version 0.7.0, **build 442**, Release non signé pour iLoader. [Artefact vérifié 12841010670](https://github.com/tomyrms/Drivy/actions/runs/40742302908/artifacts/12841010670), téléchargé dans `artifacts/simplification-253/94348f6f/ios/Drivy.ipa` (17 922 866 octets).

Les trois entrées de `SHA256SUMS.txt` concordent. Empreinte de l'IPA : `98e3f9ddb00f83527af0edae0d777fed4b1073d7357f011e0d8f876c55059d7b`. `build-info.json` confirme le commit, le run, l'archive créée, les contrôles de signature attendus et la connexion scolaire configurée. L'accès Messages de qualification est inclus ; aucune qualification générale Messages ou physique n'est revendiquée. Les commits API/web et recettes ultérieurs ne modifient pas `apps/ios`.

Pour l'essai des correctifs : dans les cours, vérifier la présence du prochain cours et des offres, puis une offre dont le délai passe avec sa fiche ouverte ; dans le replay, lancer la lecture, choisir une observation longue, vérifier qu'elle reste affichée et reprendre la lecture. Le contrôle automatisé de l'expiration porte sur l'état métier de la fiche/confirmation ; il ne remplace pas un essai visuel de l'échéance sur appareil. `manualSelectionPausesLongNoteUntilPlaybackResumes` a exécuté sélection → pause → instant et texte conservés → reprise du suivi via le point d'entrée effectivement appelé par la vue.

## Limites de clôture

La [revue des 24 sujets et des 15 corrections UX](revue-cloture-253-20261028.md) distingue la réalisation, la comparaison documentaire et la qualification. S07 conserve les lacunes réglementaires explicites. S14 est un audit terminé avec une décision **BLOCKED** pour l'activation réelle du GPS obligatoire ; clôturer cet audit n'autorise pas cette activation. `GPS_ONLY_QUALIFICATION_SCHOOL_IDS` reste vide en exploitation. Les mesures sur appareils, la provenance hors B/BE, le délai de retrait distant et VoiceOver physique ne sont pas qualifiés par ces tests.

## Mise en ligne des correctifs

La version web/API actuellement déployée reste celle du [reçu précédent](deploiement-reset-253-20261028.md), `a41cf64d153252dc133a60f29755f0685516be8f`. Les correctifs postérieurs sont distincts de ce déploiement et de la remise à zéro déjà exécutée.

Leur déploiement éventuel concerne uniquement `drivy-refonte-api`, `drivy-refonte-web` et `drivy-refonte-course-worker` sur CT114, avec une sauvegarde préalable de `drivy_refonte` sur CT113. Aucun changement d'identité, de clé, de configuration GPS/Messages ou de données utilisateur n'est prévu. Une seule migration nouvelle depuis la version publiée : la permission d'audit additive citée plus haut ; aucune transformation de lignes. Retour arrière : remettre le lien de release précédente puis redémarrer les trois services ; la permission additive reste compatible avec l'ancien code. Le point de restauration privé demeure disponible si une restauration complète devait être décidée. Cette mise en ligne nécessite l'accord distinct demandé par le porteur pour le homelab ; elle n'est pas annoncée comme effectuée.
