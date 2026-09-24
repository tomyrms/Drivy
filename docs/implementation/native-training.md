# Dossier de formation natif

Le dossier élève ouvre maintenant une formation réelle et ses trois lectures : leçons, bilans partagés et parcours pédagogique. Les maquettes de référence sont `04_dossier`, `14_mes_lecons` et `16_parcours` dans le répertoire de conception immuable.

## Parcours livrés

- AP22/AP24 : liste du dossier et détail de la formation sous les droits courants.
- AP39 avec `trainingId` : rendez-vous et historique, pagination explicite.
- AP55/AP56 : bilans publiés, versions conservées et motif de correction lorsqu’il existe.
- AP58 : appréciation par compétence, date, contexte et lien vers le bilan source. Les compétences non observées viennent du référentiel lié à l’offre de cette formation. Aucun score global.
- Le suivi opérationnel d’une leçon rejoint le module existant de préparation, souhait et bilan. La consultation du dossier ne charge jamais ses notes privées. ADMIN seul ne déclenche aucune lecture pédagogique.
- AP23 : création avec choix explicite d’une offre actuelle, activée et approuvée, date de début facultative puis relecture. ADMIN et INSTRUCTOR déjà autorisé sur l’élève peuvent ouvrir ce formulaire. AP07, réservé à ADMIN, n’est pas sollicité dans ce parcours moniteur.

Les générations de requêtes empêchent une réponse ancienne de remplacer le contexte courant. La navigation se reconstruit lors d’un changement de personne, d’école, d’époque d’accès ou de rôles. Les erreurs de droits purgent les projections concernées. Aucun document, permis, compte, élève ou rendez-vous synthétique n’est créé par ces vues.

## Création par un moniteur : reçu et affectation distincts

AP23 ne crée **aucune affectation**. Le formulaire indique avant confirmation que l’administration affectera ensuite le moniteur à la nouvelle formation. Une réponse 201 décodée et vérifiée constitue la confirmation directe de création ; l’application n’exige pas un AP24 réussi pour reconnaître cet effet.

Si cette réponse est perdue, l’outbox chiffrée conserve les octets, la clé d’opération et le contexte de la demande. La vérification AP72 recherche le reçu correspondant. Le renvoi réutilise exactement la même demande, après une nouvelle barrière de durabilité. Une demande reprise n’est jamais effacée à cause d’un simple 4xx. Un changement de contexte interdit son renvoi et conserve sa référence.

La portée réelle des deux lectures diffère :

- AP24 applique `visibleTraining` dans `queries.ts` : le moniteur doit être affecté à cette formation précise.
- AP72 filtre l’auteur de l’opération et exige encore ses droits scolaires. Pour `CREATE_TRAINING`, la jointure avec le profil élève contrôle le dossier sous RLS ; elle n’applique pas `visibleTraining` à la nouvelle formation. L’affectation existante sur une autre formation de cet élève maintient cet accès au dossier. Le reçu ne contient que les six champs de `OperationResult`.
- Une perte réelle des droits sur le dossier peut rendre AP72 inaccessible ; 404 ne permet alors aucune conclusion. La demande reste conservée. Cette situation ne découle pas normalement de la seule création d’une formation non encore affectée.

## Vérification bornée

Une recette métier locale a exercé les routes actuelles avec PostgreSQL 17, migrations 001 à 007, JWT de recette signés et vérifiés, et rôle runtime `drivy_app` sans privilège superutilisateur ni contournement RLS. Elle n’utilise pas Keycloak ni les données hébergées.

| Vérification | Résultat |
| --- | --- |
| AP23 par moniteur déjà affecté à l’élève, offre distincte | 201 |
| AP72 par cet auteur avant toute nouvelle affectation | 200, six champs canoniques uniquement |
| AP24 sur la nouvelle formation par ce moniteur | 404 |
| Rejeu AP23 avec les mêmes octets et la même clé | 201, même identifiant |
| AP72 demandé par un autre moniteur | 404 |
| Effets conservés | Une formation, zéro affectation |

La base dédiée `drivy_training_receipt_test` et le rôle migrateur temporaire ont été supprimés après la recette. Le script et le journal locaux sont dans `artifacts/check-training-receipt.mts` et `artifacts/check-training-receipt.log` ; ils ne sont pas livrés dans l’application. Aucune campagne de tests supplémentaire n’a été lancée.

Le lot natif initial est le commit `b40c877`, compilé avec succès dans l’IPA 0.7.0/build21, source`394d4cd`, run`36054482531`. Les finitions visuelles suivantes et l’indépendance de la navigation des bilans vis-à-vis d’AP58 attendent leur compilation d’intégration ; aucune qualification physique n’est déduite de ces builds.
