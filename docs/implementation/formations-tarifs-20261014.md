# Formations et tarifs : une fiche par permis

Réalisation du 14 octobre 2026, branche `claude/formations-tarifs-20261014`, partie de `5482dd8` (Studio). Le dossier de conception 3.17 et le canon OpenAPI 3.11.0 sont inchangés ; R35, R75 et T049 ont été relus, ainsi que les décisions du 13 octobre (textes proposés, motif d’approbation retiré de l’interface). La direction Studio est conservée : Manrope, cobalt, sombre anthracite, Base UI, tokens sémantiques, tables sobres et formulaires bornés. Les écrans Apple ne sont pas modifiés. **Rien n’est déployé.**

## 1. Cartographie réelle

| Notion | Données | Règle retenue |
|---|---|---|
| Permis | `category_code` (texte de 30 caractères) | Organise la fiche ; ce n’est pas un contrôle du permis de l’élève, ni un réglage réglementaire. |
| Parcours | Chaîne `offering_version` d’un `offering_key`, avec `curriculum_version_id`, `policy_version_id`, durée habituelle | Cas courant : un parcours par permis, sans niveau visible. Plusieurs clés : jamais fusionnées, présentées comme parcours distincts. |
| Compétences / règles | `curriculum_version` + `competency_definition` ; `school_policy_version` (séquences par permis) | Contenus immuables ; une modification crée une version rattachée au seul parcours modifié. |
| Tarif | Chaîne `service_product_version` d’un `product_key`, avec `terms_version_id` | Portée par permis (pas de `offeringId`) : commun aux parcours d’un permis, ce que la fiche dit explicitement. |
| Conditions commerciales | `commercial_terms_version` (séquence école) | Lues et modifiées depuis le tarif ; partage réel affiché. |
| Formation d’un élève | `training.offering_id` (version précise) | Inchangée par toute édition du catalogue. Les leçons de cette formation gardent la procédure de sa version (`lessons.ts`, `SCHOOL_POLICY_CHANGED`). |

`offering_version` n’avait pas de nom : la migration **033** ajoute `label` facultatif (1 à 120 caractères, sans espace de bord). Les lignes existantes restent à `NULL` : « Parcours » ou « Parcours sans nom », jamais un nom tiré d’un tarif ou d’une clé. Le test de migration peuplée 030→033 vérifie qu’aucune ligne n’est modifiée hormis cette colonne vide.

## 2. Destinations et adresses

| Adresse | Contenu |
|---|---|
| `/formations` | Liste des permis (tarifs, élèves en formation, badge seulement « À compléter » ou « Non proposée », calculé au serveur), accès aux prestations sans permis, « Ajouter une formation ». |
| `/formations?category=A&view=general\|competences\|deroulement\|tarifs[&programme=clé]` | Fiche du permis. Les rubriques ont une adresse propre (rechargement, nouvel onglet, précédent/suivant) ; la fiche reste montée entre elles. |
| `…&view=historique[&selection=id]` | Historique (action secondaire) : versions des parcours et des tarifs, éléments non rattachés, version consultée et ses usages. |
| `/formations?view=nouvelle[&category=A]` | Assistant d’une seule formation. |
| `/prestations` | Prestations sans permis (même liste et même éditeur de tarif, sans catégorie). |
| `/conditions[?selection=id]` | Consultation des conditions et de leurs tarifs ; la modification passe par le tarif. |

Anciennes adresses `/offres`, `/referentiels`, `/procedures`, `/prestations`, `/conditions` avec `selection`, `category`, `from` : la référence est relue (`GET formations/references/{id}`). Une version actuelle utilisée par un seul parcours ouvre sa rubrique ; une version précédente, un contenu utilisé par plusieurs parcours ou un élément non rattaché s’affiche dans l’historique du permis, avec ses usages, sans choisir de parcours. Un tarif sans permis ouvre `/prestations`, des conditions ouvrent `/conditions`. La redirection remplace l’entrée d’historique. Les prochaines actions de l’école visent maintenant `formations` (tarif de l’élève : `selection` + `view=tarifs`) et non plus le guide.

## 3. Périmètres d’édition et effets

Chaque rubrique se lit puis s’édite sur place (« Modifier », « Modifier les compétences », « Modifier les règles », « Ajouter un tarif »), avec un enregistrement explicite, Annuler, et l’effet annoncé au moment de l’enregistrement.

