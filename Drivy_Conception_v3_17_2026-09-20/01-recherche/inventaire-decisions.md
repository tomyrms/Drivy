# Inventaire fonctionnel et matrice de décision

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Lecture de la matrice

Une **capacité** décrit un problème à résoudre, indépendamment des anciens écrans. **IC** signifie qu’une implémentation est identifiable dans le code consulté, sans garantie d’exécution correcte. **PA** signifie partielle ou chaîne incomplète ; **PR**, prévue dans la documentation ; **NV**, fonctionnement impossible à vérifier avec les éléments inspectés. Même IC ne signifie ni test réussi ni disponibilité en production.

Les quatre familles de décision sont « essentielle », « secondaire », « à simplifier/fusionner/repenser » et « à écarter ». Les libellés courts *À repenser* et *À simplifier* appartiennent à la troisième famille. Une refonte peut donc être essentielle dans le nouveau périmètre : consulter la destination **F**, **U** ou **X**. **F01–F23** sont le cœur proposé ; **U** les extensions ; **X** les exclusions justifiées. Les complexités sont relatives (impact et risque), sans conversion en jours.

Les décisions issues du benchmark restent des **REC/HYP**, car aucune statistique d’usage n’a été fournie. La centralité du GPS, son caractère facultatif et l’inscription volontaire aux cours sont en revanche des exigences explicites du porteur ; leurs bénéfices terrain restent à mesurer. Les lignes écartées ne sont pas qualifiées de « réellement obsolètes » sans preuve. L’exclusion porte sur la nouvelle implémentation, pas sur l’effacement des données existantes.

## Vue de décision

