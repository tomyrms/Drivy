# Stratégie de tests, fixtures et recettes détaillées

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Statut de cette campagne

**Tous les tests produit ci-dessous sont spécifiés, pas exécutés.** Aucun résultat de l’ancienne suite, de l’app future, d’un serveur réel ou d’une recette utilisateur n’est revendiqué. La seule exécution réalisée dans ce livrable porte sur des vérifications documentaires listées dans la [revue de cohérence](../06-gouvernance/revue-coherence.md).

Chaque test garde son identifiant lors d’une implémentation. Dans l’outil de suivi, consigner version du contrat, commit, environnement, fixture, résultat, preuve et ticket d’anomalie. Ne pas confondre test non lancé, test bloqué, test échoué et test réussi. Les résultats de qualité visuelle ou métier nécessitent une observation humaine, pas uniquement un snapshot binaire.

<a id="protocole-de-preuve"></a>
## Protocole de preuve commun

En cas de concurrence, utiliser deux connexions/transactions réelles ; pour capteurs, push et persistance native, qualifier le binaire et l’appareil. Pour fichiers/exports, contrôler les octets et les échanges réseau/stockage, pas uniquement les métadonnées.

Chaque scénario exige le commit de l’application et du serveur, la version du contrat, la fixture de départ, les commandes réellement envoyées, les résultats observés et les états persistés avant/après. Les traces sont expurgées des secrets et données personnelles. Vérifier les effets attendus **et l’absence des effets interdits**. Le type de recette figure dans le registre de traçabilité ; une assertion de schéma ne remplace pas le test d’intégration ou d’appareil demandé.

La ligne « Preuve attendue » d’un scénario précise les éléments particuliers lorsqu’ils existent. Son absence renvoie à ce protocole, pas à une dispense. Un cas sans environnement ou dépendance réelle est NOT_EXECUTED/BLOCKED, jamais PASSED. Aucun des scénarios produit de ce dossier n’est déclaré exécuté.

## Stratégie et environnements

Les tests unitaires couvrent calculs purs : intervalles, règles de prix/solde, sélection de dernière observation, limites et transitions. Les tests d’intégration lancent un vrai PostgreSQL isolé et testent transactions, RLS et migrations avec le rôle applicatif. Les mocks sont adaptés au fournisseur email ou identité pour certains scénarios, pas à une prétendue preuve de concurrence SQL. Les contrats valident JSON, erreurs, compatibilité et permissions. Les parcours bout en bout utilisent comptes synthétiques, stockage privé de test et builds réels.

La CI démarre les dépendances nécessaires par services CI ou conteneurs éphémères, applique migrations, crée fixtures et détruit l’environnement de test. Un Docker lancé sur l’ordinateur du développeur ne conditionne pas le fonctionnement de la CI distante. Avant toute commande destructive, vérifier que l’URL et l’identité de la base appartiennent explicitement au périmètre de test. Aucun test de restauration ne touche la production active.

## Jeu de données de référence

École A et école B, noms entièrement fictifs. Dans A : deux ADMIN, deux INSTRUCTOR, un moniteur également élève ; deux élèves homonymes, dont un suit deux formations B et A, chaque offre disposant d’un référentiel synthétique explicitement non officiel. Même Person peut appartenir à B sans partage de dossiers. Prévoir pièce READY, REJECTED et QUARANTINED ; leçon PLANNED, COMPLETED, CANCELLED et NO_SHOW ; brouillon privé ; bilan remplacé ; paiement partiel ; invitation expirée ; affectation retirée.

Les montants de recette (par exemple 9 000 centimes) et dates de septembre/octobre 2026 sont des valeurs synthétiques, pas tarifs ou rendez-vous de l’utilisateur. Les données ne doivent pas reprendre de vrais noms/coordonnées de l’archive. Une seed déterministe permet de reproduire chaque scénario à partir d’une base vide. Une deuxième série aléatoire révèle les hypothèses cachées sur identifiants ou ordre de listes.

## Niveaux de preuve avant ouverture

Les risques bloquants sont fuite inter-écoles, perte de bilan, double réservation, double encaissement, publication involontaire et restauration inutilisable. Aucun ne reçoit une dérogation implicite au motif d’un petit nombre d’utilisateurs. Les objectifs de performance sont mesurés sur volumes et appareils qualifiés ; proposer par exemple un budget de réponse interactif dans le protocole ne constitue pas un engagement de service déjà atteint.

Pour les essais utilisateurs, proposer des tâches réalistes à l’arrêt : trouver la prochaine leçon, préparer un point, déplacer sans perdre le rendez-vous initial, noter un constat hors ligne, comprendre une correction et retrouver sa prochaine étape. Recruter les trois rôles et différents niveaux d’aisance numérique. Le nombre de participants, la durée et les seuils sont à convenir ; aucun entretien n’a été réalisé pour ce dossier.

## Catalogue exécutable à traduire en tests

Les T001–T056 reprennent les critères des fonctions prioritaires ; les suivants croisent plusieurs domaines et incidents. Les assertions vérifient état, permissions, effets et messages ; « le bouton existe » ne suffit pas.

