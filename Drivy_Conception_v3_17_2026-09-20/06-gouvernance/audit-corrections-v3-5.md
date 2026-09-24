# Revue complète et compléments : Drivy V3.4 vers V3.5

> 19 septembre 2026 · [Index](../README.md) · [Liste des fonctions](../01-fonctionnalites-prevues.md). Dossier de conception uniquement, aucun code modifié ou build exécuté.

<a id="apports"></a>
## Résultat et méthode

Cette version remplace la V3.4. La revue part du ZIP complet, pas uniquement des extraits visibles dans la conversation. Les contrôles transversaux parcourent tous les Markdown et le contrat ; la lecture sémantique croise périmètre, consentement, préparation, cours, identité, finance, archivage, API, données, écrans et roadmap. Elle ne constitue pas une preuve exhaustive de toutes les propriétés possibles du système.

Le contrôleur antérieur passait sur la V3.4. Des incohérences subsistaient donc malgré ses tests de liens et schémas : [résultat avant correction](../annexes/controle-v3-4-avant-correction.json). Les sources commerciales des dix écoles restent datées ; elles n’ont pas été toutes reconsultées. La reconsultation externe de cette passe est ciblée sur Apple/Xcode et la suppression de compte, pas une nouvelle étude UI/UX ou réglementaire scolaire.

Les 11 ensembles ci-dessous comprennent des contradictions corrigées, des précisions de règles et le complément d’un manque déjà connu. Ce ne sont pas 11 dysfonctionnements reproduits dans l’ancienne application. Les propositions ajoutées pour lever un manque sont indiquées ; aucun choix métier n’est présenté comme approuvé par une école sans preuve.

## Constats, corrections et vérification à réaliser

| ID | Constat source V3.4 | Correction intégrée V3.5 | Nature / preuve attendue |
|---|---|---|---|
| V35-01 | Une clause API demandait encore If-Match "0" pour la première présence, en contradiction avec R11 et les corrections V3.2 | Clause alignée sur If-None-Match: * puis ETag réel ; contrôle lexical ajouté | Contradiction documentaire ; T285 |
| V35-02 | Design system promettait un accent scolaire configurable alors que F13 et le modèle le refusaient au pilote | Nom/logo/contact conservés ; palette Drivy commune, personnalisation d’accent différée explicitement | Arbitrage conservateur sans ajout artificiel de thème ; T297 |
| V35-03 | U02 disait que les points manuels étaient possibles au cœur, mais Preparation ne les représentait pas | PlannedWaypoint, liste versionnée, bornes et privacy ; distinction de la trace mesurée | Fonction annoncée complétée, limite 20 proposée ; T290–T292 |
| V35-04 | Langue de cours annoncée consultable/filtrable sans champ dans la série ou l’offre | teachingLanguage explicite, projection et filtre d’offres, langue figée après publication ; filtre de site non promis sans contrat | Contrat complété ; catalogue de langues proposé, pas ciblage personnel ; T293–T295 |
| V35-05 | PermitCommand pouvait APPROVE sans preuve et REJECT sans motif ; output final pouvait avoir contrôleur nul | Conditions de forme et projection finale alignées sur R07 ; contrôles de document et habilitation demeurent serveur | Contradiction schéma/règle ; T286–T287 et cas JSON |
| V35-06 | Priorité du refus connue mais conflit d’un refus SELF avec accord verbal ultérieur insuffisamment explicite | R101 protège le refus personnel, autorise sa révision personnelle explicite sans réanimer de bail | Précision conservatrice proposée ; T288–T289 |
| V35-07 | Des descriptions de canal suivaient l’école sans rendre uniforme la préférence individuelle | Conjonction école/personne/technique ; calendrier séparé de campagne et confirmation in-app | Clarification sans forcer un canal ; T296 |
| V35-08 | Roadmap rangeait scores de conduite parmi le différé, malgré X01 ; risque de confondre U01 reclassé et extension | Exclu ≠ différé ≠ cœur, catalogue utilisateur avec frontières explicites | Correction de périmètre, pas nouvelle exclusion du GPS |
| V35-09 | Un passage GPS évoquait encore un choix définitif du client, alors que Swift est accepté | Qualification porte sur intégration/appareil, pas remise en question de Swift ; Android autonome conservé | Cohérence de décision et contrôles Swift |
| V35-10 | DM06 restait un workflow non contracté de clôture globale | F01/F14 détaillés, AP193–AP198, E49/J29, machine à états et reçu limité | Complément connu, pas découverte nouvelle ; T298–T310. Validation opérationnelle toujours bloquante |
| V35-11 | Phases de traçabilité et présentations de périmètre hétérogènes ; liste technique peu lisible ; contrôles historiques présentés comme courants risqués | Phases réconciliées, catalogue F01–F23, rapport actuel et différenciation des fixtures historiques | Complément documentaire et non-régression reproductible |

Les [preuves avant correction](../annexes/preuves-audit-v3-5.json) donnent chemins, lignes et schémas sources. Le [diff](../annexes/corrections-v3-4-vers-v3-5.patch) décrit les changements de références ; les rapports historiques ne sont pas réécrits comme résultats actuels.

## Correspondance avec les demandes du porteur