| ID | Capacité | Preuve | Classement | Destination | Complexité |
|---|---|---|---|---|---|
| [C01](#c01) | Écoles et séparation des dossiers | IC | Essentielle | F01 | Élevée |
| [C02](#c02) | Connexion, sessions et renouvellement | IC | À repenser | F01 | Élevée |
| [C03](#c03) | Déverrouillage biométrique local | NV | Secondaire | U11 | Moyenne |
| [C04](#c04) | Invitation et rattachement à une école | IC | Essentielle | F02 | Moyenne |
| [C05](#c05) | Fiche élève et recherche | IC | Essentielle | F02 | Moyenne |
| [C06](#c06) | Archivage d’élève | IC | À repenser | F14 | Élevée |
| [C07](#c07) | Offres de permis de l’école | IC | Essentielle | F03 | Moyenne |
| [C08](#c08) | Plusieurs permis pour un élève | IC | Essentielle | F03 | Élevée |
| [C09](#c09) | Photo et examen du permis d’élève | IC | À repenser | F03 | Élevée |
| [C10](#c10) | Affectation d’un moniteur référent | IC | Essentielle | F03 | Moyenne |
| [C11](#c11) | Horaires de travail et durée préférée | IC | Essentielle | F04 | Moyenne |
| [C12](#c12) | Pauses, indisponibilités et vacances | IC | Essentielle | F04 | Élevée |
| [C13](#c13) | Agenda jour et semaine | IC | À repenser | F05 / F19 | Moyenne |
| [C14](#c14) | Créer, déplacer et supprimer une leçon | IC | À repenser | F05 | Élevée |
| [C15](#c15) | Démarrer, terminer, rouvrir la conduite | IC | À repenser | F07 | Élevée |
| [C16](#c16) | Objectifs et souhaits de la prochaine leçon | IC | Essentielle | F06 | Moyenne |
| [C17](#c17) | Leçon standard, préparation examen, examen | IC | À simplifier | F05 | Faible |
| [C18](#c18) | Carte et GPS pendant la leçon | IC | Essentielle | F15 | Très élevée |
| [C19](#c19) | Évaluations vert-orange-rouge | IC | À repenser | F08 | Élevée |
| [C20](#c20) | Fautes géolocalisées et timeline live | IC | À repenser | F16 | Très élevée |
| [C21](#c21) | Relecture et statistiques d’un trajet | NV | Essentielle | F16 / U06 | Élevée |
| [C22](#c22) | Itinéraires modèles et points de passage | IC | Secondaire | U02 | Élevée |
| [C23](#c23) | Fautes fréquentes d’un itinéraire | IC | À repenser | U02 | Moyenne |
| [C24](#c24) | Transformer un trajet en itinéraire | NV | Secondaire | U02 | Élevée |
| [C25](#c25) | Validation d’une compétence | IC | À repenser | F08 | Élevée |
| [C26](#c26) | Échelle personnalisable et notes par leçon | IC | À repenser | F08 | Élevée |
| [C27](#c27) | Score global normalisé sur dix | IC | À écarter | X01 | Moyenne |
| [C28](#c28) | Prérequis à faire, planifier, terminer | IC | À repenser | F03 / F18 / U08 | Élevée |
| [C29](#c29) | Documents généraux | IC | Essentielle | F09 | Élevée |
| [C30](#c30) | Photos prises après la leçon | IC | À simplifier | F09 | Moyenne |
| [C31](#c31) | Pièces dommages véhicule et fiches exercice | IC | À simplifier | F09 | Moyenne |
| [C32](#c32) | Déduplication des médias | IC | Secondaire | U12 | Élevée |
| [C33](#c33) | Conversation école-élève | IC | Secondaire | U03 | Élevée |
| [C34](#c34) | Lecture des messages et actualisation | IC | À repenser | U03 | Élevée |
| [C35](#c35) | Enregistrement appareil push | PA | Essentielle | F11 / F19 | Moyenne |
| [C36](#c36) | Alertes permis et compteurs contextuels | IC | À repenser | F03 | Moyenne |
| [C37](#c37) | Rappel hebdomadaire des impayés | PA | Secondaire | U07 | Moyenne |
| [C38](#c38) | Badges de progression et gamification | IC | À écarter | X02 | Moyenne |
| [C39](#c39) | Statistiques heures et activité | IC | Essentielle V3 | F23 (avancé : U06) | Moyenne |
| [C40](#c40) | Indicateurs revenus et réussite | IC | À repenser | F23 partiel / U06 | Élevée |
| [C41](#c41) | Marquage payé/non payé | IC | À repenser | F10 | Élevée |
| [C42](#c42) | Encaissement Stripe/TWINT/Apple Pay | PR | Secondaire | U05 | Très élevée |
| [C43](#c43) | Cache et brouillons hors ligne | IC | Essentielle | F12 | Très élevée |
| [C44](#c44) | Réessais et conflits de synchronisation | IC | À repenser | F12 | Très élevée |
| [C45](#c45) | Logo et identité propre à chaque école | IC | À simplifier | F13 | Faible |
| [C46](#c46) | Fonds routiers, effets, émoticônes de thème | IC | À écarter | X03 | Faible |
| [C47](#c47) | Profil utilisateur et préférences | IC | À simplifier | F01 | Moyenne |
| [C48](#c48) | Traductions françaises, allemandes, anglaises | NV | À repenser | F13 | Moyenne |
| [C49](#c49) | États vides, erreurs, confirmations | PA | Essentielle | F12 | Moyenne |
| [C50](#c50) | Gestes rapides et retours haptiques | NV | À simplifier | F13 | Faible |
| [C51](#c51) | Consultation inter-écoles et changement d’espace | IC | Essentielle | F01 | Élevée |
| [C52](#c52) | Export, effacement et conservation réglementaire | PR | Essentielle | F14 | Élevée |
| [C53](#c53) | Catalogue de prestations et durées | Exigence V2, non exécutée | Essentielle | F17 | Voir fiche |
| [C54](#c54) | Packs composites et soldes de droits | Exigence V2, non exécutée | Essentielle | F17 | Voir fiche |
| [C55](#c55) | Publication de séries de cours | Exigence V2, non exécutée | Essentielle | F18 | Voir fiche |
| [C56](#c56) | Offres dans le calendrier élève | Exigence V2, non exécutée | Essentielle | F19 | Voir fiche |
| [C57](#c57) | Inscription volontaire selon capacité | Exigence V2, non exécutée | Essentielle | F18 | Voir fiche |
| [C58](#c58) | Présences et validation de formation | Exigence V2, non exécutée | Essentielle | F18 | Voir fiche |
| [C59](#c59) | Notification ciblée des élèves concernés | Exigence V2, non exécutée | Essentielle | F19 / F11 | Voir fiche |
| [C60](#c60) | Choix GPS indépendant de la leçon | Exigence V2, non exécutée | Essentielle | F15 | Voir fiche |

<a id="c01"></a>
### C01 · Écoles et séparation des dossiers

**Besoin et valeur :** Empêcher le mélange des personnes et documents de deux écoles. **Utilisateurs :** École, équipe, élève.

**État constaté :** IC. [Preuve EV02](audit-existant.md#ev02). **Décision :** Essentielle, destination F01. **Dépendances :** Identité ; règles d’accès. **Complexité relative :** Élevée.

**Justification et limite :** Le schéma atteste School et Membership ; aucune isolation de production certifiée.

<a id="c02"></a>
### C02 · Connexion, sessions et renouvellement

**Besoin et valeur :** Accéder au bon espace et pouvoir révoquer un appareil. **Utilisateurs :** Tous.

**État constaté :** IC. [Preuve EV06](audit-existant.md#ev06). **Décision :** À repenser, destination F01. **Dépendances :** Fournisseur OIDC ; session serveur. **Complexité relative :** Élevée.

**Justification et limite :** Ne pas reprendre une authentification maison sans justification ; les révocations réelles ne sont pas établies.

<a id="c03"></a>
### C03 · Déverrouillage biométrique local

**Besoin et valeur :** Éviter une saisie répétée sans confondre identité serveur et déverrouillage local. **Utilisateurs :** Utilisateurs mobiles.

**État constaté :** NV. [Preuve EV14](audit-existant.md#ev14). **Décision :** Secondaire, destination U11. **Dépendances :** Session ; coffre système. **Complexité relative :** Moyenne.

**Justification et limite :** Fichiers biométriques présents ; fonctionnement réel non essayé. Protection native du stockage reste nécessaire au cœur.

<a id="c04"></a>
### C04 · Invitation et rattachement à une école

**Besoin et valeur :** Créer une relation autorisée sans dupliquer les personnes. **Utilisateurs :** Administration, élève, moniteur.

**État constaté :** IC. [Preuve EV02](audit-existant.md#ev02). **Décision :** Essentielle, destination F02. **Dépendances :** F01 ; email vérifié. **Complexité relative :** Moyenne.

**Justification et limite :** Code et statuts présents ; reprise des jetons anciens interdite.

<a id="c05"></a>
### C05 · Fiche élève et recherche

**Besoin et valeur :** Identifier rapidement la bonne personne. **Utilisateurs :** Équipe.

**État constaté :** IC. [Preuve EV21](audit-existant.md#ev21). **Décision :** Essentielle, destination F02. **Dépendances :** Appartenance ; minimisation. **Complexité relative :** Moyenne.

**Justification et limite :** Recherche insensible aux accents à spécifier ; ne pas exiger une adresse complète sans finalité.

<a id="c06"></a>
### C06 · Archivage d’élève

**Besoin et valeur :** Clore une relation sans effacer arbitrairement son historique. **Utilisateurs :** Administration.

**État constaté :** IC. [Preuve EV03](audit-existant.md#ev03). **Décision V3 :** À repenser, destination F14/F22. **Dépendances :** Formations, engagements, captures, comptes, droits et rétention. **Complexité relative :** Élevée.

**Justification et limite :** Archiver, retirer un accès et effacer sont trois opérations différentes.

<a id="c07"></a>
### C07 · Offres de permis de l’école

**Besoin et valeur :** Limiter les formations aux catégories réellement proposées. **Utilisateurs :** Administration.

**État constaté :** IC. [Preuve EV03](audit-existant.md#ev03). **Décision :** Essentielle, destination F03. **Dépendances :** Référentiel pédagogique validé. **Complexité relative :** Moyenne.

**Justification et limite :** La liste de catégories du code ne prouve pas leur contenu ni leur couverture juridique.

<a id="c08"></a>
### C08 · Plusieurs permis pour un élève

**Besoin et valeur :** Séparer progression, pièces et leçons par formation. **Utilisateurs :** Équipe, élève.

**État constaté :** IC. [Preuve EV03](audit-existant.md#ev03). **Décision :** Essentielle, destination F03. **Dépendances :** Personne ; catalogue. **Complexité relative :** Élevée.

**Justification et limite :** Structure attestée ; champs hérités sur le dossier général à ne pas reconduire.

<a id="c09"></a>
### C09 · Photo et examen du permis d’élève

**Besoin et valeur :** Préparer une vérification humaine traçable. **Utilisateurs :** Élève, personnel habilité.

**État constaté :** IC. [Preuve EV03](audit-existant.md#ev03). **Décision :** À repenser, destination F03. **Dépendances :** F09 ; dates ; politique école. **Complexité relative :** Élevée.

**Justification et limite :** Un document téléchargé ou marqué confirmé ne vaut pas autorisation légale automatique.

<a id="c10"></a>
### C10 · Affectation d’un moniteur référent

**Besoin et valeur :** Désigner qui accompagne une formation et voit les bilans. **Utilisateurs :** Administration, moniteur.

**État constaté :** IC. [Preuve EV03](audit-existant.md#ev03). **Décision :** Essentielle, destination F03. **Dépendances :** Habilitations par formation. **Complexité relative :** Moyenne.

**Justification et limite :** Un moniteur de remplacement doit être explicitement affecté.

<a id="c11"></a>
### C11 · Horaires de travail et durée préférée

**Besoin et valeur :** Proposer des créneaux réalistes. **Utilisateurs :** Moniteur.

**État constaté :** IC. [Preuve EV20](audit-existant.md#ev20). **Décision :** Essentielle, destination F04. **Dépendances :** Fuseau ; contraintes. **Complexité relative :** Moyenne.

**Justification et limite :** 50 minutes est une valeur ancienne, pas une obligation métier universelle.

<a id="c12"></a>
### C12 · Pauses, indisponibilités et vacances

**Besoin et valeur :** Empêcher une réservation sur une absence. **Utilisateurs :** Moniteur, administration.

**État constaté :** IC. [Preuve EV09](audit-existant.md#ev09). **Décision :** Essentielle, destination F04. **Dépendances :** Intervalles ; revue des rendez-vous existants. **Complexité relative :** Élevée.

**Justification et limite :** Ajouter une indisponibilité ne doit pas supprimer des leçons en silence.

<a id="c13"></a>
### C13 · Agenda jour et semaine

**Besoin et valeur :** Trouver le prochain rendez-vous et organiser la semaine. **Utilisateurs :** Équipe, élève.

**État constaté :** IC. [Preuve EV20](audit-existant.md#ev20). **Décision :** À repenser, destination F05 / F19. **Dépendances :** Créneaux ; droits ; accessibilité. **Complexité relative :** Moyenne.

**Justification et limite :** Agenda personnel et calendrier élève d’offres/engagements ; une offre n’est pas une inscription.

<a id="c14"></a>
### C14 · Créer, déplacer et supprimer une leçon

**Besoin et valeur :** Fixer et modifier un engagement sans collision. **Utilisateurs :** Équipe.

**État constaté :** IC. [Preuve EV07](audit-existant.md#ev07). **Décision :** À repenser, destination F05. **Dépendances :** F03 ; F04 ; transactions. **Complexité relative :** Élevée.

**Justification et limite :** Suppression historique remplacée par annulation motivée. Le contrôle sérialisable ancien est reconnu.

<a id="c15"></a>
### C15 · Démarrer, terminer, rouvrir la conduite

**Besoin et valeur :** Documenter ce qui a réellement eu lieu. **Utilisateurs :** Moniteur.

**État constaté :** IC. [Preuve EV07](audit-existant.md#ev07). **Décision :** À repenser, destination F07. **Dépendances :** Bilan ; correction ; dates. **Complexité relative :** Élevée.

**Justification et limite :** Pas de bouton de départ obligatoire au cœur ; clôture après leçon et corrections auditées.

<a id="c16"></a>
### C16 · Objectifs et souhaits de la prochaine leçon

**Besoin et valeur :** Relier le dernier bilan à la préparation suivante. **Utilisateurs :** Élève, moniteur.

**État constaté :** IC. [Preuve EV07](audit-existant.md#ev07). **Décision :** Essentielle, destination F06. **Dépendances :** Formation ; bilan publié. **Complexité relative :** Moyenne.

**Justification et limite :** Souhait élève distinct d’un objectif accepté par le moniteur.

<a id="c17"></a>
### C17 · Leçon standard, préparation examen, examen

**Besoin et valeur :** Donner un contexte sans simuler la réussite à l’examen. **Utilisateurs :** Équipe.

**État constaté :** IC. [Preuve EV03](audit-existant.md#ev03). **Décision :** À simplifier, destination F05. **Dépendances :** Catalogue ; résultats déclarés. **Complexité relative :** Faible.

**Justification et limite :** Pilote : leçon individuelle avec objectif libre ; gestion des examens officiels différée.

<a id="c18"></a>
### C18 · Carte et GPS pendant la leçon

**Besoin et valeur :** Revenir sur un passage précis si ce besoin est confirmé. **Utilisateurs :** Moniteur, élève.

**État constaté :** IC. [Preuve EV25](audit-existant.md#ev25). **Décision :** Essentielle, destination F15. **Dépendances :** Permissions ; batterie ; vie privée ; segmentation. **Complexité relative :** Très élevée.

**Justification et limite :** Le GPS central est une exigence explicite ; fiabilité terrain non vérifiée, à tester en première gate.

<a id="c19"></a>
### C19 · Évaluations vert-orange-rouge

**Besoin et valeur :** Expliquer une observation pédagogique. **Utilisateurs :** Moniteur, élève.

**État constaté :** IC. [Preuve EV04](audit-existant.md#ev04). **Décision :** À repenser, destination F08. **Dépendances :** Référentiel versionné ; contexte. **Complexité relative :** Élevée.

**Justification et limite :** Couleur seule abandonnée ; niveaux textuels contextualisés, pas chronométrage en circulation.

<a id="c20"></a>
### C20 · Fautes géolocalisées et timeline live

**Besoin et valeur :** Associer un événement à un lieu lorsque cela aide le débriefing. **Utilisateurs :** Moniteur.

**État constaté :** IC. [Preuve EV04](audit-existant.md#ev04). **Décision :** À repenser, destination F16. **Dépendances :** Trace fiable ; attention ; consentements. **Complexité relative :** Très élevée.

**Justification et limite :** Observations situées du cœur, préparées à l’arrêt ou après ; aucune saisie obligatoire en mouvement.

<a id="c21"></a>
### C21 · Relecture et statistiques d’un trajet

**Besoin et valeur :** Comprendre un trajet enregistré. **Utilisateurs :** Élève, moniteur.

**État constaté :** NV. [Preuve EV26](audit-existant.md#ev26). **Décision :** Essentielle, destination F16 / U06. **Dépendances :** Segments ; qualité GPS ; rétention. **Complexité relative :** Élevée.

**Justification et limite :** Replay simple au cœur ; statistiques avancées différées. Le code existant ne prouve pas la fluidité ou la qualité du nouveau replay.

<a id="c22"></a>
### C22 · Itinéraires modèles et points de passage

**Besoin et valeur :** Préparer des situations pédagogiques réutilisables. **Utilisateurs :** Moniteur.

**État constaté :** IC. [Preuve EV05](audit-existant.md#ev05). **Décision :** Secondaire, destination U02. **Dépendances :** F06 ; carte ; versions. **Complexité relative :** Élevée.

**Justification et limite :** Valeur plausible ; pas nécessaire pour publier un bilan utile.

<a id="c23"></a>
### C23 · Fautes fréquentes d’un itinéraire

**Besoin et valeur :** Préparer une vigilance contextuelle. **Utilisateurs :** Moniteur.

**État constaté :** IC. [Preuve EV05](audit-existant.md#ev05). **Décision :** À repenser, destination U02. **Dépendances :** Itinéraires ; vocabulaire. **Complexité relative :** Moyenne.

**Justification et limite :** Les suggestions ne doivent pas se transformer en fautes réellement commises.

<a id="c24"></a>
### C24 · Transformer un trajet en itinéraire

**Besoin et valeur :** Capitaliser une leçon sans conserver toute donnée personnelle. **Utilisateurs :** Moniteur.

**État constaté :** NV. [Preuve EV25](audit-existant.md#ev25). **Décision :** Secondaire, destination U02. **Dépendances :** U01 ; anonymisation ; droits. **Complexité relative :** Élevée.

**Justification et limite :** Chaîne complète non vérifiée. Exiger retrait des données de l’élève avant réutilisation.

<a id="c25"></a>
### C25 · Validation d’une compétence

**Besoin et valeur :** Attester une observation avec date et contexte. **Utilisateurs :** Moniteur.

**État constaté :** IC. [Preuve EV05](audit-existant.md#ev05). **Décision :** À repenser, destination F08. **Dépendances :** Version du référentiel. **Complexité relative :** Élevée.

**Justification et limite :** Ne pas conserver plusieurs sources de vérité parallèles.

<a id="c26"></a>
### C26 · Échelle personnalisable et notes par leçon

**Besoin et valeur :** Décrire une autonomie observée. **Utilisateurs :** Équipe, élève.

**État constaté :** IC. [Preuve EV12](audit-existant.md#ev12). **Décision :** À repenser, destination F08. **Dépendances :** Référentiel ; bilans. **Complexité relative :** Élevée.

**Justification et limite :** L’échelle proposée doit être validée pédagogiquement, pas déclarée standard suisse.

<a id="c27"></a>
### C27 · Score global normalisé sur dix

**Besoin et valeur :** Ne pas créer une fausse précision sur l’aptitude à conduire. **Utilisateurs :** Élève, moniteur.

**État constaté :** IC. [Preuve EV12](audit-existant.md#ev12). **Décision :** À écarter, destination X01. **Dépendances :** Aucune dépendance prioritaire. **Complexité relative :** Moyenne.

**Justification et limite :** Exclusion proposée faute de validation de sens. Ce n’est pas une preuve que tout score est inutile.

<a id="c28"></a>
### C28 · Prérequis à faire, planifier, terminer

**Besoin et valeur :** Suivre les démarches autour du permis. **Utilisateurs :** Équipe, élève.

**État constaté :** IC. [Preuve EV29](audit-existant.md#ev29). **Décision :** À repenser, destination F03 / F18 / U08. **Dépendances :** Portée par formation ; sources cantonales. **Complexité relative :** Élevée.

**Justification et limite :** Statuts/preuves nécessaires aux cours au cœur ; démarches réglementaires étendues différées. Admissibilité et accomplissement distincts.

<a id="c29"></a>
### C29 · Documents généraux

**Besoin et valeur :** Partager les pièces nécessaires au parcours. **Utilisateurs :** Équipe, élève.

**État constaté :** IC. [Preuve EV19](audit-existant.md#ev19). **Décision :** Essentielle, destination F09. **Dépendances :** Droits ; scanner de fichiers ; rétention. **Complexité relative :** Élevée.

**Justification et limite :** Limiter les formats et finalités au lieu d’un dépôt documentaire universel.

<a id="c30"></a>
### C30 · Photos prises après la leçon

**Besoin et valeur :** Illustrer un bilan avec une pièce pertinente. **Utilisateurs :** Moniteur.

**État constaté :** IC. [Preuve EV27](audit-existant.md#ev27). **Décision :** À simplifier, destination F09. **Dépendances :** F08 ; transfert différé. **Complexité relative :** Moyenne.

**Justification et limite :** Optionnel, pas une condition de publication. Pas de capture obligatoire en direct.

<a id="c31"></a>
### C31 · Pièces dommages véhicule et fiches exercice

**Besoin et valeur :** Classer une pièce sans multiplier les modules. **Utilisateurs :** Équipe.

**État constaté :** IC. [Preuve EV04](audit-existant.md#ev04). **Décision :** À simplifier, destination F09. **Dépendances :** Catégorie ; confidentialité. **Complexité relative :** Moyenne.

**Justification et limite :** Les dommages sans finalité pédagogique sortent du pilote, la pièce pédagogique reste possible.

<a id="c32"></a>
### C32 · Déduplication des médias

**Besoin et valeur :** Réduire le stockage sans fuite entre écoles. **Utilisateurs :** Exploitation.

**État constaté :** IC. [Preuve EV04](audit-existant.md#ev04). **Décision :** Secondaire, destination U12. **Dépendances :** Hash scoped école ; suppression référencée. **Complexité relative :** Élevée.

**Justification et limite :** Ne pas dédupliquer globalement ni lier les droits à un hash.

<a id="c33"></a>
### C33 · Conversation école-élève

**Besoin et valeur :** Conserver un échange contextualisé. **Utilisateurs :** Équipe, élève.

**État constaté :** IC. [Preuve EV22](audit-existant.md#ev22). **Décision :** Secondaire, destination U03. **Dépendances :** Responsabilité de réponse ; modération ; rétention. **Complexité relative :** Élevée.

**Justification et limite :** Contact téléphone/email suffisant pour pilote ; besoin à mesurer, non déclaré obsolète.

<a id="c34"></a>
### C34 · Lecture des messages et actualisation

**Besoin et valeur :** Éviter de confondre réception et réponse attendue. **Utilisateurs :** Équipe, élève.

**État constaté :** IC. [Preuve EV02](audit-existant.md#ev02). **Décision :** À repenser, destination U03. **Dépendances :** Lectures par personne ; événements. **Complexité relative :** Élevée.

**Justification et limite :** staffReadAt partagé n’est pas une preuve de lecture par chaque membre.

<a id="c35"></a>
### C35 · Enregistrement appareil push

**Besoin et valeur :** Recevoir un rappel facultatif. **Utilisateurs :** Tous.

**État constaté :** PA. [Preuve EV13](audit-existant.md#ev13). **Décision :** Essentielle, destination F11 / F19. **Dépendances :** F11 ; APNs/FCM ; permissions. **Complexité relative :** Moyenne.

**Justification et limite :** Notifications de service incluses avec préférences et ciblage ; livraison appareil toujours à tester.

<a id="c36"></a>
### C36 · Alertes permis et compteurs contextuels

**Besoin et valeur :** Rendre visible une action manquante. **Utilisateurs :** Élève, équipe.

**État constaté :** IC. [Preuve EV15](audit-existant.md#ev15). **Décision :** À repenser, destination F03. **Dépendances :** État de vérification ; lien ciblé. **Complexité relative :** Moyenne.

**Justification et limite :** Ne pas multiplier les badges rouges dans Profil et ailleurs.

<a id="c37"></a>
### C37 · Rappel hebdomadaire des impayés

**Besoin et valeur :** Repérer les règlements à vérifier. **Utilisateurs :** Équipe.

**État constaté :** PA. [Preuve EV07](audit-existant.md#ev07). **Décision :** Secondaire, destination U07. **Dépendances :** F10 ; événements ; échéancier. **Complexité relative :** Moyenne.

**Justification et limite :** Résumé sur sept jours attesté ; notification réellement délivrée non prouvée.

<a id="c38"></a>
### C38 · Badges de progression et gamification

**Besoin et valeur :** Éviter des récompenses sans lien validé avec l’apprentissage. **Utilisateurs :** Élève.

**État constaté :** IC. [Preuve EV24](audit-existant.md#ev24). **Décision :** À écarter, destination X02. **Dépendances :** Aucune au cœur. **Complexité relative :** Moyenne.

**Justification et limite :** Décision réversible sur preuve d’usage ; les anciens badges restent consultables en archive si utiles.

<a id="c39"></a>
### C39 · Statistiques heures et activité

**Besoin et valeur :** Analyser une activité quand les données sont fiables. **Utilisateurs :** Équipe.

**État constaté :** IC. [Preuve EV23](audit-existant.md#ev23). **Décision V3 :** Essentielle pour M01–M09 définis, destination F23 ; analyses avancées restent U06. **Dépendances :** Leçons et calendrier stabilisés. **Complexité relative :** Moyenne.

**Justification et limite :** Ne pas mettre des métriques au premier plan de chaque journée.

<a id="c40"></a>
### C40 · Indicateurs revenus et réussite

**Besoin et valeur :** Éviter la confusion entre montant prévu, dû, encaissé et résultat déclaré. **Utilisateurs :** Administration.

**État constaté :** IC. [Preuve EV23](audit-existant.md#ev23). **Décision V3 :** À repenser : encaissements internes définis vers F23 ; réussite/rentabilité non documentées restent U06 ou exclues. **Dépendances :** F10 ; données vérifiées. **Complexité relative :** Élevée.

**Justification et limite :** L’archive ne prouve ni une comptabilité complète ni des résultats officiels.

<a id="c41"></a>
### C41 · Marquage payé/non payé

**Besoin et valeur :** Connaître le solde sans perdre les paiements partiels. **Utilisateurs :** Équipe, élève.

**État constaté :** IC. [Preuve EV07](audit-existant.md#ev07). **Décision :** À repenser, destination F10. **Dépendances :** Journal interne ; autorisations. **Complexité relative :** Élevée.

**Justification et limite :** Remplacer le booléen par des écritures et un solde calculé.

<a id="c42"></a>
### C42 · Encaissement Stripe/TWINT/Apple Pay

**Besoin et valeur :** Encaisser en ligne si volume et coûts le justifient. **Utilisateurs :** École, élève.

**État constaté :** PR. [Preuve EV01](audit-existant.md#ev01). **Décision :** Secondaire, destination U05. **Dépendances :** Prestataire ; remboursements ; contrat. **Complexité relative :** Très élevée.

**Justification et limite :** Annonce documentaire, pas intégration opérationnelle démontrée.

<a id="c43"></a>
### C43 · Cache et brouillons hors ligne

**Besoin et valeur :** Ne pas perdre un bilan lors d’une interruption réseau. **Utilisateurs :** Moniteur mobile.

**État constaté :** IC. [Preuve EV14](audit-existant.md#ev14). **Décision :** Essentielle, destination F12. **Dépendances :** Chiffrement ; droits ; durée de cache. **Complexité relative :** Très élevée.

**Justification et limite :** Reprise explicite, sans réservation présentée comme confirmée hors ligne.

<a id="c44"></a>
### C44 · Réessais et conflits de synchronisation

**Besoin et valeur :** Résoudre une concurrence sans perte ni double effet. **Utilisateurs :** Moniteur.

**État constaté :** IC. [Preuve EV10](audit-existant.md#ev10). **Décision :** À repenser, destination F12. **Dépendances :** Idempotence ; versions ; interface de conflit. **Complexité relative :** Très élevée.

**Justification et limite :** Des protections existent ; ne pas les confondre avec une résolution universelle.

<a id="c45"></a>
### C45 · Logo et identité propre à chaque école

**Besoin et valeur :** Identifier l’école sans rendre l’interface incohérente. **Utilisateurs :** Administration.

**État constaté :** IC. [Preuve EV28](audit-existant.md#ev28). **Décision :** À simplifier, destination F13. **Dépendances :** Médias ; identité Drivy. **Complexité relative :** Faible.

**Justification et limite :** Nom et logo, pas couleur arbitraire de danger ou système complet de thèmes.

<a id="c46"></a>
### C46 · Fonds routiers, effets, émoticônes de thème

**Besoin et valeur :** Réduire décoration et ambiguïté dans un outil de travail. **Utilisateurs :** Tous.

**État constaté :** IC. [Preuve EV15](audit-existant.md#ev15). **Décision :** À écarter, destination X03. **Dépendances :** Aucune. **Complexité relative :** Faible.

**Justification et limite :** La nouvelle DA est indépendante ; les anciens fichiers ne sont pas détruits.

<a id="c47"></a>
### C47 · Profil utilisateur et préférences

**Besoin et valeur :** Gérer identité et session sans cacher les actions métier dans Profil. **Utilisateurs :** Tous.

**État constaté :** IC. [Preuve EV02](audit-existant.md#ev02). **Décision V3 :** À simplifier, destination F01/F21. **Dépendances :** OIDC, profil administratif scolaire, politiques de collecte. **Complexité relative :** Moyenne.

**Justification et limite :** Le compte ne doit pas devenir un regroupement des fonctions difficiles à classer.

<a id="c48"></a>
### C48 · Traductions françaises, allemandes, anglaises

**Besoin et valeur :** Préparer une interface multilingue cohérente. **Utilisateurs :** Tous.

**État constaté :** NV. [Preuve EV18](audit-existant.md#ev18). **Décision :** À repenser, destination F13. **Dépendances :** Catalogue des chaînes ; formats locaux. **Complexité relative :** Moyenne.

**Justification et limite :** Fichiers présents ; couverture et qualité non évaluées. Pilote FR, architecture localisable.

<a id="c49"></a>
### C49 · États vides, erreurs, confirmations

**Besoin et valeur :** Comprendre une absence de données et ne pas perdre une saisie. **Utilisateurs :** Tous.

**État constaté :** PA. [Preuve EV17](audit-existant.md#ev17). **Décision :** Essentielle, destination F12. **Dépendances :** Design system ; erreurs API. **Complexité relative :** Moyenne.

**Justification et limite :** Demandes et composants existent ; cohérence de tous les écrans non testée.

<a id="c50"></a>
### C50 · Gestes rapides et retours haptiques

**Besoin et valeur :** Accélérer une action sans en cacher l’accès. **Utilisateurs :** Mobile.

**État constaté :** NV. [Preuve EV15](audit-existant.md#ev15). **Décision :** À simplifier, destination F13. **Dépendances :** Accessibilité ; alternative explicite. **Complexité relative :** Faible.

**Justification et limite :** Confort secondaire, jamais seul moyen de déclencher une action.

<a id="c51"></a>
### C51 · Consultation inter-écoles et changement d’espace

**Besoin et valeur :** Ne pas transporter un cache ou un brouillon dans le mauvais contexte. **Utilisateurs :** Utilisateurs multi-écoles.

**État constaté :** IC. [Preuve EV02](audit-existant.md#ev02). **Décision :** Essentielle, destination F01. **Dépendances :** Epoch de droits ; sessions. **Complexité relative :** Élevée.

**Justification et limite :** Aucune fusion automatique des dossiers pédagogiques entre écoles.

<a id="c52"></a>
### C52 · Export, effacement et conservation réglementaire

**Besoin et valeur :** Permettre un traitement maîtrisé des données. **Utilisateurs :** École, personne concernée.

**État constaté :** PR. [Preuve EV16](audit-existant.md#ev16). **Décision :** Essentielle, destination F14. **Dépendances :** Inventaire ; rétention ; exploitation. **Complexité relative :** Élevée.

**Justification et limite :** Intentions documentaires ; processus complet non établi dans l’archive.

## Besoins ajoutés par la nouvelle conception

Ces besoins ne sont pas présentés comme déjà implémentés dans l’ancien produit.

| ID | Besoin nouveau ou rendu explicite | Destination | Justification | Validation |
|---|---|---|---|---|
| N01 | Journal de règlements partiels et corrections | F10 | Le besoin dépasse un simple indicateur payé. | Confirmer le réel outil comptable de l’école. |
| N02 | Référentiel pédagogique et bilans versionnés | F08 | Éviter de modifier rétrospectivement une observation. | Valider l’échelle et la responsabilité de publication. |
| N03 | Révocation, isolation des caches et droits par formation | F01, F12 | Réduire l’exposition lors de remplacements et changements de rôle. | Faire approuver les profils d’accès. |
| N04 | Tampon manuel entre leçons | F04, F05 | Tenir compte d’un déplacement sans moteur de routage. | Observer distances et lieux habituels. |
| N05 | État de livraison des confirmations | F11 | Une transaction réussie n’est pas un email reçu. | Fournisseur et politique de relance à choisir. |
| N06 | Ressource véhicule partagée | U09 | Utile si plusieurs moniteurs utilisent le même véhicule. | Nombre de véhicules et mode d’affectation inconnus. |

## Fermeture de l’inventaire

Chaque capacité identifiée a une destination et une raison. La liste n’est pas un inventaire garanti de tous les comportements cachés du programme. Une nouvelle preuve découverte reçoit C53 puis les identifiants suivants ; ne pas renuméroter les lignes. Une réintroduction d’élément X requiert une décision motivée, et non un glissement automatique vers une « phase finale ». Les extensions sont cadrées dans [Extensions et exclusions](../03-fonctionnel/extensions.md).

<a id="c53"></a>
### C53 · Catalogue de prestations et durées

**Origine :** Recherche S33–S42. **État constaté :** exigence de conception V2, pas implémentation vérifiée dans l’archive.

**Décision :** Essentielle, destination F17. **Valeur et justification :** Éviter une durée/unité universelle ; versions et dates d’effet.

**Dépendances :** identité/école, règles de domaine, données, transactions et autorisations. **Complexité relative :** élevée pour transactions/permissions ; inconnue en charge sans équipe ni mesures. **Limite :** configuration et usages à valider au pilote ; aucun entretien revendiqué.

<a id="c54"></a>
### C54 · Packs composites et soldes de droits

**Origine :** Recherche S33–S42. **État constaté :** exigence de conception V2, pas implémentation vérifiée dans l’archive.

**Décision :** Essentielle, destination F17. **Valeur et justification :** Distinguer achat, droits réservés/utilisés et règlement ; ne pas refacturer les utilisations.

**Dépendances :** identité/école, règles de domaine, données, transactions et autorisations. **Complexité relative :** élevée pour transactions/permissions ; inconnue en charge sans équipe ni mesures. **Limite :** configuration et usages à valider au pilote ; aucun entretien revendiqué.

<a id="c55"></a>
### C55 · Publication de séries de cours

**Origine :** Exigence P04. **État constaté :** exigence de conception V2, pas implémentation vérifiée dans l’archive.

**Décision :** Essentielle, destination F18. **Valeur et justification :** Dates multiples, ressources et profil ; publication ne crée aucune inscription.

**Dépendances :** identité/école, règles de domaine, données, transactions et autorisations. **Complexité relative :** élevée pour transactions/permissions ; inconnue en charge sans équipe ni mesures. **Limite :** configuration et usages à valider au pilote ; aucun entretien revendiqué.

<a id="c56"></a>
### C56 · Offres dans le calendrier élève

**Origine :** Exigence P04. **État constaté :** exigence de conception V2, pas implémentation vérifiée dans l’archive.

**Décision :** Essentielle, destination F19. **Valeur et justification :** Tous les élèves de l’audience voient des offres distinctes des rendez-vous.

**Dépendances :** identité/école, règles de domaine, données, transactions et autorisations. **Complexité relative :** élevée pour transactions/permissions ; inconnue en charge sans équipe ni mesures. **Limite :** configuration et usages à valider au pilote ; aucun entretien revendiqué.

<a id="c57"></a>
### C57 · Inscription volontaire selon capacité

**Origine :** Exigence P04. **État constaté :** exigence de conception V2, pas implémentation vérifiée dans l’archive.

**Décision :** Essentielle, destination F18. **Valeur et justification :** Dernière place transactionnelle ; message Complet et aucune préinscription automatique.

**Dépendances :** identité/école, règles de domaine, données, transactions et autorisations. **Complexité relative :** élevée pour transactions/permissions ; inconnue en charge sans équipe ni mesures. **Limite :** configuration et usages à valider au pilote ; aucun entretien revendiqué.

<a id="c58"></a>
### C58 · Présences et validation de formation

**Origine :** Conception déduite P04. **État constaté :** exigence de conception V2, pas implémentation vérifiée dans l’archive.

**Décision :** Essentielle, destination F18. **Valeur et justification :** Réservation ne prouve pas accomplissement ; preuves, blocs et validation humaine.

**Dépendances :** identité/école, règles de domaine, données, transactions et autorisations. **Complexité relative :** élevée pour transactions/permissions ; inconnue en charge sans équipe ni mesures. **Limite :** configuration et usages à valider au pilote ; aucun entretien revendiqué.

<a id="c59"></a>
### C59 · Notification ciblée des élèves concernés

**Origine :** Exigence P04. **État constaté :** exigence de conception V2, pas implémentation vérifiée dans l’archive.

**Décision :** Essentielle, destination F19 / F11. **Valeur et justification :** Statut d’exigence vérifié, pas de doublons multi-permis ; canaux facultatifs.

**Dépendances :** identité/école, règles de domaine, données, transactions et autorisations. **Complexité relative :** élevée pour transactions/permissions ; inconnue en charge sans équipe ni mesures. **Limite :** configuration et usages à valider au pilote ; aucun entretien revendiqué.

<a id="c60"></a>
### C60 · Choix GPS indépendant de la leçon

**Origine :** Exigence P02. **État constaté :** exigence de conception V2, pas implémentation vérifiée dans l’archive.

**Décision :** Essentielle, destination F15. **Valeur et justification :** Démarrage explicite et leçon complète sans collecte, sans perte pédagogique.

**Dépendances :** identité/école, règles de domaine, données, transactions et autorisations. **Complexité relative :** élevée pour transactions/permissions ; inconnue en charge sans équipe ni mesures. **Limite :** configuration et usages à valider au pilote ; aucun entretien revendiqué.

<a id="c61"></a>
### C61 · Workspace web de gestion

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F22. **Valeur et justification :** Recherche, filtres, dossiers détaillés et commandes contextuelles dans un navigateur ; même identité et autorisation que l’app.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c62"></a>
### C62 · Tablette sur tous les modules

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F15 F16 F22. **Valeur et justification :** Carte, replay, calendrier, dossiers, cours, documents, bilans et réglages adaptatifs ; pas un téléphone étiré.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c63"></a>
### C63 · Qualification GPS et appareil unique

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F15 F21. **Valeur et justification :** Séparer réseau/localisation, diagnostic lié au matériel/build ; pas relais téléphone-tablette implicite.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c64"></a>
### C64 · Onboarding de l’école

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F20. **Valeur et justification :** Préparer organisation, catégories, offres et politiques par capacité ; modules facultatifs non bloquants.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c65"></a>
### C65 · Accueil élève app et web

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F21. **Valeur et justification :** Profil progressif, catégories souhaitées, déclarations et étapes utiles ; identité existante réutilisée sans transfert de dossiers.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c66"></a>
### C66 · Accueil personnel du moniteur

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F21. **Valeur et justification :** Comprendre ses accès, premières tâches et préparation d’appareil sans refaire le setup de propriétaire.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c67"></a>
### C67 · Reprise multi-appareils et versions

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F20 F21. **Valeur et justification :** Étapes sauvegardées serveur, conflits explicites, reprise ciblée après politique nouvelle.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c68"></a>
### C68 · Archivage guidé, lot et restauration

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F14 F22. **Valeur et justification :** Impact avant archive, états par ligne, historique selon accès, restauration sans réactiver les droits anciens.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c69"></a>
### C69 · Paramètres détaillés et délégation

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F13 F20 F22. **Valeur et justification :** Configuration groupée et droits explicites, effets sur offres futures sans réécriture historique.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c70"></a>
### C70 · Profil administratif et photo facultative

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F09 F21. **Valeur et justification :** Finalités/stades bornés, photos privées nettoyées ; liste minimale distincte du détail.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c71"></a>
### C71 · Indicateurs opérationnels définis

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F23. **Valeur et justification :** Cohortes, périodes, montants et données incomplètes ; pas d’évaluation automatique ni surveillance GPS.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).

<a id="c72"></a>
### C72 · Export de gestion borné

**Origine :** demande utilisateur V3 ou traduction de conception explicitement proposée, pas observation dans le code. **État :** spécifié, non implémenté.

**Décision :** Essentielle au périmètre proposé, destination F22 F23. **Valeur et justification :** Jeu minimal/versionné et filtre autorisé, durée24h proposée, recontrôle et neutralisation CSV.

**Dépendances :** identité scolaire, permissions, données et transactions versionnées. **Complexité relative :** moyenne à élevée suivant adaptation/qualifications et droits ; aucune charge précise affirmée sans équipe ni mesures. **Validation :** parcours, règles et recettes V3 dans la [traçabilité](../06-gouvernance/tracabilite.md).