- **Général** : nom du parcours (exigé quand le permis en a plusieurs, unique dans le permis), proposé ou non aux nouvelles inscriptions, durée habituelle d’une leçon (utilisée par la planification).
- **Compétences** : libellé et description ; ajout, retrait, montée et descente par boutons (focus conservé, annonce vocale) ; ordre = ordre affiché ; clés conservées pour les éléments repris, générées (`competence-xxxxxxxx`) pour les nouveaux, jamais saisies. Une clé reprise ne transfère aucune progression : l’élève inscrit garde son référentiel.
- **Déroulement et annulation** : deux textes dans le même contexte, sources en second niveau ; l’exemple Drivy s’insère seulement dans un champ vide, sinon il reste consultable.
- **Tarifs** : nom, type (leçon, accompagnement à l’examen, cours collectif si le module est actif ; « autre prestation » pour les prestations sans permis), durée et unité, prix CHF, validité, proposé ou non, conditions. Prix absent refusé, zéro accepté et transmis tel quel.

Une édition pédagogique s’applique aux **nouvelles inscriptions** : les élèves inscrits gardent leur programme et leur procédure, y compris pour leurs prochaines leçons. Une modification de tarif laisse les réservations confirmées à leur prix et leurs conditions photographiés. Les saisies restent en mémoire : changer de rubrique les conserve (point sur l’onglet, « modification en cours » pour les lecteurs d’écran) ; quitter la fiche, recharger ou utiliser précédent/suivant pendant une saisie demande confirmation. Rien n’est écrit dans le stockage du navigateur ; seules les métadonnées de reçu AP72 existantes restent en `sessionStorage`.

## 4. Socle serveur (`apps/api/src/formation-catalogue.ts`)

Lectures (ADMIN courant, transaction `REPEATABLE READ`, aucune dépendance à `readAll` ni à sa limite de 1 000 entrées) : `GET formations`, `formations/sheet?category=`, `formations/uncategorized-tariffs`, `formations/terms`, `formations/references/{id}`. Les têtes de tarifs passent par `service_product_current`, qui voit aussi les versions masquées à un ADMIN sans `CONFIGURE_CATALOG` ; la fiche signale alors un accès commercial partiel.

Commandes composées, toutes par `schoolCommand` (verrou scolaire, droits relus, opération, audit et reçu dans le même commit, `Idempotency-Key` = `operationId`, réponse 201) :

| Commande | Effet | Concurrence |
|---|---|---|
| `POST formations/programmes` · `UPDATE_FORMATION_PROGRAMME` | Nouvelles versions des seuls contenus modifiés (compétences, règles) puis nouvelle version du parcours qui les référence ; ADMIN. | `expectedOfferingVersionId` comparé à la tête exacte : `FORMATION_CHANGED` (409) ; aucune modification : `FORMATION_UNCHANGED` sans version. |
| `POST formations` · `CREATE_FORMATION` | Compétences, règles, parcours, conditions et premier tarif de leçon ; ADMIN + `CONFIGURE_CATALOG`. Ne touche ni confidentialité, ni informations élèves, ni statut d’école. | `NEW` refusé si le permis a déjà un parcours (`FORMATION_ALREADY_EXISTS`) ; parcours supplémentaire seulement avec `ADDITIONAL_PROGRAMME` et un nom distinct. |
| `POST formations/tariffs` · `SAVE_TARIFF` | Création, ou nouvelle version d’un tarif avec conditions conservées (`KEEP`) ou propres à ce tarif (`NEW`) ; ADMIN + `CONFIGURE_CATALOG`. | `expectedProductVersionId` : `TARIFF_CHANGED` ; `TARIFF_UNCHANGED` sans version. |

Le guide de préparation réutilise désormais les mêmes fonctions d’écriture (`insertCurriculum`, `insertProcedure`, `insertOffering`, `insertTerms`, `insertProduct`) ; son mode `existingOfferingId` reste « ajouter un tarif » et n’est pas employé par la fiche. Les schémas sont publiés dans [`apps/api/contracts/formations.json`](../../apps/api/contracts/formations.json), généré par `apps/api/scripts/generate-formations-contract.ts`. Le BFF autorise ces seules routes (code de permis borné, sans caractère de contrôle).

**Tarifs futurs.** `service_product_current()` choisit la version maximale sans tenir compte de la date ; ce comportement n’est pas présenté comme une programmation tarifaire. La fiche applique une modification dès aujourd’hui (ou dès la date déjà prévue d’un tarif pas encore commencé) ; un nouveau tarif peut commencer plus tard sous sa propre clé. La route historique `POST service-products` refuse désormais une version future sur un tarif déjà applicable (`TARIFF_SCHEDULING_UNSUPPORTED`), ce qui supprime l’intervalle sans tarif. Une version désactivée reste la version courante : aucune ancienne version n’est ressuscitée.

