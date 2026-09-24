# Enrichissement V3.3 : UI/UX, iOS 26/27 et préparation Android

> **Historique conservé, non normatif pour la technologie mobile.** La décision Swift de la [V3.4](changements-v3-4.md) remplace les recommandations mobiles antérieures ; les constats et résultats ci-dessous restent ceux de leur version d’origine.
> 19 septembre 2026 · [Index](../README.md). Nouvelle référence documentaire basée sur V3.2. Le code de l’application n’est pas modifié.

<a id="apports"></a>
## Apports de cette version

La recherche externe est intégrée dans huit nouveaux documents substantiels et dans les références existantes. Elle ne remplace pas le produit par une app d’IA : GPS pédagogique central mais facultatif, cours proposés sans inscription automatique, packs, onboarding, tablette et gestion web restent conservés.

| Domaine | Changement concret |
|---|---|
| UI/UX | Six patterns appliqués aux écrans existants, hiérarchie d’action, alternatives accessibles, états cohérents avec le serveur. |
| Qualité et AI slop | Définition sourcée, AS01–AS10, exemples de microcopie, brief pour développeur/agent et procédure de revue. |
| iOS/iPadOS | Couverture de conception 26/27, matrice SDK/OS/outillage, contrôles natifs et Liquid Glass avec repli. |
| GPS natif | Profil Expo distinct des capacités Core Location ; décision sur permission minimale à qualifier, source durable indépendante de la carte. |
| Android | Préparation technique G0, disponibilité différée, FGS/permissions, retour, insets, tablette et binaire 16 Ko. |
| Intégration commune | OIDC système, liens relus sous droits, push non transactionnel, stockage/backup, mises à jour et cycles de vie. |
| Publication | Déclarations de données, binaire réel, suppression globale distincte de l’archive, règles d’achat selon nature de prestation. |
| Validation | 16 exigences MX et 40 cas MOB supplémentaires, tous à exécuter ; registres et contrôles documentaires séparés. |

## Clarifications qui évitent une implémentation contradictoire

**Coins et matériaux.** Les rayons fixes et contrastes opaques du design system restent utilisables pour les composants personnalisés. Ils ne forcent plus à redessiner les contrôles natifs iOS récents, et ne certifient pas les fonds translucides.

**Android futur, préparation immédiate.** « Plus tard » concerne la mise à disposition, pas la première compilation ou la découverte d’une dépendance iOS-only. Le parcours technique minimal doit être éprouvé tôt.

**Capture de fond.** Les exigences du wrapper Expo ne sont pas présentées comme une propriété universelle d’iOS. Une adoption de Core Location natif exige un adaptateur et des essais, pas seulement un changement de libellé de permission.

**Versions.** La disponibilité d’un SDK Apple 27 ne prouve pas la qualification de Drivy. Les règles de soumission Apple/Google ne définissent pas à elles seules l’OS minimum des utilisateurs. Le statut ALPHA d’Expo Maps est signalé comme risque de cœur de produit.

**Fin de compte.** L’archivage scolaire et l’effacement d’un trajet ne satisfont pas par eux-mêmes le parcours de suppression d’identité globale ; la lacune de contrat est explicite.

<a id="decisions"></a>
## Décisions ouvertes, responsables et conditions de sortie

