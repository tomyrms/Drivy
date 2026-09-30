# Revue et améliorations natives — 30 septembre 2026

## Mandat

Après les deux passes web, le porteur demande une revue de l’application **native iPhone et iPad**, avec corrections de présentation et des difficultés de parcours. Cette autorisation concerne désormais les écrans natifs ; elle ne demande pas de remplacer leur identité « Cartographie native ». Les couleurs, la typographie système, les onglets par rôle et les composants SwiftUI sont conservés.

Trois agents traitent agenda/démarrage, dossiers/compte et séance/carte. L’intégration principale relit les changements, complète les fixtures et coordonne la compilation et les captures Apple. Les réponses de contrôle restent fictives, isolées du réseau dans les seuls builds DEBUG du simulateur.

## Guides appliqués

Le routeur `ui-skills-root` et son catalogue orientent le choix. `swiftui-ui-patterns` couvre les formulaires, feuilles, colonnes et Dynamic Type ; `better-layout`, `better-ui`, `better-typography`, `better-writing` et `better-accessibility` servent aux regroupements, à la hiérarchie, aux cibles et aux libellés. Les prescriptions HTML ou CSS ne remplacent pas les comportements natifs. Les références de conception, contrats et scénarios de chaque parcours restent la source métier.

## Composition et parcours

- **Compte et trajets** : Profil donne un accès direct à une destination Trajets ; l’historique n’est plus repoussé sous toutes les actions du compte. Les préférences de leçon restent accessibles près de cet accès.
- **Agenda et accueil** : repli des titres et actions en grande taille de texte, suppression des lignes de lieu vides, distinction entre erreur de chargement et vraie absence de leçon.
- **Planification et démarrage** : regroupement des données de rendez-vous, réduction des répétitions de durée/prix, états de demande incertaine et reprise de lecture visibles.
- **Dossiers et compte** : contacts, actions et formulaires adaptables ; points d’entrée cohérents vers la leçon et ses formations.
- **Séance et bilan** : rédaction prioritaire sur téléphone, aperçu du trajet plus compact, signalement accessible sans déplacer la liste d’observations.
- **GPS et replay** : choix sans GPS explicite dans la préparation, repères temporels utilisables et signalements adaptés au texte agrandi.
- **Composants communs** : états vides de section moins hauts ; l’illustration de connexion s’efface lorsque la hauteur ou la taille de texte donne priorité au contenu.
- **Reprise et stabilité** : retour manuel à l’accueil du moniteur après « Plus tard », après lecture de son état serveur ; identifiants distincts pour les mois communs aux leçons futures et passées ; saisie du motif de permis protégée à la fermeture.

Les erreurs, états privés, confirmations et écritures durables ne sont pas retirés pour gagner de la place. Les constats précis et leurs limites sont consignés dans les revues spécialisées liées ci-dessous.

## Vérification

Compilation Apple, tests iPhone/iPad et revue des nouvelles captures en attente. Les résultats doivent être ajoutés après exécution ; la lecture du code et les anciennes captures ne constituent pas une qualification du lot courant.

La campagne prévue couvre les écrans de connexion/compte, rejoindre une école, onboarding, agenda, démarrage et planification, dossiers/progression, invitations, trajets, séance/observations et replay. Elle ajoute les écrans côté élève, les préférences personnelles et trois observations renseignées, absents des précédents rendus ciblés.

GPS réel, batterie, haptique, VoiceOver physique et installation/signature iLoader restent distincts des essais simulateur.

## Capacités encore distinctes de cette passe

La photo de profil dépend du circuit documentaire : le serveur refuse actuellement une pièce non disponible (`DOCUMENT_NOT_READY`). Aucun bouton d’envoi sans écriture fonctionnelle n’a été ajouté. L’édition des disponibilités reste sur le web ; le renouvellement automatique de l’accueil à minuit reste à traiter. Le recalage GPS sur la route et sa qualification en circulation relèvent toujours de la campagne terrain décrite dans la liste de retours.

Les captures sont des contrôles de composition et de navigation sur données fictives. Elles ne prouvent ni une authentification réelle, ni une écriture durable, ni la qualité GPS. Les tests de modèle vérifient séparément la reprise, les limites de saisie et les périmètres d’accès.

## Revues spécialisées

- [Agenda et démarrage](native-agenda-review-20260930.md)
- [Compte et dossier](native-account-dossier-review-20260930.md)
- [Séance, GPS et replay](native-field-ui-review-20260930.md)
