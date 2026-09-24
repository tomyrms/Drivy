# Revue corrective de la version 3.13

> Drivy · Référence de conception 3.13 · 20 septembre 2026

Cette passe corrige une erreur de marque introduite dans la version précédente et poursuit la consolidation sans modifier le contrat HTTP ni prétendre exécuter l’application.

## Résumé

V3.13 rétablit **Drivy** (D-R-I-V-Y) comme nom unique du produit, retire la variante erronée de la référence courante et transforme le registre des 101 libellés de modèle en une aide de contrôle plutôt qu’en un plan implicite de 101 tables. Elle ajoute une **Definition of Ready** pour G1/G2 et un profil d’implémentation par tranches verticales.

Le contrat OpenAPI reste **3.11.0**, avec 201 opérations et 376 schémas : cette passe n’ajoute aucune route ni aucun schéma métier. Les 422 scénarios métier et 68 scénarios mobiles restent `NOT_EXECUTED` sur le produit.

## Corrections de référence

### C313-01 · Marque officielle

Le nom officiel et visible est **Drivy**, sans E. Les titres, textes, lecteur, maquettes, scripts courants, environnement d’audit et nom de l’archive utilisent cette orthographe. Les identifiants techniques `drivy` sont déjà cohérents et ne demandent pas de migration cosmétique.

### C313-02 · Registre de modèle ≠ schéma physique

Le registre conserve ses concepts pour la traçabilité, mais précise désormais qu’une ligne n’autorise pas la création automatique d’une table, collection, endpoint ou écran. Les projections, DTO, sous-objets et états calculés restent dérivés ou embarqués jusqu’à ce qu’un cycle de vie, une contrainte, une rétention, une concurrence, une cardinalité ou une mesure justifie leur séparation.

### C313-03 · Tranches G1/G2 démontrables

G1/G2 est découpé en G1A accès/école, G1B configuration minimale, G2A leçon sans GPS, G2B capture/observation live et G2C continuité. Ce découpage ne réduit pas le périmètre produit final : il empêche seulement de construire horizontalement toutes les couches avant qu’un parcours puisse être démontré.

### C313-04 · Definition of Ready

Une tranche n’est `READY` que si action/utilisateur, source de vérité, échec/concurrence, persistance minimale, contrat/UI et preuve attendue sont identifiés. Une spécification volumineuse ne suffit pas. La Definition of Done existante reste inchangée dans son principe et complète cette entrée.

### C313-05 · Critères de séparation physique

Toute nouvelle persistance indépendante doit défendre au moins une raison concrète : cycle/autorisation, contrainte de stockage, concurrence/idempotence, rétention/purge, cardinalité, volume/indexation ou preuve de performance. Avant migration, elle doit être rattachée à une commande, une lecture, un invariant, une politique de données et un scénario de preuve.

<a id="decisions"></a>
## Décisions maintenues

- refonte assumée ;
- Swift natif pour iPhone/iPad, Android futur distinct ;
- direction A « Cartographie native » ;
- GPS central mais facultatif ;
- observation pédagogique possible pendant la leçon, sans publication automatique ;
- documentation détaillée conservée, mais implémentation progressive et anti-surmodélisation ;
- aucune réussite documentaire ne vaut test produit.

## Ce que V3.13 ne prouve pas

V3.13 n’exécute aucun build Swift, trajet GPS, base PostgreSQL, stockage objet, APNs, entretien utilisateur, audit juridique ou test de sécurité en circulation. Les propositions de regroupement physique sont un profil d’implémentation à confronter au code et aux contraintes réelles ; elles ne sont pas des migrations déjà validées.
