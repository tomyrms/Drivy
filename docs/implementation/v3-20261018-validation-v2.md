# V3 : validation préalable de V2

Date : 18 octobre 2026. Base V1 `7c117cd`, V2 `6fe4656`, branche de travail `audit/validation-v3-20261018`.

## Périmètre exact

Les cinq commits V2 sont `74038b3` (step-up lié au sujet initial), `131fb5a` (erreur et reprise de lecture du consentement GPS), `00b6521` (recette intégrée), `a6c2043` (rapport), `6fe4656` (traçabilité). Diff V1..V2 : 11 fichiers, 531 insertions, 8 suppressions. Aucun changement natif iOS.

## Résultats exécutés avant les changements produit V3

| Exigence | Contrôle | Observation |
|---|---|---|
| Runtime contractuel | Node portable officiel, SHA256 vérifié, installations verrouillées root/web/infra séparées | Node v24.22.0, pas de changement du runtime global |
| API | typecheck, suite complète sur PostgreSQL local, build TypeScript | 37 fichiers, 447 tests réussis, compilation réussie |
| Web | typecheck client/serveur, suite complète, build Vite et serveur | 236 tests réussis, compilation réussie |
| V1/V2 interactions | scripts check-audit-regressions, check-audit-v2-regressions, check-web-redesign | 5 + 5 + 41 scénarios réussis. React réel, transport synthétique uniquement |
| Intégration publique | check-school-opening --skip-account-recovery --audit-v2 | 82 contrôles réussis, Edge vers Keycloak, BFF, API, PostgreSQL et Mailpit réels sur loopback, identités de test |
| Step-up V2 | tests BFF et recette audit-v2 | Refus du changement de sujet, session initiale préservée, sujet interne non exposé |
| Consentement GPS V2 | tests navigateur et recette intégrée | Échec explicite, reprise et reconnexion, aucun consentement inventé, refus de permission sans divulgation |
| iOS | Inspection ciblée des contrats et tests présents | Aucune exécution native, aucun appareil ni runner Apple accessible dans cette session |

Archive : `artifacts/v3-20261018/`, journaux des tâches `1522787quf`, `160286fwtl`, `193710udwr`. La recette intégrée utilise des données synthétiques mais de vrais services. Elle ne qualifie ni le GPS physique ni la production. La récupération de mot de passe est exclue.

## Incident d'environnement

La première suite API a été interrompue par la disparition de modules partagés. Un agent avait lancé npm ci via une jonction pointant finalement vers les dépendances du dépôt initial. Ce n'est pas une régression produit ni une preuve d'incompatibilité Node24. Les jonctions du coordinateur ont été retirées, puis trois installations locales indépendantes ont été réalisées. La suite complète propre a ensuite réussi. Les dépendances manquantes du dépôt initial sont restaurées sans suppression ni modification de ses fichiers suivis, après vérification de l'identité des package.json et lockfile.

## Verdict

**V2 prête sous conditions pour fusion**, sur le périmètre web/API qualifié sous Node24. Aucune régression V2 confirmée par ces contrôles. L'absence de régression n'est pas garantie par des tests verts. Une livraison iOS complète reste conditionnée à la recette Apple, et toute fusion exige l'accord explicite du propriétaire. Rien n'est fusionné ni déployé.
