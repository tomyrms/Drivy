# Préparation web : contrat de réalisation

Tranche du 13 octobre 2026, issue du plan validé. Le canon OpenAPI 3.11.0 et le dossier de conception restent inchangés. La migration 030 ajoute le brouillon au propriétaire `school_setup` ; aucun GET ne crée de données.

## Droit d’ouverture avant l’existence de l’école

Les validations de réalisation résident dans `src/school-opening-model.ts` ; la migration029 crée `school_opening_link`. `SCHOOL_OPENING_OPERATORS_JSON` autorise des couples OIDC issuer/subject exacts ; un ADMIN scolaire n’obtient pas ce privilège.

| Route | Contrat |
|---|---|
| GET `/v1/operator/school-opening-links` | Liste bornée de droits, état/date uniquement ; jamais de secret ni de données de l’école créée. |
| POST `/v1/operator/school-opening-links` | `{operationId,token}` ; token aléatoire de 32 octets généré par le BFF, empreinte SHA256 en base, identifiants école/membership réservés, validité de sept jours configurable. |
| POST `/v1/operator/school-opening-links/{id}/revoke` | `{operationId}` ; révocation durable d’un droit encore disponible. |
| POST `/v1/school-openings/preview` | `{token}` ; aperçu authentifié, aucune consommation. Un autre compte ne reçoit pas l’identité de l’école d’un lien utilisé. |
| POST `/v1/school-openings` | `{operationId,token,schoolName,displayName,contactEmail,contactPhone,timeZone,instructs}` ; confirmation atomique sous verrou du lien et de l’identité OIDC. |
| GET `/v1/school-openings/operations/{operationId}` | Reçu lié au principal exact avec droits relus, même après perte de la session BFF. |

Les commandes exigent la concordance `Idempotency-Key`/`operationId`. Un rejeu de consommation identique retrouve le résultat ; un corps différent sous la même opération reçoit409. Si le lien USED est revisité par son consommateur avec une **nouvelle** opération, la réponse constitue une récupération : elle porte l’opération d’origine et ignore les nouveaux champs. Le BFF traite ce cas explicitement. Un autre principal ne récupère pas le résultat. Un rejeu de révocation avec le même UUID et le même lien retourne le reçu ; réutiliser cet UUID pour un autre lien ou lancer une nouvelle révocation d’un lien déjà révoqué reçoit409.

Le BFF garde en mémoire le secret et l’intention avant envoi, les retire de l’URL avant OIDC, puis relit le reçu en cas de réponse perdue. Une école existante se retrouve depuis le compte, sans réutiliser le secret. Les coordonnées sont limitées comme celles du guide (téléphone de 32 caractères, fuseau nommé accepté par les règles scolaires). Les jetons OAuth restent dans le BFF.

## Routes du guide

Toutes les routes sont sous `/v1/schools/{schoolId}/setup-draft`, réservées à un ADMIN courant. Les réponses privées utilisent `no-store` et l’enveloppe habituelle.

| Route | Résultat |
|---|---|
| GET base | Brouillon, version propre, étape, auteur/date, contenu et statut DRAFT/APPLIED. Sans saisie, projection des coordonnées/textes/champs déjà en vigueur. |
| PUT base | `{operationId,currentStep,content}` ; sauvegarde partielle versionnée, sans adoption. |
| GET `/templates` | Bases pédagogiques A/A1/B/BE, politique minimale de champs, structures de confidentialité, d’annulation et de conditions commerciales à compléter. Aucun tarif et aucune affirmation réglementaire. |
| GET `/preview?activate=true\|false` | Contenu exact, sections sélectionnées, versions école/configuration/brouillon, digest de revue, erreurs de champs et effets de l’adoption. Paramètre explicite obligatoire. |
| POST `/complete` | `{operationId,expectedSchoolVersion,expectedConfigurationVersion,reviewDigest,reviewAcknowledged:true,activate}` ; application atomique de la sélection. |
| GET `/next-actions` | Prochaines actions et `planningReady`, qui indique seulement la préparation structurelle de l’école. Aucun créneau ni autorisation de conduite n’est garanti. |

Les écritures exigent `Idempotency-Key` égal à `operationId` et `If-Match` de la version du brouillon. `SAVE_SCHOOL_SETUP_DRAFT` et `APPLY_SCHOOL_SETUP_DRAFT` utilisent la ressource `SchoolSetupDraft`, identifiant scolaire, avec reçu AP72. Le résultat d’application possède `id`, `schoolId`, `version`, `draft`, `school` et les identifiants des versions appliquées. Un renvoi conserve l’intention et les octets ; une autre opération ne sert pas à résoudre une réponse perdue.

## Contenu et application