| Demande exprimée | État documentaire courant | Référence |
|---|---|---|
| Drivy, sans e | Nom utilisé dans les références actives ; anciennes pièces de provenance restent historiques | Synthèse et catalogue |
| Swift natif, pas une application partagée imposée | Décision conservée ; SwiftUI, MapKit et Core Location proposés directement | [Client Apple](../04-technique/architecture-client-swift.md) |
| GPS au centre, sans obligation par leçon | F15/F16 dans le premier parcours terrain ; refus explicite et séance sans GPS | [GPS](../03-fonctionnel/gps-replay.md) |
| Calendrier de sensibilisation, notification ciblée, inscription volontaire, capacité | F18/F19 conservés, pas de place prise en ouvrant la notification | [Cours](../03-fonctionnel/cours-collectifs.md) |
| Offres et packs adaptables aux écoles | F17 conservé, prestations distinctes, absence de pack possible | [Catalogue](../03-fonctionnel/catalogue-packs.md) |
| Tablette pour GPS et reste du produit | Compositions et qualification iPad conservées | [Plateformes](../02-experience/plateformes-tablette-web.md) |
| Web détaillé, dossiers, archives et statistiques | F22/F23, permissions distinctes du support | [Gestion](../03-fonctionnel/gestion-web-archivage.md) |
| Onboarding école, élève et moniteur | Progressif, photo facultative, sans demande GPS injustifiée | [Onboarding](../03-fonctionnel/onboarding.md) |
| UI/UX cohérente, éviter AI slop | Charte AS01–AS10 et états réels conservés, pas de chatbot ajouté | [Qualité](../02-experience/qualite-ui-ux-anti-slop.md) |
| iOS/iPadOS 26/27, Android futur | Cibles étudiées, builds non qualifiés ; client Android distinct | [Guide iOS](../04-technique/integration-ios-ipados.md) |

Cette table établit une correspondance de conception. Elle ne prouve pas que le futur rendu ou comportement satisfait les utilisateurs. Les interfaces réelles, le GPS en conditions routières et les parcours avec moniteurs/élèves restent à tester.

<a id="decisions"></a>
## Ce qui reste à décider ou à démontrer

| Point | Ce qui est écrit | Ce qui manque encore et conséquence |
|---|---|---|
| DM01–DM03 | Swift accepté, candidats UI/cartes/outillage natifs | Appareils, minimum OS, versions et mesures ; pas de support public déclaré sans binaire qualifié |
| DM04 | Android après, contrat commun | Ressources, pile finale et qualification avant lancement Android |
| DM05 | Stockage chiffré et coffre natifs proposés | Édition/licence, accès sous verrouillage, migration et pertes de clés sur appareils |
| DM06 | Demande et suivi globaux contractualisés | Fournisseur, rétentions, délai annoncé, orchestration et dernier ADMIN ; publication interdite avant validation opérationnelle |
| DM07/DM08 | Critères qualité et séparation des modèles économiques | Seuils mesurés, coûts réels et distribution approuvés |
| GPS | Démarrage initial autorisé en ligne, une capture choisie par publication, pilote individuel voiture | Confirmer acceptabilité du mode initial hors réseau, des interruptions, des bornes et du périmètre multi-captures |
| Cours et packs | États, crédit/présence/paiement séparés | Conditions commerciales applicables, langues utiles et profils réglementaires validés avec les écoles |
| Produit et design | Directions, écrans et charte proposés | Essais utilisateurs et maquettes/implémentation ; aucun entretien ni observation terrain n’a été effectué |

La documentation contient donc encore des validations nécessaires, pas un produit « parfait » certifié. Les principales fonctions ont des règles et parcours liés ; une politique d’école, un budget ou une mesure d’appareil ne doit pas être inventé pour remplir une case. Les [limites du catalogue](../01-fonctionnalites-prevues.md) sont explicites.

## Contrat et compatibilité

Le contrat passe de info.version 3.2.0 hérité à **3.5.0**, avant implémentation. Il ajoute six opérations globales, des DTO de suppression et PlannedWaypoint, les champs de langue et des validations de permis. Les routes existantes ne sont pas renumérotées. Les clients doivent utiliser le contrat complet actuel ; les types nouveaux ne peuvent pas être supposés présents dans un serveur ancien.

L’ajout de teachingLanguage aux séries impose un choix explicite lors d’une éventuelle migration, sans inventer la langue des cours historiques. Un ancien enregistrement de Preparation initialise une liste de repères vide, ce qui signifie absence de plan enregistré, pas preuve qu’aucun lieu n’avait été envisagé. L’ancienne application n’est pas modifiée.

## Portée des contrôles

Le [rapport courant](../annexes/verification-documentaire.json) valide les liens, schémas, exemples, registres et contrôles de contrat. Les cas ajoutés utilisent des données fictives ; la [comparaison avant/après](../annexes/comparaison-contrats-v3-4-v3-5.json) distingue les structures nouvellement créées de celles réellement plus strictes. Ce n’est pas un test de base de données, d’identité ou de GPS.

Les 310 scénarios T et 52 scénarios MOB demeurent **NOT_EXECUTED**. Les contrôles Swift portent sur la documentation et la décision de pile, non sur un compilateur. Le lecteur HTML est testé séparément dans Chromium avec tailles de fenêtre simulées. Aucune maquette native, aucun test utilisateur et aucune conformité juridique ne sont certifiés.

Les huit archives sources sont conservées ; le code de l’ancienne application reste inchangé. La version livrée inclut des scripts, des rapports datés et un manifeste d’empreintes pour reproduire la vérification, plutôt qu’une promesse d’absence totale d’erreurs.
