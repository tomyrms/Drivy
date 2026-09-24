# Web, tablettes et accueil : fondements et limites de preuve

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; choix détaillés proposés, à valider. [Index](../README.md).

## Origine de cette révision

**Demandé par le porteur :** un espace web de gestion détaillée, les statistiques utiles, la gestion et l’archivage des élèves, la tablette comme support de premier plan pour le GPS et le reste de l’app, et un onboarding cohérent pour élèves, moniteurs et écoles. L’orthographe de référence reste **Drivy**.

**Hypothèse, pas résultat d’enquête :** « les moniteurs utilisent beaucoup de tablettes ». Aucun taux d’équipement ni entretien supplémentaire n’est disponible. Nous concevons pour ce besoin explicite sans le transformer en statistique sur les écoles suisses.

Le [relevé des dix écoles](auto-ecoles-suisses.md) reste la base des variantes commerciales. Il n’a pas été remplacé par des hypothèses de marché. Ses offres conservent leur date et leurs limites de vérification ; cette révision n’est pas une nouvelle enquête tarifaire.

## Observations externes effectivement consultées

| Référence | Ce que la source établit | Traduction proposée pour Drivy, distincte du constat |
|---|---|---|
| [S48](../06-gouvernance/sources.md#s48), Apple, fiche iPad Air | La rubrique Localisation sépare tous les modèles des modèles Wi-Fi + Cellular ; GPS/GNSS figure dans le second groupe. | Ne pas promettre une capture autonome précise sur toute tablette ; qualifier chaque modèle et séparer compatibilité app et capture. |
| [S49](../06-gouvernance/sources.md#s49), Android, applications adaptatives | L’interface dépend de la fenêtre disponible et doit préserver la continuité quand sa taille change ; panneaux et entrées clavier/pointeur sont documentés. | Une tablette n’est pas un téléphone agrandi. Carte + panneau en largeur suffisante ; retour à un panneau sans perdre la séance. |
| [S50](../06-gouvernance/sources.md#s50), W3C, Orientation | Le contenu ne doit pas imposer une orientation sauf caractère essentiel de celle-ci. | Aucun verrou paysage global : le moniteur garde accès à la séance en portrait et dans une fenêtre réduite. |
| [S51](../06-gouvernance/sources.md#s51), W3C, Reflow | La redistribution du contenu évite une navigation bidimensionnelle générale ; certaines représentations intrinsèquement bidimensionnelles ont une exception. | Le tableau peut défiler dans son conteneur, pas toute la page ; le formulaire reste lisible en zoom et la carte a une alternative textuelle. |
| [S52](../06-gouvernance/sources.md#s52), W3C, Redundant Entry | Dans un même processus, les données déjà fournies doivent être disponibles sans nouvelle saisie, sauf exceptions prévues. | Reprendre un onboarding dans l’autre interface et proposer les valeurs déjà connues sans recopier automatiquement les données d’une autre école. |
| [S53](../06-gouvernance/sources.md#s53), W3C, formulaires multi-pages | Découpage logique, indication de progression et information sur les étapes. | Quelques étapes par objectif, sauvegarde explicite et liens Retour ; pas un formulaire administratif géant. |
| [S54](../06-gouvernance/sources.md#s54), W3C, taille des cibles | Le critère de minimum web et ses exceptions sont explicités. | Cibles Drivy volontairement plus grandes pour les gestes de séance ; minimum normatif web et cible ergonomique produit restent distincts. |
| [S55](../06-gouvernance/sources.md#s55), OWASP, autorisation | Moindre privilège, refus par défaut et vérification de chaque requête. | Se connecter au web ne donne pas davantage de droits ; un accès aux statistiques ne donne pas accès aux traces GPS. |
| [S56](../06-gouvernance/sources.md#s56), OWASP, sessions | Les protections des sessions et cookies sont traitées. | Session web via BFF, pas de jeton durable dans localStorage ni dossier élève dans un cache hors ligne web. |
| [S57](../06-gouvernance/sources.md#s57), OWASP, CSV Injection | Du texte exporté peut être interprété comme formule par un tableur. | Les exports de gestion protègent les cellules textuelles et restent limités à une portée autorisée. |
| [S58](../06-gouvernance/sources.md#s58), React | Une application construite avec un outil tel que Vite doit aussi prendre en charge routage, données et autres besoins applicatifs. | React DOM pour les tableaux du web est un choix d’équipe proposé, pas une architecture complète fournie automatiquement. |
| [S99](../06-gouvernance/sources.md#s99), Apple, Core Location, consulté en V3.4 | La collecte de fond utilise des sessions et déclarations natives explicites. | Prototype Swift sur téléphone **et** tablette, avec verrouillage et stockage, avant promesse de fiabilité. |
| [S47](../06-gouvernance/sources.md#s47), PFPDT, information, reconsulté en V3 | Finalités et destinataires font partie de l’information sur la collecte. | Justifier chaque champ et expliquer le GPS séparément. La politique détaillée des données est une proposition, pas une certification juridique. |

Les recommandations de composition et les seuils d’interface sont des choix de Drivy. Ni W3C, ni Apple, ni Android ne valident l’efficacité de cette application. La documentation Android sert ici de référence de comportement, pas de preuve que le futur client Android ou le client Swift l’implémente déjà.

## Recherche ciblée, pas étude de terrain inventée

Les sources nouvelles sont des pages primaires de constructeurs, de standards et de sécurité. La page Apple HIG Layout n’a renvoyé qu’un écran exigeant JavaScript ; elle n’est pas utilisée comme preuve substantielle. Des recherches générales ont renvoyé des résultats non pertinents ; ils ont été exclus. Les pages officielles accessibles ont été ouvertes directement. Aucune interface commerciale protégée, aucun navigateur d’une école ni aucune tablette de moniteur n’ont été testés.

La décision de prévoir le web et la tablette vient du porteur. Les sources aident à en préciser les contraintes. Le choix d’un onboarding progressif est une recommandation de conception, non une conclusion d’une étude de conversion.

## Points à observer au pilote

Mesurer qualitativement la préparation d’une séance sur tablette, la lecture du bilan avec l’élève, la gestion d’une série collective au clavier et l’archivage d’un dossier sans perdre son historique. Tester le même onboarding commencé sur le web et poursuivi dans l’app, avec refus GPS et photo absente.

Relever les modèles d’appareils, types de connexion et usages réels avec l’accord des participants. Distinguer matériel sans récepteur adapté, permission refusée, réseau absent et app interrompue. Aucun test ne doit enregistrer un élève à son insu.

Le succès attendu est une tâche accomplie correctement et comprise, pas un taux maximal d’autorisation GPS, de photo ajoutée ou de données personnelles renseignées.