## 5. Client web

`formations.tsx` (aiguillage), `formation-sheet.tsx` (liste, fiche, tarifs, historique), `formation-editors.tsx` (éditeurs contrôlés communs à la fiche et à l’assistant), `formation-wizard.tsx`, `formation-references.tsx` (anciennes adresses, conditions, prestations sans permis), `formation-model.ts` (règles pures testées), `formation-api.ts` (lectures validées), `formations-studio.css`. Une seule commande par intention passe par le magasin de commandes : envoi, résultat incertain, vérification AP72, renvoi de la même opération. Un conflit garde la saisie, propose « Recharger la fiche », puis signale que la version enregistrée entre-temps est affichée avant tout nouvel enregistrement.

`catalog.tsx`, `commerce.tsx` et leurs styles sont retirés après audit : seules la fixture visuelle et la recette les utilisaient. Les anciens types de commande restent déclarés dans `command-core.ts` : une demande en attente restaurée depuis la session doit rester vérifiable. Les routes BFF historiques du catalogue restent autorisées pour la compatibilité ; aucun écran ne les appelle plus.

## 6. Arbitrages hors énoncé, à valider par le porteur

1. Parcours ancien sans prix de référence (`default_price_cents` nul, cas des fixtures G1A) : la fiche ne fabrique pas de prix ; l’enregistrement répond `PROGRAMME_REFERENCE_PRICE_MISSING` et oriente vers l’assistant. Ce prix de référence est recopié, jamais affiché.
2. L’assistant exige un premier tarif de **leçon individuelle** (la planification en a besoin) et donc `CONFIGURE_CATALOG`.
3. Un tarif créé reçoit ses propres conditions ; la réutilisation explicite de conditions d’un autre tarif n’est pas proposée.
4. Changer de rubrique ne pose aucune question (saisie conservée) ; précédent/suivant du navigateur, eux, demandent confirmation pendant une saisie.
5. La liste de permis proposée par l’assistant reprend les catégories suisses courantes ; un autre code reste saisissable. Aucune n’est présentée comme une obligation.

## 7. Résultats exécutés

Localement, sur cette branche, avec PostgreSQL 17 isolée en conteneur (jamais une base d’exploitation) :

- **451 tests API / 38 fichiers**, dont `formations.integration.test.ts` (12 scénarios : lecture agrégée, référence hors première page avec 1 100 versions, programme et inscriptions existantes, bilan existant, nouvelle inscription, aucune version superflue, deux administrations concurrentes, renvoi et reçu AP72, échec injecté par déclencheur avec rollback complet, droits retirés et autre école, prix et conditions partagées, ajout sans réadoption des textes, désactivation, conditions expirées, dates futures, assistant, parcours supplémentaire, élève à deux permis, anciennes références), le guide et la migration peuplée adaptés, SMTP via Mailpit.
- **247 tests web / 22 fichiers**, typages API/web/tests, builds API et web.
- **Recette intégrée : 98 contrôles réussis** navigateur Chromium → Keycloak éphémère → BFF → API → PostgreSQL isolée, sur le build compilé. Après une première leçon réelle : Permis B s’ouvre depuis la liste ; compétences modifiées au clavier, saisie conservée entre rubriques, une seule opération, élève inscrit sur son ancienne version, relecture après rechargement ; tarif ajouté avec réponse perdue après commit puis reçu AP72 (un seul tarif, aucun texte réadopté, école toujours active) ; modification concurrente suivie d’un conflit explicite puis d’une seconde version, réservation existante intacte ; assistant du permis A (proposition à relire, prix jamais prérempli ni remplacé par zéro) ; ancienne adresse d’une version précédente ; précédent/suivant ; 390 px et thème sombre. Ce passage a révélé et fait corriger un débordement des rubriques à 390 px.
- **Revue navigateur sur fixture** (Edge) : 45 scénarios sans échec, dont 7 nouveaux pour la fiche ; 66 captures des 11 vues Formations en clair/sombre à 1440, 1024 et 390 px, sans débordement, sans erreur JavaScript ni violation axe (règles WCAG 2.2 A/AA).

[Captures synthétiques](proofs/formations-tarifs-20261014/index.html).

## 8. Limites

Pas encore exécuté en CI au moment de la rédaction. Non qualifiés : Safari, lecteur d’écran physique, zoom natif à 200 %, recette avec une auto-école. Les résultats axe « incomplets » restent à relire. La fixture visuelle ne prouve ni durabilité ni historique ; ces garanties reposent sur les tests PostgreSQL et la recette intégrée. Aucun déploiement, aucune donnée d’exploitation lue.
