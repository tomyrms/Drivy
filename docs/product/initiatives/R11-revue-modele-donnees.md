# R11 — Revue complète du modèle de données avant production

## Intention

Quand le périmètre fonctionnel de Drivy sera quasiment complet et stabilisé, effectuer une **revue complète du modèle de données** avant la mise en production durable.

L’objectif est de vérifier que la structure de données finale reste cohérente avec l’ensemble des fonctionnalités réellement livrées et qu’elle ne conserve pas des choix devenus fragiles, redondants ou difficiles à faire évoluer.

## Revue attendue

Examiner notamment :

- tables, relations, cardinalités, contraintes, clés et index ;
- séparation des écoles et isolation multi-tenant ;
- modèles de permissions et rattachements utilisateur/école ;
- historique, versionnement, archivage et suppressions ;
- données dérivées, duplications et sources de vérité ;
- cohérence entre leçons, formations, cours, élèves, moniteurs, finances, messagerie et autres modules livrés ;
- intégrité transactionnelle, concurrence, idempotence et migrations ;
- données personnelles, durées de conservation et minimisation ;
- performances des lectures/écritures importantes sur un volume représentatif ;
- champs devenus obsolètes, ambiguïtés, dette de migration et risques de bugs liés au schéma.

## Résultat attendu

Produire un état clair :

- ce qui est sain et peut rester tel quel ;
- ce qui doit être corrigé avant production ;
- ce qui peut être simplifié ou normalisé ;
- ce qui mérite au contraire d’être dénormalisé pour des raisons mesurées ;
- les migrations nécessaires, leur risque et leur stratégie de retour arrière ;
- les invariants qui doivent être protégés par contraintes et tests.

Ne pas refaire le modèle de données pour le principe. Toute modification doit partir d’un problème démontré ou d’un risque concret, avec un plan de migration vérifiable.

## Moment de lancement

À lancer **après stabilisation des fonctionnalités principales et avant la production durable**, lorsque le modèle réel de l’application est suffisamment complet pour qu’une revue globale soit pertinente.

Aucune issue de développement n’est créée automatiquement depuis cette fiche.