Le contenu borne quatre sections sélectionnables : IDENTITY, PRIVACY, PROFILE, CATALOGUE. Elles contiennent les coordonnées ; les textes et leur provenance ; les champs autorisés et date d’effet ; au plus douze formations avec programme, déroulement, annulation, conditions, durée, prix en centimes et date d’effet. Les schémas exacts sont dans `apps/api/contracts/school-setup-draft.json`, générés par `scripts/generate-school-setup-contract.ts` depuis les validations de réalisation.

Une formation `apply:false` est reportée et conservée dans le brouillon. `priceCents:null` ne devient jamais zéro. Une formation sélectionnée sans prix, durée, conditions, programme ou procédure complets bloque l’application. `existingOfferingId` permet d’ajouter un tarif à une offre active de la même école/catégorie sans modifier ses références pédagogiques. Son annulation reste celle de la formation : un texte non vide dans le brouillon est refusé par `SETUP_INHERITED_CANCELLATION`, pour éviter une adoption apparente d’un texte ignoré. Les clés internes sont dérivées de l’UUID du brouillon de formation ; une formation déjà appliquée ne se recrée pas à l’identique sous une nouvelle opération.

La sauvegarde conserve les explications encore vides et une durée temporaire nulle ou égale à zéro. La revue exige les règles complètes et une durée de 1 à 480 minutes. Les exemples commerciaux laissent délais, modalités et éventuels frais sous forme de `[à compléter : …]` ; ces emplacements bloquent l’application jusqu’à leur remplacement.

L’application relit les droits, versions, modèles et références sous le verrou scolaire. L’autorisation commerciale `CONFIGURE_CATALOG` reste requise pour les prestations. L’adoption de la notice conserve ses textes exacts, son auteur et l’instant serveur. La politique de champs est liée à cette notice ; une date future ne devient pas applicable aujourd’hui. Les mêmes validations de champs, programme et procédure que les routes métier sont réutilisées. La confirmation ne crée ni élève, ni leçon, ni accord GPS.

L’identité, les versions de confidentialité/profil/catalogue/conditions/prestations, la transition ACTIVE, le reçu et l’audit partagent un commit. Un échec conserve le brouillon et annule tous les changements actifs de cette commande. Les objets reportés ne bloquent pas l’activation minimale. Pour une école déjà ACTIVE, `activate:false` applique seulement les sections sélectionnées et préserve les autres données. La nouvelle adoption d’une notice conserve l’effet actuel de révocation des captures autorisées ; la revue l’annonce.

APPLIED ne supprime pas le brouillon : contenu et formations reportées restent disponibles. Un nouveau PUT crée une nouvelle version DRAFT. La maintenance doit sélectionner uniquement les sections voulues ; elle ne doit pas réadopter les anciens textes pour ajouter un tarif.

## Prochaines actions et preuves

Les actions réutilisent la readiness scolaire et les règles réelles du profil/formation/affectation. Les actions de premier usage sont supprimées dès qu’une leçon existe, y compris annulée ; les blocages structurels courants restent affichables. Une invitation en attente n’est pas présentée comme acceptée. La dernière action indique de planifier dans l’app Drivy et vise le dossier de l’élève pour sa consultation web. Les projections renvoient des identifiants autorisés, jamais les valeurs personnelles du dossier.

`school-onboarding-migration.integration.test.ts` prépare une base synthétique au niveau 028, avec écoles ACTIVE/DRAFT, textes et catalogue, puis applique le migrateur 029/030. Il compare toutes les lignes historiques, les reçus et les anciens checksums, vérifie l’entrée existante et les lectures de brouillon sans écriture, puis réexécute les migrations pour contrôler leur absence d’effet supplémentaire. Ce test ne lit aucune base d’exploitation.

`school-onboarding.integration.test.ts` couvre reprise, séparation lecture/sauvegarde/adoption, droits et écoles, concurrence/idempotence, prix absent, placeholder/modèle, rollback après écriture de la notice et du programme, maintenance d’une école active sans doublonner les tarifs, politique future et prochaines actions.

Le [run CI 38403370545](https://github.com/tomyrms/Drivy/actions/runs/38403370545), commit `22650ba`, est réussi : 424 tests API dans 36 fichiers, dont les 10 scénarios de préparation, les 14 scénarios d’ouverture et le test de migration peuplée 028→029/030 ; les suites métier utilisent PostgreSQL 17 réel. Il valide aussi 217 tests web, les builds/typechecks API et web et l’intégrité documentaire. La recette navigateur intégrée et les preuves Apple sont consignées dans [le bilan de réalisation](realisation-onboarding-ecole-20261013.md).

Localement, les 127 tests unitaires API ciblés, le typecheck et la compilation API ont réussi ; les modifications suivantes ont repassé le typecheck avant leur qualification complète en CI. Docker local était indisponible : aucune exécution PostgreSQL locale n’est revendiquée. La migration est vérifiée sur des données synthétiques, sans restauration d’une sauvegarde d’exploitation. Ces résultats ne constituent ni un déploiement, ni une validation juridique des textes d’une école, ni un test physique de GPS, de batterie ou de VoiceOver.
