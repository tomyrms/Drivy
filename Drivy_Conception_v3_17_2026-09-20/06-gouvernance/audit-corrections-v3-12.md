# Revue corrective de la version 3.12

> Drivy · Référence de conception 3.12 · 20 septembre 2026

Cette passe poursuit la consolidation de V3.11. Elle ne modifie ni le code de l’application ni le périmètre fonctionnel pour créer artificiellement une nouvelle version. Son objectif est de réduire l’ambiguïté de la référence active et d’empêcher que des décisions documentaires soient interprétées comme des validations produit.

## Résumé

V3.12 a modifié la normalisation du nom visible sur la base d’une interprétation erronée du brief ; cette partie est annulée par V3.13. Elle consolide le registre de décisions et les questions ouvertes, rattache ces questions aux gates de réalisation, introduit un cadre explicite pour les qualités non fonctionnelles et améliore les preuves attendues lors de la recherche utilisateur. Le contrat HTTP reste **OpenAPI 3.11.0** : aucune route ni aucun schéma métier n’est ajouté par cette passe.

Les identifiants techniques ou preuves historiques contenant `drivy` ne sont pas renommés automatiquement. Un changement de nom interne sans bénéfice fonctionnel pourrait casser une preuve, une migration, un domaine de test ou une référence de provenance. La marque visible et la référence active utilisent en revanche **Drivy**.

## Corrections de référence

### C312-01 · Normalisation de marque annulée en V3.13

Cette correction de V3.12 reposait sur une mauvaise interprétation : le nom officiel était déjà **Drivy**. V3.13 rétablit ce nom dans toute la référence active et dans le livrable. Le reste de la consolidation V3.12 demeure applicable.

### C312-02 · Registre de décisions consolidé

Les décisions **D01 à D33** sont regroupées dans l’ordre numérique avec un statut documentaire explicite. Les hypothèses et les questions ne sont plus intercalées au fil des anciennes versions. Les questions **Q01 à Q14**, ainsi que DM06 et DM07, disposent d’un tableau de pilotage indiquant la gate, le responsable attendu et la preuve de fermeture.

### C312-03 · Budget de qualité avant pilote

**DM07** interdit de conclure qu’une qualité est acquise parce qu’un parcours fonctionne. Démarrage, capture GPS, autonomie, saisie live, synchronisation, API, fichiers, restauration et accessibilité doivent avoir une cible approuvée puis une mesure associée. En l’absence de cible ou de mesure requise, le statut est **`NOT_QUALIFIED`**, jamais `PASSED`.

Aucun seuil numérique de performance n’a été inventé dans cette passe. Les objectifs d’exploitation déjà proposés restent des budgets à approuver puis à mesurer.

### C312-04 · Recherche utilisateur traçable

Le protocole de recherche comporte maintenant une fiche de preuve par session : contexte, rôle, scénario, observations factuelles, difficultés, citations autorisées, interprétation séparée et décision éventuelle. Pour la saisie pendant la leçon, la recherche doit comparer repère rapide, qualification lors d’un arrêt approprié et reprise après leçon sans demander une manipulation dangereuse en circulation.

Cette structure ne signifie pas qu’un entretien a été réalisé. **Aucune recherche utilisateur nouvelle n’est revendiquée par V3.12.**

### C312-05 · Maquettes priorisées par risque

La couverture reste honnête : toutes les fiches écran ne sont pas dessinées. Avant de figer G1/G2, la priorité de maquettage est donnée aux parcours à erreur coûteuse ou décision irréversible, notamment conflit de planning, permissions, arrêt/clôture de leçon, absence de GPS, suppression de compte et reprise des états critiques. Les écrans G3/G4 sont priorisés ensuite selon leur gate.

### C312-06 · Version documentaire distincte du contrat

Le dossier est **V3.12**, tandis que le contrat OpenAPI reste **3.11.0** parce que cette passe n’ajoute ni route ni schéma. Les versions propres des artefacts inchangés, comme certains tokens, restent également inchangées. Une version documentaire n’entraîne plus mécaniquement une renumérotation de tous les artefacts.

<a id="decisions"></a>
## Décisions maintenues

- refonte assumée plutôt que prolongement implicite de l’ancien code ;
- Swift natif pour iPhone et iPad ; Android reste un chantier ultérieur distinct ;
- GPS central mais facultatif par leçon ;
- saisie pédagogique pendant la leçon conservée comme besoin, avec modalités à qualifier ;
- observation privée distincte de l’évaluation publiée ;
- suppression globale spécifiée, tandis que DM06 reste ouvert sur procédures, délais, rétentions et dernier administrateur ;
- aucune capacité n’est déclarée validée par la seule réussite des contrôles documentaires.

## Ce que V3.12 ne prouve pas

Cette passe n’exécute pas le produit. Elle ne constitue ni :

- un build Swift ou un test sur iPhone/iPad ;
- un test GPS en mouvement, d’autonomie ou de chauffe ;
- un test backend, base de données, stockage objet ou notifications réels ;
- un entretien avec un moniteur, un élève ou une auto-école ;
- une validation juridique, App Review, sécurité ou exploitation ;
- une preuve de performance, disponibilité ou charge.

Les contrôles automatisés de cette livraison vérifient uniquement la cohérence et les artefacts documentaires qu’ils annoncent explicitement.

## Sortie attendue

V3.12 doit être utilisable sans reconstituer l’intention depuis les journaux antérieurs : [COMMENCER_ICI](../COMMENCER_ICI.md) fournit l’entrée, le [registre](glossaire-decisions-questions.md) porte les décisions et questions, la [roadmap](../05-realisation/roadmap-backlog.md) porte les gates, et les journaux V3.x antérieurs restent des preuves historiques.