| ID | Décision requise | Proposition / conséquence | Responsable à désigner |
|---|---|---|---|
| DM01 | Minimum commercial iOS/iPadOS et appareils | Qualifier 26 et 27 ; ne promettre chaque cellule qu’après essai. | Produit et responsable mobile |
| DM02 | Couple Expo/RN/Xcode et adaptation native | Version exacte après build ; comparer profil Expo et pont Swift minimal pour GPS. | Responsable mobile |
| DM03 | Fournisseur et wrapper cartographique | Comparer candidates ; ALPHA n’est pas retenu implicitement pour le cœur. | Mobile et exploitation |
| DM04 | Profil Android et date de mise à disposition | Prototype tôt, cible Play à jour, lancement après qualification téléphone/tablette. | Produit et mobile |
| DM05 | Protection de clés/fichiers et sauvegardes | Concilier capture autorisée sous verrouillage et protection ; ne pas promettre restauration de données locales non envoyées. | Mobile et sécurité |
| DM06 | Contrat global de suppression du compte | Workflow décrit ; extension d’identité/API, responsabilités et tests requis avant store public. Les routes scolaires seules ne suffisent pas. | Backend, responsable des données et produit |
| DM07 | Budgets de performance et critères UX | Mesurer sur matériel réel ; approuver seuils avant les utiliser comme gate. | Produit et qualité |
| DM08 | Distribution et modèle économique | Distinguer leçons physiques, contenus numériques et abonnement logiciel ; règles de chaque store à revalider. | Produit et publication |

Une décision non résolue n’est pas convertie en valeur technique au hasard. DM06 est un blocage de publication publique, pas une excuse pour considérer l’archivage comme suppression. Les autres questions produit/juridiques restent dans le [registre général](glossaire-decisions-questions.md).

## Contrats et compatibilité documentaire

Le fichier **OpenAPI reste identique octet pour octet à V3.2** ; son `info.version` 3.2 désigne le contrat hérité, alors que ce dossier a la version 3.3. Les 192 opérations, 344 schémas et T001–T284 ne sont pas augmentés artificiellement pour des précisions de présentation. La clôture globale n’y est pas faussement annoncée comme implémentée.

Les registres MOB/MX sont complémentaires et distincts des métriques M01–M09 et des tests métier T. Les documents historiques et comparaisons V3.1/V3.2 restent datés ; leurs nombres ne sont pas réécrits comme des résultats V3.3.

## Recherche et portée de la vérification

35 entrées S62–S96 documentent les consultations de cette passe ; plusieurs reconsultent des URLs déjà connues. Elles couvrent Apple, Android/Google, Expo, React Native, le projet react-native-maps, W3C, OWASP, IETF, Nielsen Norman Group et Merriam-Webster. Les faits externes sont séparés des recommandations. Les annonces d’un éditeur ne constituent pas un test utilisateur.

Les contrôles courants figurent dans la [revue de cohérence](revue-coherence.md) et les rapports annexes. Ils vérifient liens, références, contrat hérité, registre mobile, cohérence des statuts et rendu du lecteur. Les 109 cas de schéma sont rejoués ; ils ne sont pas 109 tests de l’app. Les 284 scénarios métier et 40 scénarios mobiles restent NOT_EXECUTED.

Aucun build Xcode/Android, essai GPS/batterie, audit d’accessibilité de l’app, enquête utilisateur ou certification de sécurité n’a été effectué. Les tarifs des dix auto-écoles et les règles réglementaires scolaires ne sont pas réétudiés ici. L’absence d’AI slop n’est pas certifiée par un détecteur : la charte fournit des critères de travail à appliquer à l’implémentation.

## Utiliser la référence

Commencer par la [recherche](../01-recherche/ui-ux-mobile-etat-art.md), puis [iOS/iPadOS](../04-technique/integration-ios-ipados.md), [Android](../04-technique/preparation-android.md) et [qualité](../02-experience/qualite-ui-ux-anti-slop.md). La [qualification](../05-realisation/qualification-mobile-ui-ux.md) définit les preuves suivantes. Toutes les autres fonctions restent consultables dans le lecteur intégré ; aucun addendum concurrent n’est à assembler.

## Ajustement des tokens

Une ambiguïté supplémentaire a été corrigée : la V3.2 portait une cible générique 48 et des minima par plateforme 44/48 sans séparer clairement leurs usages. La V3.3 conserve les minima tactiles personnalisés iOS/web 44 et Android 48, et réserve 48 au minimum visé pour les commandes principales/critiques. La clé générique ambiguë est retirée ; ces valeurs sont des propositions Drivy, pas une nouvelle norme de plateforme.
