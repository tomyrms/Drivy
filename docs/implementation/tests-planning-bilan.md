# Filet de tests PostgreSQL — planning, prestations et bilan

Tranche du 25 septembre 2026 (plan P0-1 a/b). Elle couvre par des tests d’intégration réels du code déjà déployé et jusqu’ici non testé : AP31–AP37, AP39–AP43, AP100/AP101 et l’extension `commercial-terms`, AP45–AP49, AP52–AP56, AP58, AP65, ainsi que l’extension de reprise `report-drafts` et AP177 `PLAN_LESSON`.

## Mise en place commune

`apps/api/test/support/harness.ts` (pas un fichier de test) :

- recrée le schéma `drivy` de la base `drivy_test`, applique **toutes** les migrations (`001`–`011`) sous un propriétaire NOSUPERUSER/NOBYPASSRLS, insère les fixtures synthétiques existantes (`scripts/fixtures.ts`) ;
- construit l’API avec des JWT signés par une clé éphémère locale ; chaque requête métier s’exécute sous `drivy_app` avec RLS forcée ;
- prépare un contexte scolaire synthétique (procédure et référentiel approuvés, politique de champs publiée, notice adoptée), puis crée conditions commerciales, prestation et ouverture **par les routes réelles** ; les leçons sont créées par AP40, jamais en SQL. Seul `moveToPast` décale une leçon déjà créée dans le passé, pour éprouver AP44/AP50 sans horloge simulée ;
- `expectContract` valide la réponse complète (enveloppe comprise) contre le schéma canonique d’OpenAPI 3.11.0, sans le modifier.

Les tests capture existants appliquent désormais aussi `010`/`011` (sinon la projection de leçon, qui relit le contrôle de permis, n’existerait pas) ; leur contrôle RLS attend 44 tables protégées.

## Couverture

| Fichier | Parcours | Contrôles principaux |
|---|---|---|
| `lessons.integration.test.ts` | Conditions et prestations | grant `CONFIGURE_CATALOG` exigé même pour ADMIN, brouillon invisible sans grant, rejeu et `IDEMPOTENCY_MISMATCH`, conditions non approuvées, site non configuré, prestation incomplète, autre école |
| | Ouvertures et fermetures | moniteur sur soi seulement, ADMIN sur tous, élève refusé, If-Match 428/412, moniteur immuable, retrait idempotent, fermeture invalide, AP72 |
| | Leçons AP39–AP43 | création via AP40 (concurrente et rejouée : un seul audit), fuseau, créneau passé, prix, procédure changée, ENTITLEMENT, chevauchement élève et tampon moniteur (`SLOT_CONFLICT`), fermeture bloquée par rendez-vous et bloquant un créneau, déplacement (428/412, accord, changement de durée), annulation rejouée puis `LESSON_CLOSED`, événements outbox, lecture élève/autre élève/autre moniteur/autre école, affectation retirée, pagination et curseur lié à la personne, AP72 |
| | AP177 | `PLAN_LESSON` prêt, `INSTRUCTOR_NOT_ASSIGNED`, `PLANNING_ACCESS_REQUIRED` |
| `lesson-reports.integration.test.ts` | Préparation et souhait AP45–AP48 | brouillon privé du moniteur (ADMIN, élève, autre moniteur : 404 ; non-membre : 403), référentiel, limites, 428/412, rejeu, repères conservés/vidés, souhait écrit par l’élève seul, leçon close |
| | Constat, bilan, progression, compte | anomalie requise sans permis, intervalle réel, ADMIN seul refusé, constat concurrent rejoué avec une seule charge, compte lisible par ADMIN/élève/moniteur de la leçon, reprise du brouillon, pièces et sélections non livrées refusées, conflit de publication, publication rejouée, lecture élève et moniteur nouvellement affecté, ADMIN seul exclu, progression, correction motivée et révision précédente immuable, affectation retirée, révision non modifiable par le runtime, ENTITLEMENT sans effet partiel |
| `lesson-outcomes.integration.test.ts` | Santé, permis, AP44/AP50/AP57/AP88 | voir [g2-permis.md](g2-permis.md) et [g2-issues-lecon.md](g2-issues-lecon.md) |

## Défaut trouvé et corrigé

AP48 avec `lessonId` renvoyait 404 à l’élève : la leçon était relue `FOR UPDATE`, ce qui exige un droit de modification qu’il n’a pas. La lecture n’est plus verrouillée (le verrou d’école sérialise les changements de résultat).

## Limites

- Les tests tournent sur PostgreSQL 16 local ; PostgreSQL 17 n’a pas été relancé pour cette tranche.
- La CI ne lance toujours les tests d’intégration que sur `workflow_dispatch` (P0-1 c non traité : `.github/` hors périmètre).
- Aucune qualification native, web ou déployée n’est déduite de ces tests.
