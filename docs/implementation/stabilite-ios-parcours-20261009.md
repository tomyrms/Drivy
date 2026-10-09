# Stabilisation iOS : compte, dossier et cohérence des lectures — 9 octobre 2026

Cette passe conserve la direction visuelle et les destinations existantes. Elle accompagne la correction du démarrage durable des leçons. La référence de conception reste intacte.

## Références et parcours examinés

Lecture de `COMMENCER_ICI.md`, règles R01–R03, R11, R76–R82, contrats AP172–AP177 et recettes T001/T002, T239/T240. L’examen couvre la connexion et les changements d’école, les feuilles de compte/profil/invitation, le dossier et sa progression, la pagination des formations et le filtrage des leçons.

## Corrections

- **Relecture concurrente du compte.** Deux écrans pouvaient relire le compte simultanément sous la même génération. Une réponse ancienne pouvait remplacer les droits récents, le nom ou fermer un compte que la dernière réponse autorisait. Chaque relecture possède désormais sa propre génération ; les anciennes réponses et anciennes erreurs sont ignorées. La lecture silencieuse conserve les écrans ouverts.
- **Formation impossible à rouvrir après un refus temporaire.** Le modèle partagé conservait définitivement `accessRevoked`, même après une nouvelle lecture autorisée du compte et de la formation. Cette lecture réussie rétablit l’accès local ; un nouveau refus continue de purger la projection.
- **Conflit de modification du profil.** Une relecture replaçait auparavant un champ saisi localement sur une nouvelle version du profil, même lorsque ce même champ avait changé au serveur. Le brouillon et sa version de base sont maintenant conservés, l’envoi est bloqué et un rechargement explicite, confirmé, permet de reprendre les informations de l’école. Des modifications de champs différents peuvent toujours être réconciliées ; aucune commande n’est envoyée automatiquement. Le profil et l’accueil guidé partagent cet affichage d’erreur.
- **Contacts ambigus.** La construction des liens d’appel/SMS retirait aussi des lettres et des signes `+` internes : un téléphone accompagné d’une note ou d’un poste pouvait devenir un autre numéro. Seuls les séparateurs de présentation usuels sont retirés ; une valeur ambiguë reste lisible sans action de composition incorrecte.
- **Dossier et historique des leçons.** Les filtres utilisent le démarrage réellement enregistré. Une leçon non démarrée dont l’horaire est passé apparaît dans le groupe « En attente » du dossier, jamais dans « À terminer ». Le filtre d’historique « À terminer » exige lui aussi un démarrage réel. Le souhait pour la prochaine leçon ne vise plus une leçon déjà démarrée.
- **Objectifs perdus au départ du GPS.** La fiche ouverte depuis Aujourd’hui disparaît lorsque l’onglet montre le trajet. Le démarrage d’une leçon et le départ ultérieur du GPS sauvegardent désormais les objectifs et la note modifiés avant cette transition. Un objectif invalide ou un refus d’écriture conserve la saisie et bloque le départ.
- **Fiche fermée après démarrage manuel sans GPS.** La création, la préparation GPS et la fiche de leçon forment une seule chaîne de présentation. Aujourd’hui suspend ses relectures pendant cette chaîne et invalide une lecture déjà en vol ; la fermeture finale relit la journée. L’enregistrement des objectifs, la fin de leçon ou un retour des Réglages ne retirent plus le bouton portant la fiche. Le changement de compte ou d’école reste prioritaire et ferme la chaîne.

## Nettoyage vérifié

Suppression de l’état d’offre unique des invitations, remplacé dans les interfaces par l’ensemble des permis sélectionnés, et de ses propriétés dérivées sans lecteur. Suppression de la projection `pastLessons` non utilisée. L’ancien appel d’accueil `skipOptional` n’avait plus d’appelant produit ; les tests utilisent désormais la commande `skipping` de l’interface réelle, qui conserve les étapes explicitement passées.

L’écran `SchoolTrainingView` est conservé : il sert encore à la revue visuelle. Le dossier produit emploie directement `SchoolTrainingScreen`. Aucun écran n’est retiré sur la seule absence d’un lien depuis la navigation produit.

## Vérification

Tests Swift ajoutés ou étendus : réponses de compte arrivant dans le désordre (succès et refus tardif), réouverture d’une formation après 401, distinction attente/démarrage dans les filtres, souhait après démarrage, numéros ambigus, conflit de profil conservé après plusieurs relectures, rechargement explicite et modifications concurrentes de champs différents. Les tests d’invitation et d’accueil continuent de vérifier les mêmes commandes après le nettoyage.

Les tests de cycle de leçon vérifient également l’ordre sauvegarde des objectifs puis démarrage, la conservation de la saisie après refus, le blocage des objectifs invalides et la même sauvegarde avant un départ GPS ultérieur. La présentation native de toute la chaîne manuelle sans GPS reste à vérifier au simulateur et sur appareil ; ces tests de modèle ne la qualifient pas.

`git diff --check -- apps/ios` exécuté sans erreur de whitespace. Les tests Swift/SwiftUI requièrent la campagne GitHub Actions sur Apple pilotée par la passe principale ; leur résultat final est consigné dans `STATUS.md`. Aucun résultat de compilation, de simulateur ou d’appareil physique n’est déduit de l’inspection Windows.

À vérifier sur les rendus et appareils : présentation du conflit de profil aux grandes tailles de texte, retour des feuilles après rechargement, composition téléphone/SMS via les applications système. Les preuves physiques GPS, batterie et VoiceOver restent distinctes de ces vérifications.