| Test | Sujet | Fonction | Niveau |
|---|---|---|---|
| [T001](#t001) | Connexion multi-écoles | F01 | Intégration + recette de parcours |
| [T002](#t002) | Révocation pendant une session | F01 | Intégration + recette de parcours |
| [T003](#t003) | Course dernier ADMIN | F01 | Intégration + recette de parcours |
| [T004](#t004) | Changement de compte natif | F01 | Intégration + recette de parcours |
| [T005](#t005) | Acceptation nominale | F02 | Intégration + recette de parcours |
| [T006](#t006) | Double acceptation | F02 | Intégration + recette de parcours |
| [T007](#t007) | Compte différent | F02 | Intégration + recette de parcours |
| [T008](#t008) | Renvoi | F02 | Intégration + recette de parcours |
| [T009](#t009) | Multi-permis | F03 | Intégration + recette de parcours |
| [T010](#t010) | Remplacement de document | F03 | Intégration + recette de parcours |
| [T011](#t011) | Formation en pause | F03 | Intégration + recette de parcours |
| [T012](#t012) | Affectation retirée | F03 | Intégration + recette de parcours |
| [T013](#t013) | Pause de midi | F04 | Intégration + recette de parcours |
| [T014](#t014) | Modification conflictuelle | F04 | Intégration + recette de parcours |
| [T015](#t015) | Heure inexistante | F04 | Intégration + recette de parcours |
| [T016](#t016) | Tampon | F04 | Intégration + recette de parcours |
| [T017](#t017) | Course de réservation | F05 | Intégration + recette de parcours |
| [T018](#t018) | Collision élève multi-permis | F05 | Intégration + recette de parcours |
| [T019](#t019) | Déplacement refusé | F05 | Intégration + recette de parcours |
| [T020](#t020) | Réponse perdue | F05 | Intégration + recette de parcours |
| [T021](#t021) | Souhait séparé | F06 | Intégration + recette de parcours |
| [T022](#t022) | Première leçon | F06 | Intégration + recette de parcours |
| [T023](#t023) | Leçon annulée | F06 | Intégration + recette de parcours |
| [T024](#t024) | Deux éditeurs | F06 | Intégration + recette de parcours |
| [T025](#t025) | Clôture atomique | F07 | Intégration + recette de parcours |
| [T026](#t026) | Horloge passée | F07 | Intégration + recette de parcours |
| [T027](#t027) | Résultat concurrent | F07 | Intégration + recette de parcours |
| [T028](#t028) | Correction avec paiement | F07 | Intégration + recette de parcours |
| [T029](#t029) | Publication minimale utile | F08 | Intégration + recette de parcours |
| [T030](#t030) | Brouillon invisible | F08 | Intégration + recette de parcours |
| [T031](#t031) | Envoi tardif | F08 | Intégration + recette de parcours |
| [T032](#t032) | Correction historisée | F08 | Intégration + recette de parcours |
| [T033](#t033) | Type falsifié | F09 | Intégration + recette de parcours |
| [T034](#t034) | Envoi interrompu | F09 | Intégration + recette de parcours |
| [T035](#t035) | Accès autre école | F09 | Intégration + recette de parcours |
| [T036](#t036) | Bilan sans photo prête | F09 | Intégration + recette de parcours |
| [T037](#t037) | Paiement partiel | F10 | Intégration + recette de parcours |
| [T038](#t038) | Double effet évité | F10 | Intégration + recette de parcours |
| [T039](#t039) | Remboursement excessif | F10 | Intégration + recette de parcours |
| [T040](#t040) | Correction de montant | F10 | Intégration + recette de parcours |
| [T041](#t041) | Email indisponible | F11 | Intégration + recette de parcours |
| [T042](#t042) | Bilan privé | F11 | Intégration + recette de parcours |
| [T043](#t043) | Destinataire révoqué | F11 | Intégration + recette de parcours |
| [T044](#t044) | Webhook doublé | F11 | Intégration + recette de parcours |
| [T045](#t045) | Arrêt brutal | F12 | Intégration + recette de parcours |
| [T046](#t046) | Conflit avec annulation | F12 | Intégration + recette de parcours |
| [T047](#t047) | Lease expirée | F12 | Intégration + recette de parcours |
| [T048](#t048) | Disque plein | F12 | Intégration + recette de parcours |
| [T049](#t049) | Réglage non rétroactif | F13 | Intégration + recette de parcours |
| [T050](#t050) | Catalogue vide | F13 | Intégration + recette de parcours |
| [T051](#t051) | Identité scolaire | F13 | Intégration + recette de parcours |
| [T052](#t052) | Changement sensible | F13 | Intégration + recette de parcours |
| [T053](#t053) | Archivage avec rendez-vous | F14 | Intégration + recette de parcours |
| [T054](#t054) | Portée multi-écoles | F14 | Intégration + recette de parcours |
| [T055](#t055) | Export restreint | F14 | Intégration + recette de parcours |
| [T056](#t056) | Restauration après suppression | F14 | Intégration + recette de parcours |
| [T057](#t057) | Isolation objet et recherche | F01 F03 F09 | Intégration sécurité |
| [T058](#t058) | RLS avec vrai rôle applicatif | F01 | Intégration PostgreSQL |
| [T059](#t059) | Double réservation concurrente | F05 | Intégration concurrence |
| [T060](#t060) | Élève multi-permis concurrent | F03 F05 | Intégration concurrence |
| [T061](#t061) | Personne cumulant les rôles | F01 F05 | Intégration SQL |
| [T062](#t062) | Fermeture et réservation en course | F04 F05 | Intégration concurrence |
| [T063](#t063) | Retour au printemps | F04 F05 | Unitaire + intégration |
| [T064](#t064) | Heure répétée en automne | F04 F05 | Unitaire + interface |
| [T065](#t065) | Téléphone en voyage | F05 | Appareil réel |
| [T066](#t066) | Perte de réponse après clôture | F07 F12 | Intégration panne |
| [T067](#t067) | Même clé, autre charge | F07 F10 F12 | Intégration API |
| [T068](#t068) | Rollback de clôture | F07 F10 F11 | Intégration transaction |
| [T069](#t069) | Deux encaissements parallèles | F10 | Intégration concurrence |
| [T070](#t070) | Annulation déjà encaissée | F07 F10 | Intégration métier |
| [T071](#t071) | Accord pédagogique périmé | F07 F08 | Intégration autorisation |
| [T072](#t072) | Observation ancienne tardive | F08 F12 | Intégration projection |
| [T073](#t073) | Retrait de dernière observation | F08 | Intégration projection |
| [T074](#t074) | Snapshot interrompu | F12 | Intégration mobile |
| [T075](#t075) | Ordre de commit et curseur | F12 | Intégration SQL concurrence |
| [T076](#t076) | Pagination dans une transaction | F12 | Intégration sync |
| [T077](#t077) | Révocation pendant snapshot | F01 F12 | Intégration sécurité |
| [T078](#t078) | Horloge et cache expiré | F12 | Appareil réel |
| [T079](#t079) | Faux type et fichier excessif | F09 | Intégration sécurité fichiers |
| [T080](#t080) | Scanner indisponible | F09 | Intégration panne |
| [T081](#t081) | Ticket volé ou ancien | F01 F09 | Intégration sécurité |
| [T082](#t082) | Pièce de permis remplacée | F03 F09 | Intégration métier |
| [T083](#t083) | Logo sans élève fictif | F09 F13 | Intégration API |
| [T084](#t084) | Email en panne après réservation | F05 F11 | Intégration panne |
| [T085](#t085) | Événement devenu obsolète | F05 F11 | Intégration worker |
| [T086](#t086) | Fuite par journaux | F09 F14 | Sécurité observabilité |
| [T087](#t087) | Export de mauvaise portée | F01 F14 | Intégration vie privée |
| [T088](#t088) | Restauration après effacement | F14 | Exercice exploitation |
| [T089](#t089) | Sauvegarde complète et clés | F14 | Exercice restauration |
| [T090](#t090) | Texte agrandi et lecteur d’écran | F05 F08 F13 | Recette accessibilité |
| [T091](#t091) | Clavier et réduction des mouvements | F05 F08 | Recette accessibilité |
| [T092](#t092) | Contrat client ancien | F01 F12 | Intégration compatibilité |
| [T093](#t093) | Offre nouvelle version | F03 F13 | Intégration SQL |
| [T094](#t094) | Volume synthétique et contention | F05 F12 | Performance exploratoire |
| [T095](#t095) | Réauthentification privilégiée | F01 F13 F14 | Intégration sécurité |
| [T096](#t096) | Purge de dépôt orphelin | F09 F14 | Intégration exploitation |

<a id="t001"></a>
### T001 · Connexion multi-écoles

**Statut :** À réaliser. **Fonctions :** F01. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R02](../03-fonctionnel/regles-etats.md#r02), [R03](../03-fonctionnel/regles-etats.md#r03), [R04](../03-fonctionnel/regles-etats.md#r04), [R34](../03-fonctionnel/regles-etats.md#r34), [R37](../03-fonctionnel/regles-etats.md#r37).

**Étant donné :** Compte membre de A et B ; choisir A.

**Quand :** Se connecter au compte membre de A et B, choisir A, ouvrir la liste des élèves et une URL profonde de B, puis basculer explicitement vers B.

**Alors :** Les listes, URLs et cache n’exposent que A ; le passage à B remplace la projection.

**Preuve attendue :** Réponses de listes et d’URL expurgées, identifiant de périmètre courant et inspection du cache avant/après bascule ; aucune ligne de B dans la projection A.

<a id="t002"></a>
### T002 · Révocation pendant une session

**Statut :** À réaliser. **Fonctions :** F01. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R02](../03-fonctionnel/regles-etats.md#r02), [R03](../03-fonctionnel/regles-etats.md#r03), [R04](../03-fonctionnel/regles-etats.md#r04), [R34](../03-fonctionnel/regles-etats.md#r34), [R37](../03-fonctionnel/regles-etats.md#r37).

**Étant donné :** Un ADMIN retire un moniteur alors qu’un token est encore valide.

**Quand :** Ouvrir une session moniteur dans A, faire retirer son appartenance par un ADMIN depuis une autre session, puis tenter une lecture et une modification de leçon avec le token initial.

**Alors :** La commande suivante est refusée ; aucun événement métier ni écriture n’est créé.

**Preuve attendue :** Refus des deux requêtes et diff des données métier/outbox vide ; journal de révocation sans token.

<a id="t003"></a>
### T003 · Course dernier ADMIN

**Statut :** À réaliser. **Fonctions :** F01. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R02](../03-fonctionnel/regles-etats.md#r02), [R03](../03-fonctionnel/regles-etats.md#r03), [R04](../03-fonctionnel/regles-etats.md#r04), [R34](../03-fonctionnel/regles-etats.md#r34), [R37](../03-fonctionnel/regles-etats.md#r37).

**Étant donné :** Deux administrateurs essaient simultanément de retirer l’autre.

**Quand :** Synchroniser deux requêtes de retrait à une barrière de transaction : ADMIN 1 retire ADMIN 2 pendant qu’ADMIN 2 retire ADMIN 1 ; attendre les deux réponses.

**Alors :** Au moins un ADMIN actif subsiste ; la seconde transaction est refusée.

**Preuve attendue :** États commités et nombre d’ADMIN actifs après les deux transactions, résultat du conflit ; au moins un administrateur subsiste.

<a id="t004"></a>
### T004 · Changement de compte natif

**Statut :** À réaliser. **Fonctions :** F01. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R02](../03-fonctionnel/regles-etats.md#r02), [R03](../03-fonctionnel/regles-etats.md#r03), [R04](../03-fonctionnel/regles-etats.md#r04), [R34](../03-fonctionnel/regles-etats.md#r34), [R37](../03-fonctionnel/regles-etats.md#r37).

**Étant donné :** Un compte avec cache se déconnecte puis un autre se connecte.

**Quand :** Charger un dossier et sauvegarder un brouillon local avec le compte 1, se déconnecter, connecter le compte 2 puis ouvrir les vues récentes et le lien profond du dossier initial.

**Alors :** Aucun nom, document ou brouillon du premier n’est visible au second.

**Preuve attendue :** Captures des vues et inspection des espaces locaux/chiffrement après changement ; aucun contenu du compte 1 accessible au compte 2.

<a id="t005"></a>
### T005 · Acceptation nominale

**Statut :** À réaliser. **Fonctions :** F02. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R03](../03-fonctionnel/regles-etats.md#r03), [R05](../03-fonctionnel/regles-etats.md#r05), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12).

**Étant donné :** Une invitation valide vise le compte authentifié.

**Quand :** Ouvrir le lien d’invitation valide dans la session visée, confirmer son acceptation puis charger le dossier créé et ses formations.

**Alors :** Une appartenance et un dossier sont créés, aucune formation fictive.

**Preuve attendue :** Identifiants d’appartenance et de dossier uniques, invitation consommée une fois, liste de formations sans catégorie ajoutée automatiquement.

<a id="t006"></a>
### T006 · Double acceptation

**Statut :** À réaliser. **Fonctions :** F02. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R03](../03-fonctionnel/regles-etats.md#r03), [R05](../03-fonctionnel/regles-etats.md#r05), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12).

**Étant donné :** Le même compte soumet deux fois la même opération.

**Quand :** Soumettre deux acceptations de la même invitation avec le même operationId et la même charge utile, dont une après perte simulée de la première réponse.

**Alors :** Même résultat, un seul dossier et un seul effet métier.

**Preuve attendue :** Deux réponses réconciliées vers les mêmes identifiants, une seule consommation et un seul événement de création.

<a id="t007"></a>
### T007 · Compte différent

**Statut :** À réaliser. **Fonctions :** F02. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R03](../03-fonctionnel/regles-etats.md#r03), [R05](../03-fonctionnel/regles-etats.md#r05), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12).

**Étant donné :** Une autre adresse vérifiée tente de consommer le lien.

**Quand :** Ouvrir le lien d’invitation destiné au compte 1 dans une session dont seule l’adresse du compte 2 est vérifiée, puis confirmer.

**Alors :** Refus, invitation non consommée, aucune donnée privée retournée.

**Preuve attendue :** Réponse de refus expurgée, invitation encore utilisable par le destinataire et absence de dossier créé pour le compte 2.

<a id="t008"></a>
### T008 · Renvoi

**Statut :** À réaliser. **Fonctions :** F02. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R03](../03-fonctionnel/regles-etats.md#r03), [R05](../03-fonctionnel/regles-etats.md#r05), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12).

**Étant donné :** Le personnel renvoie une invitation.

**Quand :** Renvoyer l’invitation depuis le dossier scolaire, essayer l’ancien lien puis accepter le nouveau avec le compte destinataire.

**Alors :** L’ancien lien ne fonctionne plus ; le nouveau garde les rôles autorisés.

**Preuve attendue :** Ancien lien rejeté, nouvelle invitation de même portée/rôles autorisés, aucune élévation de privilège.

<a id="t009"></a>
### T009 · Multi-permis

**Statut :** À réaliser. **Fonctions :** F03. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R06](../03-fonctionnel/regles-etats.md#r06), [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R35](../03-fonctionnel/regles-etats.md#r35), [R36](../03-fonctionnel/regles-etats.md#r36).

**Étant donné :** Un élève suit deux catégories activées.

**Quand :** Créer une leçon dans la formation B et une dans la formation A du même élève ; publier une observation de compétence dans B puis consulter les deux progressions.

**Alors :** Chaque leçon et observation conserve sa formation ; aucune progression croisée.

**Preuve attendue :** Clés de formation des leçons et révisions ; progression A inchangée et compétence étrangère à B refusée.

<a id="t010"></a>
### T010 · Remplacement de document

**Statut :** À réaliser. **Fonctions :** F03. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R06](../03-fonctionnel/regles-etats.md#r06), [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R35](../03-fonctionnel/regles-etats.md#r35), [R36](../03-fonctionnel/regles-etats.md#r36).

**Étant donné :** Une pièce approuvée est remplacée.

**Quand :** Déposer une nouvelle pièce admissible à la place de la pièce approuvée, finaliser le dépôt puis consulter le contrôle courant et l’historique habilité.

**Alors :** Nouveau contrôle PENDING, ancien contrôle conservé en historique restreint.

**Preuve attendue :** Nouveau contrôle PENDING sans réemploi de l’approbation ; ancien contrôle conservé et inaccessible hors des droits prévus.

<a id="t011"></a>
### T011 · Formation en pause

**Statut :** À réaliser. **Fonctions :** F03. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R06](../03-fonctionnel/regles-etats.md#r06), [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R35](../03-fonctionnel/regles-etats.md#r35), [R36](../03-fonctionnel/regles-etats.md#r36).

**Étant donné :** Une formation a encore des leçons futures.

**Quand :** Demander la mise en pause de la formation possédant une leçon future sans fournir de traitement de cette leçon, puis ouvrir les conflits proposés.

**Alors :** La mise en pause exige un traitement explicite de ces leçons ; aucune suppression silencieuse.

**Preuve attendue :** Refus ou étape de traitement explicite ; réservation future toujours présente et aucune suppression/cancellation tacite.

<a id="t012"></a>
### T012 · Affectation retirée

**Statut :** À réaliser. **Fonctions :** F03. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R06](../03-fonctionnel/regles-etats.md#r06), [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R35](../03-fonctionnel/regles-etats.md#r35), [R36](../03-fonctionnel/regles-etats.md#r36).

**Étant donné :** Un moniteur perd une formation.

**Quand :** Retirer l’affectation du moniteur à la formation, puis avec sa session initiale lancer la synchronisation et tenter d’ouvrir/modifier un bilan de cette formation.

**Alors :** Accès et synchronisation sont révoqués ; aucun bilan ancien ne devient modifiable par son token.

**Preuve attendue :** Révocation/purge de portée et refus serveur de modification ; révision publiée inchangée.

<a id="t013"></a>
### T013 · Pause de midi

**Statut :** À réaliser. **Fonctions :** F04. **Règles :** [R08](../03-fonctionnel/regles-etats.md#r08), [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10), [R31](../03-fonctionnel/regles-etats.md#r31), [R35](../03-fonctionnel/regles-etats.md#r35).

**Étant donné :** Une pause coupe une plage ouverte.

**Quand :** Configurer une ouverture 10:00–15:00, une pause 12:00–13:00 et un tampon de 10 minutes ; demander les créneaux puis tenter de réserver une leçon dont le tampon recoupe 12:00.

**Alors :** Aucun créneau proposé ou confirmé ne la recoupe, tampon inclus pour le moniteur.

**Preuve attendue :** Liste de créneaux et réservation refusée ; aucune occupation moniteur ne recoupe la pause, tampon inclus.

<a id="t014"></a>
### T014 · Modification conflictuelle

**Statut :** À réaliser. **Fonctions :** F04. **Règles :** [R08](../03-fonctionnel/regles-etats.md#r08), [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10), [R31](../03-fonctionnel/regles-etats.md#r31), [R35](../03-fonctionnel/regles-etats.md#r35).

**Étant donné :** Un congé est ajouté sur une leçon future.

**Quand :** Sur une leçon confirmée 14:00–14:50, soumettre un congé moniteur 13:30–15:00 sans déplacer ni annuler la leçon.

**Alors :** Refus atomique avec liste autorisée ; la leçon reste confirmée.

**Preuve attendue :** Refus atomique avec conflit autorisé, congé non créé et leçon/version inchangées.

<a id="t015"></a>
### T015 · Heure inexistante

**Statut :** À réaliser. **Fonctions :** F04. **Règles :** [R08](../03-fonctionnel/regles-etats.md#r08), [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10), [R31](../03-fonctionnel/regles-etats.md#r31), [R35](../03-fonctionnel/regles-etats.md#r35).

**Étant donné :** Le personnel saisit une heure locale dans un saut d’heure.

**Quand :** Dans la fixture Europe/Zurich du passage à l’heure d’été, soumettre 2026-03-29 à 02:30 comme heure locale de début sans instant valide correspondant.

**Alors :** Le serveur refuse et demande une autre heure, sans décaler silencieusement.

**Preuve attendue :** Erreur de saisie/validation de l’heure inexistante, aucune conversion silencieuse vers 03:30 et aucune réservation créée.

<a id="t016"></a>
### T016 · Tampon

**Statut :** À réaliser. **Fonctions :** F04. **Règles :** [R08](../03-fonctionnel/regles-etats.md#r08), [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10), [R31](../03-fonctionnel/regles-etats.md#r31), [R35](../03-fonctionnel/regles-etats.md#r35).

**Étant donné :** Deux leçons sont adjacentes mais un tampon est configuré.

**Quand :** Créer une leçon 10:00–10:50 avec tampon moniteur de 10 minutes, puis réserver le même moniteur à 10:50 et réserver le même élève avec un autre moniteur à 10:50.

**Alors :** Le moniteur ne peut être réservé pendant le tampon ; l’élève n’est pas occupé par ce tampon.

**Preuve attendue :** Première tentative refusée pour occupation moniteur ; seconde non refusée au seul motif de ce tampon, sous réserve des autres contraintes.

<a id="t017"></a>
### T017 · Course de réservation

**Statut :** À réaliser. **Fonctions :** F05. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R08](../03-fonctionnel/regles-etats.md#r08), [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R13](../03-fonctionnel/regles-etats.md#r13), [R14](../03-fonctionnel/regles-etats.md#r14).

**Étant donné :** Deux requêtes concurrentes prennent le même moniteur et la même heure.

**Quand :** Envoyer simultanément deux créations de leçon de 10:00 à 10:50 pour le même moniteur, avec élèves et operationId distincts.

**Alors :** Une seule leçon confirme ; pas de notification pour la requête refusée.

**Preuve attendue :** Un seul commit, un conflit, une seule occupation et un seul événement de notification de réservation.

<a id="t018"></a>
### T018 · Collision élève multi-permis

**Statut :** À réaliser. **Fonctions :** F05. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R08](../03-fonctionnel/regles-etats.md#r08), [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R13](../03-fonctionnel/regles-etats.md#r13), [R14](../03-fonctionnel/regles-etats.md#r14).

**Étant donné :** Deux moniteurs réservent le même élève sur deux formations au même moment.

**Quand :** Avec deux moniteurs différents, envoyer en parallèle deux réservations qui occupent le même élève sur les formations A et B durant le même intervalle.

**Alors :** La seconde réservation est refusée au sein de l’école.

**Preuve attendue :** Une seule réservation commitée dans l’école ; contrainte d’occupation vérifiée au niveau personne, pas seulement formation.

<a id="t019"></a>
### T019 · Déplacement refusé

**Statut :** À réaliser. **Fonctions :** F05. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R08](../03-fonctionnel/regles-etats.md#r08), [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R13](../03-fonctionnel/regles-etats.md#r13), [R14](../03-fonctionnel/regles-etats.md#r14).

**Étant donné :** Le nouveau créneau est pris au moment du commit.

**Quand :** Lire la version de la leçon à déplacer, faire occuper le créneau cible par une autre transaction, puis soumettre le déplacement avec les préconditions initiales.

**Alors :** Ancien rendez-vous et version restent inchangés, aucun avis de déplacement.

**Preuve attendue :** Conflit, anciennes heures/occupations/version conservées, aucun avis de déplacement émis.

<a id="t020"></a>
### T020 · Réponse perdue

**Statut :** À réaliser. **Fonctions :** F05. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R08](../03-fonctionnel/regles-etats.md#r08), [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R13](../03-fonctionnel/regles-etats.md#r13), [R14](../03-fonctionnel/regles-etats.md#r14).

**Étant donné :** La transaction réussit mais la réponse réseau est perdue.

**Quand :** Faire commiter une réservation, couper sa réponse avant réception client, puis reprendre le suivi d’opération et réémettre la même intention avec la même clé.

**Alors :** La consultation/reprise de la même opération retrouve une seule leçon.

**Preuve attendue :** Une seule leçon/occupation, résultat identique après reprise et aucune seconde notification.

<a id="t021"></a>
### T021 · Souhait séparé

**Statut :** À réaliser. **Fonctions :** F06. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R17](../03-fonctionnel/regles-etats.md#r17), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** L’élève demande un exercice avant la leçon.

**Quand :** L’élève enregistre un souhait pour sa prochaine leçon ; le moniteur consulte ce souhait sans l’accepter et compare les objectifs pédagogiques avant/après.

**Alors :** Le moniteur voit une proposition distincte, pas un objectif déjà validé.

**Preuve attendue :** Souhait visible comme demande, objectifs officiels et observations publiées inchangés.

<a id="t022"></a>
### T022 · Première leçon

**Statut :** À réaliser. **Fonctions :** F06. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R17](../03-fonctionnel/regles-etats.md#r17), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** Aucun bilan n’existe encore.

**Quand :** Ouvrir la préparation de la toute première leçon d’une formation sans bilan précédent et renseigner un objectif.

**Alors :** État vide pédagogique, possibilité de préparer sans note artificielle.

**Preuve attendue :** État initial explicite sans fausse dernière leçon ; objectif enregistré et absence d’historique inventé.

<a id="t023"></a>
### T023 · Leçon annulée

**Statut :** À réaliser. **Fonctions :** F06. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R17](../03-fonctionnel/regles-etats.md#r17), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** Une leçon préparée est annulée.

**Quand :** Annuler la leçon préparée depuis une autre session puis tenter de modifier sa préparation avec la version initiale.

**Alors :** Les objectifs ne deviennent pas des observations ; le souhait de formation demeure.

**Preuve attendue :** Refus de modification selon état/version et conservation consultable de la préparation autorisée ; leçon non réactivée.

<a id="t024"></a>
### T024 · Deux éditeurs

**Statut :** À réaliser. **Fonctions :** F06. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R17](../03-fonctionnel/regles-etats.md#r17), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** L’élève modifie son souhait tandis que le moniteur prépare.

**Quand :** Charger la même préparation version 1 dans deux sessions ; enregistrer un objectif depuis la première puis envoyer une autre modification depuis la seconde avec version 1.

**Alors :** Aucune écriture n’écrase le texte de l’autre, versions de ressources distinctes.

**Preuve attendue :** Premier texte conservé, seconde écriture refusée par précondition et conflit présenté sans écrasement.

<a id="t025"></a>
### T025 · Clôture atomique

**Statut :** À réaliser. **Fonctions :** F07. **Règles :** [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R14](../03-fonctionnel/regles-etats.md#r14), [R15](../03-fonctionnel/regles-etats.md#r15), [R16](../03-fonctionnel/regles-etats.md#r16), [R23](../03-fonctionnel/regles-etats.md#r23), [R39](../03-fonctionnel/regles-etats.md#r39), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Une leçon prévue est réellement terminée.

**Quand :** Après arrêt local du GPS, soumettre CompleteLesson sur une leçon PLANNED avec heures réelles valides et brouillon, puis relire leçon, brouillon, charge et consommation.

**Alors :** Résultat, brouillon, charge et audit sont tous créés ou aucun ne l’est.

**Preuve attendue :** COMPLETED et brouillon/compte/consommation commités ensemble ; résultat d’opération unique et aucune publication automatique.

<a id="t026"></a>
### T026 · Horloge passée

**Statut :** À réaliser. **Fonctions :** F07. **Règles :** [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R14](../03-fonctionnel/regles-etats.md#r14), [R15](../03-fonctionnel/regles-etats.md#r15), [R16](../03-fonctionnel/regles-etats.md#r16), [R23](../03-fonctionnel/regles-etats.md#r23), [R39](../03-fonctionnel/regles-etats.md#r39), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** L’heure de fin planifiée est dépassée sans action.

**Quand :** Avancer uniquement l’horloge au-delà de la fin prévue sans transmettre de constat, puis rafraîchir la leçon et ses écritures commerciales.

**Alors :** La leçon reste PLANNED avec résultat à renseigner, pas NO_SHOW automatique.

**Preuve attendue :** Leçon non passée automatiquement à COMPLETED, aucun brouillon/encaissement créé par le temps seul.

<a id="t027"></a>
### T027 · Résultat concurrent

**Statut :** À réaliser. **Fonctions :** F07. **Règles :** [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R14](../03-fonctionnel/regles-etats.md#r14), [R15](../03-fonctionnel/regles-etats.md#r15), [R16](../03-fonctionnel/regles-etats.md#r16), [R23](../03-fonctionnel/regles-etats.md#r23), [R39](../03-fonctionnel/regles-etats.md#r39), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Un appareil termine pendant qu’un autre annule.

**Quand :** Soumettre en parallèle le constat COMPLETED et l’annulation de la même leçon avec sa version initiale et des operationId distincts.

**Alors :** Une seule commande de version courante réussit ; l’autre devient un conflit visible.

**Preuve attendue :** Une seule transition terminale, seconde requête en conflit, écritures associées seulement au résultat retenu.

<a id="t028"></a>
### T028 · Correction avec paiement

**Statut :** À réaliser. **Fonctions :** F07. **Règles :** [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R14](../03-fonctionnel/regles-etats.md#r14), [R15](../03-fonctionnel/regles-etats.md#r15), [R16](../03-fonctionnel/regles-etats.md#r16), [R23](../03-fonctionnel/regles-etats.md#r23), [R39](../03-fonctionnel/regles-etats.md#r39), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Une leçon payée est déclarée réalisée à tort.

**Quand :** Enregistrer un règlement sur une leçon réalisée, puis corriger son résultat/heures par la commande motivée prévue et consulter le journal.

**Alors :** Correction bloquée tant que compensation financière et traitement du bilan ne sont pas explicités.

**Preuve attendue :** Historique du résultat et du règlement conservé, ajustement explicite selon politique et aucune suppression du paiement.

<a id="t029"></a>
### T029 · Publication minimale utile

**Statut :** À réaliser. **Fonctions :** F08. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R11](../03-fonctionnel/regles-etats.md#r11), [R17](../03-fonctionnel/regles-etats.md#r17), [R18](../03-fonctionnel/regles-etats.md#r18), [R19](../03-fonctionnel/regles-etats.md#r19), [R20](../03-fonctionnel/regles-etats.md#r20), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** Un bilan a un point travaillé, un constat et une prochaine étape.

**Quand :** Renseigner travaillé/constat/prochaine étape dans un brouillon sans note de compétence ni pièce jointe, prévisualiser puis publier connecté.

**Alors :** Il peut être publié sans noter toutes les compétences ni joindre de photo.

**Preuve attendue :** Révision publiée contenant exactement les trois textes saisis, aucune note à zéro ni photo fictive.

<a id="t030"></a>
### T030 · Brouillon invisible

**Statut :** À réaliser. **Fonctions :** F08. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R11](../03-fonctionnel/regles-etats.md#r11), [R17](../03-fonctionnel/regles-etats.md#r17), [R18](../03-fonctionnel/regles-etats.md#r18), [R19](../03-fonctionnel/regles-etats.md#r19), [R20](../03-fonctionnel/regles-etats.md#r20), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** Un bilan non publié existe sur le serveur.

**Quand :** Avec un élève authentifié, ouvrir l’URL du brouillon non publié et relire sa progression après sauvegarde de ce brouillon par le moniteur.

**Alors :** L’élève ne voit ni son texte ni une progression qui en serait déduite.

**Preuve attendue :** Accès privé refusé et progression élève identique ; texte du brouillon absent des réponses publiques.

<a id="t031"></a>
### T031 · Envoi tardif

**Statut :** À réaliser. **Fonctions :** F08. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R11](../03-fonctionnel/regles-etats.md#r11), [R17](../03-fonctionnel/regles-etats.md#r17), [R18](../03-fonctionnel/regles-etats.md#r18), [R19](../03-fonctionnel/regles-etats.md#r19), [R20](../03-fonctionnel/regles-etats.md#r20), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** Un bilan ancien arrive après un bilan plus récent de la même compétence.

**Quand :** Publier un bilan daté de la leçon la plus récente, puis synchroniser et publier un bilan d’une leçon antérieure concernant la même compétence.

**Alors :** La projection conserve l’observation chronologiquement la plus récente.

**Preuve attendue :** Ordre par date métier/version de leçon, pas ordre d’arrivée ; projection sur l’observation la plus récente et historique complet.

<a id="t032"></a>
### T032 · Correction historisée

**Statut :** À réaliser. **Fonctions :** F08. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R11](../03-fonctionnel/regles-etats.md#r11), [R17](../03-fonctionnel/regles-etats.md#r17), [R18](../03-fonctionnel/regles-etats.md#r18), [R19](../03-fonctionnel/regles-etats.md#r19), [R20](../03-fonctionnel/regles-etats.md#r20), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** Un moniteur corrige une révision publiée.

**Quand :** Créer un brouillon de correction depuis une publication existante, saisir le motif et la modification, puis publier avec la version de base attendue.

**Alors :** Nouvelle révision et motif ; ancienne révision intacte et projection recalculée.

**Preuve attendue :** Nouvelle révision et motif, ancienne révision immuable, projection recalculée et accès conformes au retrait/remplacement.

<a id="t033"></a>
### T033 · Type falsifié

**Statut :** À réaliser. **Fonctions :** F09. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R21](../03-fonctionnel/regles-etats.md#r21), [R22](../03-fonctionnel/regles-etats.md#r22), [R30](../03-fonctionnel/regles-etats.md#r30), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** Un fichier non-image porte extension .jpg et Content-Type image/jpeg.

**Quand :** Déposer des octets non-image avec nom .jpg et type déclaré image/jpeg, finaliser puis attendre le résultat d’inspection.

**Alors :** Il n’atteint pas READY sur la seule foi de ces métadonnées.

**Preuve attendue :** Pièce non READY, motif de rejet/quarantaine et absence de lien de lecture publiable ; aucun test fondé uniquement sur l’extension.

<a id="t034"></a>
### T034 · Envoi interrompu

**Statut :** À réaliser. **Fonctions :** F09. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R21](../03-fonctionnel/regles-etats.md#r21), [R22](../03-fonctionnel/regles-etats.md#r22), [R30](../03-fonctionnel/regles-etats.md#r30), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** La connexion tombe pendant le dépôt.

**Quand :** Couper le transfert d’un fichier avant finalisation, relancer l’application puis reprendre selon le protocole du dépôt existant.

**Alors :** La pièce reste en attente et peut être reprise ; aucune pièce fantôme visible.

**Preuve attendue :** Même dépôt en attente puis résultat contrôlé ; aucune référence publiée vers des octets incomplets et aucun second document fantôme.

<a id="t035"></a>
### T035 · Accès autre école

**Statut :** À réaliser. **Fonctions :** F09. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R21](../03-fonctionnel/regles-etats.md#r21), [R22](../03-fonctionnel/regles-etats.md#r22), [R30](../03-fonctionnel/regles-etats.md#r30), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** Un utilisateur connaît documentId d’une autre école.

**Quand :** Authentifier un membre de A et demander un ticket de lecture pour le documentId appartenant à B.

**Alors :** Aucun lien de lecture ne lui est donné et le nom de fichier n’est pas révélé.

**Preuve attendue :** Réponse de refus/absence sans nom de fichier ni URL signée ; journal expurgé et aucun octet de B reçu.

<a id="t036"></a>
### T036 · Bilan sans photo prête

**Statut :** À réaliser. **Fonctions :** F09. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R21](../03-fonctionnel/regles-etats.md#r21), [R22](../03-fonctionnel/regles-etats.md#r22), [R30](../03-fonctionnel/regles-etats.md#r30), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** Le texte est prêt, une photo ne l’est pas.

**Quand :** Prévisualiser un bilan dont le texte est valide et la photo encore en transfert, exclure explicitement cette photo puis confirmer la publication.

**Alors :** Publication possible après exclusion explicite de la photo ; aucun lien cassé présenté à l’élève.

**Preuve attendue :** Révision sans référence à la pièce non READY, texte publié et photo toujours distincte/en attente.

<a id="t037"></a>
### T037 · Paiement partiel

**Statut :** À réaliser. **Fonctions :** F10. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R23](../03-fonctionnel/regles-etats.md#r23), [R24](../03-fonctionnel/regles-etats.md#r24), [R25](../03-fonctionnel/regles-etats.md#r25), [R32](../03-fonctionnel/regles-etats.md#r32).

**Étant donné :** Charge 9 000 centimes ; encaissement de 4 000.

**Quand :** Sur une charge de 9 000 centimes, enregistrer un reçu de 4 000 centimes puis consulter le compte et le résultat de leçon.

**Alors :** Reste dû 5 000 ; état partiel distinct de réalisé.

**Preuve attendue :** Reste dû 5 000 centimes, statut partiel et résultat de leçon indépendant ; ledger réconcilié.

<a id="t038"></a>
### T038 · Double effet évité

**Statut :** À réaliser. **Fonctions :** F10. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R23](../03-fonctionnel/regles-etats.md#r23), [R24](../03-fonctionnel/regles-etats.md#r24), [R25](../03-fonctionnel/regles-etats.md#r25), [R32](../03-fonctionnel/regles-etats.md#r32).

**Étant donné :** La même commande d’encaissement est renvoyée.

**Quand :** Envoyer deux fois la même commande de reçu de 4 000 centimes avec charge utile et operationId identiques.

**Alors :** Un seul mouvement, même solde et même identifiant de résultat.

**Preuve attendue :** Un seul reçu, mêmes identifiants de réponse et même solde net après les deux appels.

<a id="t039"></a>
### T039 · Remboursement excessif

**Statut :** À réaliser. **Fonctions :** F10. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R23](../03-fonctionnel/regles-etats.md#r23), [R24](../03-fonctionnel/regles-etats.md#r24), [R25](../03-fonctionnel/regles-etats.md#r25), [R32](../03-fonctionnel/regles-etats.md#r32).

**Étant donné :** Le remboursement demandé dépasse l’encaissé net.

**Quand :** Après encaissement net de 4 000 centimes, soumettre un remboursement de 4 001 centimes.

**Alors :** Refus sans écriture ni changement du solde.

**Preuve attendue :** Refus et comparaison du ledger avant/après identique ; solde et notifications inchangés.

<a id="t040"></a>
### T040 · Correction de montant

**Statut :** À réaliser. **Fonctions :** F10. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R23](../03-fonctionnel/regles-etats.md#r23), [R24](../03-fonctionnel/regles-etats.md#r24), [R25](../03-fonctionnel/regles-etats.md#r25), [R32](../03-fonctionnel/regles-etats.md#r32).

**Étant donné :** Un encaissement erroné a été enregistré.

**Quand :** Corriger un reçu erroné via une contre-écriture motivée, puis enregistrer la valeur correcte selon la procédure autorisée.

**Alors :** Contre-écriture traçable ; aucun effacement de l’entrée d’origine.

**Preuve attendue :** Entrée d’origine conservée, lien vers contre-écriture/motif et calcul net exact sans effacement d’historique.

<a id="t041"></a>
### T041 · Email indisponible

**Statut :** À réaliser. **Fonctions :** F11. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R13](../03-fonctionnel/regles-etats.md#r13), [R26](../03-fonctionnel/regles-etats.md#r26), [R32](../03-fonctionnel/regles-etats.md#r32), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** La réservation commit mais le fournisseur email échoue.

**Quand :** Faire commiter une réservation tandis que le fournisseur email de test renvoie une erreur, puis exécuter le worker de notification.

**Alors :** La leçon reste confirmée ; état d’avis en attente/échec visible.

**Preuve attendue :** Réservation toujours confirmée, notification en attente/échec et reprise bornée sans seconde réservation.

<a id="t042"></a>
### T042 · Bilan privé

**Statut :** À réaliser. **Fonctions :** F11. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R13](../03-fonctionnel/regles-etats.md#r13), [R26](../03-fonctionnel/regles-etats.md#r26), [R32](../03-fonctionnel/regles-etats.md#r32), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Un avis de publication est envoyé.

**Quand :** Publier un bilan contenant une note privée synthétique et une pièce, puis inspecter le message email/push de notification de publication.

**Alors :** Il ne contient ni compétence, ni note personnelle, ni pièce jointe sensible.

**Preuve attendue :** Message de service sans texte pédagogique, compétence, pièce sensible ou lien public ; navigation authentifiée vers la ressource.

<a id="t043"></a>
### T043 · Destinataire révoqué

**Statut :** À réaliser. **Fonctions :** F11. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R13](../03-fonctionnel/regles-etats.md#r13), [R26](../03-fonctionnel/regles-etats.md#r26), [R32](../03-fonctionnel/regles-etats.md#r32), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Un avis est en file puis les droits changent.

**Quand :** Mettre un avis en file, retirer ensuite l’accès du destinataire avant exécution du worker, puis déclencher cet envoi.

**Alors :** L’envoi est annulé ou recalculé, sans fuite de contenu.

**Preuve attendue :** Avis annulé ou audience recalculée avec accès courant ; aucun contenu devenu interdit transmis au fournisseur.

<a id="t044"></a>
### T044 · Webhook doublé

**Statut :** À réaliser. **Fonctions :** F11. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R13](../03-fonctionnel/regles-etats.md#r13), [R26](../03-fonctionnel/regles-etats.md#r26), [R32](../03-fonctionnel/regles-etats.md#r32), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Le fournisseur envoie deux fois un accusé de livraison.

**Quand :** Transmettre deux fois au webhook le même événement fournisseur de livraison, avec même identifiant et signature de test valide.

**Alors :** Un seul changement d’état de livraison ; aucun nouvel événement métier.

**Preuve attendue :** Une seule transition de livraison et aucun nouvel événement métier ni envoi supplémentaire.

<a id="t045"></a>
### T045 · Arrêt brutal

**Statut :** À réaliser. **Fonctions :** F12. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R27](../03-fonctionnel/regles-etats.md#r27), [R28](../03-fonctionnel/regles-etats.md#r28), [R34](../03-fonctionnel/regles-etats.md#r34), [R37](../03-fonctionnel/regles-etats.md#r37), [R39](../03-fonctionnel/regles-etats.md#r39), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Fermer de force l’app après une sauvegarde locale confirmée.

**Quand :** Sauvegarder un brouillon local et attendre l’acquittement de persistance, tuer l’application puis rouvrir avec le même compte et un lease valide.

**Alors :** Le brouillon réapparaît à la réouverture du même compte autorisé.

**Preuve attendue :** Texte exact restauré depuis stockage durable ; aucune sauvegarde serveur ou publication prétendue si hors ligne.

<a id="t046"></a>
### T046 · Conflit avec annulation

**Statut :** À réaliser. **Fonctions :** F12. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R27](../03-fonctionnel/regles-etats.md#r27), [R28](../03-fonctionnel/regles-etats.md#r28), [R34](../03-fonctionnel/regles-etats.md#r34), [R37](../03-fonctionnel/regles-etats.md#r37), [R39](../03-fonctionnel/regles-etats.md#r39), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Un bilan offline est envoyé après annulation serveur.

**Quand :** Sauvegarder un constat/brouillon hors ligne, annuler la leçon sur le serveur, reconnecter puis envoyer la commande en attente.

**Alors :** Aucune réactivation automatique ; conflit visible et notes conservées verrouillables.

**Preuve attendue :** Conflit explicite, leçon toujours annulée et notes locales conservées sous accès autorisé, sans réactivation automatique.

<a id="t047"></a>
### T047 · Lease expirée

**Statut :** À réaliser. **Fonctions :** F12. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R27](../03-fonctionnel/regles-etats.md#r27), [R28](../03-fonctionnel/regles-etats.md#r28), [R34](../03-fonctionnel/regles-etats.md#r34), [R37](../03-fonctionnel/regles-etats.md#r37), [R39](../03-fonctionnel/regles-etats.md#r39), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** L’app reste hors ligne au-delà de la durée autorisée.

**Quand :** Préparer un cache avec lease borné, couper le réseau, avancer au-delà de son expiration puis tenter lecture du dossier et écriture d’un bilan.

**Alors :** La projection est verrouillée ; aucune lecture ou commande métier nouvelle.

**Preuve attendue :** Projection verrouillée, commandes nouvelles empêchées, aucun contournement par changement d’horloge locale.

<a id="t048"></a>
### T048 · Disque plein

**Statut :** À réaliser. **Fonctions :** F12. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R27](../03-fonctionnel/regles-etats.md#r27), [R28](../03-fonctionnel/regles-etats.md#r28), [R34](../03-fonctionnel/regles-etats.md#r34), [R37](../03-fonctionnel/regles-etats.md#r37), [R39](../03-fonctionnel/regles-etats.md#r39), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** L’écriture locale échoue.

**Quand :** Simuler une erreur de stockage lors de la sauvegarde d’un brouillon, puis tenter de quitter la vue.

**Alors :** Aucun faux succès ; avertissement et prévention de perte avant navigation.

**Preuve attendue :** Aucun acquittement de sauvegarde, erreur visible et texte encore récupérable dans la session selon le dispositif testé.

<a id="t049"></a>
### T049 · Réglage non rétroactif

**Statut :** À réaliser. **Fonctions :** F13. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R04](../03-fonctionnel/regles-etats.md#r04), [R06](../03-fonctionnel/regles-etats.md#r06), [R35](../03-fonctionnel/regles-etats.md#r35), [R36](../03-fonctionnel/regles-etats.md#r36), [R38](../03-fonctionnel/regles-etats.md#r38).

**Étant donné :** Le prix par défaut change après une réservation.

**Quand :** Réserver une prestation au prix initial, modifier son prix de catalogue, puis relire la première réservation et en créer une seconde.

**Alors :** La réservation conserve son prix photographié ; les suivantes utilisent le nouveau.

**Preuve attendue :** Première réservation conserve son snapshot ; seconde utilise la nouvelle version tarifaire explicitement applicable.

<a id="t050"></a>
### T050 · Catalogue vide

**Statut :** À réaliser. **Fonctions :** F13. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R04](../03-fonctionnel/regles-etats.md#r04), [R06](../03-fonctionnel/regles-etats.md#r06), [R35](../03-fonctionnel/regles-etats.md#r35), [R36](../03-fonctionnel/regles-etats.md#r36), [R38](../03-fonctionnel/regles-etats.md#r38).

**Étant donné :** L’ADMIN active une catégorie sans contenu validé.

**Quand :** Tenter d’activer une offre/catégorie dont les prérequis de contenu ou de profil validé manquent.

**Alors :** Activation refusée avec éléments manquants, pas fausse prise en charge.

**Preuve attendue :** Activation refusée avec liste d’éléments manquants ; offre non présentée comme réservable ou réglementairement validée.

<a id="t051"></a>
### T051 · Identité scolaire

**Statut :** À réaliser. **Fonctions :** F13. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R04](../03-fonctionnel/regles-etats.md#r04), [R06](../03-fonctionnel/regles-etats.md#r06), [R35](../03-fonctionnel/regles-etats.md#r35), [R36](../03-fonctionnel/regles-etats.md#r36), [R38](../03-fonctionnel/regles-etats.md#r38).

**Étant donné :** Le logo est absent ou rejeté.

**Quand :** Ouvrir l’onboarding et le workspace sans logo, puis répéter avec une pièce de logo REJECTED.

**Alors :** L’interface reste lisible avec le nom, sans casser la navigation.

**Preuve attendue :** Nom scolaire lisible et navigation utilisable dans les deux cas ; aucun lien d’image cassé ni blocage indu.

<a id="t052"></a>
### T052 · Changement sensible

**Statut :** À réaliser. **Fonctions :** F13. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R04](../03-fonctionnel/regles-etats.md#r04), [R06](../03-fonctionnel/regles-etats.md#r06), [R35](../03-fonctionnel/regles-etats.md#r35), [R36](../03-fonctionnel/regles-etats.md#r36), [R38](../03-fonctionnel/regles-etats.md#r38).

**Étant donné :** Un rôle ou grant est modifié.

**Quand :** Changer un grant ou rôle sensible avec une authentification trop ancienne, puis refaire la demande après réauthentification admissible.

**Alors :** Réauthentification si nécessaire, audit et epoch actualisée.

**Preuve attendue :** Première demande refusée sans effet, seconde auditée, epoch d’autorisation modifiée et accès précédents réévalués.

<a id="t053"></a>
### T053 · Archivage avec rendez-vous

**Statut :** À réaliser. **Fonctions :** F14. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R29](../03-fonctionnel/regles-etats.md#r29), [R30](../03-fonctionnel/regles-etats.md#r30), [R32](../03-fonctionnel/regles-etats.md#r32), [R34](../03-fonctionnel/regles-etats.md#r34).

**Étant donné :** Un élève possède une leçon future.

**Quand :** Depuis la fiche d’un élève avec leçon future, demander l’aperçu d’archivage puis tenter l’archivage sans traiter le rendez-vous.

**Alors :** L’archivage direct est refusé et présente un traitement explicite.

**Preuve attendue :** Blocage listant uniquement les conflits autorisés ; dossier actif et réservation inchangée.

<a id="t054"></a>
### T054 · Portée multi-écoles

**Statut :** À réaliser. **Fonctions :** F14. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R29](../03-fonctionnel/regles-etats.md#r29), [R30](../03-fonctionnel/regles-etats.md#r30), [R32](../03-fonctionnel/regles-etats.md#r32), [R34](../03-fonctionnel/regles-etats.md#r34).

**Étant donné :** La suppression vise l’école A seulement.

**Quand :** Faire approuver puis exécuter une demande d’effacement scolaire de A pour une personne aussi membre de B, puis relire ses deux portées avec les comptes habilités.

**Alors :** Les données de B ne sont ni exposées ni effacées.

**Preuve attendue :** Objets applicables de A traités, objets de B inchangés et non inclus dans le rapport de A ; identité globale non supprimée tacitement.

<a id="t055"></a>
### T055 · Export restreint

**Statut :** À réaliser. **Fonctions :** F14. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R29](../03-fonctionnel/regles-etats.md#r29), [R30](../03-fonctionnel/regles-etats.md#r30), [R32](../03-fonctionnel/regles-etats.md#r32), [R34](../03-fonctionnel/regles-etats.md#r34).

**Étant donné :** Un export d’élève est produit.

**Quand :** Produire l’export autorisé d’un seul élève d’A dans une fixture contenant un second élève et des notes privées soumises à examen.

**Alors :** Aucun autre élève ni note privée non communicable sans examen n’est inclus.

**Preuve attendue :** Manifeste et fichiers de la seule portée approuvée ; aucun objet de l’autre élève ni inclusion automatique des notes exclues.

<a id="t056"></a>
### T056 · Restauration après suppression

**Statut :** À réaliser. **Fonctions :** F14. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R29](../03-fonctionnel/regles-etats.md#r29), [R30](../03-fonctionnel/regles-etats.md#r30), [R32](../03-fonctionnel/regles-etats.md#r32), [R34](../03-fonctionnel/regles-etats.md#r34).

**Étant donné :** Une sauvegarde antérieure à une purge est restaurée.

**Quand :** Restaurer dans un environnement isolé une sauvegarde antérieure à une purge, réappliquer les tombstones avant ouverture puis rechercher les objets effacés.

**Alors :** Les tombstones sont réappliqués avant accès utilisateur ; les données supprimées ne réapparaissent pas.

**Preuve attendue :** Journal d’ordre restauration/tombstones/ouverture et recherches API/objets sans résurrection ; aucun accès utilisateur avant convergence.

<a id="t057"></a>
### T057 · Isolation objet et recherche

**Statut :** À réaliser. **Fonctions :** F01 F03 F09. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R02](../03-fonctionnel/regles-etats.md#r02).

**Étant donné :** Deux écoles A/B et identifiants connus d’objets B.

**Quand :** Appeler listes, détails, recherche et API de fichiers sous session A.

**Alors :** Aucune donnée B dans corps, compteurs, erreurs ou métadonnées ; aucune mutation B.


<a id="t058"></a>
### T058 · RLS avec vrai rôle applicatif

**Statut :** À réaliser. **Fonctions :** F01. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R02](../03-fonctionnel/regles-etats.md#r02).

**Étant donné :** Tables A/B et rôle SQL de l’API sans propriété ni BYPASSRLS.

**Quand :** Lire et modifier B dans une transaction de contexte A.

**Alors :** Politiques bloquantes ; vérifier également qu’un contexte de pool précédent n’est pas réutilisé.


<a id="t059"></a>
### T059 · Double réservation concurrente

**Statut :** À réaliser. **Fonctions :** F05. **Règles :** [R08](../03-fonctionnel/regles-etats.md#r08), [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10), [R13](../03-fonctionnel/regles-etats.md#r13).

**Étant donné :** Deux requêtes simultanées sur même personne/intervalle.

**Quand :** Lancer les deux transactions réellement en concurrence, pas deux mocks séquentiels.

**Alors :** Une seule réservation commitée ; seconde 409 ; occupations et leçons cohérentes.


<a id="t060"></a>
### T060 · Élève multi-permis concurrent

**Statut :** À réaliser. **Fonctions :** F03 F05. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R10](../03-fonctionnel/regles-etats.md#r10).

**Étant donné :** Même personne, formations B et A, deux moniteurs.

**Quand :** Réserver deux leçons qui se chevauchent.

**Alors :** Seconde refusée dans l’école malgré deux trainingId.


<a id="t061"></a>
### T061 · Personne cumulant les rôles

**Statut :** À réaliser. **Fonctions :** F01 F05. **Règles :** [R03](../03-fonctionnel/regles-etats.md#r03), [R10](../03-fonctionnel/regles-etats.md#r10).

**Étant donné :** Une personne moniteur sur une leçon et élève sur une autre.

**Quand :** Réserver des intervalles qui se recouvrent, puis une leçon où elle occupe les deux rôles.

**Alors :** Les deux cas sont refusés ; resource_kind ne contourne pas la capacité.


<a id="t062"></a>
### T062 · Fermeture et réservation en course

**Statut :** À réaliser. **Fonctions :** F04 F05. **Règles :** [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10).

**Étant donné :** Un créneau disponible et une fermeture proposée au même instant.

**Quand :** Créer fermeture et leçon simultanément.

**Alors :** Une issue cohérente seulement ; aucune leçon commitée dans une fermeture nouvellement validée.


<a id="t063"></a>
### T063 · Retour au printemps

**Statut :** À réaliser. **Fonctions :** F04 F05. **Règles :** [R31](../03-fonctionnel/regles-etats.md#r31).

**Étant donné :** 29 mars 2026 à 02:30 Europe/Zurich.

**Quand :** Proposer puis envoyer cette heure locale.

**Alors :** Heure rejetée ; aucune conversion silencieuse vers 03:30.


<a id="t064"></a>
### T064 · Heure répétée en automne

**Statut :** À réaliser. **Fonctions :** F04 F05. **Règles :** [R31](../03-fonctionnel/regles-etats.md#r31).

**Étant donné :** 25 octobre 2026 à 02:30 Europe/Zurich.

**Quand :** Choisir successivement les deux offsets sur des fixtures distinctes.

**Alors :** Instants différents, affichage scolaire précis et durée réelle correcte.


<a id="t065"></a>
### T065 · Téléphone en voyage

**Statut :** À réaliser. **Fonctions :** F05. **Règles :** [R31](../03-fonctionnel/regles-etats.md#r31).

**Étant donné :** Rendez-vous scolaire à 14:00 Zurich, appareil dans un autre fuseau.

**Quand :** Ouvrir puis modifier un autre champ sans toucher l’heure.

**Alors :** Heure scolaire et instant du rendez-vous inchangés.


<a id="t066"></a>
### T066 · Perte de réponse après clôture

**Statut :** À réaliser. **Fonctions :** F07 F12. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Commande CompleteLesson valide.

**Quand :** Couper la réponse après commit puis renvoyer la même clé et charge.

**Alors :** Une charge, un résultat et un brouillon ; même identifiants retournés.


<a id="t067"></a>
### T067 · Même clé, autre charge

**Statut :** À réaliser. **Fonctions :** F07 F10 F12. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12).

**Étant donné :** Une opération déjà confirmée.

**Quand :** Réutiliser operationId avec montant ou corps différent.

**Alors :** 409 d’idempotence, aucun second effet.


<a id="t068"></a>
### T068 · Rollback de clôture

**Statut :** À réaliser. **Fonctions :** F07 F10 F11. **Règles :** [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Une erreur SQL injectée avant création complète de l’outbox.

**Quand :** Exécuter CompleteLesson.

**Alors :** Aucun fragment de résultat, brouillon, charge ou notification persisté.


<a id="t069"></a>
### T069 · Deux encaissements parallèles

**Statut :** À réaliser. **Fonctions :** F10. **Règles :** [R24](../03-fonctionnel/regles-etats.md#r24), [R25](../03-fonctionnel/regles-etats.md#r25).

**Étant donné :** Compte avec solde synthétique de 9 000 centimes.

**Quand :** Soumettre deux encaissements de 6 000 chacun sur la même version.

**Alors :** Un seul accepté ; solde non négatif, version courante renvoyée après rechargement.


<a id="t070"></a>
### T070 · Annulation déjà encaissée

**Statut :** À réaliser. **Fonctions :** F07 F10. **Règles :** [R16](../03-fonctionnel/regles-etats.md#r16), [R23](../03-fonctionnel/regles-etats.md#r23), [R25](../03-fonctionnel/regles-etats.md#r25).

**Étant donné :** Leçon complétée, charge et encaissement existants.

**Quand :** Corriger vers CANCELLED sans compensation financière valide.

**Alors :** Refus motivé, bilan/charge/paiement restent inchangés.


<a id="t071"></a>
### T071 · Accord pédagogique périmé

**Statut :** À réaliser. **Fonctions :** F07 F08. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R16](../03-fonctionnel/regles-etats.md#r16), [R19](../03-fonctionnel/regles-etats.md#r19).

**Étant donné :** Accord valide sur versions déterminées.

**Quand :** Modifier la proposition ou le compte, puis exécuter ; essayer aussi après expiration.

**Alors :** Refus, aucun retrait de bilan ou écriture financière ; nouvel accord nécessaire.


<a id="t072"></a>
### T072 · Observation ancienne tardive

**Statut :** À réaliser. **Fonctions :** F08 F12. **Règles :** [R17](../03-fonctionnel/regles-etats.md#r17), [R19](../03-fonctionnel/regles-etats.md#r19), [R20](../03-fonctionnel/regles-etats.md#r20).

**Étant donné :** Observation récente déjà publiée et ancien bilan reçu ensuite.

**Quand :** Publier cet ancien bilan avec sa vraie date de leçon.

**Alors :** Historique enrichi sans remplacer la progression récente.


<a id="t073"></a>
### T073 · Retrait de dernière observation

**Statut :** À réaliser. **Fonctions :** F08. **Règles :** [R19](../03-fonctionnel/regles-etats.md#r19), [R20](../03-fonctionnel/regles-etats.md#r20).

**Étant donné :** Deux observations successives sur une compétence.

**Quand :** Retirer la dernière révision avec motif et droits.

**Alors :** Projection revient à la précédente éligible ; aucune moyenne inventée.


<a id="t074"></a>
### T074 · Snapshot interrompu

**Statut :** À réaliser. **Fonctions :** F12. **Règles :** [R27](../03-fonctionnel/regles-etats.md#r27), [R34](../03-fonctionnel/regles-etats.md#r34).

**Étant donné :** Ancienne projection autorisée et nouvel instantané de plusieurs pages.

**Quand :** Couper au milieu, relancer, puis terminer.

**Alors :** Ancienne projection intacte jusqu’au remplacement atomique complet ; brouillons séparés conservés.


<a id="t075"></a>
### T075 · Ordre de commit et curseur

**Statut :** À réaliser. **Fonctions :** F12. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R34](../03-fonctionnel/regles-etats.md#r34).

**Étant donné :** Deux transactions dont une tarde avant commit et un lecteur de changements.

**Quand :** Forcer les commits dans un ordre défavorable puis paginer.

**Alors :** Tous événements éligibles reçus une fois logiquement ; aucun saut lié à allocation précoce de séquence.


<a id="t076"></a>
### T076 · Pagination dans une transaction

**Statut :** À réaliser. **Fonctions :** F12. **Règles :** [R34](../03-fonctionnel/regles-etats.md#r34), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Une clôture produit plusieurs événements et dépasse une page de changements.

**Quand :** Paginer à la limite d’un même sequence.

**Alors :** L’ordinal préserve chaque événement ; pas de perte de charge ou de brouillon.


<a id="t077"></a>
### T077 · Révocation pendant snapshot

**Statut :** À réaliser. **Fonctions :** F01 F12. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R34](../03-fonctionnel/regles-etats.md#r34), [R37](../03-fonctionnel/regles-etats.md#r37).

**Étant donné :** Premier lot de pages reçu, affectation retirée avant le suivant.

**Quand :** Demander les pages restantes et un ticket déjà émis.

**Alors :** Nouveaux accès refusés ; projection verrouillée/reconstruite selon droits actuels.


<a id="t078"></a>
### T078 · Horloge et cache expiré

**Statut :** À réaliser. **Fonctions :** F12. **Règles :** [R27](../03-fonctionnel/regles-etats.md#r27), [R37](../03-fonctionnel/regles-etats.md#r37).

**Étant donné :** Lease native près de son terme.

**Quand :** Reculer horloge, redémarrer appareil puis rester déconnecté.

**Alors :** Aucune prolongation artificielle ; accès verrouillé si échéance non vérifiable.


<a id="t079"></a>
### T079 · Faux type et fichier excessif

**Statut :** À réaliser. **Fonctions :** F09. **Règles :** [R21](../03-fonctionnel/regles-etats.md#r21), [R22](../03-fonctionnel/regles-etats.md#r22), [R33](../03-fonctionnel/regles-etats.md#r33).

**Étant donné :** Fichier exécutable nommé image.jpg et autre fichier dépassant limite.

**Quand :** Demander/enchaîner intention, envoi et finalisation.

**Alors :** Refus/REJECTED ; jamais READY ; aucun aperçu exécutable.


<a id="t080"></a>
### T080 · Scanner indisponible

**Statut :** À réaliser. **Fonctions :** F09. **Règles :** [R22](../03-fonctionnel/regles-etats.md#r22).

**Étant donné :** Fichier intègre envoyé, scanner arrêté.

**Quand :** Finaliser, tenter de lire et publier en pièce jointe.

**Alors :** QUARANTINED maintenu, pas de lecture ; texte publiable seulement avec exclusion explicite.


<a id="t081"></a>
### T081 · Ticket volé ou ancien

**Statut :** À réaliser. **Fonctions :** F01 F09. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R02](../03-fonctionnel/regles-etats.md#r02), [R21](../03-fonctionnel/regles-etats.md#r21), [R34](../03-fonctionnel/regles-etats.md#r34).

**Étant donné :** Ticket de lecture délivré à A.

**Quand :** Le rejouer comme B puis comme A après révocation.

**Alors :** Passerelle refuse même URL ; aucune redirection autonome exposée.


<a id="t082"></a>
### T082 · Pièce de permis remplacée

**Statut :** À réaliser. **Fonctions :** F03 F09. **Règles :** [R07](../03-fonctionnel/regles-etats.md#r07), [R11](../03-fonctionnel/regles-etats.md#r11), [R22](../03-fonctionnel/regles-etats.md#r22).

**Étant donné :** Contrôleur lit pièce et version N ; nouvel upload remplace la pièce courante.

**Quand :** Soumettre APPROVED avec version N.

**Alors :** 412, nouveau contrôle en attente ; aucune approbation du fichier non lu.


<a id="t083"></a>
### T083 · Logo sans élève fictif

**Statut :** À réaliser. **Fonctions :** F09 F13. **Règles :** [R21](../03-fonctionnel/regles-etats.md#r21), [R22](../03-fonctionnel/regles-etats.md#r22), [R35](../03-fonctionnel/regles-etats.md#r35).

**Étant donné :** École sans aucun élève.

**Quand :** Déposer logo puis affecter asset READY ; tenter d’affecter une pièce élève.

**Alors :** Logo possible via SchoolAsset ; substitution Document refusée ; aucun profil élève créé.


<a id="t084"></a>
### T084 · Email en panne après réservation

**Statut :** À réaliser. **Fonctions :** F05 F11. **Règles :** [R26](../03-fonctionnel/regles-etats.md#r26), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Fournisseur email indisponible.

**Quand :** Créer leçon et laisser le worker réessayer.

**Alors :** Leçon confirmée et état d’envoi distinct ; aucune nouvelle réservation à chaque essai.


<a id="t085"></a>
### T085 · Événement devenu obsolète

**Statut :** À réaliser. **Fonctions :** F05 F11. **Règles :** [R26](../03-fonctionnel/regles-etats.md#r26).

**Étant donné :** Confirmation non envoyée puis déplacement/annulation.

**Quand :** Reprendre le worker.

**Alors :** Message reflète l’état courant et ne présente pas un ancien créneau comme engagement actif.


<a id="t086"></a>
### T086 · Fuite par journaux

**Statut :** À réaliser. **Fonctions :** F09 F14. **Règles :** [R30](../03-fonctionnel/regles-etats.md#r30), [R32](../03-fonctionnel/regles-etats.md#r32).

**Étant donné :** Données synthétiques sentinelles dans bilan, token et fichier.

**Quand :** Déclencher succès, erreur, timeout et export.

**Alors :** Aucune sentinelle sensible dans logs ou traces externes ; seuls IDs/code autorisés.


<a id="t087"></a>
### T087 · Export de mauvaise portée

**Statut :** À réaliser. **Fonctions :** F01 F14. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R02](../03-fonctionnel/regles-etats.md#r02), [R29](../03-fonctionnel/regles-etats.md#r29).

**Étant donné :** Personne inscrite dans deux écoles et dossier d’un homonyme.

**Quand :** Instruire export A sous droits limités, consulter ticket avec compte distinct.

**Alors :** Contenu limité à la demande validée ; ni autre école ni homonyme ; téléchargement refusé à l’autre compte.


<a id="t088"></a>
### T088 · Restauration après effacement

**Statut :** À réaliser. **Fonctions :** F14. **Règles :** [R29](../03-fonctionnel/regles-etats.md#r29), [R30](../03-fonctionnel/regles-etats.md#r30).

**Étant donné :** Sauvegarde antérieure à une suppression approuvée et journal tombstones indépendant.

**Quand :** Restaurer en réseau isolé puis réappliquer décisions.

**Alors :** Données effacées non réexposées avant réouverture ; pièces et projections contrôlées.


<a id="t089"></a>
### T089 · Sauvegarde complète et clés

**Statut :** À réaliser. **Fonctions :** F14. **Règles :** [R30](../03-fonctionnel/regles-etats.md#r30), [R38](../03-fonctionnel/regles-etats.md#r38).

**Étant donné :** Copie base, objets et matériel de clé disponibles selon runbook.

**Quand :** Restaurer sur environnement neuf sans consulter le serveur primaire.

**Alors :** Objets lisibles autorisés, comptes rapprochés, durée et perte mesurées ; aucune fausse réussite base seule.


<a id="t090"></a>
### T090 · Texte agrandi et lecteur d’écran

**Statut :** À réaliser. **Fonctions :** F05 F08 F13. **Règles :** [R33](../03-fonctionnel/regles-etats.md#r33), [R38](../03-fonctionnel/regles-etats.md#r38).

**Étant donné :** E03/E05/E08/E14/E21 avec texte à 200 %, lecteurs d’écran et noms longs.

**Quand :** Réaliser réservation, bilan et résolution de conflit sans vision fine.

**Alors :** Ordre annoncé cohérent, aucun texte bloquant tronqué, actions nommées et focus visible.


<a id="t091"></a>
### T091 · Clavier et réduction des mouvements

**Statut :** À réaliser. **Fonctions :** F05 F08. **Règles :** [R38](../03-fonctionnel/regles-etats.md#r38).

**Étant donné :** Web étroit puis large, clavier seul ; animation réduite active.

**Quand :** Parcourir dialogues, champs, erreurs et succès.

**Alors :** Focus revient au déclencheur, aucun piège, mouvement non indispensable supprimé.


<a id="t092"></a>
### T092 · Contrat client ancien

**Statut :** À réaliser. **Fonctions :** F01 F12. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R27](../03-fonctionnel/regles-etats.md#r27), [R38](../03-fonctionnel/regles-etats.md#r38).

**Étant donné :** Ancien client possède brouillon et rencontre version incompatible.

**Quand :** Tenter sync, puis mise à jour autorisée.

**Alors :** Message d’incompatibilité explicite ; brouillon autorisé préservé ; aucun état inconnu converti en PLANNED.


<a id="t093"></a>
### T093 · Offre nouvelle version

**Statut :** À réaliser. **Fonctions :** F03 F13. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R35](../03-fonctionnel/regles-etats.md#r35).

**Étant donné :** Formation ACTIVE sur offeringKey B version 1.

**Quand :** Créer version 2 puis tenter seconde formation ACTIVE du même élève/offre logique.

**Alors :** Contrainte logique empêche duplication ; historique version 1 inchangé.


<a id="t094"></a>
### T094 · Volume synthétique et contention

**Statut :** À réaliser. **Fonctions :** F05 F12. **Règles :** [R10](../03-fonctionnel/regles-etats.md#r10), [R38](../03-fonctionnel/regles-etats.md#r38).

**Étant donné :** Jeu artificiel multi-écoles documenté, taille augmentée progressivement.

**Quand :** Mesurer planning, sync et réservations concurrentes avec rôle de production.

**Alors :** Aucune violation d’invariant ; résultats et ressources mesurés, seuils de service proposés validés séparément.


<a id="t095"></a>
### T095 · Réauthentification privilégiée

**Statut :** À réaliser. **Fonctions :** F01 F13 F14. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R04](../03-fonctionnel/regles-etats.md#r04), [R29](../03-fonctionnel/regles-etats.md#r29).

**Étant donné :** Session ancienne ADMIN et action sensible.

**Quand :** Changer rôle, effectuer correction double habilitation ou autoriser purge.

**Alors :** Réauthentification et journal présents ; absence de secret en client ou rapport.


<a id="t096"></a>
### T096 · Purge de dépôt orphelin

**Statut :** À réaliser. **Fonctions :** F09 F14. **Règles :** [R22](../03-fonctionnel/regles-etats.md#r22), [R30](../03-fonctionnel/regles-etats.md#r30).

**Étant donné :** Upload jamais finalisé et objet dont l’expiration est dépassée.

**Quand :** Lancer tâche de nettoyage puis la relancer.

**Alors :** Objet non consultable puis purgé, métadonnées cohérentes, seconde exécution sans erreur destructive.


## Débogage et entretien des tests

Une régression crée d’abord une fixture minimale et une assertion reproduisant l’écart. Ne pas rendre un test vert en supprimant le contrôle de droit ou en transformant une erreur serveur en valeur vide. Les captures d’interface sont utiles pour détecter des changements, pas pour décider seules qu’une nouvelle hiérarchie est correcte.

Une règle modifiée exige un arbitrage documenté, l’actualisation des critères, du contrat et des tests de migration éventuels. Les tests désactivés portent un motif, propriétaire et condition de réactivation. Les identifiants ne sont pas réattribués à une autre fonctionnalité.

## Campagne V2 : GPS central, packs et cours collectifs

Les fixtures V1 restent des cas unitaires de fondation ; les ventes unitaires y utilisent commercialSelection UNIT_PRICE. Les comptes possèdent ownerType/ownerId. Les fixtures de V2 ci-dessous complètent les schémas et scénarios sans prétendre exécuter les tests. Les cas de concurrence utilisent un vrai PostgreSQL et des barrières de synchronisation, pas des mocks. Les tests appareil indiquent OS, modèle, build et preuves expurgées.

<a id="t097"></a>
### T097 · Refus GPS sans perte de leçon

**Statut :** À réaliser. **Fonctions :** F15 F07 F08 F17. **Niveau :** Intégration + parcours. **Règles :** [R41](../03-fonctionnel/regles-etats.md#r41), [R49](../03-fonctionnel/regles-etats.md#r49), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Élève refuse, leçon avec pack et formation autorisée.

**Quand :** Démarrer sans enregistrement puis terminer et publier.

**Alors :** Zéro capture/point ; bilan complet et une consommation commerciale prévue, indépendante du GPS.


<a id="t098"></a>
### T098 · Heure de rendez-vous sans capture automatique

**Statut :** À réaliser. **Fonctions :** F15 F19. **Niveau :** Intégration + parcours. **Règles :** [R41](../03-fonctionnel/regles-etats.md#r41), [R55](../03-fonctionnel/regles-etats.md#r55).

**Étant donné :** Rendez-vous atteint son heure, téléphone autorisé à localiser.

**Quand :** Ne pas appuyer sur Commencer.

**Alors :** Aucune collecte, aucune autorisation de capture produite par cron ou calendrier.


<a id="t099"></a>
### T099 · Départ entièrement hors ligne

**Statut :** À réaliser. **Fonctions :** F15 F12. **Niveau :** Intégration + parcours. **Règles :** [R42](../03-fonctionnel/regles-etats.md#r42), [R27](../03-fonctionnel/regles-etats.md#r27).

**Étant donné :** Aucune autorisation GPS délivrée, réseau absent.

**Quand :** Tenter démarrage puis choisir sans enregistrement.

**Alors :** Capture initiale non permise au pilote ; leçon/brouillon utilisables sans collecte cachée.


<a id="t100"></a>
### T100 · Verrouillage et réseau perdu après autorisation

**Statut :** À réaliser. **Fonctions :** F15 F12. **Niveau :** Essai appareils réels. **Règles :** [R42](../03-fonctionnel/regles-etats.md#r42), [R43](../03-fonctionnel/regles-etats.md#r43), [R44](../03-fonctionnel/regles-etats.md#r44).

**Étant donné :** Build natif réel, autorisation valide, espace disponible.

**Quand :** Verrouiller puis couper réseau, parcourir un trajet de test encadré.

**Alors :** Comportement mesuré sur appareil ; points locaux repris selon les segments, aucun succès supposé depuis simulateur.


<a id="t101"></a>
### T101 · Terminaison de l’application

**Statut :** À réaliser. **Fonctions :** F15 F16. **Niveau :** Essai appareils réels. **Règles :** [R43](../03-fonctionnel/regles-etats.md#r43), [R45](../03-fonctionnel/regles-etats.md#r45).

**Étant donné :** Capture active avec points déjà acquittés.

**Quand :** Terminer l’app, la rouvrir et reprendre explicitement.

**Alors :** Aucune promesse de continuité ; rupture visible et pas de ligne pleine sur la période absente.


<a id="t102"></a>
### T102 · Pause puis passage répété

**Statut :** À réaliser. **Fonctions :** F15 F16. **Niveau :** Intégration + parcours. **Règles :** [R43](../03-fonctionnel/regles-etats.md#r43), [R46](../03-fonctionnel/regles-etats.md#r46).

**Étant donné :** Deux passages de test au même lieu, séparés par pause.

**Quand :** Créer une observation au second passage.

**Alors :** Ancre de segment/séquence correcte ; premier passage inchangé et pause visible.


<a id="t103"></a>
### T103 · Arrêt local pendant erreur serveur

**Statut :** À réaliser. **Fonctions :** F15 F07. **Niveau :** Intégration + parcours. **Règles :** [R42](../03-fonctionnel/regles-etats.md#r42), [R40](../03-fonctionnel/regles-etats.md#r40).

**Étant donné :** Capture active, endpoint de clôture indisponible.

**Quand :** Arrêter puis terminer la leçon.

**Alors :** Collecteur local arrêté immédiatement ; aucun point du trajet suivant ; résultat de leçon en attente explicite.


<a id="t104"></a>
### T104 · Chunk répété identique

**Statut :** À réaliser. **Fonctions :** F15. **Niveau :** Intégration + parcours. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R44](../03-fonctionnel/regles-etats.md#r44).

**Étant donné :** Chunk acquitté et réponse perdue.

**Quand :** Renvoyer même identité/hash, puis même clé de commande.

**Alors :** Un seul objet/ensemble de mesures et acquittement cohérent, aucun compteur doublé.


<a id="t105"></a>
### T105 · Chunk de contenu divergent

**Statut :** À réaliser. **Fonctions :** F15. **Niveau :** Intégration + parcours. **Règles :** [R44](../03-fonctionnel/regles-etats.md#r44).

**Étant donné :** Chunk existe avec hash A.

**Quand :** Envoyer même capture/segment/index avec hash B.

**Alors :** 409 CHUNK_HASH_MISMATCH ; ancien contenu conservé et aucun détail GPS dans log.


<a id="t106"></a>
### T106 · Arrivée GPS hors ordre

**Statut :** À réaliser. **Fonctions :** F15 F16. **Niveau :** Intégration + parcours. **Règles :** [R44](../03-fonctionnel/regles-etats.md#r44), [R45](../03-fonctionnel/regles-etats.md#r45).

**Étant donné :** Chunks 0,1,2 annoncés au manifeste.

**Quand :** Recevoir 2 puis 0 ; finaliser partiel ; recevoir 1 dans délai.

**Alors :** Projection partielle d’abord puis complète techniquement ; aucune nouvelle publication pédagogique implicite.


<a id="t107"></a>
### T107 · Zoom manuel pendant replay

**Statut :** À réaliser. **Fonctions :** F16. **Niveau :** Recette UI accessible. **Règles :** [R45](../03-fonctionnel/regles-etats.md#r45).

**Étant donné :** Replay en lecture et suivi caméra actif.

**Quand :** Zoomer/déplacer, attendre puis recentrer.

**Alors :** Lecture continue ; caméra respecte geste jusqu’au recentrage explicite.


<a id="t108"></a>
### T108 · Trajet transféré mais privé

**Statut :** À réaliser. **Fonctions :** F16 F08. **Niveau :** Intégration + parcours. **Règles :** [R47](../03-fonctionnel/regles-etats.md#r47), [R18](../03-fonctionnel/regles-etats.md#r18).

**Étant donné :** Capture SYNCED, annotations privées, bilan non publié.

**Quand :** Accéder avec compte élève ou admin sans affectation.

**Alors :** Aucun contenu privé ; workflow d’accès aux données F14 reste disponible séparément.


<a id="t109"></a>
### T109 · Bilan sans trace puis ajout explicite

**Statut :** À réaliser. **Fonctions :** F16 F08. **Niveau :** Intégration + parcours. **Règles :** [R19](../03-fonctionnel/regles-etats.md#r19), [R47](../03-fonctionnel/regles-etats.md#r47).

**Étant donné :** Bilan publié pendant transfert incomplet.

**Quand :** Terminer upload puis ajouter trajet à une nouvelle révision.

**Alors :** Ancienne révision inchangée ; pas d’ajout silencieux ; nouvelle publication explicite seulement.


<a id="t110"></a>
### T110 · Suppression des dérivés GPS

**Statut :** À réaliser. **Fonctions :** F14 F16. **Niveau :** Intégration + parcours. **Règles :** [R48](../03-fonctionnel/regles-etats.md#r48), [R30](../03-fonctionnel/regles-etats.md#r30).

**Étant donné :** Capture publiée, miniatures et caches préparés.

**Quand :** Exécuter procédure d’effacement autorisée puis restaurer sauvegarde de test.

**Alors :** Points/dérivés non exposés, tombstones réappliqués ; montant de leçon non supprimé mécaniquement.


<a id="t111"></a>
### T111 · Révocation distante hors réseau

**Statut :** À réaliser. **Fonctions :** F15 F12. **Niveau :** Intégration + parcours. **Règles :** [R42](../03-fonctionnel/regles-etats.md#r42), [R37](../03-fonctionnel/regles-etats.md#r37).

**Étant donné :** Capture autorisée, appareil déconnecté ; accès révoqué serveur ensuite.

**Quand :** Continuer jusqu’à borne puis reconnecter.

**Alors :** Limite de connaissance hors ligne constatée ; arrêt à borne, rejet post-cutoff et purge instruite ; pas de promesse instantanée.


<a id="t112"></a>
### T112 · Deux capteurs sur une leçon

**Statut :** À réaliser. **Fonctions :** F15. **Niveau :** Intégration + parcours. **Règles :** [R42](../03-fonctionnel/regles-etats.md#r42), [R12](../03-fonctionnel/regles-etats.md#r12).

**Étant donné :** Deux appareils d’un moniteur autorisé.

**Quand :** Autoriser simultanément la même leçon.

**Alors :** Une seule capture active ; autre refusée sans fusion arbitraire des points.


<a id="t113"></a>
### T113 · Durée GPS non facturable

**Statut :** À réaliser. **Fonctions :** F17 F07 F15. **Niveau :** Intégration + parcours. **Règles :** [R49](../03-fonctionnel/regles-etats.md#r49), [R23](../03-fonctionnel/regles-etats.md#r23).

**Étant donné :** Leçon 45 minutes, capture 35 minutes, une unité réservée.

**Quand :** Clôturer la prestation conforme aux conditions.

**Alors :** Une unité consommée ; pas de prorata automatique de 35/45, pas d’écart de facture calculé par GPS.


<a id="t114"></a>
### T114 · École sans packs

**Statut :** À réaliser. **Fonctions :** F17 F13. **Niveau :** Intégration + parcours. **Règles :** [R51](../03-fonctionnel/regles-etats.md#r51), [R72](../03-fonctionnel/regles-etats.md#r72).

**Étant donné :** Module packs désactivé, tarifs unitaires configurés.

**Quand :** Planifier, réaliser et régler une leçon.

**Alors :** Parcours complet sans écran vide obligatoire de packs ni création de droits artificiels.


<a id="t115"></a>
### T115 · Packs composites indépendants

**Statut :** À réaliser. **Fonctions :** F17 F18. **Niveau :** Intégration + parcours. **Règles :** [R52](../03-fonctionnel/regles-etats.md#r52), [R53](../03-fonctionnel/regles-etats.md#r53).

**Étant donné :** Achat donnant conduite, CTC et examen.

**Quand :** Réserver une conduite puis une sensibilisation.

**Alors :** Droits séparés ; aucune consommation de l’examen ; achat ne préinscrit aucune série.


<a id="t116"></a>
### T116 · Prix futurs et achats anciens

**Statut :** À réaliser. **Fonctions :** F17 F13. **Niveau :** Intégration + parcours. **Règles :** [R35](../03-fonctionnel/regles-etats.md#r35), [R51](../03-fonctionnel/regles-etats.md#r51).

**Étant donné :** Pack acquis sous version 1 ; version 2 prend effet plus tard.

**Quand :** Activer version 2 et consulter achat 1 puis nouvelle vente.

**Alors :** Conditions/soldes historiques conservés ; nouvelles ventes utilisent version applicable.


<a id="t117"></a>
### T117 · Pas de double facturation du pack

**Statut :** À réaliser. **Fonctions :** F17 F10 F07. **Niveau :** Intégration + parcours. **Règles :** [R23](../03-fonctionnel/regles-etats.md#r23), [R25](../03-fonctionnel/regles-etats.md#r25), [R54](../03-fonctionnel/regles-etats.md#r54).

**Étant donné :** Compte Purchase chargé et payé.

**Quand :** Réaliser deux leçons couvertes.

**Alors :** Deux consommations, comptes de leçon à charge nulle ; aucun nouvel encaissement hérité du pack.


<a id="t118"></a>
### T118 · Dernier droit concurrent

**Statut :** À réaliser. **Fonctions :** F17 F05 F18. **Niveau :** Intégration + parcours. **Règles :** [R53](../03-fonctionnel/regles-etats.md#r53), [R59](../03-fonctionnel/regles-etats.md#r59).

**Étant donné :** Un droit disponible compatible et deux commandes admissibles.

**Quand :** Réserver simultanément deux prestations.

**Alors :** Un HOLD au plus ; disponible jamais négatif ; commande refusée sans occupation partielle.


<a id="t119"></a>
### T119 · Première présence collective

**Statut :** À réaliser. **Fonctions :** F18 F17. **Niveau :** Intégration + parcours. **Règles :** [R54](../03-fonctionnel/regles-etats.md#r54), [R63](../03-fonctionnel/regles-etats.md#r63).

**Étant donné :** Une inscription de série avec un droit réservé.

**Quand :** Marquer deux blocs présents successivement puis rejouer la première requête.

**Alors :** Droit consommé une seule fois, pas un droit par bloc ; exigence reste partielle tant que blocs requis manquent.


<a id="t120"></a>
### T120 · Formation externe et reliquat

**Statut :** À réaliser. **Fonctions :** F03 F18 F17. **Niveau :** Intégration + parcours. **Règles :** [R61](../03-fonctionnel/regles-etats.md#r61), [R52](../03-fonctionnel/regles-etats.md#r52).

**Étant donné :** Élève fournit une preuve de CTC suivie ailleurs, pack possédant encore un droit CTC.

**Quand :** Valider la preuve avec habilitation.

**Alors :** Exigence mise à jour, droit non consommé fictivement ; éventuel remplacement/remboursement traité selon contrat.


<a id="t121"></a>
### T121 · Double leçon et unité contractuelle

**Statut :** À réaliser. **Fonctions :** F17 F05 F07. **Niveau :** Intégration + parcours. **Règles :** [R49](../03-fonctionnel/regles-etats.md#r49), [R51](../03-fonctionnel/regles-etats.md#r51).

**Étant donné :** Service 45 minutes ; réservation acceptée de deux unités.

**Quand :** Réaliser une séance double avec enregistrement partiel.

**Alors :** Deux unités consommées selon réservation ; pas de conversion implicite vers une unité de 90 minutes indépendante.


<a id="t122"></a>
### T122 · Rabais déjà inclus

**Statut :** À réaliser. **Fonctions :** F17. **Niveau :** Intégration + parcours. **Règles :** [R52](../03-fonctionnel/regles-etats.md#r52).

**Étant donné :** Total et composants acceptés d’un pack d’exemple avec réduction informative.

**Quand :** Créer l’achat.

**Alors :** Total accepté conservé ; la réduction informative n’est pas soustraite deux fois.


<a id="t123"></a>
### T123 · Remboursement et erreur comptable

**Statut :** À réaliser. **Fonctions :** F10 F17. **Niveau :** Intégration + parcours. **Règles :** [R24](../03-fonctionnel/regles-etats.md#r24), [R25](../03-fonctionnel/regles-etats.md#r25).

**Étant donné :** Paiement réel puis erreur de saisie identifiée.

**Quand :** Effectuer une contre-écriture justifiée et non un remboursement fictif.

**Alors :** Journal lié conservé ; aucune preuve d’argent rendu inventée ; soldes cohérents.


<a id="t124"></a>
### T124 · Prépayé strict non encore réglé

**Statut :** À réaliser. **Fonctions :** F17 F18. **Niveau :** Intégration + parcours. **Règles :** [R53](../03-fonctionnel/regles-etats.md#r53), [R54](../03-fonctionnel/regles-etats.md#r54).

**Étant donné :** Pack AFTER_FULL_PAYMENT avec paiement incomplet.

**Quand :** Tenter réserver avec ce droit.

**Alors :** PREPAYMENT_REQUIRED ; aucune place ni HOLD pris, alternative unitaire seulement avec nouvel accord explicite.


<a id="t125"></a>
### T125 · Publication sans réservation

**Statut :** À réaliser. **Fonctions :** F18 F19. **Niveau :** Intégration + parcours. **Règles :** [R55](../03-fonctionnel/regles-etats.md#r55), [R57](../03-fonctionnel/regles-etats.md#r57).

**Étant donné :** Série complète en brouillon et audience d’élèves actifs.

**Quand :** Publier une fois puis rejouer la commande.

**Alors :** Offres visibles et une campagne ; zéro inscription, occupation élève, charge ou consommation automatique.


<a id="t126"></a>
### T126 · Visibilité pour élève déjà formé

**Statut :** À réaliser. **Fonctions :** F19 F18. **Niveau :** Intégration + parcours. **Règles :** [R55](../03-fonctionnel/regles-etats.md#r55), [R58](../03-fonctionnel/regles-etats.md#r58).

**Étant donné :** Même école, élève COMPLETED dans audience générale.

**Quand :** Publier une nouvelle série puis ouvrir agenda.

**Alors :** Offre visible selon filtre général avec statut approprié, pas d’annonce de besoin ni bouton standard de répétition.


<a id="t127"></a>
### T127 · Tous les blocs acceptés

**Statut :** À réaliser. **Fonctions :** F18. **Niveau :** Intégration + parcours. **Règles :** [R56](../03-fonctionnel/regles-etats.md#r56), [R59](../03-fonctionnel/regles-etats.md#r59).

**Étant donné :** Série de quatre occurrences, élève admissible.

**Quand :** Soumettre inscription avec seulement trois occurrenceIds acceptés.

**Alors :** 422 SERIES_ACCEPTANCE_INCOMPLETE ; aucune place/débit ; confirmation complète indispensable.


<a id="t128"></a>
### T128 · Dernière place simultanée

**Statut :** À réaliser. **Fonctions :** F18 F17. **Niveau :** Intégration PostgreSQL concurrente. **Règles :** [R59](../03-fonctionnel/regles-etats.md#r59), [R60](../03-fonctionnel/regles-etats.md#r60).

**Étant donné :** Capacité presque atteinte, une seule place, deux élèves différents.

**Quand :** Soumettre simultanément deux inscriptions par vraies connexions PostgreSQL.

**Alors :** Exactement une confirmation et un COURSE_FULL ; une place comptée, aucun compte/droit orphelin chez perdant.


<a id="t129"></a>
### T129 · Double clic et réponse perdue

**Statut :** À réaliser. **Fonctions :** F18. **Niveau :** Intégration + parcours. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R60](../03-fonctionnel/regles-etats.md#r60).

**Étant donné :** Élève s’inscrit, commit effectué mais réponse réseau perdue.

**Quand :** Renvoyer la même operationId puis recharger agenda.

**Alors :** Une seule inscription, réponse idempotente et occurrences sans doublon.


<a id="t130"></a>
### T130 · Inscription manuelle concurrente

**Statut :** À réaliser. **Fonctions :** F18. **Niveau :** Intégration + parcours. **Règles :** [R59](../03-fonctionnel/regles-etats.md#r59), [R67](../03-fonctionnel/regles-etats.md#r67).

**Étant donné :** Le personnel saisit une demande reçue tandis que l’élève clique lui-même.

**Quand :** Exécuter les deux commandes avec clés différentes.

**Alors :** Unicité élève/série respectée ; jamais deux places ou deux charges pour la même personne.


<a id="t131"></a>
### T131 · Conflit sur un bloc tardif

**Statut :** À réaliser. **Fonctions :** F18 F05. **Niveau :** Intégration + parcours. **Règles :** [R10](../03-fonctionnel/regles-etats.md#r10), [R56](../03-fonctionnel/regles-etats.md#r56), [R59](../03-fonctionnel/regles-etats.md#r59).

**Étant donné :** Série multi-dates ; une leçon existe sur le quatrième bloc.

**Quand :** Tenter inscrire la série.

**Alors :** SCHEDULE_CONFLICT sur ensemble de série ; aucun premier bloc réservé partiellement ni révélation d’autres élèves.


<a id="t132"></a>
### T132 · Salle et moniteur occupés

**Statut :** À réaliser. **Fonctions :** F18 F04. **Niveau :** Intégration + parcours. **Règles :** [R09](../03-fonctionnel/regles-etats.md#r09), [R10](../03-fonctionnel/regles-etats.md#r10), [R57](../03-fonctionnel/regles-etats.md#r57).

**Étant donné :** Salle ou moniteur déjà engagé, y compris leçon individuelle.

**Quand :** Publier une série au même horaire.

**Alors :** Publication refusée sans campagne ; brouillon conservé avec conflit autorisé.


<a id="t133"></a>
### T133 · Réduction de capacité sous inscrits

**Statut :** À réaliser. **Fonctions :** F18. **Niveau :** Intégration + parcours. **Règles :** [R60](../03-fonctionnel/regles-etats.md#r60), [R57](../03-fonctionnel/regles-etats.md#r57).

**Étant donné :** Neuf inscrits actifs, dont deux à reconfirmer.

**Quand :** Réduire capacité à huit.

**Alors :** Refus ; les places à reconfirmer comptent, aucun élève supprimé automatiquement.


<a id="t134"></a>
### T134 · Complet sans liste d’attente

**Statut :** À réaliser. **Fonctions :** F18 F19. **Niveau :** Intégration + parcours. **Règles :** [R60](../03-fonctionnel/regles-etats.md#r60), [R68](../03-fonctionnel/regles-etats.md#r68).

**Étant donné :** Série pleine consultée par élève non inscrit.

**Quand :** Ouvrir fiche puis libérer une place d’un autre compte.

**Alors :** Complet tant que plein ; place disponible après actualisation, aucun ancien visiteur auto-inscrit.


<a id="t135"></a>
### T135 · Cours acheté ne vaut pas inscription

**Statut :** À réaliser. **Fonctions :** F17 F18. **Niveau :** Intégration + parcours. **Règles :** [R52](../03-fonctionnel/regles-etats.md#r52), [R55](../03-fonctionnel/regles-etats.md#r55).

**Étant donné :** Nouvel achat de pack incluant sensibilisation, série publiée.

**Quand :** Confirmer la vente.

**Alors :** Droit disponible mais aucune Enrollment ni occupation ; l’élève doit choisir la série.


<a id="t136"></a>
### T136 · Dates changées avec conflit

**Statut :** À réaliser. **Fonctions :** F18 F05. **Niveau :** Intégration + parcours. **Règles :** [R62](../03-fonctionnel/regles-etats.md#r62), [R10](../03-fonctionnel/regles-etats.md#r10).

**Étant donné :** Série réservée ; nouvelle date incompatible avec leçon d’un inscrit.

**Quand :** Déplacer la série.

**Alors :** Mutation refusée intégralement ; anciennes dates et places inchangées, aucune annonce prématurée.


<a id="t137"></a>
### T137 · Reconfirmation de nouvelles dates

**Statut :** À réaliser. **Fonctions :** F18 F19. **Niveau :** Intégration + parcours. **Règles :** [R62](../03-fonctionnel/regles-etats.md#r62), [R64](../03-fonctionnel/regles-etats.md#r64).

**Étant donné :** Déplacement valide de série publiée avec inscrits.

**Quand :** Ouvrir avis puis accepter nouvelles dates.

**Alors :** Place maintenue, comparatif visible, une seule reconfirmation sans nouveau droit ; offreVersion cohérente.


<a id="t138"></a>
### T138 · Silence après changement

**Statut :** À réaliser. **Fonctions :** F18. **Niveau :** Intégration + parcours. **Règles :** [R62](../03-fonctionnel/regles-etats.md#r62).

**Étant donné :** Inscription RECONFIRMATION_REQUIRED, élève sans réponse.

**Quand :** Laisser passer un rappel.

**Alors :** Aucune désinscription, pénalité ou libération implicite ; action staff visible.


<a id="t139"></a>
### T139 · Annulation élève avant délai

**Statut :** À réaliser. **Fonctions :** F18 F17. **Niveau :** Intégration + parcours. **Règles :** [R62](../03-fonctionnel/regles-etats.md#r62), [R54](../03-fonctionnel/regles-etats.md#r54).

**Étant donné :** Inscrit avec HOLD, aucune présence, délai contractuel respecté.

**Quand :** Annuler puis rejouer la même commande.

**Alors :** Place et droit libérés une fois, obligations financières traitées selon compte sans faux remboursement.


<a id="t140"></a>
### T140 · Annulation d’école avec paiement réel

**Statut :** À réaliser. **Fonctions :** F18 F10. **Niveau :** Intégration + parcours. **Règles :** [R62](../03-fonctionnel/regles-etats.md#r62), [R25](../03-fonctionnel/regles-etats.md#r25).

**Étant donné :** Série payée puis annulée par l’école.

**Quand :** Annuler et traiter la décision financière.

**Alors :** Place libérée et avis ; financialFollowUp si argent non encore remboursé ; ne pas écrire remboursement reçu avant mouvement réel.


<a id="t141"></a>
### T141 · Inscription ne valide pas présence

**Statut :** À réaliser. **Fonctions :** F18 F03. **Niveau :** Intégration + parcours. **Règles :** [R63](../03-fonctionnel/regles-etats.md#r63), [R39](../03-fonctionnel/regles-etats.md#r39).

**Étant donné :** Élève confirmé et payé mais aucun AttendanceRecord PRESENT.

**Quand :** Atteindre la fin du cours puis consulter parcours.

**Alors :** Pas de COMPLETED automatique ; statut à renseigner/partiel selon preuves.


<a id="t142"></a>
### T142 · Un bloc manquant

**Statut :** À réaliser. **Fonctions :** F18 F03. **Niveau :** Intégration + parcours. **Règles :** [R63](../03-fonctionnel/regles-etats.md#r63), [R61](../03-fonctionnel/regles-etats.md#r61).

**Étant donné :** Trois présences confirmées sur quatre blocs requis.

**Quand :** Tenter validation finale.

**Alors :** Refus de COMPLETED sans procédure de rattrapage/preuve valide ; consommation commerciale distincte.


<a id="t143"></a>
### T143 · Correction de présence concurrente

**Statut :** À réaliser. **Fonctions :** F18. **Niveau :** Intégration + parcours. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R63](../03-fonctionnel/regles-etats.md#r63).

**Étant donné :** Deux formateurs habilités lisent même version de présence.

**Quand :** Modifier simultanément PRESENT et ABSENT.

**Alors :** Une mutation, un 412 ; auteur/raison audités, aucune réécriture muette.


<a id="t144"></a>
### T144 · Présences d’autres élèves privées

**Statut :** À réaliser. **Fonctions :** F18. **Niveau :** Intégration + parcours. **Règles :** [R69](../03-fonctionnel/regles-etats.md#r69), [R02](../03-fonctionnel/regles-etats.md#r02).

**Étant donné :** Compte élève inscrit à une série de groupe.

**Quand :** Appeler liste des inscrits/présences directement.

**Alors :** 403/404 sans noms des autres participants ; son propre état reste disponible.


<a id="t145"></a>
### T145 · Deux permis, une exigence

**Statut :** À réaliser. **Fonctions :** F03 F18 F19. **Niveau :** Intégration + parcours. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R61](../03-fonctionnel/regles-etats.md#r61), [R58](../03-fonctionnel/regles-etats.md#r58).

**Étant donné :** Élève B et A avec exigence commune approuvée.

**Quand :** Publier CTC puis inscrire et valider.

**Alors :** Une annonce, une place, une preuve reliée correctement aux formations, aucun double débit.


<a id="t146"></a>
### T146 · Statut inconnu non ciblé comme besoin

**Statut :** À réaliser. **Fonctions :** F19 F03. **Niveau :** Intégration + parcours. **Règles :** [R58](../03-fonctionnel/regles-etats.md#r58), [R61](../03-fonctionnel/regles-etats.md#r61).

**Étant donné :** RequirementRecord UNKNOWN.

**Quand :** Publier une sensibilisation.

**Alors :** Offre visible mais pas annonce affirmant un besoin ; situation à confirmer, inscription bloquée si critère non validé.


<a id="t147"></a>
### T147 · Preuve externe en attente

**Statut :** À réaliser. **Fonctions :** F03 F19. **Niveau :** Intégration + parcours. **Règles :** [R61](../03-fonctionnel/regles-etats.md#r61), [R58](../03-fonctionnel/regles-etats.md#r58).

**Étant donné :** Élève déclare avoir suivi ailleurs avec document non encore contrôlé.

**Quand :** Déposer puis examiner document.

**Alors :** EVIDENCE_PENDING avant contrôle ; aucune validation sur READY technique ; ciblage mis à jour après décision.


<a id="t148"></a>
### T148 · Profil 2027 non validé

**Statut :** À réaliser. **Fonctions :** F13 F18. **Niveau :** Intégration + parcours. **Règles :** [R66](../03-fonctionnel/regles-etats.md#r66), [R57](../03-fonctionnel/regles-etats.md#r57).

**Étant donné :** Profil 2027 DRAFT_REQUIRES_REVIEW et série de janvier 2027.

**Quand :** Tenter publier en reprenant critères 2026 par défaut.

**Alors :** PROFILE_NOT_APPROVED ; pas de règle de permis élève codée en dur pour contourner la revue.


<a id="t149"></a>
### T149 · Cours à frontière de régime

**Statut :** À réaliser. **Fonctions :** F13 F18. **Niveau :** Intégration + parcours. **Règles :** [R66](../03-fonctionnel/regles-etats.md#r66), [R35](../03-fonctionnel/regles-etats.md#r35).

**Étant donné :** Série comportant une date avant et une après changement de profil.

**Quand :** Publier sans procédure transitoire approuvée.

**Alors :** Revue nécessaire ; aucun choix automatique du régime par seule date de création.


<a id="t150"></a>
### T150 · Ciblage relu avant envoi

**Statut :** À réaliser. **Fonctions :** F19 F11. **Niveau :** Intégration + parcours. **Règles :** [R58](../03-fonctionnel/regles-etats.md#r58), [R65](../03-fonctionnel/regles-etats.md#r65).

**Étant donné :** Campagne en attente, élève TO_DO lors publication.

**Quand :** Valider la preuve externe avant traitement du destinataire.

**Alors :** Annonce de besoin non envoyée ; un message déjà accepté auparavant reste possible et son lien relit l’état.


<a id="t151"></a>
### T151 · Refus push sans perte de place

**Statut :** À réaliser. **Fonctions :** F11 F18 F19. **Niveau :** Intégration + parcours. **Règles :** [R65](../03-fonctionnel/regles-etats.md#r65), [R26](../03-fonctionnel/regles-etats.md#r26).

**Étant donné :** Permission push refusée, compte connecté.

**Quand :** Consulter agenda et s’inscrire.

**Alors :** Confirmation serveur/in-app intacte, aucune obligation d’autoriser push pour réserver.


<a id="t152"></a>
### T152 · Échec fournisseur après confirmation

**Statut :** À réaliser. **Fonctions :** F11 F18. **Niveau :** Intégration + parcours. **Règles :** [R26](../03-fonctionnel/regles-etats.md#r26), [R65](../03-fonctionnel/regles-etats.md#r65).

**Étant donné :** Inscription commitée, fournisseur indisponible.

**Quand :** Traiter puis rejouer outbox.

**Alors :** Place inchangée, une entrée logique in-app, tentatives bornées et identifiées par canal.


<a id="t153"></a>
### T153 · Notification de changement après accomplissement

**Statut :** À réaliser. **Fonctions :** F11 F19 F18. **Niveau :** Intégration + parcours. **Règles :** [R58](../03-fonctionnel/regles-etats.md#r58), [R62](../03-fonctionnel/regles-etats.md#r62).

**Étant donné :** Élève inscrit, exigence devenue COMPLETED après preuve externe.

**Quand :** Déplacer la série encore réservée.

**Alors :** Avis transactionnel à cet inscrit malgré exclusion des nouvelles annonces de besoin.


<a id="t154"></a>
### T154 · Lien ancien et droits révoqués

**Statut :** À réaliser. **Fonctions :** F11 F19. **Niveau :** Intégration + parcours. **Règles :** [R70](../03-fonctionnel/regles-etats.md#r70), [R02](../03-fonctionnel/regles-etats.md#r02).

**Étant donné :** Push reçu avant retrait d’école.

**Quand :** Ouvrir le lien après révocation.

**Alors :** Authentification puis refus sans contenu privé, pas inscription par GET.


<a id="t155"></a>
### T155 · Masquer les offres

**Statut :** À réaliser. **Fonctions :** F19. **Niveau :** Intégration + parcours. **Règles :** [R55](../03-fonctionnel/regles-etats.md#r55), [R64](../03-fonctionnel/regles-etats.md#r64).

**Étant donné :** Élève possède une inscription et plusieurs offres visibles.

**Quand :** Désactiver Afficher les cours disponibles.

**Alors :** Engagements personnels conservés ; aucune annulation ni notification d’annulation.


<a id="t156"></a>
### T156 · Dédoublonnage calendrier

**Statut :** À réaliser. **Fonctions :** F19 F18. **Niveau :** Intégration + parcours. **Règles :** [R64](../03-fonctionnel/regles-etats.md#r64).

**Étant donné :** Offre de quatre occurrences affichée puis inscription confirmée.

**Quand :** Actualiser calendrier après réponse perdue et reprise.

**Alors :** Chaque occurrence apparaît une fois en engagement, jamais offre et engagement doublés.


<a id="t157"></a>
### T157 · Heure locale inexistante/ambiguë

**Statut :** À réaliser. **Fonctions :** F18 F19. **Niveau :** Intégration temps. **Règles :** [R31](../03-fonctionnel/regles-etats.md#r31), [R66](../03-fonctionnel/regles-etats.md#r66).

**Étant donné :** Occurrence saisie près d’un changement d’heure Europe/Zurich.

**Quand :** Valider heure inexistante puis heure ambiguë sans offset choisi.

**Alors :** Heure inexistante refusée ; ambiguïté résolue explicitement, UTC/fuseau et toutes dates cohérents.


<a id="t158"></a>
### T158 · Cours sans collecte GPS

**Statut :** À réaliser. **Fonctions :** F18 F15. **Niveau :** Intégration + parcours. **Règles :** [R41](../03-fonctionnel/regles-etats.md#r41), [R72](../03-fonctionnel/regles-etats.md#r72).

**Étant donné :** Occurrence de sensibilisation en salle.

**Quand :** Ouvrir la liste des présences.

**Alors :** Aucune permission GPS demandée ni capture lancée ; présence attestée humainement.


<a id="t159"></a>
### T159 · Désactiver module avec engagements

**Statut :** À réaliser. **Fonctions :** F13 F18. **Niveau :** Intégration + parcours. **Règles :** [R72](../03-fonctionnel/regles-etats.md#r72), [R29](../03-fonctionnel/regles-etats.md#r29).

**Étant donné :** Module cours actif et inscriptions futures.

**Quand :** Désactiver le module.

**Alors :** Refus et impacts à résoudre ; pas de disparition des cours de l’agenda.


<a id="t160"></a>
### T160 · Délégation de cours sans traces

**Statut :** À réaliser. **Fonctions :** F13 F18 F16. **Niveau :** Intégration + parcours. **Règles :** [R69](../03-fonctionnel/regles-etats.md#r69), [R02](../03-fonctionnel/regles-etats.md#r02).

**Étant donné :** Personnel MANAGE_COURSES/TAKE_ATTENDANCE sans affectation de conduite.

**Quand :** Gérer son cours puis demander une capture d’élève.

**Alors :** Cours autorisé dans son périmètre, trace refusée ; pas d’élargissement de droits pédagogique implicite.


<a id="t161"></a>
### T161 · Notifications accessibles et langue

**Statut :** À réaliser. **Fonctions :** F11 F19. **Niveau :** Recette accessibilité. **Règles :** [R65](../03-fonctionnel/regles-etats.md#r65), [R72](../03-fonctionnel/regles-etats.md#r72).

**Étant donné :** Interface avec grand texte/lecteur d’écran et langue activée.

**Quand :** Lire offre, confirmation et cours complet.

**Alors :** Types distincts annoncés, dates lisibles, aucun texte critique tronqué ni couleur seule.


<a id="t162"></a>
### T162 · Charges et droits après migration

**Statut :** À réaliser. **Fonctions :** F17 F14. **Niveau :** Intégration + parcours. **Règles :** [R23](../03-fonctionnel/regles-etats.md#r23), [R29](../03-fonctionnel/regles-etats.md#r29), [R35](../03-fonctionnel/regles-etats.md#r35).

**Étant donné :** Ancien marquage payé et traces de qualité inconnue.

**Quand :** Préparer import de test puis rapprocher.

**Alors :** Pas de pack, présence, précision ou accord inventés ; source historique et validations explicites.



## Recettes supplémentaires V3 : spécifications non exécutées

Les tests ci-dessous doivent être implémentés et exécutés sur les interfaces et services futurs. Les éventuels calculs de fixture dans le contrôle documentaire ne constituent pas leur exécution.

| ID | Cas | Fonctions | Niveau |
|---|---|---|---|
| [T163](#t163) | Setup refusé au moniteur non ADMIN | F01 F20 | Intégration API + parcours |
| [T164](#t164) | Activer le workspace sans modules facultatifs | F13 F20 | Intégration API + parcours |
| [T165](#t165) | Offre incomplète sans planification autorisée | F03 F13 F20 | Intégration API + parcours |
| [T166](#t166) | Deux responsables modifient le setup | F13 F20 | Intégration API + parcours |
| [T167](#t167) | Reprise web vers tablette du setup | F20 F21 | Intégration API + parcours |
| [T168](#t168) | Politique nouvelle sans réécrire les achats | F13 F17 F20 | Intégration API + parcours |
| [T169](#t169) | Catégorie retirée avec dépendances | F03 F13 F20 | Intégration API + parcours |
| [T170](#t170) | Photo obligatoire interdite dans les politiques | F13 F20 F21 | Intégration API + parcours |
| [T171](#t171) | Profil collectif non approuvé | F18 F20 | Intégration API + parcours |
| [T172](#t172) | Rejeu activation idempotent | F01 F20 | Intégration API + parcours |
| [T173](#t173) | Erreur de champ et navigation clavier du wizard | F20 F21 | Accessibilité manuelle + automatisée |
| [T174](#t174) | École DRAFT ne vend pas ni ne publie | F17 F18 F20 | Intégration API + parcours |
| [T175](#t175) | Invitation ne crée pas une formation validée | F02 F03 F21 | Intégration API + parcours |
| [T176](#t176) | Validation de demande atomique | F03 F21 | Intégration API + parcours |
| [T177](#t177) | Refuser photo GPS push sans bloquer | F11 F15 F21 | Intégration API + parcours |
| [T178](#t178) | Naissance future et adresse conditionnelle | F21 | Intégration API + parcours |
| [T179](#t179) | Noms Unicode sans troncature | F21 | Intégration API + parcours |
| [T180](#t180) | Reprise explicite de coordonnées dans B | F01 F21 | Intégration API + parcours |
| [T181](#t181) | Homonymes non fusionnés | F02 F21 | Intégration API + parcours |
| [T182](#t182) | Contact scolaire distinct du login | F01 F21 | Intégration API + parcours |
| [T183](#t183) | Dépôt photo mal formé | F09 F21 | Intégration API + parcours |
| [T184](#t184) | Photo sans EXIF ni partage inter-élèves | F09 F21 | Intégration API + parcours |
| [T185](#t185) | Saisie assistée ne signe pas le choix élève | F02 F15 F21 | Intégration API + parcours |
| [T186](#t186) | Cours suivi ailleurs reste à vérifier | F03 F18 F21 | Intégration API + parcours |
| [T187](#t187) | Moniteur invité n’accède pas au setup propriétaire | F01 F21 | Intégration API + parcours |
| [T188](#t188) | Dernière place perdue pendant complément profil | F18 F19 F21 | Intégration API + parcours |
| [T189](#t189) | Politique modifiée sans recommencer tout | F13 F20 F21 | Intégration API + parcours |
| [T190](#t190) | Invitation expirée et lien profond sûr | F01 F02 F21 | Intégration API + parcours |
| [T191](#t191) | Deux accueils personnels concurrents | F21 | Intégration API + parcours |
| [T192](#t192) | Rotation pendant capture sans redémarrage | F12 F15 F16 | Appareil réel + journaux expurgés |
| [T193](#t193) | Toute l’app en tablette étroite | F05 F08 F18 F21 | Appareils et accessibilité |
| [T194](#t194) | Tablette non qualifiée sans faux GPS | F15 F21 | Appareil réel + API |
| [T195](#t195) | Aucun relais implicite téléphone-tablette | F12 F15 | Intégration concurrente + appareils |
| [T196](#t196) | Permission révoquée après diagnostic | F15 F21 | Appareil réel |
| [T197](#t197) | Une tablette partagée ne mélange pas les comptes | F01 F12 F16 | Sécurité appareil + API |
| [T198](#t198) | Présentation élève sans données privées | F08 F16 | Recette d’interface |
| [T199](#t199) | Arrêt système et transfert différé sur tablette | F12 F15 F16 | Appareil réel + ingestion |
| [T200](#t200) | Scope identique web et app | F01 F22 | Intégration API + parcours |
| [T201](#t201) | Données sensibles absentes de la liste | F21 F22 | Intégration API + parcours |
| [T202](#t202) | Archivage ne révoque pas appartenance | F14 F22 | Intégration API + parcours |
| [T203](#t203) | Formation en pause bloque archivage | F03 F14 F22 | Intégration API + parcours |
| [T204](#t204) | Engagement collectif futur bloque | F18 F22 | Intégration API + parcours |
| [T205](#t205) | Solde et droit réservé bloquent | F10 F17 F22 | Intégration API + parcours |
| [T206](#t206) | Droits restants conservés avec avertissement | F14 F17 F22 | Intégration API + parcours |
| [T207](#t207) | Preview obsolète après nouveau rendez-vous | F05 F22 | Intégration API + parcours |
| [T208](#t208) | Preview expirée ou autre auteur | F14 F22 | Intégration API + parcours |
| [T209](#t209) | Lot à résultats partiels sans tout-ou-rien | F14 F22 | Intégration API + parcours |
| [T210](#t210) | Lot explicite, maximum et rejeu | F14 F22 | Intégration API + parcours |
| [T211](#t211) | Arrivée tardive de brouillon après archive | F12 F14 F22 | Intégration API + parcours |
| [T212](#t212) | Restaurer sans réactiver ancien accès | F01 F03 F14 F22 | Intégration API + parcours |
| [T213](#t213) | Changement de droits pendant job | F01 F22 | Intégration API + parcours |
| [T214](#t214) | Purge et archive indépendantes | F14 F22 | Intégration API + parcours |
| [T215](#t215) | Compte et durée de séances sans GPS | F07 F15 F23 | Intégration API + parcours |
| [T216](#t216) | Multi-permis dédupliqué | F03 F23 | Intégration API + parcours |
| [T217](#t217) | Archivage ne réécrit pas activité passée | F14 F23 | Intégration API + parcours |
| [T218](#t218) | Durée manquante non remplacée par GPS | F07 F15 F23 | Intégration API + parcours |
| [T219](#t219) | Taux annulations sur cohorte terminale | F05 F23 | Intégration API + parcours |
| [T220](#t220) | Remplissage pondéré de séries | F18 F23 | Intégration API + parcours |
| [T221](#t221) | Paiement de pack compté une seule fois | F10 F17 F23 | Intégration API + parcours |
| [T222](#t222) | Remboursement réel et résultat net | F10 F23 | Intégration API + parcours |
| [T223](#t223) | Contre-écriture corrige la période originale | F10 F23 | Intégration API + parcours |
| [T224](#t224) | Filtres moniteur ne ventilent pas packs | F17 F23 | Intégration API + parcours |
| [T225](#t225) | Solde dû ne compte pas prix seulement prévu | F05 F10 F23 | Intégration API + parcours |
| [T226](#t226) | Période civile et changement d’heure | F23 | Intégration API + parcours |
| [T227](#t227) | Absence de droit financier dans réponses | F01 F22 F23 | Intégration API + parcours |
| [T228](#t228) | Pré-requis et bilans en retard définis | F08 F21 F23 | Intégration API + parcours |
| [T229](#t229) | Export filtré sans données excessives | F22 F23 | Intégration API + parcours |
| [T230](#t230) | Cellules CSV neutralisées | F22 F23 | Sécurité export + tableurs cibles |
| [T231](#t231) | Droit retiré après export READY | F01 F22 F23 | Intégration API + parcours |
| [T232](#t232) | Session web sans persistance sensible et CSRF | F01 F21 F22 | Sécurité navigateur + API |

<a id="t163"></a>
### T163 · Setup refusé au moniteur non ADMIN

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F20. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R73](../03-fonctionnel/regles-etats.md#r73). **Niveau :** Intégration API + parcours.

**Étant donné :** École DRAFT et compte INSTRUCTOR sans ADMIN.

**Quand :** Appeler saveSchoolSetup puis activateSchool avec identifiants connus.

**Alors :** 403 ; School, configuration, membres et outbox inchangés.


<a id="t164"></a>
### T164 · Activer le workspace sans modules facultatifs

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F13 F20. **Règles :** [R74](../03-fonctionnel/regles-etats.md#r74), [R80](../03-fonctionnel/regles-etats.md#r80). **Niveau :** Intégration API + parcours.

**Étant donné :** Identité/contact/notice/politique approuvés ; packs et collectif désactivés ; aucun logo.

**Quand :** Relire readiness puis activer avec les bonnes versions.

**Alors :** Workspace ACTIVE ; modules inutilisés ne bloquent pas ; aucune fausse offre ou catégorie créée.


<a id="t165"></a>
### T165 · Offre incomplète sans planification autorisée

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F03 F13 F20. **Règles :** [R74](../03-fonctionnel/regles-etats.md#r74), [R75](../03-fonctionnel/regles-etats.md#r75). **Niveau :** Intégration API + parcours.

**Étant donné :** École active, catégorie demandée sans référentiel approuvé et prix vide.

**Quand :** Tenter création d’offre prête puis planification.

**Alors :** Offre reste brouillon/refus explicite ; montant vide non converti à zéro ; aucune autorisation légale simulée.


<a id="t166"></a>
### T166 · Deux responsables modifient le setup

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F13 F20. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R76](../03-fonctionnel/regles-etats.md#r76). **Niveau :** Intégration API + parcours.

**Étant donné :** Deux navigateurs chargent version4 du même progrès.

**Quand :** A sauvegarde puis B soumet If-Match4.

**Alors :** A obtient version5 ; B reçoit412 et différences ; aucune perte de la modification A.


<a id="t167"></a>
### T167 · Reprise web vers tablette du setup

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F20 F21. **Règles :** [R76](../03-fonctionnel/regles-etats.md#r76), [R82](../03-fonctionnel/regles-etats.md#r82). **Niveau :** Intégration API + parcours.

**Étant donné :** Deux étapes sauvegardées serveur ; troisième seulement saisie en mémoire web.

**Quand :** Fermer la session puis ouvrir le même compte sur tablette.

**Alors :** Reprise au dernier état confirmé ; aucune affirmation que le champ non envoyé est sauvegardé.


<a id="t168"></a>
### T168 · Politique nouvelle sans réécrire les achats

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F13 F17 F20. **Règles :** [R75](../03-fonctionnel/regles-etats.md#r75), [R99](../03-fonctionnel/regles-etats.md#r99). **Niveau :** Intégration API + parcours.

**Étant donné :** Pack acheté sous prix/conditions version1.

**Quand :** Publier nouveau prix et règle future depuis setup.

**Alors :** Achat, solde et conditions version1 inchangés ; futures ventes utilisent version2 explicitement.


<a id="t169"></a>
### T169 · Catégorie retirée avec dépendances

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F03 F13 F20. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R75](../03-fonctionnel/regles-etats.md#r75). **Niveau :** Intégration API + parcours.

**Étant donné :** Formation active et future leçon pour une catégorie.

**Quand :** Demander sa désactivation.

**Alors :** Impacts montrés ; aucune formation/leçon supprimée ; traitement explicite avant retrait des nouvelles opérations.


<a id="t170"></a>
### T170 · Photo obligatoire interdite dans les politiques

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F13 F20 F21. **Règles :** [R77](../03-fonctionnel/regles-etats.md#r77), [R80](../03-fonctionnel/regles-etats.md#r80). **Niveau :** Intégration API + parcours.

**Étant donné :** ADMIN crée politique avec profilePhotoDocumentId REQUIRED.

**Quand :** Envoyer createProfileFieldPolicy.

**Alors :** 422 ; champ facultatif reste facultatif, même via API directe.


<a id="t171"></a>
### T171 · Profil collectif non approuvé

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18 F20. **Règles :** [R66](../03-fonctionnel/regles-etats.md#r66), [R74](../03-fonctionnel/regles-etats.md#r74). **Niveau :** Intégration API + parcours.

**Étant donné :** Cours configuré mais profil réglementaire non approuvé.

**Quand :** Activer workspace puis publier le cours.

**Alors :** Activation générale possible si prête ; publication refusée ; aucune notification de série non publiée.


<a id="t172"></a>
### T172 · Rejeu activation idempotent

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F20. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R73](../03-fonctionnel/regles-etats.md#r73), [R74](../03-fonctionnel/regles-etats.md#r74). **Niveau :** Intégration API + parcours.

**Étant donné :** Activation valide dont la réponse réseau est perdue.

**Quand :** Renvoyer même operationId/charge.

**Alors :** Même résultat, une transition, aucun doublon de membres, d’offres ou d’événements.


<a id="t173"></a>
### T173 · Erreur de champ et navigation clavier du wizard

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F20 F21. **Règles :** [R76](../03-fonctionnel/regles-etats.md#r76), [R100](../03-fonctionnel/regles-etats.md#r100). **Niveau :** Accessibilité manuelle + automatisée.

**Étant donné :** Wizard ouvert à largeur compacte, zoom200%, clavier seul et lecteur d’écran.

**Quand :** Soumettre contact invalide puis corriger et revenir étape précédente.

**Alors :** Erreur liée au champ/annoncée, focus logique, saisie conservée, aucun bouton inaccessible.


<a id="t174"></a>
### T174 · École DRAFT ne vend pas ni ne publie

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F17 F18 F20. **Règles :** [R73](../03-fonctionnel/regles-etats.md#r73), [R74](../03-fonctionnel/regles-etats.md#r74). **Niveau :** Intégration API + parcours.

**Étant donné :** ADMIN autorisé au setup mais workspace non activé.

**Quand :** Contourner UI et appeler vente/inscription/publication.

**Alors :** Refus readiness/école, pas d’argent ni de place ni annonce créés ; commandes de configuration seules permises.


<a id="t175"></a>
### T175 · Invitation ne crée pas une formation validée

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F02 F03 F21. **Règles :** [R05](../03-fonctionnel/regles-etats.md#r05), [R79](../03-fonctionnel/regles-etats.md#r79). **Niveau :** Intégration API + parcours.

**Étant donné :** Invitation élève valide et offre B active.

**Quand :** Accepter puis choisir B dans onboarding.

**Alors :** Un Learner et une TrainingRequest PENDING ; aucune Training approuvée sans décision autorisée.


<a id="t176"></a>
### T176 · Validation de demande atomique

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F03 F21. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R12](../03-fonctionnel/regles-etats.md#r12), [R79](../03-fonctionnel/regles-etats.md#r79). **Niveau :** Intégration API + parcours.

**Étant donné :** Demande PENDING avec moniteur et offre valides.

**Quand :** Approuver deux fois avec la même opération.

**Alors :** Une Training et affectation, même trainingId ; pas de permis automatiquement APPROVED.


<a id="t177"></a>
### T177 · Refuser photo GPS push sans bloquer

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F11 F15 F21. **Règles :** [R77](../03-fonctionnel/regles-etats.md#r77), [R80](../03-fonctionnel/regles-etats.md#r80), [R100](../03-fonctionnel/regles-etats.md#r100). **Niveau :** Intégration API + parcours.

**Étant donné :** Élève au minimum d’identité conforme.

**Quand :** Passer photo et refuser permissions facultatives puis finir accueil.

**Alors :** Accès au calendrier/bilans ; aucun badge profil incomplet pour ces refus ; aucune capture autorisée implicitement.


<a id="t178"></a>
### T178 · Naissance future et adresse conditionnelle

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F21. **Règles :** [R77](../03-fonctionnel/regles-etats.md#r77), [R81](../03-fonctionnel/regles-etats.md#r81). **Niveau :** Intégration API + parcours.

**Étant donné :** Politique exige naissance avant un cours précis, pas adresse à JOIN.

**Quand :** Saisir une date future puis la corriger ; laisser adresse vide à JOIN.

**Alors :** Date future refusée en clair ; adresse vide ne bloque pas l’entrée ; date nécessaire demandée à action pertinente.


<a id="t179"></a>
### T179 · Noms Unicode sans troncature

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F21. **Règles :** [R33](../03-fonctionnel/regles-etats.md#r33), [R77](../03-fonctionnel/regles-etats.md#r77), [R100](../03-fonctionnel/regles-etats.md#r100). **Niveau :** Intégration API + parcours.

**Étant donné :** Nom contenant accents, apostrophe et caractères non latins, longueur autorisée.

**Quand :** Sauvegarder sur web puis lire sur app.

**Alors :** Identité conservée, pas alphabet imposé ; dépassement150 renvoie erreur sans couper silencieusement.


<a id="t180"></a>
### T180 · Reprise explicite de coordonnées dans B

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F21. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R03](../03-fonctionnel/regles-etats.md#r03), [R78](../03-fonctionnel/regles-etats.md#r78). **Niveau :** Intégration API + parcours.

**Étant donné :** Même personne invitée dans B après A, avec documents et choix A.

**Quand :** Rejoindre B puis accepter la reprise de ses coordonnées autorisées.

**Alors :** Seuls champs explicitement confirmés sont copiés ; aucune pièce, trace, droit, formation ni choix GPS A dans B.


<a id="t181"></a>
### T181 · Homonymes non fusionnés

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F02 F21. **Règles :** [R03](../03-fonctionnel/regles-etats.md#r03), [R78](../03-fonctionnel/regles-etats.md#r78). **Niveau :** Intégration API + parcours.

**Étant donné :** Deux Person vérifiées avec mêmes noms.

**Quand :** Inviter et accepter chacune.

**Alors :** Deux dossiers liés à leur identité correcte ; aucune fusion par nom ou naissance.


<a id="t182"></a>
### T182 · Contact scolaire distinct du login

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F21. **Règles :** [R03](../03-fonctionnel/regles-etats.md#r03), [R77](../03-fonctionnel/regles-etats.md#r77). **Niveau :** Intégration API + parcours.

**Étant donné :** Compte authentifié par email A ; contact souhaité B.

**Quand :** Modifier contactEmail scolaire.

**Alors :** Connexion OIDC reste A ; B ne devient pas automatiquement identité vérifiée ou propriétaire d’invitation.


<a id="t183"></a>
### T183 · Dépôt photo mal formé

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F09 F21. **Règles :** [R21](../03-fonctionnel/regles-etats.md#r21), [R22](../03-fonctionnel/regles-etats.md#r22), [R77](../03-fonctionnel/regles-etats.md#r77). **Niveau :** Intégration API + parcours.

**Étant donné :** Intention PROFILE_PHOTO avec PDF ou image surdimensionnée.

**Quand :** Soumettre MIME PDF puis image supérieure à2MiB ; essayer pointeur document non READY.

**Alors :** Uploads/pointeur refusés ; onboarding sans photo toujours possible ; pipeline ne publie rien.


<a id="t184"></a>
### T184 · Photo sans EXIF ni partage inter-élèves

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F09 F21. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R22](../03-fonctionnel/regles-etats.md#r22), [R77](../03-fonctionnel/regles-etats.md#r77). **Niveau :** Intégration API + parcours.

**Étant donné :** Image JPEG valide avec métadonnées EXIF, appartenant à l’élève A ; compte distinct de l’élève B pour tester l’accès interdit. Aucune détection de visage n’est supposée.

**Quand :** Traiter l’image puis lire photo avec le second compte.

**Alors :** Dérivé nettoyé selon pipeline ; deuxième élève refusé ; aucun champ de localisation de photo exposé.


<a id="t185"></a>
### T185 · Saisie assistée ne signe pas le choix élève

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F02 F15 F21. **Règles :** [R80](../03-fonctionnel/regles-etats.md#r80), [R97](../03-fonctionnel/regles-etats.md#r97). **Niveau :** Intégration API + parcours.

**Étant donné :** Moniteur habilité renseigne un contact en présence de l’élève.

**Quand :** Sauvegarder par API puis tenter même canal pour consentement personnel GPS.

**Alors :** Provenance STAFF_ASSISTED/acteur conservée ; aucune acceptation personnelle inventée ; choix GPS séparé.


<a id="t186"></a>
### T186 · Cours suivi ailleurs reste à vérifier

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F03 F18 F21. **Règles :** [R61](../03-fonctionnel/regles-etats.md#r61), [R79](../03-fonctionnel/regles-etats.md#r79). **Niveau :** Intégration API + parcours.

**Étant donné :** Élève déclare une sensibilisation et joint document.

**Quand :** Terminer onboarding puis consulter Requirement.

**Alors :** État déclaré/en attente ; pas COMPLETED, pas cours validé ni place annulée automatiquement.


<a id="t187"></a>
### T187 · Moniteur invité n’accède pas au setup propriétaire

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F21. **Règles :** [R73](../03-fonctionnel/regles-etats.md#r73), [R86](../03-fonctionnel/regles-etats.md#r86). **Niveau :** Intégration API + parcours.

**Étant donné :** INSTRUCTOR nouveau membre sans grant global.

**Quand :** Accepter invitation et suivre accueil.

**Alors :** E47 puis préparation appareil facultative ; aucun E38 obligatoire ni élargissement de droits aux autres élèves.


<a id="t188"></a>
### T188 · Dernière place perdue pendant complément profil

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18 F19 F21. **Règles :** [R59](../03-fonctionnel/regles-etats.md#r59), [R81](../03-fonctionnel/regles-etats.md#r81), [R98](../03-fonctionnel/regles-etats.md#r98). **Niveau :** Intégration API + parcours.

**Étant donné :** Cours avec1place, élève A au formulaire complément ; B est prêt.

**Quand :** B confirme sa place puis A revient du formulaire.

**Alors :** A voit Complet après relecture ; pas d’inscription ni de HOLD pour A.


<a id="t189"></a>
### T189 · Politique modifiée sans recommencer tout

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F13 F20 F21. **Règles :** [R75](../03-fonctionnel/regles-etats.md#r75), [R76](../03-fonctionnel/regles-etats.md#r76), [R99](../03-fonctionnel/regles-etats.md#r99). **Niveau :** Intégration API + parcours.

**Étant donné :** Profil déjà complété, nouvelle politique future avec un champ justifié.

**Quand :** Ouvrir app et une action concernée.

**Alors :** Seul complément utile demandé ; ancien cours/bilan inchangé ; pas reset intégral ou refus global.


<a id="t190"></a>
### T190 · Invitation expirée et lien profond sûr

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F02 F21. **Règles :** [R05](../03-fonctionnel/regles-etats.md#r05), [R98](../03-fonctionnel/regles-etats.md#r98). **Niveau :** Intégration API + parcours.

**Étant donné :** Lien périmé ou destination externe injectée.

**Quand :** Ouvrir puis s’authentifier.

**Alors :** Expiration claire sans consommer invitation ; destination externe refusée, pas de token/PII dans analytics URL.


<a id="t191"></a>
### T191 · Deux accueils personnels concurrents

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F21. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R76](../03-fonctionnel/regles-etats.md#r76), [R100](../03-fonctionnel/regles-etats.md#r100). **Niveau :** Intégration API + parcours.

**Étant donné :** App et navigateur au même progrès STUDENT version3.

**Quand :** Modifier étapes différentes puis sauvegarder successivement.

**Alors :** Premier commit conservé ; second412 avec reprise utile ; pas de deuxième dossier ou auto-inscription.


<a id="t192"></a>
### T192 · Rotation pendant capture sans redémarrage

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F15 F16. **Règles :** [R42](../03-fonctionnel/regles-etats.md#r42), [R82](../03-fonctionnel/regles-etats.md#r82), [R83](../03-fonctionnel/regles-etats.md#r83). **Niveau :** Appareil réel + journaux expurgés.

**Étant donné :** Capture native autorisée sur tablette, points déjà collectés.

**Quand :** Passer portrait/paysage puis fenêtre étroite pendant essai sécurisé.

**Alors :** captureId, séquence et file inchangés ; pas double service ni perte d’observation/zoom manuel.


<a id="t193"></a>
### T193 · Toute l’app en tablette étroite

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F08 F18 F21. **Règles :** [R82](../03-fonctionnel/regles-etats.md#r82), [R100](../03-fonctionnel/regles-etats.md#r100). **Niveau :** Appareils et accessibilité.

**Étant donné :** Agenda, dossier, bilan, présences et onboarding ouverts successivement.

**Quand :** Réduire fenêtre, agrandir texte, utiliser clavier et toucher.

**Alors :** Actions accessibles et données non tronquées de façon irréversible ; navigation/focus cohérents, pas layout seulement GPS adapté.


<a id="t194"></a>
### T194 · Tablette non qualifiée sans faux GPS

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F15 F21. **Règles :** [R80](../03-fonctionnel/regles-etats.md#r80), [R84](../03-fonctionnel/regles-etats.md#r84). **Niveau :** Appareil réel + API.

**Étant donné :** Appareil hors profil qualifié, Internet actif et carte visible.

**Quand :** Ouvrir diagnostic puis essayer capture.

**Alors :** Capture non autorisée ; agenda/replay/bilan/séance sans capture disponibles ; réseau distinct du positionnement.


<a id="t195"></a>
### T195 · Aucun relais implicite téléphone-tablette

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F15. **Règles :** [R42](../03-fonctionnel/regles-etats.md#r42), [R83](../03-fonctionnel/regles-etats.md#r83), [R84](../03-fonctionnel/regles-etats.md#r84). **Niveau :** Intégration concurrente + appareils.

**Étant donné :** Téléphone enregistre la leçon ; tablette connectée au même compte.

**Quand :** Essayer démarrage sur tablette avant arrêt/réconciliation.

**Alors :** Conflit CAPTURE_DEVICE_BUSY/active lesson ; aucune deuxième capture ou reprise silencieuse.


<a id="t196"></a>
### T196 · Permission révoquée après diagnostic

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F15 F21. **Règles :** [R41](../03-fonctionnel/regles-etats.md#r41), [R83](../03-fonctionnel/regles-etats.md#r83), [R84](../03-fonctionnel/regles-etats.md#r84). **Niveau :** Appareil réel.

**Étant donné :** Diagnostic QUALIFIED, puis permission localisation retirée dans OS.

**Quand :** Démarrer ou reprendre action nécessitant localisation.

**Alors :** Contrôle local actualisé ; diagnostic NEEDS_CHECK ou blocage ; aucune collecte furtive.


<a id="t197"></a>
### T197 · Une tablette partagée ne mélange pas les comptes

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F12 F16. **Règles :** [R34](../03-fonctionnel/regles-etats.md#r34), [R85](../03-fonctionnel/regles-etats.md#r85), [R95](../03-fonctionnel/regles-etats.md#r95). **Niveau :** Sécurité appareil + API.

**Étant donné :** Compte A avec file et notes privées ; compte B doit utiliser appareil.

**Quand :** Déconnexion/verrou puis connexion B et retour navigation.

**Alors :** Pas de donnée A en aperçu/cache ; file A non envoyée sous B ; politique de sortie explicite.


<a id="t198"></a>
### T198 · Présentation élève sans données privées

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F08 F16. **Règles :** [R18](../03-fonctionnel/regles-etats.md#r18), [R47](../03-fonctionnel/regles-etats.md#r47), [R85](../03-fonctionnel/regles-etats.md#r85). **Niveau :** Recette d’interface.

**Étant donné :** Bilan publié et note privée sur même leçon, autres élèves en liste.

**Quand :** Activer vue de présentation, naviguer/replier panneau et revenir.

**Alors :** Seulement publication autorisée dans présentation ; pas note privée, autres élèves ni réglages financiers.


<a id="t199"></a>
### T199 · Arrêt système et transfert différé sur tablette

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F15 F16. **Règles :** [R42](../03-fonctionnel/regles-etats.md#r42), [R43](../03-fonctionnel/regles-etats.md#r43), [R44](../03-fonctionnel/regles-etats.md#r44), [R82](../03-fonctionnel/regles-etats.md#r82). **Niveau :** Appareil réel + ingestion.

**Étant donné :** Capture déjà autorisée, perte réseau puis interruption système.

**Quand :** Relancer plus tard et transférer segments réellement enregistrés.

**Alors :** Trajet partiel signalé ; aucun point interpolé présenté comme mesuré ; bilan réalisable sans trace complète.


<a id="t200"></a>
### T200 · Scope identique web et app

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F22. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R02](../03-fonctionnel/regles-etats.md#r02), [R86](../03-fonctionnel/regles-etats.md#r86). **Niveau :** Intégration API + parcours.

**Étant donné :** Moniteur affecté à A, non affecté à B dans même école.

**Quand :** Demander dossiers via web puis API native, filtre/global stats.

**Alors :** Accès B refusé dans détails, listes, compteurs et téléchargements ; web ne donne aucun droit supplémentaire.


<a id="t201"></a>
### T201 · Données sensibles absentes de la liste

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F21 F22. **Règles :** [R77](../03-fonctionnel/regles-etats.md#r77), [R86](../03-fonctionnel/regles-etats.md#r86), [R95](../03-fonctionnel/regles-etats.md#r95). **Niveau :** Intégration API + parcours.

**Étant donné :** Dossiers ont dates de naissance, adresses, notes et traces.

**Quand :** Charger liste E34 et inspecter réponse réseau.

**Alors :** Projection minimale sans ces champs ; cacher colonne ne suffit pas si payload les contient.


<a id="t202"></a>
### T202 · Archivage ne révoque pas appartenance

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F14 F22. **Règles :** [R29](../03-fonctionnel/regles-etats.md#r29), [R87](../03-fonctionnel/regles-etats.md#r87). **Niveau :** Intégration API + parcours.

**Étant donné :** Dossier sans blocages, Membership LEARNER active, bilan publié.

**Quand :** Preview puis archive confirmé.

**Alors :** archivedAt défini, Membership inchangée ; historique propre publié consultable, nouvelles offres/opérations refusées.


<a id="t203"></a>
### T203 · Formation en pause bloque archivage

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F03 F14 F22. **Règles :** [R88](../03-fonctionnel/regles-etats.md#r88). **Niveau :** Intégration API + parcours.

**Étant donné :** Training PAUSED et aucune future leçon.

**Quand :** Demander aperçu puis tenter forcer archive.

**Alors :** Blocage formation à résoudre ; aucune fermeture automatique de Training.


<a id="t204"></a>
### T204 · Engagement collectif futur bloque

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18 F22. **Règles :** [R62](../03-fonctionnel/regles-etats.md#r62), [R88](../03-fonctionnel/regles-etats.md#r88). **Niveau :** Intégration API + parcours.

**Étant donné :** Enrollment CONFIRMED ou RECONFIRMATION_REQUIRED pour une occurrence future.

**Quand :** Prévisualiser archivage.

**Alors :** Blocage lié au cours ; pas annulation ni libération de place/réservation automatique.


<a id="t205"></a>
### T205 · Solde et droit réservé bloquent

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F10 F17 F22. **Règles :** [R88](../03-fonctionnel/regles-etats.md#r88), [R89](../03-fonctionnel/regles-etats.md#r89). **Niveau :** Intégration API + parcours.

**Étant donné :** Compte avec balance positive et droit HOLD.

**Quand :** Prévisualiser/committer sans résolution.

**Alors :** Deux motifs clairs selon droits ; aucune remise, consommation ni remboursement générés.


<a id="t206"></a>
### T206 · Droits restants conservés avec avertissement

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F14 F17 F22. **Règles :** [R89](../03-fonctionnel/regles-etats.md#r89). **Niveau :** Intégration API + parcours.

**Étant donné :** Dossier sans blocage,2droits disponibles non réservés à échéance future.

**Quand :** Archiver après reconnaissance des avertissements.

**Alors :** Droits et date d’échéance identiques ; ni remboursement ni remise à zéro ; avertissement audité.


<a id="t207"></a>
### T207 · Preview obsolète après nouveau rendez-vous

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F22. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R88](../03-fonctionnel/regles-etats.md#r88). **Niveau :** Intégration API + parcours.

**Étant donné :** Aperçu prêt puis autre opérateur crée engagement compatible.

**Quand :** Commiter ancien aperçu/version.

**Alors :** Refus412 ou409 impact nouveau ; dossier reste actif, leçon conservée.


<a id="t208"></a>
### T208 · Preview expirée ou autre auteur

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F14 F22. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R88](../03-fonctionnel/regles-etats.md#r88). **Niveau :** Intégration API + parcours.

**Étant donné :** Aperçu de plus de15minutes ou créé par autre membre.

**Quand :** Appeler archive avec cet identifiant.

**Alors :** 410 expiration ou403/404 selon visibilité ; pas usage comme jeton d’autorisation.


<a id="t209"></a>
### T209 · Lot à résultats partiels sans tout-ou-rien

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F14 F22. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R90](../03-fonctionnel/regles-etats.md#r90). **Niveau :** Intégration API + parcours.

**Étant donné :** Trois lignes confirmées ; une devient bloquée avant traitement.

**Quand :** Traiter le lot.

**Alors :** Deux ARCHIVED, une BLOCKED ; job PARTIAL ; aucun rollback secret des réussites et aucune force sur échec.


<a id="t210"></a>
### T210 · Lot explicite, maximum et rejeu

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F14 F22. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R90](../03-fonctionnel/regles-etats.md#r90). **Niveau :** Intégration API + parcours.

**Étant donné :** Recherche retourne200dossiers.

**Quand :** Essayer sélection implicite totale, puis51IDs, puis rejouer un lot valide de2.

**Alors :** Pas de sélection implicite acceptée ;51 refusé ; rejeu valide même job/effets, pas autre lot.


<a id="t211"></a>
### T211 · Arrivée tardive de brouillon après archive

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F14 F22. **Règles :** [R34](../03-fonctionnel/regles-etats.md#r34), [R88](../03-fonctionnel/regles-etats.md#r88). **Niveau :** Intégration API + parcours.

**Étant donné :** Appareil avait un brouillon non connu ; serveur archive après contrôles connus.

**Quand :** Reconnecter et soumettre la commande tardive.

**Alors :** Conflit expliqué et procédure de réconciliation ; pas perte silencieuse ni restauration automatique du Learner.


<a id="t212"></a>
### T212 · Restaurer sans réactiver ancien accès

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F03 F14 F22. **Règles :** [R87](../03-fonctionnel/regles-etats.md#r87), [R91](../03-fonctionnel/regles-etats.md#r91). **Niveau :** Intégration API + parcours.

**Étant donné :** Dossier archivé, Membership révoquée, formations terminées et ancien refus GPS.

**Quand :** Restaurer par ADMIN.

**Alors :** Dossier actif uniquement ; Membership révoquée, formations/choix inchangés ; pas engagement recréé.


<a id="t213"></a>
### T213 · Changement de droits pendant job

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F22. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R86](../03-fonctionnel/regles-etats.md#r86), [R90](../03-fonctionnel/regles-etats.md#r90). **Niveau :** Intégration API + parcours.

**Étant donné :** Lot lancé puis grant MANAGE_LEARNER_ARCHIVES retiré avant ligne2.

**Quand :** Continuer worker et consulter résultat.

**Alors :** Lignes suivantes ACCESS_REVOKED sans mutation ; résultats privés non livrés à acteur devenu non habilité.


<a id="t214"></a>
### T214 · Purge et archive indépendantes

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F14 F22. **Règles :** [R30](../03-fonctionnel/regles-etats.md#r30), [R87](../03-fonctionnel/regles-etats.md#r87), [R89](../03-fonctionnel/regles-etats.md#r89), [R91](../03-fonctionnel/regles-etats.md#r91). **Niveau :** Intégration API + parcours.

**Étant donné :** Trace archivée atteint échéance de conservation validée.

**Quand :** Exécuter purge puis restaurer dossier.

**Alors :** Coordonnées purgées ne reviennent pas ; bilan conservé selon politique ; aucune promesse de restauration totale.


<a id="t215"></a>
### T215 · Compte et durée de séances sans GPS

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F07 F15 F23. **Règles :** [R49](../03-fonctionnel/regles-etats.md#r49), [R92](../03-fonctionnel/regles-etats.md#r92). **Niveau :** Intégration API + parcours.

**Étant donné :** Trois leçons complétées45,50,90minutes, une sans capture, deux learners.

**Quand :** Calculer M01/M02/M03 pour la période réelle.

**Alors :** M01=3 ; M02=11100secondes ; M03=2. Aucune exclusion liée au GPS.


<a id="t216"></a>
### T216 · Multi-permis dédupliqué

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F03 F23. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R92](../03-fonctionnel/regles-etats.md#r92). **Niveau :** Intégration API + parcours.

**Étant donné :** Même learner avec leçons A et B, plus un autre learner.

**Quand :** Calculer M03.

**Alors :** Deux élèves distincts, pas trois formations comptées comme trois personnes.


<a id="t217"></a>
### T217 · Archivage ne réécrit pas activité passée

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F14 F23. **Règles :** [R87](../03-fonctionnel/regles-etats.md#r87), [R92](../03-fonctionnel/regles-etats.md#r92). **Niveau :** Intégration API + parcours.

**Étant donné :** Une leçon de la période appartient à dossier archivé aujourd’hui.

**Quand :** Comparer métriques avant/après archivage.

**Alors :** M01/M02/M03 inchangés tant que sources conservées ; filtre actif ne supprime pas implicitement historique.


<a id="t218"></a>
### T218 · Durée manquante non remplacée par GPS

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F07 F15 F23. **Règles :** [R49](../03-fonctionnel/regles-etats.md#r49), [R92](../03-fonctionnel/regles-etats.md#r92). **Niveau :** Intégration API + parcours.

**Étant donné :** Source importée avec actualEnd absent et trace40minutes.

**Quand :** Calculer M02.

**Alors :** Donnée exclue de durée et incomplétude signalée ; aucune substitution40 ou durée planifiée.


<a id="t219"></a>
### T219 · Taux annulations sur cohorte terminale

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F23. **Règles :** [R14](../03-fonctionnel/regles-etats.md#r14), [R92](../03-fonctionnel/regles-etats.md#r92). **Niveau :** Intégration API + parcours.

**Étant donné :** Sur période prévue :6réalisées,2annulées,2absences,3encore planifiées.

**Quand :** Calculer M04.

**Alors :** Dénominateur10 ; deux taux20% ;3nonclôturées signalées séparément, pas faute élève déduite.


<a id="t220"></a>
### T220 · Remplissage pondéré de séries

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18 F23. **Règles :** [R60](../03-fonctionnel/regles-etats.md#r60), [R92](../03-fonctionnel/regles-etats.md#r92). **Niveau :** Intégration API + parcours.

**Étant donné :** Séries à venir de capacités8et12 avec6et3inscrits dont reconfirmations.

**Quand :** Calculer M05 avec quatre blocs par série.

**Alors :** Numérateur9, dénominateur20,45% ; pas75%+25%moyenné et pas36participants.


<a id="t221"></a>
### T221 · Paiement de pack compté une seule fois

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F10 F17 F23. **Règles :** [R23](../03-fonctionnel/regles-etats.md#r23), [R93](../03-fonctionnel/regles-etats.md#r93). **Niveau :** Intégration API + parcours.

**Étant donné :** Pack payé146000centimes,10leçons couvertes par droits.

**Quand :** Consommer trois leçons puis calculer M06.

**Alors :** 146000centimes, aucun nouvel encaissement provenant des leçons couvertes.


<a id="t222"></a>
### T222 · Remboursement réel et résultat net

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F10 F23. **Règles :** [R24](../03-fonctionnel/regles-etats.md#r24), [R93](../03-fonctionnel/regles-etats.md#r93). **Niveau :** Intégration API + parcours.

**Étant donné :** Encaissements146000et11000, remboursement réel10000même période.

**Quand :** Calculer M06.

**Alors :** 147000centimes ; libellé journal net, pas bénéfice ni solde bancaire.


<a id="t223"></a>
### T223 · Contre-écriture corrige la période originale

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F10 F23. **Règles :** [R25](../03-fonctionnel/regles-etats.md#r25), [R93](../03-fonctionnel/regles-etats.md#r93). **Niveau :** Intégration API + parcours.

**Étant donné :** Encaissement11000en septembre inversé par REVERSAL en octobre ; autres flux fixture.

**Quand :** Relire septembre après correction connue.

**Alors :** Effet de11000retiré de septembre ; total136000avec fixture ; recordedAt octobre auditable, pas remboursement supposé.


<a id="t224"></a>
### T224 · Filtres moniteur ne ventilent pas packs

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F17 F23. **Règles :** [R92](../03-fonctionnel/regles-etats.md#r92), [R93](../03-fonctionnel/regles-etats.md#r93). **Niveau :** Intégration API + parcours.

**Étant donné :** Compte d’achat sans attribution d’encaissement à moniteur/site.

**Quand :** Appliquer filtre moniteur à M06.

**Alors :** NOT_APPLICABLE/explication ou métrique absente selon droits ; pas répartition arbitraire égale ou par leçons.


<a id="t225"></a>
### T225 · Solde dû ne compte pas prix seulement prévu

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F10 F23. **Règles :** [R23](../03-fonctionnel/regles-etats.md#r23), [R92](../03-fonctionnel/regles-etats.md#r92). **Niveau :** Intégration API + parcours.

**Étant donné :** Leçon future annoncée110CHF sans charge créée ; autre compte charge100CHF solde30CHF.

**Quand :** Calculer M07.

**Alors :** 3000centimes débiteurs de charges réelles, pas140CHF ; snapshot actuel indiqué.


<a id="t226"></a>
### T226 · Période civile et changement d’heure

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F23. **Règles :** [R31](../03-fonctionnel/regles-etats.md#r31), [R92](../03-fonctionnel/regles-etats.md#r92). **Niveau :** Intégration API + parcours.

**Étant donné :** École Europe/Zurich ; leçons autour du changement d’heure et bornes locales.

**Quand :** Demander intervalle civil avec toDateExclusive.

**Alors :** Conversion UTC correcte, pas doublon/oubli ; dénominateurs cohérents, période affichée en heure école.


<a id="t227"></a>
### T227 · Absence de droit financier dans réponses

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F22 F23. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R86](../03-fonctionnel/regles-etats.md#r86), [R94](../03-fonctionnel/regles-etats.md#r94). **Niveau :** Intégration API + parcours.

**Étant donné :** Moniteur sans VIEW_FINANCIAL_METRICS ouvre activité propre puis école.

**Quand :** Inspecter payload/exports et modifier query scope.

**Alors :** Aucun montant scolaire exposé ; absence de grant distincte de zéro ; scope non autorisé refusé.


<a id="t228"></a>
### T228 · Pré-requis et bilans en retard définis

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F08 F21 F23. **Règles :** [R77](../03-fonctionnel/regles-etats.md#r77), [R80](../03-fonctionnel/regles-etats.md#r80), [R92](../03-fonctionnel/regles-etats.md#r92). **Niveau :** Intégration API + parcours.

**Étant donné :** Élève sans photo et refusGPS ; autre manque un champ nécessaire ; une leçon sans première publication et une avec correction brouillon.

**Quand :** Calculer M08/M09.

**Alors :** Photo/refus non comptés ; manque réellement nécessaire compté ; M09 compte première publication absente, pas correction privée après publication.


<a id="t229"></a>
### T229 · Export filtré sans données excessives

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F22 F23. **Règles :** [R86](../03-fonctionnel/regles-etats.md#r86), [R96](../03-fonctionnel/regles-etats.md#r96). **Niveau :** Intégration API + parcours.

**Étant donné :** Export STUDENT_LIST scope autorisé.

**Quand :** Générer fichier puis inspecter en-tête, lignes et manifest.

**Alors :** Colonnes minimales/version/date, aucune naissance/adresse/document/GPS ni élève hors scope ; un max10000lignes appliqué.


<a id="t230"></a>
### T230 · Cellules CSV neutralisées

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F22 F23. **Règles :** [R96](../03-fonctionnel/regles-etats.md#r96). **Niveau :** Sécurité export + tableurs cibles.

**Étant donné :** Noms fictifs commençant par =,+,-,@ et caractères de contrôle.

**Quand :** Exporter et ouvrir avec les tableurs cibles en environnement de test isolé.

**Alors :** Aucune formule active ; échappement des séparateurs/guillemets et neutralisation documentés ; valeur originale conservée en base.


<a id="t231"></a>
### T231 · Droit retiré après export READY

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F22 F23. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R95](../03-fonctionnel/regles-etats.md#r95), [R96](../03-fonctionnel/regles-etats.md#r96). **Niveau :** Intégration API + parcours.

**Étant donné :** Job READY puis retrait de grant, ou expiration24h.

**Quand :** Tenter téléchargement direct et ancienne URL.

**Alors :** Refus même si fichier existe ; pas URLpublique/bucket ouvert ; purge à échéance, job traçable sans contenu excessif.


<a id="t232"></a>
### T232 · Session web sans persistance sensible et CSRF

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F21 F22. **Règles :** [R95](../03-fonctionnel/regles-etats.md#r95), [R96](../03-fonctionnel/regles-etats.md#r96), [R100](../03-fonctionnel/regles-etats.md#r100). **Niveau :** Sécurité navigateur + API.

**Étant donné :** Session BFF authentifiée et dossier ouvert ; origine étrangère prête une mutation.

**Quand :** Inspecter storage/cache puis envoyer requête sans CSRF, déconnecter et utiliser retour navigateur.

**Alors :** Pas token/dossier en localStorage/workercache ; mutation étrangère refusée ; retour ne réexpose pas le dossier ; avertissement sur fichiers téléchargés.



<a id="non-régression-de-la-revue-corrective-v31"></a>
## Recettes d’activation, publication et gestion
Ces 28 scénarios supplémentaires sont des **spécifications NOT_EXECUTED**, distinctes des validations JSON Schema effectivement lancées dans le vérificateur documentaire. Les tests antérieurs gardent leurs identifiants.

<a id="t233"></a>
### T233 · Activation initiale non circulaire

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F20. **Règles :** [R74](../03-fonctionnel/regles-etats.md#r74), [R75](../03-fonctionnel/regles-etats.md#r75). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** École DRAFT, configuration minimale complète ; CAN_USE_WORKSPACE est encore faux.

**Quand :** Activer avec la version attendue.

**Alors :** activationReady est vrai avant la transition ; ACTIVE et CAN_USE_WORKSPACE vrai après commit. Aucun contournement du contrôle ADMIN.


<a id="t234"></a>
### T234 · Préparation globale distincte de l’autorisation de leçon

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F20 F15. **Règles :** [R74](../03-fonctionnel/regles-etats.md#r74), [R81](../03-fonctionnel/regles-etats.md#r81), [R83](../03-fonctionnel/regles-etats.md#r83). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** École prête pour le GPS mais élève refusant la capture ou appareil non qualifié.

**Quand :** Consulter la préparation globale puis tenter une autorisation de capture contextualisée.

**Alors :** La préparation de l’école ne permet pas de contourner le refus, les droits ou le diagnostic ; démarrage sans enregistrement disponible.


<a id="t235"></a>
### T235 · Activation et changement simultané de configuration

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F20. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R35](../03-fonctionnel/regles-etats.md#r35), [R74](../03-fonctionnel/regles-etats.md#r74), [R75](../03-fonctionnel/regles-etats.md#r75). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** École DRAFT et aperçu de préparation à version N.

**Quand :** Une autre requête retire un préalable puis l’activation soumet la version N.

**Alors :** Conflit de version ; aucune activation sur une préparation périmée. Nouvelle lecture requise.


<a id="t236"></a>
### T236 · Archivage délégué avec périmètre pédagogique

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F22. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R36](../03-fonctionnel/regles-etats.md#r36), [R86](../03-fonctionnel/regles-etats.md#r86), [R88](../03-fonctionnel/regles-etats.md#r88). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Moniteur avec MANAGE_LEARNER_ARCHIVES, élèves A affecté et B non affecté, dossiers sans blocage.

**Quand :** Prévisualiser puis archiver A et B par app et web.

**Alors :** A possible selon droits courants ; B refusé. Un moniteur sans délégation est refusé même sur le web.


<a id="t237"></a>
### T237 · Remboursement à traiter malgré solde nul

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F10 F18 F22. **Règles :** [R62](../03-fonctionnel/regles-etats.md#r62), [R88](../03-fonctionnel/regles-etats.md#r88), [R89](../03-fonctionnel/regles-etats.md#r89). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Inscription annulée avec financialFollowUp REFUND_REQUIRED et solde comptable courant nul.

**Quand :** Prévisualiser et confirmer l’archivage.

**Alors :** ARCHIVE_BLOCKED, avec ARCHIVE_FINANCIAL_FOLLOW_UP_REQUIRED dans les blocages ; ni effacement du suivi ni clôture artificielle.


<a id="t238"></a>
### T238 · Capture terminale à envoyer et capture encore autorisée

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F15 F22. **Règles :** [R42](../03-fonctionnel/regles-etats.md#r42), [R88](../03-fonctionnel/regles-etats.md#r88). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Deux dossiers : A avec capture STOPPED et envoi incomplet ; B avec autorisation non terminale.

**Quand :** Prévisualiser leur archivage.

**Alors :** A reçoit un avertissement d’envoi à traiter selon conservation ; B un blocage d’autorisation active. Une collecte terminale ne devient pas active par son transfert restant.


<a id="t239"></a>
### T239 · Modification partielle du profil autorisée

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F02 F21. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R77](../03-fonctionnel/regles-etats.md#r77). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Profil complet, moniteur habilité à mettre à jour seulement le contact.

**Quand :** PATCH contenant operationId, policyVersionId et contactPhone, sans noms.

**Alors :** Téléphone modifié, noms inchangés ; les champs protégés éventuellement ajoutés entraînent le refus de la commande entière.


<a id="t240"></a>
### T240 · Versions cohérentes entre les deux commandes de profil

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F02 F21. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R78](../03-fonctionnel/regles-etats.md#r78). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Learner et AdministrativeProfile issus du même agrégat, deux clients à la même version logique.

**Quand :** Modifier le contact via AP16 puis soumettre l’ancien profil via AP176.

**Alors :** Le premier commit incrémente les versions des deux projections ; la seconde commande périmée ne remplace pas le contact.


<a id="t241"></a>
### T241 · Politique de photo réellement facultative

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F09 F20 F21. **Règles :** [R77](../03-fonctionnel/regles-etats.md#r77), [R80](../03-fonctionnel/regles-etats.md#r80), [R100](../03-fonctionnel/regles-etats.md#r100). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** École édite sa politique de champs.

**Quand :** Déclarer profilePhotoDocumentId REQUIRED/JOIN, puis OPTIONAL/OPTIONAL/PERSONALISATION.

**Alors :** Première commande invalide au contrat ; seconde recevable. L’absence de photo ne bloque ni adhésion ni parcours métier.


<a id="t242"></a>
### T242 · Approbation de formation et permis à contrôler

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F03 F05 F21. **Règles :** [R06](../03-fonctionnel/regles-etats.md#r06), [R07](../03-fonctionnel/regles-etats.md#r07), [R79](../03-fonctionnel/regles-etats.md#r79). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Demande de formation élève, moniteur affecté non ADMIN ; autre élève a une formation active et un justificatif à vérifier.

**Quand :** Le moniteur tente approuver la demande ; planifier puis démarrer la conduite pour le second élève.

**Alors :** Approbation réservée ADMIN ; planification permise avec avertissement de justificatif, conduite bloquée tant que la vérification requise manque.


<a id="t243"></a>
### T243 · Preuve d’une demande enregistrée par le personnel

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18. **Règles :** [R59](../03-fonctionnel/regles-etats.md#r59), [R67](../03-fonctionnel/regles-etats.md#r67). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Personnel habilité saisissant une demande reçue hors application.

**Quand :** Soumettre source RECORDED_REQUEST sans note, puis avec note et identité d’opérateur authentifiée.

**Alors :** Note absente refusée ; note valide n’accorde aucun droit à elle seule. Acteur et périmètre contrôlés côté service ; SELF ne reçoit pas de fausse note.


<a id="t244"></a>
### T244 · Dates d’inscription sans duplication

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18. **Règles :** [R56](../03-fonctionnel/regles-etats.md#r56), [R59](../03-fonctionnel/regles-etats.md#r59). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Série comportant quatre occurrences à accepter.

**Quand :** Transmettre deux fois le même identifiant dans acceptedOccurrenceIds.

**Alors :** Contrat refuse la duplication ; côté service, l’ensemble doit aussi correspondre exactement à toutes les occurrences requises de la révision acceptée.


<a id="t245"></a>
### T245 · Réinscription explicite après annulation

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F10 F17 F18. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R54](../03-fonctionnel/regles-etats.md#r54), [R59](../03-fonctionnel/regles-etats.md#r59), [R62](../03-fonctionnel/regles-etats.md#r62). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Relation d’inscription annulée, remboursement en attente puis réglé.

**Quand :** Tenter une réinscription avant puis après résolution, puis rejouer la commande réussie.

**Alors :** Avant résolution refus ; après accord explicite, cycle incrémenté et capacité/droits revérifiés. Même compte financier, aucun INITIAL dupliqué ni encaissement automatique ; retry idempotent.


<a id="t246"></a>
### T246 · Observation publiée indépendante du brouillon

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F08 F16. **Règles :** [R18](../03-fonctionnel/regles-etats.md#r18), [R19](../03-fonctionnel/regles-etats.md#r19), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Bilan publié avec observation et version sources identifiées.

**Quand :** Modifier ou retirer ensuite l’observation privée.

**Alors :** La révision publiée et sa copie d’observation ne changent pas ; aucune dépendance à un draftId exposée à l’élève.


<a id="t247"></a>
### T247 · Arrivée tardive de points après publication

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F16. **Règles :** [R19](../03-fonctionnel/regles-etats.md#r19), [R44](../03-fonctionnel/regles-etats.md#r44), [R47](../03-fonctionnel/regles-etats.md#r47). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Bilan publié avec geometrySnapshotId et manifeste déterminé.

**Quand :** Recevoir un nouveau chunk autorisé puis consulter ancien bilan et replay privé.

**Alors :** Privé peut intégrer les points ; ancien geometrySnapshotId inchangé. Leur partage exige une nouvelle révision explicite, sous réserve des droits et de l’effacement.


<a id="t248"></a>
### T248 · Course de versions lors de publication GPS

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F08 F16. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R18](../03-fonctionnel/regles-etats.md#r18), [R47](../03-fonctionnel/regles-etats.md#r47). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Sélection avec expectedCaptureVersion et observationVersions.

**Quand :** Modifier une observation ou capture entre prévisualisation et commit, ou fournir des versions ne couvrant pas exactement la sélection.

**Alors :** Publication refusée avec CAPTURE_REVIEW_CHANGED lorsque la sélection est périmée ; pas de snapshot partiel ni de bilan publié à l’insu du moniteur.


<a id="t249"></a>
### T249 · Projection élève sans données privées du collecteur

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F08 F16. **Règles :** [R01](../03-fonctionnel/regles-etats.md#r01), [R02](../03-fonctionnel/regles-etats.md#r02), [R47](../03-fonctionnel/regles-etats.md#r47), [R85](../03-fonctionnel/regles-etats.md#r85). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Bilan publié et brouillon non publié différents.

**Quand :** L’élève consulte replay de la révision ; tente getCapture, la liste privée des observations et AP07 (roster administratif).

**Alors :** Replay limité au snapshot publié ; pas de jeton, identité appareil, draftId ou notes non sélectionnées ; routes privées refusées. Mode présentation applique la même projection.


<a id="t250"></a>
### T250 · Expiration indépendante du démarrage local tardif

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F15. **Règles :** [R42](../03-fonctionnel/regles-etats.md#r42), [R83](../03-fonctionnel/regles-etats.md#r83). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Autorisation émise à 09:00, borne maximale proposée 12:00 ; application démarrée localement à 10:00.

**Quand :** Continuer la collecte jusqu’à la borne autorisée.

**Alors :** Aucun décalage automatique de l’expiration à 13:00 ; arrêt local à la borne, segments horodatés. Le serveur ne prétend pas connaître un état local hors réseau.


<a id="t251"></a>
### T251 · Preuves séparées pour collecte et transfert différé

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F15. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R34](../03-fonctionnel/regles-etats.md#r34), [R42](../03-fonctionnel/regles-etats.md#r42), [R44](../03-fonctionnel/regles-etats.md#r44). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Preuve de collecte expirée, preuve d’envoi encore valide et points antérieurs à la borne.

**Quand :** Envoyer avec signedUploadAuthorization puis révoquer l’accès et retenter.

**Alors :** Premier envoi contrôlé possible avant uploadDeadline ; nouvelle collecte interdite. Après révocation, jeton d’envoi seul ne suffit plus. Aucun point hors intervalle n’est accepté.


<a id="t252"></a>
### T252 · Diagnostic de capture sans abonnement push

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F15 F21. **Règles :** [R80](../03-fonctionnel/regles-etats.md#r80), [R83](../03-fonctionnel/regles-etats.md#r83), [R84](../03-fonctionnel/regles-etats.md#r84). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Installation authentifiée sur appareil candidat, permission notifications refusée.

**Quand :** Exécuter assessCaptureDevice puis demander une capture avec les autres prérequis.

**Alors :** Installation enregistrée dans le diagnostic sans jeton push ; notifications ne conditionnent pas l’autorisation GPS. Résultat de diagnostic ne remplace pas qualification terrain.


<a id="t253"></a>
### T253 · Pagination d’un long segment de replay

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F16. **Règles :** [R43](../03-fonctionnel/regles-etats.md#r43), [R45](../03-fonctionnel/regles-etats.md#r45), [R71](../03-fonctionnel/regles-etats.md#r71). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Segment logique de 12 001 points autorisés, pages limitées à 1 000 points au total.

**Quand :** Parcourir tous les curseurs de la même révision.

**Alors :** Tous les points retournés une seule fois, mêmes segmentId/segmentIndex ; indicateurs de continuation, aucune fausse rupture GPS à la limite de page ; droits/version liés au curseur.


<a id="t254"></a>
### T254 · Délégation financière indépendante des indicateurs scolaires

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F23. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R86](../03-fonctionnel/regles-etats.md#r86), [R94](../03-fonctionnel/regles-etats.md#r94). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Personnel avec VIEW_FINANCIAL_METRICS seul, puis autre compte avec VIEW_SCHOOL_METRICS seul.

**Quand :** Consulter les indicateurs à scope SCHOOL.

**Alors :** Premier reçoit seulement les mesures financières autorisées ; second pas M06/M07. Les indicateurs interdits sont omis, jamais affichés comme zéro.


<a id="t255"></a>
### T255 · Unités et types des statistiques contraints

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F23. **Règles :** [R23](../03-fonctionnel/regles-etats.md#r23), [R92](../03-fonctionnel/regles-etats.md#r92), [R93](../03-fonctionnel/regles-etats.md#r93). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Valeurs M02, M04, M06 et séries temporelles fictives.

**Quand :** Valider secondes entières, ratio borné, centimes signés entiers ; essayer unités incohérentes et identifiants de série différents.

**Alors :** Contrat refuse chaque incohérence ; pas de M09 temporel implicite. Les cinq séries possibles restent M01/M02/M03/M04/M06.


<a id="t256"></a>
### T256 · Accomplissement déclaré et état canonique

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F03 F18 F21. **Règles :** [R39](../03-fonctionnel/regles-etats.md#r39), [R61](../03-fonctionnel/regles-etats.md#r61), [R79](../03-fonctionnel/regles-etats.md#r79). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Élève déclare un cours suivi ailleurs.

**Quand :** Déposer la preuve puis la faire examiner.

**Alors :** UNKNOWN avant déclaration, EVIDENCE_PENDING après preuve non validée ; pas de PENDING_REVIEW/VERIFIED inventé pour cet agrégat ; COMPLETED exige la validation métier.


<a id="t257"></a>
### T257 · Audience sans rattachement géographique inventé

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18 F19. **Règles :** [R55](../03-fonctionnel/regles-etats.md#r55), [R58](../03-fonctionnel/regles-etats.md#r58), [R65](../03-fonctionnel/regles-etats.md#r65). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** École publie une offre et choisit un ciblage de catégorie.

**Quand :** Tenter un filtre d’audience site/langue, puis un filtre sur Training actif validé.

**Alors :** Pilotage par catégorie accepté ; sites/langues d’audience non vides refusés au pilote. Adresse/GPS/langue UI ne servent jamais de rattachement caché ; aucune inscription automatique.


<a id="t258"></a>
### T258 · Occupation historique de ressource préservée

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F07. **Règles :** [R08](../03-fonctionnel/regles-etats.md#r08), [R10](../03-fonctionnel/regles-etats.md#r10), [R15](../03-fonctionnel/regles-etats.md#r15). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Leçon réalisée et occupation historique correspondante.

**Quand :** Importer ou modifier une autre réservation sur le même intervalle historique.

**Alors :** L’occupation active au sens métier ne disparaît pas parce que la date est passée ; le conflit reste détectable. Correction explicite obligatoire.


<a id="t259"></a>
### T259 · Projection de configuration école complète

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F13 F20. **Règles :** [R35](../03-fonctionnel/regles-etats.md#r35), [R72](../03-fonctionnel/regles-etats.md#r72), [R75](../03-fonctionnel/regles-etats.md#r75). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** École dont les modules ont changé avec nouvelle configurationVersion.

**Quand :** Lire School depuis app et web puis soumettre une configuration périmée.

**Alors :** Les quatre flags modules et configurationVersion sont retournés ; refus de l’ancienne version. Les données historiques ne sont pas réécrites.


<a id="t260"></a>
### T260 · Types d’export sans alias ambigu

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F14 F22 F23. **Règles :** [R30](../03-fonctionnel/regles-etats.md#r30), [R96](../03-fonctionnel/regles-etats.md#r96). **Niveau :** Contrat + intégration métier selon scénario.

**Étant donné :** Demandes de gestion et demande d’accès aux données personnelles distinctes.

**Quand :** Utiliser STUDENT_LIST, METRICS et PRIVACY selon routes/droits, puis un ancien alias MANAGEMENT_LIST.

**Alors :** Alias non contractuel refusé ; projections et accès restent distincts. Aucun export de gestion n’hérite du contenu exhaustif de PRIVACY.


<a id="non-régression-additionnelle-v32"></a>
## Recettes des contrats et transactions
Les scénarios suivants sont spécifiés, **NOT_EXECUTED**. Les validations JSON exécutées séparément ne remplacent aucune de ces recettes.

<a id="t261"></a>
### T261 · Pagination ordinaire, limite et suite

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F17 F18. **Règles :** [R33](../03-fonctionnel/regles-etats.md#r33), [R71](../03-fonctionnel/regles-etats.md#r71). **Première tranche :** G3.

**Étant donné :** Une liste contient plus de 100 éléments.

**Quand :** Lire sans limite, à 100 puis à 101, et poursuivre le curseur.

**Alors :** 50 par défaut ; 100 maximum ; valeur 101 refusée ; pas de troncature ni mélange avec la capacité totale d’un cours.


<a id="t262"></a>
### T262 · Enveloppes homogènes des listes ajoutées

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F17 F18. **Règles :** [R33](../03-fonctionnel/regles-etats.md#r33). **Première tranche :** G2→G3 selon domaine.

**Étant donné :** Clients natif et web consomment les 15 routes de listes concernées.

**Quand :** Lire catalogue, droits, cours, présences et observations.

**Alors :** Toujours data/requestId/serverTime ; pages vides et suivantes lisibles par le même mécanisme.


<a id="t263"></a>
### T263 · Commande en cours et réponse perdue

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F12 F18. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R27](../03-fonctionnel/regles-etats.md#r27). **Première tranche :** G3.

**Étant donné :** Une inscription est en cours et sa réponse initiale est perdue.

**Quand :** Recevoir 202, consulter AP72 puis rejouer même corps/clé.

**Alors :** Pas de badge Inscrit avant résultat confirmé ; un seul HOLD et une seule place ; 404 intermédiaire ne génère pas une nouvelle clé.


<a id="t264"></a>
### T264 · Job accepté distinct d’une commande en cours

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F14 F22. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12), [R30](../03-fonctionnel/regles-etats.md#r30). **Première tranche :** G4.

**Étant donné :** Une demande d’export peut rester en cours ou retourner un Job créé.

**Quand :** Consommer chacune des branches 202.

**Alors :** PENDING ne donne pas de fichier ; Job créé n’est pas READY ; aucun téléchargement annoncé avant autorisation et fin réelle.


<a id="t265"></a>
### T265 · Première présence concurrente

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18. **Règles :** [R11](../03-fonctionnel/regles-etats.md#r11), [R63](../03-fonctionnel/regles-etats.md#r63). **Première tranche :** G3.

**Étant donné :** Aucun relevé n’existe pour l’occurrence et le cycle courant.

**Quand :** Deux opérateurs font le PUT conditionnel If-None-Match puis une correction If-Match.

**Alors :** Une seule création version 1 ; l’autre précondition échoue ; pas de version 0 fictive ni de double consommation.


<a id="t266"></a>
### T266 · Ancienne présence après réinscription

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18. **Règles :** [R59](../03-fonctionnel/regles-etats.md#r59), [R63](../03-fonctionnel/regles-etats.md#r63). **Première tranche :** G3.

**Étant donné :** Inscription réactivée au cycle 2 après résolution des obligations du cycle 1.

**Quand :** Envoyer une présence préparée sur URI du cycle 1.

**Alors :** ENROLLMENT_CYCLE_CHANGED ; aucun fait ni HOLD du cycle 2 modifié ; historique cycle 1 intact.


<a id="t267"></a>
### T267 · Présence définitive et date réelle du bloc

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18. **Règles :** [R54](../03-fonctionnel/regles-etats.md#r54), [R63](../03-fonctionnel/regles-etats.md#r63). **Première tranche :** G3.

**Étant donné :** Une occurrence n’est pas terminée.

**Quand :** Valider PRESENT/ABSENT, puis EXCUSED documenté ; réessayer PRESENT après fin.

**Alors :** Pas de présence/absence définitive avant fin au pilote ; EXCUSED ne consomme pas et ne valide rien ; fait réel après fin reste vérifié humainement.


<a id="t268"></a>
### T268 · Déplacement collectif et échéances atomiques

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18 F19. **Règles :** [R62](../03-fonctionnel/regles-etats.md#r62). **Première tranche :** G3.

**Étant donné :** Une série publiée est avancée ou reportée.

**Quand :** Soumettre des échéances incohérentes, puis une proposition complète cohérente.

**Alors :** Sur erreur, aucune date, place ou notification changée ; sur succès, échéances et dates cohérentes, inscrits à reconfirmer sans perte silencieuse de conditions.


<a id="t269"></a>
### T269 · Modèle de cours mutable, série figée

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18 F19. **Règles :** [R51](../03-fonctionnel/regles-etats.md#r51), [R58](../03-fonctionnel/regles-etats.md#r58). **Première tranche :** G3.

**Étant donné :** Une série publiée reprend un modèle de sensibilisation.

**Quand :** Modifier requirementType, produit ou profil du modèle pour des créations futures.

**Alors :** La série existante conserve son snapshot ; annonces/validation ne ciblent pas une autre exigence.


<a id="t270"></a>
### T270 · Nouveau tarif de cours sans refaire les achats

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F17 F18. **Règles :** [R23](../03-fonctionnel/regles-etats.md#r23), [R59](../03-fonctionnel/regles-etats.md#r59), [R62](../03-fonctionnel/regles-etats.md#r62). **Première tranche :** G3.

**Étant donné :** Deux élèves inscrits au prix et aux conditions de leur cycle.

**Quand :** AP192 COMMERCIAL puis nouvelle inscription ; AP192 EDITORIAL séparément.

**Alors :** Nouveau prix pour nouvel inscrit ; anciens comptes/snapshots intacts. Titre corrigé sans nouvelle campagne et sans invalidation du prix accepté.


<a id="t271"></a>
### T271 · Reconfirmation de dates sans acceptation de nouveau prix

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F18. **Règles :** [R59](../03-fonctionnel/regles-etats.md#r59), [R62](../03-fonctionnel/regles-etats.md#r62). **Première tranche :** G3.

**Étant donné :** Tarif futur a augmenté, puis dates déplacées.

**Quand :** Un ancien inscrit reconfirme les dates.

**Alors :** acceptedOfferRevision actualisée mais acceptedCommercialSnapshot inchangé ; comparaison d’échéances explicite, pas de retenue nouvelle silencieuse.


<a id="t272"></a>
### T272 · Durée modifiée sans révision commerciale

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F17. **Règles :** [R13](../03-fonctionnel/regles-etats.md#r13), [R51](../03-fonctionnel/regles-etats.md#r51). **Première tranche :** G2 puis financement G3.

**Étant donné :** Leçon PLANNED 45 minutes couverte par une unité.

**Quand :** Passer à 90 minutes sans commercialChange.

**Alors :** LESSON_COMMERCIAL_CHANGE_REQUIRED, ancien créneau, version, compte et HOLD conservés.


<a id="t273"></a>
### T273 · Durée, créneau et droits changés ensemble

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F17. **Règles :** [R13](../03-fonctionnel/regles-etats.md#r13), [R53](../03-fonctionnel/regles-etats.md#r53). **Première tranche :** G3.

**Étant donné :** Passage explicite à une double leçon selon produit ; un seul droit disponible.

**Quand :** Soumettre commercialChange pour deux unités, puis recommencer après régularisation.

**Alors :** Échec initial sans déplacement ni RELEASE résiduel ; succès atomique avec révision historique et quantité contractuelle correcte, indépendante du GPS.


<a id="t274"></a>
### T274 · Baisse de prix et argent déjà reçu

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F10. **Règles :** [R13](../03-fonctionnel/regles-etats.md#r13), [R24](../03-fonctionnel/regles-etats.md#r24). **Première tranche :** G3.

**Étant donné :** Un compte de séance planifiée contient un encaissement réel.

**Quand :** Réviser le prix en dessous du net reçu.

**Alors :** Refus atomique, aucune fausse sortie d’argent. Traiter le remboursement réel par son circuit avant une nouvelle révision admissible.


<a id="t275"></a>
### T275 · Reversal d’un prépaiement déjà activé

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F10 F17. **Règles :** [R24](../03-fonctionnel/regles-etats.md#r24), [R53](../03-fonctionnel/regles-etats.md#r53). **Première tranche :** G3.

**Étant donné :** Achat AFTER_FULL_PAYMENT, droits actifs.

**Quand :** Contrepasser un reçu erroné ou enregistrer un remboursement rendant le paiement insuffisant.

**Alors :** SUSPENDED_PAYMENT et usableQuantity=0 au même commit, registre conservé ; nouvelles réservations refusées.


<a id="t276"></a>
### T276 · Dernier droit contre correction de paiement concurrente

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F10 F17. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R53](../03-fonctionnel/regles-etats.md#r53), [R54](../03-fonctionnel/regles-etats.md#r54). **Première tranche :** G3.

**Étant donné :** Réservation et remboursement/reversal d’achat se disputent les mêmes droits.

**Quand :** Exécuter les deux ordres de commit avec deux connexions.

**Alors :** Soit réservation acquise avant correction et conservée à traiter, soit droits suspendus avant réservation et refus ; jamais confirmation sur un paiement déjà invalidé.


<a id="t277"></a>
### T277 · Suspension de pack et engagements existants

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F17 F18. **Règles :** [R53](../03-fonctionnel/regles-etats.md#r53), [R54](../03-fonctionnel/regles-etats.md#r54). **Première tranche :** G3.

**Étant donné :** Une leçon et un cours ont des HOLD avant suspension.

**Quand :** Déplacer sans augmentation, réaliser la prestation, puis tenter une augmentation nette.

**Alors :** Engagements non supprimés silencieusement ; consommation de HOLD honoré permise et suivie ; droits supplémentaires refusés tant que financement insuffisant.


<a id="t278"></a>
### T278 · Invalidation des domaines ajoutés

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F18 F19. **Règles :** [R27](../03-fonctionnel/regles-etats.md#r27), [R64](../03-fonctionnel/regles-etats.md#r64). **Première tranche :** G2→G3 selon domaine.

**Étant donné :** Client natif possède anciens cours, exigences, droits et choix GPS.

**Quand :** Lire SyncChange après mutations autorisées.

**Alors :** Types reconnus, API spécialisées relues, aucun point brut dans le flux ; un refus connu arrête la capture selon les règles existantes.


<a id="t279"></a>
### T279 · Reconstruction de snapshot et caches enrichis

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F12 F15. **Règles :** [R27](../03-fonctionnel/regles-etats.md#r27), [R37](../03-fonctionnel/regles-etats.md#r37), [R48](../03-fonctionnel/regles-etats.md#r48). **Première tranche :** G2.

**Étant donné :** Curseur expiré ou accessEpoch changé avec ancien cache de replay/offres.

**Quand :** Construire un nouveau snapshot.

**Alors :** Bascule atomique des données de base, anciens caches enrichis invalidés, pas de réexposition de trajet retiré ; brouillons autorisés préservés séparément.


<a id="t280"></a>
### T280 · Effacement géographique visible jusque dans le JSON

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F14 F16. **Règles :** [R19](../03-fonctionnel/regles-etats.md#r19), [R48](../03-fonctionnel/regles-etats.md#r48). **Première tranche :** G2 puis exploitation G4.

**Étant donné :** Bilan publié contient un trajet et ses dérivés.

**Quand :** Effacer la capture puis lire bilan/replay/URLs et réouvrir caches autorisés.

**Alors :** Aucun segment, observation GPS, geometrySnapshotId ou curseur utilisable dans tombstone ; dérivés purgés ; seul texte autonome justifié conservé.


<a id="t281"></a>
### T281 · Retrait du partage sans accès privé de secours

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F16. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48). **Première tranche :** G2.

**Étant donné :** Élève lisait un replay publié ensuite retiré.

**Quand :** Lire tombstone puis appeler la vue PRIVATE et ancien curseur.

**Alors :** Aucune route de secours ne livre les données privées ; 404 hors scope et invalidation des pages déjà reçues dès connaissance du retrait.


<a id="t282"></a>
### T282 · Ensembles d’options et de manifeste

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F15 F17. **Règles :** [R33](../03-fonctionnel/regles-etats.md#r33), [R43](../03-fonctionnel/regles-etats.md#r43), [R53](../03-fonctionnel/regles-etats.md#r53). **Première tranche :** G2→G3 selon domaine.

**Étant donné :** Une option peut créer un droit ; un manifeste référence des chunks.

**Quand :** Envoyer deux fois la même option ou le même index ; puis des identifiants uniques mais étrangers.

**Alors :** Doublons refusés par forme ; références étrangères refusées au service ; pas de GRANT doublé ni de trajet artificiellement complet.


<a id="t283"></a>
### T283 · Droit révoqué pendant attente de transaction

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F01 F05 F10. **Règles :** [R02](../03-fonctionnel/regles-etats.md#r02), [R12](../03-fonctionnel/regles-etats.md#r12). **Première tranche :** G1→G3 selon commande.

**Étant donné :** Une commande attend un verrou tandis que son grant est révoqué.

**Quand :** Forcer les deux ordres de verrous/commit.

**Alors :** Si révocation commitée d’abord, pas d’effet sous ancien grant ; sinon la commande précède la révocation. Pas de deadlock non borné ; ordre déterministe.


<a id="t284"></a>
### T284 · Crash après réservation d’intention

**Statut :** NOT_EXECUTED, spécification. **Fonctions :** F05 F12. **Règles :** [R12](../03-fonctionnel/regles-etats.md#r12). **Première tranche :** G2.

**Étant donné :** Marqueur d’opération en cours, interruption avant ou après commit des effets.

**Quand :** Exécuter la reprise du worker puis rejouer même clé.

**Alors :** Recherche de preuve durable et exclusion de commit concurrent ; un seul effet, pas de blocage éternel, pas de nouvelle clé automatique.


<a id="recettes-dintégration-mobile-v34"></a>
## Recettes d’intégration mobile
Les T001–T350 ci-dessus restent inchangés et **NOT_EXECUTED**. Le [catalogue mobile courant](qualification-mobile-ui-ux.md#mob001) ajoute les essais spécifiques UI/UX, iOS/iPadOS 26/27, Android, cycle natif et distribution, également non exécutés. Leur [registre JSON](../annexes/qualification-mobile-v3-10.json) associe MX, F, E et plateforme. Ils ne sont pas mélangés aux indicateurs M01–M09.

Les contrôles de ce dossier ne valident pas ces scénarios : le lecteur HTML est un document, pas l’application. Le choix et l’état des plateformes testées doivent figurer dans la matrice de builds effective.


<a id="t285"></a>
## T285 · Première présence sans version fictive

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G3. **Fonctions :** F18. **Règles :** R11.

**Étant donné :** Aucune AttendanceRecord pour le cycle courant.

**Quand :** Créer avec If-None-Match: *, puis tenter If-Match: "0".

**Alors :** La première forme crée version 1 ; la seconde est refusée sans effet ; une correction exige l’ETag réel.



<a id="t286"></a>
## T286 · Permis approuvé sans preuve

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G1. **Fonctions :** F03. **Règles :** R07.

**Étant donné :** Document absent et physicalSeen=false.

**Quand :** Soumettre APPROVED.

**Alors :** Rejet de forme et aucun PermitCheck approuvé ; avec UUID seul le service vérifie encore READY, scope et examen autorisé.



<a id="t287"></a>
## T287 · Rejet de permis sans motif

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G1. **Fonctions :** F03. **Règles :** R07.

**Étant donné :** Contrôleur habilité, pièce connue.

**Quand :** Envoyer REJECTED avec null, vide ou espaces comme motif.

**Alors :** Rejet de forme ; motif utile accepté sous droits, contrôleur/date imposés serveur.



<a id="t288"></a>
## T288 · Refus SELF protégé

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G2. **Fonctions :** F15 F21. **Règles :** R101.

**Étant donné :** Refus de l’élève applicable à la leçon.

**Quand :** Le personnel ajoute un accord verbal plus récent.

**Alors :** 409 RECORDING_CHOICE_PROTECTED ; refus effectif conservé et aucun bail créé.



<a id="t289"></a>
## T289 · Révision explicite personnelle

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G2. **Fonctions :** F15 F21. **Règles :** R101.

**Étant donné :** Refus SELF existant ; ancien bail révoqué.

**Quand :** L’élève autorise explicitement cette séance puis le moniteur choisit Démarrer.

**Alors :** Nouvelle preuve de choix et autorisation requise ; ancien bail non réanimé. Un refus propre à une autre séance reste applicable.



<a id="t290"></a>
## T290 · Repère préparé privé et non mesuré

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G2. **Fonctions :** F06 F15 F16. **Règles :** R102.

**Étant donné :** Permission OS refusée, préparation accessible au moniteur.

**Quand :** Ajouter manuellement un repère et consulter côté élève.

**Alors :** Préparation possible sans collecte ; repère privé non révélé par replay/bilan ni enregistré comme position réelle.



<a id="t291"></a>
## T291 · Remplacement de repères concurrent

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G2. **Fonctions :** F06 F12. **Règles :** R102 R11.

**Étant donné :** Deux vues sur la même version de préparation.

**Quand :** Remplacer puis vider avec ancien ETag ; envoyer ensuite une commande qui omet la liste.

**Alors :** 412 pour version ancienne ; omission conserve liste courante ; [] valide la vide. IDs dupliqués refusés par service.



<a id="t292"></a>
## T292 · Purge des coordonnées préparées

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F06 F14. **Règles :** R102 R104.

**Étant donné :** Repères, cache et export autorisé antérieur existent.

**Quand :** Appliquer purge géographique et reconnecter un client.

**Alors :** Repères et dérivés maîtrisés retirés selon scope ; aucun retour via cache/index/replay. Limites de copies déjà exportées documentées.



<a id="t293"></a>
## T293 · Langue de cours réelle

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G3. **Fonctions :** F18 F19. **Règles :** R105.

**Étant donné :** Série en brouillon sans langue.

**Quand :** Tenter publier sans teachingLanguage ; choisir de puis publier.

**Alors :** Champ exigé ; détail et offre calendrier indiquent la langue choisie. Pas de déduction du nom de l’élève.



<a id="t294"></a>
## T294 · Filtre de langue et engagement

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G3. **Fonctions :** F18 F19. **Règles :** R105.

**Étant donné :** Une inscription confirmée à un cours de ; offres fr et de.

**Quand :** Filtrer les offres fr.

**Alors :** Offre de non inscrite filtrée ; rendez-vous de confirmé toujours visible. Curseur du filtre précédent non réutilisé.



<a id="t295"></a>
## T295 · Langue publiée immuable

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G3. **Fonctions :** F18. **Règles :** R105.

**Étant donné :** Une série publiée contient des inscrits.

**Quand :** Tenter modifier sa langue par titre/offer-revisions ou PUT draft.

**Alors :** Refus sans mutation ; nouvelle offre et annulation coordonnées si besoin, aucune réinscription automatique.



<a id="t296"></a>
## T296 · Préférences canal sans override

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G3. **Fonctions :** F11 F19. **Règles :** R65.

**Étant donné :** École active push/email ; personne refuse annonces et transactionalPush.

**Quand :** Publier un cours puis confirmer une inscription explicitement demandée.

**Alors :** Pas d’envoi externe interdit ; confirmation consultable dans l’app. courseOffersInApp=false n’efface pas calendrier.



<a id="t297"></a>
## T297 · Paramètre de couleur absent du pilote

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G1. **Fonctions :** F13 F22. **Règles :** R35 R100.

**Étant donné :** École créée avec logo et coordonnées.

**Quand :** Ouvrir paramètres et envoyer une couleur non définie dans le contrat.

**Alors :** Aucun contrôle trompeur d’accent ; commande inconnue refusée. Palette de Drivy stable ; logo reste facultatif.



<a id="t298"></a>
## T298 · Suppression sans école

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R103.

**Étant donné :** Personne authentifiée sans appartenance active.

**Quand :** Ouvrir E49, réauthentifier, obtenir aperçu et confirmer.

**Alors :** Demande durable accessible ; pas d’exigence schoolId ni redirection forcée vers invitation.



<a id="t299"></a>
## T299 · Dépôt avec dette ou dernier ADMIN

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14 F22. **Règles :** R103 R104.

**Étant donné :** Dette ou dernier administrateur vérifié.

**Quand :** Initier suppression.

**Alors :** SUBMITTED reçu ; obligations signalées et coordination bornée, pas refus blanket ni promotion du support. Aucun COMPLETED fictif avant résolution.



<a id="t300"></a>
## T300 · Suppression et changement d’aperçu

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R103.

**Étant donné :** Aperçu créé, une appartenance change ou aperçu expire.

**Quand :** Confirmer ancienne version.

**Alors :** 412 ou 410 ; relecture explicite. Aucune confirmation sous conditions nouvelles invisibles.



<a id="t301"></a>
## T301 · Double demande globale

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R103 R104.

**Étant donné :** Deux appareils authentifiés.

**Quand :** Confirmer simultanément avec même puis différentes clés.

**Alors :** Une seule demande active et un jeu de tâches ; résultat et reçu limités au propriétaire ; corps différent même clé refusé.



<a id="t302"></a>
## T302 · Suppression d’autrui interdite

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R103.

**Étant donné :** ADMIN scolaire connaît un requestId appartenant à un élève.

**Quand :** Lire ou retirer cette demande.

**Alors :** 404 sans fuite ; aucun pouvoir global déduit du rôle scolaire.



<a id="t303"></a>
## T303 · Retrait concurrent au traitement

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R104.

**Étant donné :** Demande IN_REVIEW.

**Quand :** Synchroniser AP197 et passage PROCESSING sur deux transactions.

**Alors :** Un seul ordre valide : WITHDRAWN sans tâches destructives, ou PROCESSING et retrait409. ETag périmé412 sans relecture silencieuse.



<a id="t304"></a>
## T304 · Reçu séparé de session

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R104.

**Étant donné :** Sessions révoquées au passage PROCESSING ; reçu valide.

**Quand :** Lire AP198 puis tenter /v1/me et une route scolaire avec reçu.

**Alors :** Statut réduit seul accessible ; toutes routes métier refusées. Un token OIDC ne remplace pas le reçu.



<a id="t305"></a>
## T305 · Perte ou expiration du reçu

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R104.

**Étant donné :** Reçu perdu/expiré, compte en traitement.

**Quand :** Ouvrir suivi et demander récupération.

**Alors :** Aucune fuite par email non vérifié ni requestId seul ; voie assistée vérifiée et délai de suivi communiqué.



<a id="t306"></a>
## T306 · Prestataire en panne

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R104.

**Étant donné :** Tâche de suppression externe échoue.

**Quand :** Rejouer le worker et consulter statut.

**Alors :** PROCESSING, reprise idempotente et prochain suivi ; pas COMPLETED sur acceptation d’un job.



<a id="t307"></a>
## T307 · Suppression pendant capture hors réseau

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14 F15 F12. **Règles :** R104 R42.

**Étant donné :** Capture autorisée sur appareil hors ligne.

**Quand :** Passer compte PROCESSING ailleurs puis reconnecter.

**Alors :** Borne locale appliquée ; à connaissance révocation arrêt/purge et envois interdits ; reçu inutilisable pour uploader. Pas d’effacement instantané prétendu hors ligne.



<a id="t308"></a>
## T308 · Rétention et fin de compte distinctes

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R104.

**Étant donné :** Dossier conservé selon décision validée et autres données éligibles à effacement.

**Quand :** Traiter puis restituer manifeste et résultat.

**Alors :** Rétentions expliquées, accès minimisés ; compte non réactivé pour dette, documents non annoncés effacés à tort.



<a id="t309"></a>
## T309 · Restauration sans résurrection

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G5. **Fonctions :** F01 F14. **Règles :** R104.

**Étant donné :** Compte COMPLETED et sauvegarde antérieure.

**Quand :** Restaurer et tenter ancien refresh token, lien et nouveau login.

**Alors :** Tombstones rejoués avant service ; aucune réactivation de session/dossier. Une nouvelle inscription est une relation distincte.



<a id="t310"></a>
## T310 · Formulaire global sans faux succès

**Statut :** NOT_EXECUTED. **Introduit :** V3.5. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R103 R104.

**Étant donné :** App native/web avec lecteur d’écran et connexion interrompue.

**Quand :** Confirmer, quitter écran, reprendre la même intention, puis recevoir201/202.

**Alors :** État de demande reçue/en cours exact ; pas de compte annoncé supprimé ; receiptToken jamais dans URL/log ou notifications.


<a id="t311"></a>
## T311 · Texte pédagogique sans capture

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G2. **Fonctions :** F08 F16. **Règles :** R46 R47.

**Étant donné :** Un bilan avec annotation textuelle privée sans ancrage et aucune capture.

**Quand :** Publier captureSelection=null et la référence/version de cette annotation.

**Alors :** Le texte est copié dans textObservations ; aucun GeometrySnapshot, permission GPS ni carte factice.


<a id="t312"></a>
## T312 · Annotation modifiée après revue

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G2. **Fonctions :** F08 F16. **Règles :** R11 R46 R47.

**Étant donné :** Le moniteur a sélectionné une version puis une autre session modifie le texte.

**Quand :** Publier avec l’ancienne version.

**Alors :** Conflit, aucun bilan ni annotation partiellement publié ; nouvelle revue requise.


<a id="t313"></a>
## T313 · Ancrage interdit dans la sélection textuelle

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G2. **Fonctions :** F08 F16. **Règles :** R46 R48.

**Étant donné :** Une observation appartient à une capture privée.

**Quand :** Envoyer son ID dans textObservationSelection plutôt que captureSelection.

**Alors :** Refus de service ; le retrait d’ancrage n’est pas une publication automatique du commentaire.


<a id="t314"></a>
## T314 · Même annotation avec deux versions

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G2. **Fonctions :** F08. **Règles :** R46 R47.

**Étant donné :** Une liste contient deux références au même ID avec versions différentes.

**Quand :** Soumettre la sélection.

**Alors :** Refus par clé métier malgré objets JSON différents ; aucun doublon copié.


<a id="t315"></a>
## T315 · Retrait GPS et texte autonome

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G4. **Fonctions :** F08 F14 F16. **Règles :** R46 R48.

**Étant donné :** Une révision contient un snapshot GPS et une note textuelle autonome.

**Quand :** Retirer le partage GPS puis traiter une demande visant aussi le texte.

**Alors :** La vue GPS est expurgée ; la note ne disparaît pas par effet indirect mais suit séparément la décision applicable aux données du bilan.


<a id="t316"></a>
## T316 · Arrêt avant premier point

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G2. **Fonctions :** F15. **Règles :** R43 R44.

**Étant donné :** La capture autorisée est lancée mais aucun point n’est acquis.

**Quand :** Arrêter localement puis transférer le manifeste vide.

**Alors :** Aucun point zéro ; écran « Aucun point enregistré » ; dernier index null pour segment vide, segments=[] si aucun ouvert.


<a id="t317"></a>
## T317 · Pause vide puis segment mesuré

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G2. **Fonctions :** F15 F16. **Règles :** R43 R45.

**Étant donné :** Premier segment sans point, puis reprise avec une mesure.

**Quand :** Sceller puis relire les segments.

**Alors :** Le segment vide n’invente pas de géométrie et ne supprime pas le segment mesuré ; indices et dernière séquence réels conservés.


<a id="t318"></a>
## T318 · Manifeste non vide sans chunk

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G2. **Fonctions :** F15. **Règles :** R43 R44.

**Étant donné :** expectedPointCount positif mais indices de chunks vides.

**Quand :** Envoyer puis tenter finalisation.

**Alors :** Rejet de forme ; aucune mention de transfert complet de mesures absentes.


<a id="t319"></a>
## T319 · Cours terminé et élève absent partout

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17 F18 F22. **Règles :** R54 R63 R106.

**Étant donné :** Toutes occurrences terminées, relevés ABSENT, HOLD entier encore ouvert.

**Quand :** Revoir puis clôturer avec décision RELEASE et versions.

**Alors :** Libération exacte du HOLD et CLOSED au même commit ; absences conservées et aucun frais/remboursement automatique.


<a id="t320"></a>
## T320 · Présence concurrente à la clôture

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R11 R63 R106.

**Étant donné :** Une revue de clôture suppose absence totale ; un autre formateur saisit PRESENT.

**Quand :** Confirmer l’ancienne liste de libération.

**Alors :** COURSE_SETTLEMENT_CHANGED ; aucun crédit libéré ni clôture partielle.


<a id="t321"></a>
## T321 · Droits de clôture insuffisants

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R02 R106.

**Étant donné :** Un moniteur possède MANAGE_COURSES sans SELL_SERVICES.

**Quand :** Clôturer une série nécessitant une libération.

**Alors :** Refus explicite de cette opération ; ne pas contourner par TAKE_ATTENDANCE ou un autre support.


<a id="t322"></a>
## T322 · Clôture sans solder un remboursement

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17 F18 F22. **Règles :** R88 R106.

**Étant donné :** Les droits inutilisés sont libérables mais financialFollowUp reste REFUND_REQUIRED.

**Quand :** Clôturer puis demander un archivage.

**Alors :** La clôture n’efface pas le suivi financier ; l’archivage reste bloqué avec motif.


<a id="t323"></a>
## T323 · Présence corrigée après crédit réutilisé

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R63 R106.

**Étant donné :** Un HOLD a été libéré à clôture et le crédit utilisé ailleurs.

**Quand :** Corriger tardivement l’absence en PRESENT.

**Alors :** Présence exacte enregistrée et suivi de droit REVIEW_REQUIRED ; aucune unité reprise ni exigence validée en secret. Révision V3.7 : l’ancien résultat de refus est conservé uniquement dans l’archive V3.6, pas dans cette recette active.


<a id="t324"></a>
## T324 · Remise d’un accès externe

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17. **Règles :** R53 R107.

**Étant donné :** Lot EXTERNAL_SERVICE utilisable ; accès réellement remis.

**Quand :** Consigner une unité et la date avec même opération en cas de délai.

**Alors :** Un CONSUME direct visible au journal, aucune leçon, présence ou activation fournisseur prétendue.


<a id="t325"></a>
## T325 · Accompagnement examen non assimilé à une leçon

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17 F23. **Règles :** R92 R107.

**Étant donné :** Un droit EXAM_SUPPORT a été honoré hors d’une leçon pédagogique.

**Quand :** Consigner sa remise puis lire M01/M06/M09.

**Alors :** Pas de leçon ni bilan obligatoire créé ; encaissements inchangés ; aucun résultat officiel d’examen déduit.


<a id="t326"></a>
## T326 · Dernier droit remis deux fois simultanément

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17. **Règles :** R12 R53 R107.

**Étant donné :** Une seule unité utilisable et deux opérateurs.

**Quand :** Envoyer deux nouvelles intentions concurrentes.

**Alors :** Une seule consommation acceptée, seconde insuffisance ; le reliquat ne devient jamais négatif.


<a id="t327"></a>
## T327 · Réponse perdue après remise

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17. **Règles :** R12 R107.

**Étant donné :** AP199 commite puis sa réponse est perdue.

**Quand :** Rejouer même clé et même corps.

**Alors :** Même mouvement et version confirmée, aucun second débit.


<a id="t328"></a>
## T328 · Corriger une remise consignée par erreur

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17. **Règles :** R54 R107.

**Étant donné :** Un CONSUME direct existe et n’est pas restauré.

**Quand :** AP114 avec source et motif puis rejeu et seconde intention.

**Alors :** RESTORE append-only dans le plafond et l’unicité existants ; pas de suppression ni double restauration.


<a id="t329"></a>
## T329 · Base de pack avec option

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F10 F17 F20. **Règles :** R52 R108.

**Étant donné :** Base fictive 100000, option de 12000, montant négocié absent.

**Quand :** Acheter avec cette option puis sans dans une autre vente.

**Alors :** Totaux 112000 et 100000 ; un seul INITIAL par achat, droits correspondants seulement.


<a id="t330"></a>
## T330 · Option comportant plusieurs composants

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17. **Règles :** R108.

**Étant donné :** Deux composants partagent une optionKey, un supplément unique.

**Quand :** Acheter l’option puis répéter sa clé dans la requête.

**Alors :** Supplément compté une fois ; liste répétée rejetée, pas de droits dupliqués.


<a id="t331"></a>
## T331 · Prix exceptionnel sans délégation implicite

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F10 F17. **Règles :** R02 R108.

**Étant donné :** Un vendeur possède SELL_SERVICES mais pas ADMIN.

**Quand :** Envoyer priceOverride avec motif.

**Alors :** Refus ; ADMIN peut confirmer un prix réellement convenu sans modifier les quantités.


<a id="t332"></a>
## T332 · Nouvelle grille entre revue et achat

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17. **Règles :** R11 R52 R108.

**Étant donné :** L’élève a accepté une offre versionnée ; les conditions sélectionnées deviennent incohérentes.

**Quand :** Confirmer sous l’ancienne revue.

**Alors :** OFFER_CHANGED ou conflit documenté ; aucun prix actualisé silencieusement.


<a id="t333"></a>
## T333 · Frais inclus et inscription offerte

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F10 F17. **Règles :** R108.

**Étant donné :** Lignes de base dont frais inclus et ligne à zéro.

**Quand :** Valider l’offre puis acheter.

**Alors :** Somme exacte égale à la base ; pas de lot pédagogique pour la ligne de frais, aucun second débit au compte.


<a id="t334"></a>
## T334 · Suppression avec plus d’une page d’écoles

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R103 R104.

**Étant donné :** 101 appartenances autorisées dans le manifeste.

**Quand :** Créer aperçu, lire une page puis confirmer globalement.

**Alors :** Total 101 explicite, continuation privée disponible, confirmation de toutes les appartenances sans appel/email requis.


<a id="t335"></a>
## T335 · Curseur de suppression d’une autre personne

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R01 R103.

**Étant donné :** Une personne connaît un curseur d’aperçu étranger.

**Quand :** Appeler AP200 avec sa propre session.

**Alors :** Aucune ligne, nom ou quantité du manifeste étranger divulgué.


<a id="t336"></a>
## T336 · Appartenance ajoutée après aperçu

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R11 R103.

**Étant donné :** Aperçu complet puis nouvelle appartenance acceptée.

**Quand :** Confirmer ancien aperçu.

**Alors :** Refus de version/périmètre, nouvelle revue globale ; aucune école oubliée.


<a id="t337"></a>
## T337 · Dernier administrateur avant PROCESSING

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R04 R104.

**Étant donné :** École ACTIVE dont le demandeur est seul ADMIN actif.

**Quand :** Déposer puis traiter la demande.

**Alors :** Dépôt accepté ; IN_REVIEW avec suivi jusqu’à relève acceptée ou fermeture coordonnée ; jamais ACTIVE sans ADMIN après révocation.


<a id="t338"></a>
## T338 · Relève révoquée concurremment

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R04 R104.

**Étant donné :** Un successeur est actif au moment de la revue de continuité.

**Quand :** Révoquer ce rôle pendant le passage PROCESSING.

**Alors :** Ordre/verrous sérialisent les deux effets ; aucune école ACTIVE sans administrateur actif.


<a id="t339"></a>
## T339 · Commande gagnant avant clôture globale

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G4. **Fonctions :** F01 F05 F14. **Règles :** R02 R104.

**Étant donné :** Une réservation détient la porte d’accès avant la clôture.

**Quand :** Commiter réservation puis PROCESSING.

**Alors :** Engagement connu du traitement global ; aucune réponse de succès perdue dans l’inventaire.


<a id="t340"></a>
## T340 · Clôture globale gagnant avant commande

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G4. **Fonctions :** F01 F05 F14. **Règles :** R02 R104.

**Étant donné :** PROCESSING prend la porte exclusive avant une nouvelle réservation.

**Quand :** La réservation attend puis reprend.

**Alors :** Relecture CLOSING et refus sous droits actuels ; aucun engagement supplémentaire.


<a id="t341"></a>
## T341 · Premières préférences sur deux appareils

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G1. **Fonctions :** F11 F21. **Règles :** R11 R70 R78.

**Étant donné :** Nouvelle appartenance créée sans préférences antérieures.

**Quand :** Lire depuis web et app puis modifier simultanément.

**Alors :** Même objet version 1, canaux externes false ; If-Match arbitre ; GET ne crée pas d’acceptation.


<a id="t342"></a>
## T342 · Aucun choix GPS enregistré

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G1. **Fonctions :** F15 F21. **Règles :** R41 R101.

**Étant donné :** Dossier accessible sans événement de choix.

**Quand :** Lire AP152 et ouvrir la fiche sans enregistrer.

**Alors :** 404 RECORDING_CHOICE_NOT_SET, texte compréhensible ; pas d’acteur SELF inventé ni de permission requise pour lire.


<a id="t343"></a>
## T343 · Préférences historiques préservées

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G5. **Fonctions :** F11 F21. **Règles :** R70 R78.

**Étant donné :** Un ancien utilisateur a des choix explicites de canaux.

**Quand :** Migrer la structure et revenir dans l’onboarding.

**Alors :** Les choix existants ne sont pas écrasés par les défauts des nouveaux comptes ; absence historique signalée et initialisée explicitement.


<a id="t344"></a>
## T344 · Notifications refusées, calendrier utile

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F11 F19. **Règles :** R64 R70.

**Étant donné :** Tous canaux externes désactivés.

**Quand :** Publier une sensibilisation et ouvrir le calendrier élève.

**Alors :** L’offre reste consultable et inscription explicite disponible ; aucune réception de push promise.


<a id="t345"></a>
## T345 · Références actives et historiques

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G1. **Fonctions :** F01. **Règles :** R98.

**Étant donné :** Recherche documentaire renvoie plusieurs versions.

**Quand :** Ouvrir index puis historique via le lecteur.

**Alors :** Version active et statut historique identifiables ; aucune instruction de runtime partagé réintroduite dans le client Swift.


<a id="t346"></a>
## T346 · Décodage Swift du segment vide

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G2. **Fonctions :** F15 F16. **Règles :** R43 R45.

**Étant donné :** DTO de segment avec lastSequence=null et compte zéro.

**Quand :** Décoder puis présenter sur iPhone/iPad.

**Alors :** Pas d’erreur par Int non optionnel, pas de position zéro ni de demande de localisation pour le replay.


<a id="t347"></a>
## T347 · Ancienne vente sans détail d’option

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G5. **Fonctions :** F10 F17. **Règles :** R108.

**Étant donné :** Un achat historique ne décrit pas les suppléments d’options.

**Quand :** Préparer migration et affichage du dossier.

**Alors :** Prix historique conservé ; détail indiqué non disponible, aucune somme reconstruite depuis le tarif actuel.


<a id="t348"></a>
## T348 · Traitement manuel sans parcours support imposé

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G4. **Fonctions :** F01 F14. **Règles :** R103 R104.

**Étant donné :** Suppression nécessitant coordination de continuité en interne.

**Quand :** Terminer la demande dans app/web.

**Alors :** La personne n’est pas forcée à téléphoner/envoyer un email pour initier ; délai communiqué et suivi actif, pas exception réglementée présumée.


<a id="t349"></a>
## T349 · Bilan préparé sans réseau

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G2. **Fonctions :** F08 F12. **Règles :** R27 R46.

**Étant donné :** Notes textuelles prêtes localement sans connexion.

**Quand :** Demander publication puis retrouver réseau.

**Alors :** En attente locale, pas publié ; relecture droits/versions avant publication explicite avec sélections conservées.


<a id="t350"></a>
## T350 · Rejeu de clôture avec libérations

**Statut :** NOT_EXECUTED. **Introduit :** V3.6. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R12 R106.

**Étant donné :** Clôture atomique réussie mais réponse perdue.

**Quand :** Rejouer même opération puis relire droits et présences.

**Alors :** Un seul RELEASE par HOLD et même résultat CLOSED ; pas de remboursement ni seconde libération.


<a id="recettes-supplémentaires-v37"></a>
## Recettes des preuves, sources et notifications
**Statut global : NOT_EXECUTED.** Ces scénarios ne sont pas les modèles isolés ni les validations JSON exécutés dans le dossier.

<a id="t351"></a>
## T351 · Correction après crédit dépensé

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R109.

**Étant donné :** Série close, crédit rendu et utilisé ailleurs ; formateur habilité.

**Quand :** Corriger ABSENT en PRESENT sur le cycle courant.

**Alors :** Présence sauvegardée ; suivi REVIEW_REQUIRED, aucun mouvement ni attestation créé.


<a id="t352"></a>
## T352 · Consommation sur le lot d’origine

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R109 R12.

**Étant donné :** Présence exacte et suivi ouvert, reliquat utilisable suffisant.

**Quand :** ADMIN confirme AP201 puis rejoue la même opération.

**Alors :** Une consommation de quantité dérivée seulement, suivi SETTLED, replay sans second débit.


<a id="t353"></a>
## T353 · Crédit devenu insuffisant

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R109.

**Étant donné :** Aperçu du suivi préparé ; lot dépensé entre-temps.

**Quand :** Confirmer CONSUME_FROM_ORIGINAL_LOT.

**Alors :** Refus atomique d’AP201 ; suivi ouvert et présence inchangée, jamais crédit négatif.


<a id="t354"></a>
## T354 · Renonciation sans argent inventé

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F17 F10 F18. **Règles :** R109 R24.

**Étant donné :** ADMIN, suivi ouvert, lot épuisé et dette séparée.

**Quand :** Confirmer WAIVE_CONSUMPTION avec motif.

**Alors :** Suivi clos, aucun GRANT/RESTORE/paiement/remise ; dette et présences conservées.


<a id="t355"></a>
## T355 · Formateur sans droit financier

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R109 R02.

**Étant donné :** TAKE_ATTENDANCE seul sur le cours.

**Quand :** Corriger présence puis tenter AP201.

**Alors :** Correction autorisée ; résolution refusée, même via web ou nouvelle clé.


<a id="t356"></a>
## T356 · Rétraction avant régularisation

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R109 R11.

**Étant donné :** Suivi REVIEW_REQUIRED et un seul PRESENT, aperçu ADMIN en attente.

**Quand :** Retirer ce PRESENT puis confirmer l’ancien aperçu.

**Alors :** Suivi NOT_REQUIRED ; ancien commit refuse ; aucun mouvement de droit.


<a id="t357"></a>
## T357 · Deux résolutions concurrentes

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R109 R12.

**Étant donné :** Deux ADMIN lisent les mêmes versions.

**Quand :** Consommer et renoncer simultanément avec deux clés distinctes.

**Alors :** Une seule résolution ; autre refus de version/état sans deuxième effet.


<a id="t358"></a>
## T358 · Remboursement et droit simultanés

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G4. **Fonctions :** F17 F18 F22. **Règles :** R109 R88.

**Étant donné :** Solde zéro mais REFUND_REQUIRED et suivi de droit ouvert.

**Quand :** Résoudre un seul suivi puis archiver.

**Alors :** L’autre suivi reste visible et bloquant ; aucune confusion entre dette, remboursement et droit.


<a id="t359"></a>
## T359 · Accomplissement indépendant du crédit

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F03 F18 F17. **Règles :** R109 R110.

**Étant donné :** Toutes présences et preuves valides ; suivi de droit non réglé.

**Quand :** Valider l’exigence avec le grant correct.

**Alors :** Validation pédagogique possible sans paiement fictif ; le suivi commercial reste ouvert.


<a id="t360"></a>
## T360 · Correction puis restauration motivée

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F17 F18. **Règles :** R109 R54.

**Étant donné :** Droit régularisé consommé puis présence rectifiée de nouveau.

**Quand :** Corriger le fait ; demander RESTORE séparément et répéter.

**Alors :** Aucune restitution automatique ; restauration autorisée plafonnée/idempotente, historique des deux décisions conservé.


<a id="t361"></a>
## T361 · Cycle de preuve ancien

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F03 F18. **Règles :** R110 R63.

**Étant donné :** Demande de validation préparée sur cycle 1 ; relation passée au cycle 2.

**Quand :** Envoyer la demande sur cycle 1.

**Alors :** Ne pas substituer cycle 2 ; refus explicite ou traitement historique hors de ce parcours, jamais validation courante abusive.


<a id="t362"></a>
## T362 · Validation sans preuve

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F03 F18. **Règles :** R110.

**Étant donné :** Statut demandé COMPLETED sans source interne ni document.

**Quand :** Soumettre AP122.

**Alors :** Refus ; aucun reviewer ou document fabriqué.


<a id="t363"></a>
## T363 · Exemption non prévue

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F03 F18. **Règles :** R110.

**Étant donné :** Commande EXEMPT bien formée ; profil ne prévoit pas ce motif.

**Quand :** Valider sous un compte habilité.

**Alors :** EXEMPTION_NOT_APPLICABLE ; droit ADMIN ne contourne pas la règle du profil.


<a id="t364"></a>
## T364 · Présence corrigée après accomplissement

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F03 F18. **Règles :** R110 R63.

**Étant donné :** COMPLETED basé sur des relevés identifiés.

**Quand :** Passer une présence source à ABSENT.

**Alors :** EVIDENCE_PENDING et basis courante nulle au même commit ; ancienne décision auditée, nouvelle validation nécessaire.


<a id="t365"></a>
## T365 · Pièce invalidée

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F03 F09 F18. **Règles :** R110.

**Étant donné :** Deux exigences de la même école dépendent d’une pièce vérifiée.

**Quand :** Invalider sa valeur métier.

**Alors :** Les deux décisions passent à vérifier ; aucun accès ni modification dans une autre école.


<a id="t366"></a>
## T366 · Purge régulière distincte de fraude

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G4. **Fonctions :** F03 F09 F14. **Règles :** R110.

**Étant donné :** Preuve contrôlée puis purge autorisée par politique approuvée.

**Quand :** Purger les octets selon cette politique.

**Alors :** Aucune accusation ou invalidation automatique erronée ; seul reçu minimal justifié subsiste ; sinon réexamen explicite.


<a id="t367"></a>
## T367 · Validation et correction concurrentes

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F03 F18. **Règles :** R110 R11.

**Étant donné :** Deux transactions réelles sur preuve et exigence.

**Quand :** Valider pendant qu’une présence source est corrigée.

**Alors :** Ordre de commit cohérent : pas d’état final COMPLETED fondé sur preuve déjà invalidée.


<a id="t368"></a>
## T368 · Engagement déjà acquis

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F03 F05 F18. **Règles :** R110.

**Étant donné :** Leçon/cours réservé avant réexamen d’une exigence.

**Quand :** Corriger sa preuve, puis tenter un nouvel acte qui la requiert.

**Alors :** Ancien engagement conservé avec suivi ; nouvel acte revalide et peut refuser, aucune retenue automatique.


<a id="t369"></a>
## T369 · Réexamen et campagne

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F03 F19. **Règles :** R110 R70.

**Étant donné :** Exigence complète devenue EVIDENCE_PENDING.

**Quand :** Publier une offre et exécuter son ciblage.

**Alors :** Pas d’annonce ciblée de besoin certain ; calendrier toujours consultable.


<a id="t370"></a>
## T370 · Sources répétées et versionnées

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F03 F18. **Règles :** R110.

**Étant donné :** Deux références au même justificatif avec versions différentes dans une preuve.

**Quand :** Construire/valider la décision.

**Alors :** Unicité par id au service ; versions vérifiées, pas de doubles blocs/prétextes de complétude.


<a id="t371"></a>
## T371 · Position de la leçon précédente

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G2. **Fonctions :** F15 F16. **Règles :** R111 R43.

**Étant donné :** Nouvelle leçon autorisée ; cache de position antérieure.

**Quand :** Recevoir ce point après le démarrage.

**Alors :** Aucun point attribué à la nouvelle leçon ; attente de position réelle.


<a id="t372"></a>
## T372 · Batch ancien mais valide

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G2. **Fonctions :** F12 F15. **Règles :** R111 R42.

**Étant donné :** Mesures prises dans l’intervalle autorisé, reçues/transportées plus tard.

**Quand :** Traiter un lot avant scellement puis transférer après retour réseau.

**Alors :** Les mesures admissibles gardent leur date ; pas de rejet universel à quinze secondes ni prolongation de collecte.


<a id="t373"></a>
## T373 · Horloge modifiée

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G2. **Fonctions :** F15 F12. **Règles :** R111 R42.

**Étant donné :** Capture active et bail monotone ; saut de l’horloge civile.

**Quand :** Livrer des positions après le saut.

**Alors :** Rupture/arrêt si mapping non fiable, aucun bail rallongé ni points réécrits.


<a id="t374"></a>
## T374 · Précision invalide

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G2. **Fonctions :** F15 F16. **Règles :** R111.

**Étant donné :** Mesure négative/non finie ou coordonnée par défaut sans source.

**Quand :** Passer la mesure à l’admission.

**Alors :** Rejet de l’objet non exploitable ; pas de précision zéro fabriquée ; état sans signal honnête.


<a id="t375"></a>
## T375 · Origine géographique réelle

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G2. **Fonctions :** F15 F16. **Règles :** R111.

**Étant donné :** Source synthétique authentifiée de test avec mesure (0,0) valide dans l’intervalle.

**Quand :** Admettre cette mesure.

**Alors :** Ne pas rejeter uniquement pour (0,0) ; aucune valeur par défaut n’est produite en absence de source.


<a id="t376"></a>
## T376 · Callback après scellement

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G2. **Fonctions :** F15 F12. **Règles :** R111 R43.

**Étant donné :** Manifeste scellé puis batch de mesures anciennes reçu.

**Quand :** Livrer le callback.

**Alors :** Manifeste stable ; aucune insertion tardive, transfert reprend sans faux ajout.


<a id="t377"></a>
## T377 · Compte changé sur tablette

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G1. **Fonctions :** F01 F11. **Règles :** R112.

**Étant donné :** Installation utilisée par A puis connexion authentifiée de B et révocation de A.

**Quand :** Réinscrire le token puis dispatcher une ancienne notification de A.

**Alors :** Version/propriétaire périmés refusés avant nouvel envoi ; droits de B non hérités de A.


<a id="t378"></a>
## T378 · APNs et mauvais environnement

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G1. **Fonctions :** F11. **Règles :** R112.

**Étant donné :** Binaire signé développement et configuration fournisseur production.

**Quand :** Soumettre ou dispatcher le token incohérent.

**Alors :** PUSH_ENVIRONMENT_MISMATCH ; pas de réussite annoncée.


<a id="t379"></a>
## T379 · Ancienne révocation push

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G1. **Fonctions :** F01 F11. **Règles :** R112 R11.

**Étant donné :** Route A obsolète, nouvelle liaison B active.

**Quand :** Rejouer AP149 de A.

**Alors :** Ne pas révoquer B ; refus sous identité/version courantes.


<a id="t380"></a>
## T380 · Plusieurs écoles, même compte

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F01 F11 F19. **Règles :** R112.

**Étant donné :** Même compte/installation avec routes de deux écoles.

**Quand :** Désactiver une route scolaire.

**Alors :** Autre route autorisée conservée ; aucune visibilité inter-écoles.


<a id="t381"></a>
## T381 · Notification déjà chez le fournisseur

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G1. **Fonctions :** F01 F11. **Règles :** R112.

**Étant donné :** Push déjà accepté par le fournisseur avant déconnexion hors ligne.

**Quand :** Livrer puis ouvrir le message après changement de compte.

**Alors :** Payload externe générique ; aucune promesse de rappel ; relecture refuse le dossier non autorisé.


<a id="t382"></a>
## T382 · Web sans faux token natif

**Statut :** NOT_EXECUTED. **Introduit :** V3.7. **Première tranche :** G3. **Fonctions :** F11 F19. **Règles :** R112.

**Étant donné :** Élève sur portail web sans push natif.

**Quand :** Consulter cours/centre interne puis soumettre WEB à AP148.

**Alors :** Parcours web intact ; requête natif WEB refusée, aucun Web Push présenté comme configuré.


<a id="t383"></a>
## T383 · Objet de dépôt remplacé après analyse

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09. **Règles :** R22.

**Étant donné :** Un dépôt a été scellé et contrôlé.

**Quand :** Réutiliser le ticket PUT pour changer le contenu puis lire le document.

**Alors :** Le staging refuse le remplacement ; la lecture conserve la génération contrôlée, aucune nouvelle donnée n’est publiée.


<a id="t384"></a>
## T384 · Staging recréé après nettoyage

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09 F14. **Règles :** R22 R30.

**Étant donné :** La génération canonique est scellée et une clé staging nettoyée.

**Quand :** Recréer le staging avec un ticket encore techniquement valide.

**Alors :** Aucune relecture de staging par le scanner ou la passerelle ; la génération canonique reste inchangée.


<a id="t385"></a>
## T385 · Suppression pendant scan

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09 F14. **Règles :** R22 R30.

**Étant donné :** Un worker traite une génération QUARANTINED.

**Quand :** Supprimer la pièce puis terminer le scan.

**Alors :** Le compare-and-set refuse la promotion ; les dérivés tardifs sont nettoyés et DELETED ne redevient jamais READY.


<a id="t386"></a>
## T386 · Résultat de génération périmée

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09 F13. **Règles :** R22.

**Étant donné :** Un résultat de scan porte une ancienne version/génération.

**Quand :** Le rejouer après changement autorisé du propriétaire.

**Alors :** Aucune promotion ni remplacement du canonique ; événement technique minimal sans contenu sensible.


<a id="t387"></a>
## T387 · Décodage borné

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09. **Règles :** R22 R33.

**Étant donné :** Une petite entrée compressée produit une charge démesurée au décodage.

**Quand :** Exécuter le pipeline avec limites qualifiées.

**Alors :** Arrêt borné et état de rejet/quarantaine explicite ; pas de READY ni épuisement non borné des workers.


<a id="t388"></a>
## T388 · Réponse PUT perdue

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09. **Règles :** R22.

**Étant donné :** Le premier PUT est reçu mais sa réponse perdue.

**Quand :** Réessayer en conditionnel puis finaliser.

**Alors :** Un 412 déclenche réconciliation ; une seule génération et aucun document fantôme ni succès READY prématuré.


<a id="t389"></a>
## T389 · URL expirée après réception complète

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09. **Règles :** R22.

**Étant donné :** Les octets sont reçus ; URL expirée, intention conservée et droits valides.

**Quand :** Finaliser via l’API authentifiée.

**Alors :** La génération est scellée sans nouveau PUT ni nouvelle intention.


<a id="t390"></a>
## T390 · URL expirée sans objet

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09. **Règles :** R22.

**Étant donné :** L’URL expire sans contenu finalisable.

**Quand :** Réconcilier puis accepter un nouveau dépôt.

**Alors :** Nouvelle intention explicite, références de brouillon modifiées volontairement ; ancien objet invisible puis nettoyé.


<a id="t391"></a>
## T391 · Rejeu de création après expiration

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09 F13. **Règles :** R22.

**Étant donné :** Une clé idempotente de création désigne un ancien ticket.

**Quand :** Rejouer la création.

**Alors :** Même résultat et même expiration ; aucun renouvellement implicite ni corps différent accepté.


<a id="t392"></a>
## T392 · Changement de compte pendant transfert

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F01 F09 F12. **Règles :** R22 R02.

**Étant donné :** Un dépôt appartient à une session et école A.

**Quand :** Passer au compte B pendant une réponse retardée.

**Alors :** Aucun bearer B ni rattachement B ; résultat tardif ignoré ou conservé sous son contexte chiffré autorisé.


<a id="t393"></a>
## T393 · Document READY sans type

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09. **Règles :** R22.

**Étant donné :** Un service tente de projeter READY avec detectedMime=null.

**Quand :** Valider puis décoder la réponse.

**Alors :** Contrat refusé ; aucune icône PDF par défaut ni aperçu trompeur.


<a id="t394"></a>
## T394 · Photo sous mauvaise finalité

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09 F21. **Règles :** R22 R33.

**Étant donné :** Une photo de profil reçoit un PDF, un rattachement de leçon ou plus de 2 MiB.

**Quand :** Tenter la promotion/affectation.

**Alors :** Refus ; la photo antérieure ou les initiales demeurent et l’onboarding non bloqué par la photo facultative.


<a id="t395"></a>
## T395 · Logo READY inadmissible

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09 F13. **Règles :** R22 R33.

**Étant donné :** Un nouveau logo a un type ou une taille invalide.

**Quand :** Tenter son passage READY puis la sélection en paramètres.

**Alors :** Aucun logo inadmissible affecté ; ancien logo courant conservé.


<a id="t396"></a>
## T396 · Scanner indisponible

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09. **Règles :** R22.

**Étant donné :** Le staging est scellé mais le scanner indisponible.

**Quand :** Relancer le worker et consulter la fiche.

**Alors :** Rester QUARANTINED sans aperçu ; aucune erreur n’accorde READY.


<a id="t397"></a>
## T397 · Publication sans pièce non prête

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G2. **Fonctions :** F08 F09. **Règles :** R22.

**Étant donné :** Le bilan contient une pièce en quarantaine.

**Quand :** Publier le texte en confirmant son exclusion puis terminer le scan.

**Alors :** Pas de rattachement tardif à la révision ; texte conservé et nouvelle publication explicite requise.


<a id="t398"></a>
## T398 · Export de gestion réellement CSV

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G4. **Fonctions :** F14 F22 F23. **Règles :** R96.

**Étant donné :** Un export STUDENT_LIST ou METRICS est READY.

**Quand :** Télécharger AP91 et vérifier métadonnées/colonnes.

**Alors :** CSV UTF-8 et nom .csv ; type/taille/hash des octets exacts, pas de ZIP masqué.


<a id="t399"></a>
## T399 · Export privé réellement ZIP

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G4. **Fonctions :** F14. **Règles :** R96.

**Étant donné :** Une demande PRIVACY produit un export READY.

**Quand :** Télécharger AP91 avec droits courants.

**Alors :** ZIP et nom .zip ; seul le manifeste autorisé est remis, pas un CSV de gestion par défaut.


<a id="t400"></a>
## T400 · Export non disponible

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G4. **Fonctions :** F14 F22. **Règles :** R96.

**Étant donné :** Un export est PREPARING, FAILED ou EXPIRED.

**Quand :** Consulter puis tenter de télécharger.

**Alors :** Métadonnées publiques de contenu nulles et pas de fichier rendu disponible.


<a id="t401"></a>
## T401 · Affectation retirée après génération

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G4. **Fonctions :** F14 F22. **Règles :** R96.

**Étant donné :** Un export contient un dossier devenu hors périmètre, mais EXPORT_MANAGEMENT demeure.

**Quand :** Demander un ticket ou les octets.

**Alors :** Refus du manifeste ancien ; une régénération sous droits actuels est proposée sans troncature cachée.


<a id="t402"></a>
## T402 · Nom sûr et copie externe

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G4. **Fonctions :** F14 F22. **Règles :** R96.

**Étant donné :** Un fichier d’export doit être sauvegardé hors Drivy.

**Quand :** Contrôler CR/LF, chemin, suffixe, hash puis partager.

**Alors :** Nom technique sûr, intégrité vérifiée ; avertissement explicite sur la copie non révocable.


<a id="t403"></a>
## T403 · Bearer vers stockage

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F01 F09 F13. **Règles :** R22.

**Étant donné :** Un ticket contient une origine ou un en-tête arbitraire.

**Quand :** Exécuter le client avec instrumentation réseau.

**Alors :** Aucune requête vers origine inconnue ; aucun bearer Drivy ni cookie API vers le stockage.


<a id="t404"></a>
## T404 · Redirection de contenu privé

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G1. **Fonctions :** F09 F14. **Règles :** R22 R96.

**Étant donné :** La passerelle retourne un redirect inattendu.

**Quand :** Suivre le téléchargement d’une pièce/export.

**Alors :** Le client refuse la redirection sans transférer ses credentials ni exposer une URL publique.


<a id="t405"></a>
## T405 · Cache sensible après déconnexion

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G2. **Fonctions :** F01 F09 F12 F14. **Règles :** R02 R30.

**Étant donné :** Des médias/exports ont été consultés sans sauvegarde externe volontaire.

**Quand :** Se déconnecter et inspecter caches/tmp puis ouvrir une ancienne réponse.

**Alors :** Aucun cache HTTP clair réutilisable ; fichiers et projections suivent la purge scolaire/compte.


<a id="t406"></a>
## T406 · Snapshot et capture en cours

**Statut :** NOT_EXECUTED. **Introduit :** V3.10. **Première tranche :** G2. **Fonctions :** F01 F12 F15. **Règles :** R02 R41.

**Étant donné :** Une scène privée affiche une capture autorisée.

**Quand :** Passer en arrière-plan puis changer de contexte et revenir.

**Alors :** Couverture opaque avant snapshot sans arrêt GPS causé par la couverture ; retour sous génération valide uniquement.


## Recettes des observations pendant la leçon

Les scénarios suivants mettent en œuvre [R46](../03-fonctionnel/regles-etats.md#r46). Ils sont des spécifications à exécuter sur le produit, pas des résultats de la revue documentaire.

<a id="t407"></a>
### T407 · Observation avant constat

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Leçon PLANNED, moniteur affecté et formation active ; aucun ReportDraft.

**Quand :** Envoyer AP162 origin LIVE, draftId null, thème « priorité à droite », statut ATTENTION et instant conservé.

**Alors :** Observation privée rattachée à la leçon et auteur de session ; aucun brouillon, résultat, charge ou publication créé.

**Preuve attendue :** État PLANNED inchangé, ligne GeoObservation avec draftId nul, absence d’effets commerciaux et absence de lecture élève.

<a id="t408"></a>
### T408 · Observation sans GPS

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Choix GPS refusé, permission OS absente, lease local valide.

**Quand :** Ajouter un thème/statut depuis E04 sans carte puis synchroniser AP162 avec captureId/segmentId/pointSequence nuls.

**Alors :** Aucune demande de localisation, aucun CaptureSession ou point ; observation textuelle retrouvée au bilan après constat.

**Preuve attendue :** Instrumentation Core Location sans sollicitation, triplet nul côté stockage/API et capture de la liste pédagogique.

<a id="t409"></a>
### T409 · Persistance et relance hors ligne

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Contexte scolaire autorisé, réseau coupé et capacité de persistance locale disponible.

**Quand :** Ajouter une observation, attendre l’accusé local, tuer puis rouvrir l’app avec le même compte ; reconnecter et renvoyer la même intention.

**Alors :** Texte/thème/statut/instant identiques, une seule observation serveur et indicateurs local/synchronisé distincts.

**Preuve attendue :** Journal chiffré durable, operationId identique, un seul effet AP162 ; test sur appareil, pas sur la seule galerie.

<a id="t410"></a>
### T410 · Chunk GPS non encore reçu

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Point admissible sauvegardé localement et ancre choisie, chunk non acquitté au serveur.

**Quand :** Tenter AP162 ancré, recevoir ANCHOR_NOT_READY, envoyer le chunk puis reprendre la même commande selon sa reprise non commitée.

**Alors :** Aucun faux succès initial ni point inventé ; une seule observation ancrée après disponibilité et contrôle des droits.

**Preuve attendue :** Ordre des échanges, refus transitoire, acquittement chunk et lecture de l’ancre exacte segment/séquence.

<a id="t411"></a>
### T411 · Avant la première position

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Capture autorisée mais aucune mesure admissible sauvegardée, puis variante avec capture en pause.

**Quand :** Marquer un moment et ajouter une observation qualifiée dans chaque variante, sans demander de nouveau point.

**Alors :** Triplet d’ancre nul, instant préservé ; arrivée ultérieure d’un point ne rattache rien automatiquement.

**Preuve attendue :** Absence d’ancien point/sequence 0 fabriquée et valeurs inchangées après réception de la première mesure.

<a id="t412"></a>
### T412 · Clôture après observation

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Une observation LIVE privée sans draftId existe pour l’auteur qui va constater la leçon.

**Quand :** Arrêter localement le GPS puis envoyer AP49 ; lire le brouillon, l’observation et la progression élève.

**Alors :** Rattachement au brouillon initial et version incrémentée dans la transaction ; aucune sélection/publication/note automatique.

**Preuve attendue :** Ancien/nouveau draftId et version, invariants atomiques, progression identique ; test de rollback sur erreur injectée.

<a id="t413"></a>
### T413 · Création et clôture concurrentes

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Leçon PLANNED et observation LIVE à envoyer ; aucune publication.

**Quand :** Faire courir AP162 et AP49 avec deux connexions, en testant les deux ordres de verrou/commit.

**Alors :** Observation soit rattachée par AP49, soit ajoutée au brouillon initial encore modifiable ; jamais perdue ni dupliquée.

**Preuve attendue :** Deux ordres contrôlés, un brouillon initial, une observation dans chacun des cas, aucune publication.

<a id="t414"></a>
### T414 · Observation arrivée après publication

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Une intention LIVE locale n’a pas été envoyée ; le bilan initial a déjà été publié.

**Quand :** Reconnecter et envoyer AP162 avec draftId nul ; ouvrir ensuite une correction explicite et reprendre l’observation vers ce brouillon.

**Alors :** 409 OBSERVATION_REVIEW_REQUIRED d’abord ; texte local préservé sous droits valides, publication initiale inchangée ; reprise seulement après décision explicite.

**Preuve attendue :** Ancien snapshot identique, nouvelle intention vers la correction avec instant d’origine, aucune auto-publication.

<a id="t415"></a>
### T415 · Rattachement et modification concurrente

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Client a lu l’observation privée version 1 avant constat.

**Quand :** Faire rattacher l’observation par AP49 puis envoyer AP163 avec If-Match de la version 1.

**Alors :** 412 ; état rattaché conservé, utilisateur invité à relire sans écrasement ni copie silencieuse.

**Preuve attendue :** Version serveur supérieure, comparaison texte/association intacte et requête rejetée.

<a id="t416"></a>
### T416 · Repère non qualifié non publié

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Brouillon contient un repère MARKER et une observation QUALIFIED.

**Quand :** Sélectionner le repère pour AP54, puis refaire une sélection explicite qui l’exclut ou le qualifie d’abord.

**Alors :** Première publication refusée 422 OBSERVATION_NOT_QUALIFIED sans révision partielle ; seconde possible après revue conforme.

**Preuve attendue :** Nombre de révisions inchangé au refus, version sélectionnée correcte à la réussite et aucune note inférée.

<a id="t417"></a>
### T417 · Statut d’événement distinct du niveau

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Trois observations LIVE sur la même compétence portent ATTENTION puis POSITIVE puis ATTENTION.

**Quand :** Clore, relire les événements et publier uniquement la sélection voulue sans saisir de niveau de compétence.

**Alors :** Plusieurs événements conservés ; aucune moyenne, note zéro, niveau ou progression calculés automatiquement.

**Preuve attendue :** Payload publié avec métadonnées sélectionnées et observations de compétence vides ; projection finale inchangée.

<a id="t418"></a>
### T418 · Isolation auteur et écoles

**Statut :** À réaliser. **Fonctions :** F01 F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82), [R02](../03-fonctionnel/regles-etats.md#r02), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Observation privée de A ; compte élève de A et moniteur de B avec identifiants connus.

**Quand :** Tenter AP161/AP163/AP164 sous ces comptes puis falsifier un auteur dans la commande AP162.

**Alors :** Lecture/mutation privées refusées ; auteur client rejeté par forme et auteur serveur dérivé de session.

**Preuve attendue :** Réponses expurgées et absence de texte, identifiants privés ou modifications hors périmètre.

<a id="t419"></a>
### T419 · Annulation et révocation avant reprise

**Statut :** À réaliser. **Fonctions :** F01 F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82), [R02](../03-fonctionnel/regles-etats.md#r02), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Une observation est en file locale ; variante 1 leçon annulée, variante 2 droits du moniteur retirés.

**Quand :** Reconnecter et tenter l’envoi dans chaque variante.

**Alors :** Conflit d’état ou refus d’accès ; aucune réactivation ; contenu local soumis au verrouillage/purge du lease et à la réconciliation autorisée.

**Preuve attendue :** État terminal et epoch respectés ; aucun envoi sous un autre compte ni export de contournement.

<a id="t420"></a>
### T420 · Rotation et continuité des observations

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Une observation est confirmée localement et un formulaire non confirmé est ouvert sur iPad.

**Quand :** Redimensionner, tourner, changer de panneau, retrouver la leçon puis ouvrir E08 après constat.

**Alors :** Observation persistée une fois, champs non confirmés conservés selon le modèle de vue ; liste de bilan reprend les identifiants sans nouvelle commande.

**Preuve attendue :** Compteurs operationId, état des champs et liste avant/après ; actions d’arrêt accessibles au grand texte.

<a id="t421"></a>
### T421 · Suppression géographique et snapshot textuel

**Statut :** À réaliser. **Fonctions :** F01 F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82), [R02](../03-fonctionnel/regles-etats.md#r02), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Observation LIVE ancrée publiée ; une autre observation sans GPS est publiée dans le même périmètre autorisé.

**Quand :** Exécuter le retrait/purge géographique selon R48, puis lire le replay et le bilan textuel autorisé.

**Alors :** Ancres, miniatures et géométrie retirées ; aucun identifiant GPS dans PublishedTextObservation, texte conservé seulement selon la politique applicable.

**Preuve attendue :** Contrôle stockage/caches/réponses publiées, absence de géographie résiduelle et audit sans coordonnées.

<a id="t422"></a>
### T422 · Échec disque sans faux acquittement

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R15](../03-fonctionnel/regles-etats.md#r15), [R17](../03-fonctionnel/regles-etats.md#r17), [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R82](../03-fonctionnel/regles-etats.md#r82).

**Étant donné :** Le formulaire d’observation contient un thème/statut mais la persistance locale échoue.

**Quand :** Confirmer la saisie puis tenter de fermer le panneau et d’arrêter le GPS.

**Alors :** Aucun message de sauvegarde réussie ni compteur artificiel ; contenu en mémoire signalé non sauvegardé, arrêt GPS reste immédiatement accessible.

**Preuve attendue :** Injection d’échec disque, message et compteur exacts, appel d’arrêt local indépendant de la sauvegarde.


<a id="t423"></a>
### T423 · Moment figé dès ouverture

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Une capture possède un point admissible P1 à t0.

**Quand :** Ouvrir Signaler à t0, recevoir P2 à t1, puis choisir Signalisation et Attention.

**Alors :** Une seule observation conserve observedAt=t0 et P1, pas P2 ni l’heure d’envoi.

**Preuve attendue :** Comparer snapshot de panneau, intention persistée et DTO ; refuser une mutation automatique de l’ancre.

<a id="t424"></a>
### T424 · Annulation sans événement parasite

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Aucune observation n’existe et le panneau est fermé.

**Quand :** Ouvrir Signaler, sélectionner Stationnement puis annuler avant tout statut.

**Alors :** Compteur inchangé, aucun AP162/AP164, focus rendu à Signaler.

**Preuve attendue :** Journal serveur vide et outbox sans commande ; capture indépendante toujours active.

<a id="t425"></a>
### T425 · Double appui de confirmation

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Une intention contient le thème Priorité à droite et son instant figé.

**Quand :** Actionner rapidement deux fois Attention · enregistrer avec un acquittement local retardé.

**Alors :** Une seule intention persistée et une seule clé réutilisée pour sa reprise.

**Preuve attendue :** Nombre de commits locaux et effets serveur égal à un malgré deux événements UI.

<a id="t426"></a>
### T426 · Révocation pendant choix du thème

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Une ancre candidate est disponible et un choix de thème est ouvert.

**Quand :** Recevoir un refus/purge connu avant confirmation puis choisir À retravailler.

**Alors :** Aucune ancre interdite envoyée ; champs autorisés conservés avec revue explicite sans position.

**Preuve attendue :** Observer l’absence de coordonnées et références révoquées dans toutes les commandes émises.

<a id="t427"></a>
### T427 · Déclencheur dans la plus petite fenêtre

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** E23 est actif sur la plus petite cellule de DM01 et aux tailles de texte extrêmes.

**Quand :** Ouvrir la leçon et changer la taille de texte, la hauteur et le panneau de contexte.

**Alors :** Signaler et Arrêter restent dans la zone sûre sans défilement ; la carte et le contexte secondaire se replient.

**Preuve attendue :** Mesurer les rectangles par rapport à la fenêtre native et parcourir les commandes au lecteur d’écran.

<a id="t428"></a>
### T428 · Fenêtre partagée avec intention ouverte

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Un signalement non confirmé possède un instant, une ancre et un thème sur iPad.

**Quand :** Passer du plein écran à Split View, réduire la fenêtre puis revenir.

**Alors :** Le même contexte est conservé, sans recréer capture ni observation ; le statut reste non choisi.

**Preuve attendue :** Comparer identifiants, instant, ancre et nombre de commits avant/après chaque transition.

<a id="t429"></a>
### T429 · Retour réduit sans perte de sens

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Réduire les animations et Augmenter le contraste sont actifs.

**Quand :** Signaler une observation positive puis fermer et rouvrir sa liste.

**Alors :** Aucune translation/échelle décorative obligatoire ; texte et forme transmettent le résultat et le statut.

**Preuve attendue :** Contrôler styles natifs, hiérarchie accessible et retour après persistance sans s’appuyer sur un haptique.

<a id="t430"></a>
### T430 · Thème absent du référentiel local

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Le référentiel autorisé ne contient pas le thème de stationnement attendu.

**Quand :** Ouvrir le signalement et chercher cette catégorie.

**Alors :** Aucune compétence inventée ; choix du référentiel disponible ou repère non qualifié.

**Preuve attendue :** Vérifier tous les competencyId émis et l’absence de note par défaut.

<a id="t431"></a>
### T431 · Repère sans GPS puis qualification

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Le GPS est arrêté ; un repère temporel a été enregistré.

**Quand :** Qualifier le repère en Signalisation / Attention et ouvrir le replay privé.

**Alors :** Instant d’origine conservé, aucune ancre créée, repère temporel visible dans la liste sans point carte.

**Preuve attendue :** Comparer DTO avant/après et absence de requête de localisation au cours du parcours.

<a id="t432"></a>
### T432 · Observation privée et replay publié

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Deux observations LIVE privées coexistent avec une ancienne révision publiée.

**Quand :** Ouvrir le replay privé puis lire le replay élève de l’ancienne révision.

**Alors :** Le privé retrouve les événements ; l’élève ne voit que le snapshot publié, sans fuite de compteur ni de thème.

**Preuve attendue :** Comparer réponses autorisées et arbre accessible de chaque rôle pour la même leçon.

<a id="t433"></a>
### T433 · Retrait après réponse perdue

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** AP162 a peut-être été appliqué mais son résultat n’est pas reçu.

**Quand :** Demander le retrait de l’observation puis retrouver le réseau.

**Alors :** Réconcilier l’opération, retirer via AP164 si créée ; ne pas réémettre une création différente ni annoncer Retirée trop tôt.

**Preuve attendue :** Injecter perte de réponse avant et après commit et vérifier états visibles et absence de doublon.

<a id="t434"></a>
### T434 · Caméra manuelle et événement sélectionné

**Statut :** À réaliser. **Fonctions :** F08 F12 F15 F16. **Règles :** [R46](../03-fonctionnel/regles-etats.md#r46), [R47](../03-fonctionnel/regles-etats.md#r47), [R48](../03-fonctionnel/regles-etats.md#r48).

**Étant donné :** Le replay privé lit une trace avec une observation et une lacune connue.

**Quand :** Déplacer/zoomer manuellement pendant x1 puis sélectionner l’observation et recentrer explicitement.

**Alors :** Le zoom ne pause pas la lecture ; le suivi ne reprend qu’à la demande, aucune position interpolée dans la lacune.

**Preuve attendue :** Comparer temps réel écoulé et replay, état du suivi caméra, instant sélectionné et masquage du curseur dans la lacune.
