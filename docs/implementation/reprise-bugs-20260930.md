# Reprise de la passe de correction du 30 septembre 2026

## État retrouvé

La passe de Claude est conservée dans `39704b6` (32 fichiers natifs). Le run Apple `36693678299` compile, mais échoue dans `SchoolTripsTests.theProfileFilterNarrowsWhatTheServerReturnedWithoutWideningIt`. L'IPA indépendante `36693678755` compile ; cela ne qualifie pas la campagne native.

Le test de filtre retournait une enveloppe de trajets à `/v1/me`. Le contrôle d'identité préalable de `SchoolCaptureClient.read(verifying:)` refusait cette réponse et aucun trajet n'était chargé. La fixture distingue désormais compte et trajets ; le test exige un chargement réussi avant de vérifier les filtres. Un nouveau cas change `accessEpoch` avant la pagination et vérifie la purge des trajets, sans nouvelle lecture de capture. Les contrôles de droits du produit restent en place.

La revue complémentaire trouve un chemin de fermeture restant : `SchoolLearnerDetailView.singleTraining` retirait la formation chargée dès que `trainingsError` devenait non nul. La formation conserve maintenant son identité pendant cette panne ; l'erreur de relecture du dossier ou des formations s'affiche avec Réessayer. Les refus d'accès restent traités par le workspace, qui invalide les données concernées.

L'agenda absorbait également toutes les erreurs de relecture au retour sur son onglet, y compris une session expirée. Ce mode silencieux est supprimé ; la feuille de leçon reste portée par la racine stable de l'écran.

Références : conception `COMMENCER_ICI.md`, R36/R37, contrat OpenAPI canonique 3.11.0 (identité et droits courants), scénarios T002/T004/T012 et protocole de preuve ; décisions du 28 septembre pour le partage et la séparation app/web. Le dossier de conception reste intact.

## Backend et homelab

Vérification distante du 30 septembre : release active `5406f65307eb4aee7c70536f309a1b4c7c5e6a5c`, code API/web/infra identique à `39704b6`. Les 20 migrations sont comparées par nom et SHA-256, API/web/identité sont actifs, les processus API/web utilisent la release attendue et la sonde interne de disponibilité répond. Contrôles HTTPS : `/app/` 200, `/refonte/v1/me` 401, santé et administration d'identité non publiques (404).

La preuve privée du déploiement antérieur indique une sauvegarde `pg_dump` vérifiée avant migration020, le 30 septembre à 08:19:55 UTC. Cette reprise ne redéploie pas du code serveur identique et ne modifie aucune donnée hébergée. Les profils GPS d'essai ne valent toujours pas qualification physique.

CI backend exacte de `39704b6`, run `36693678804` : API 218/218 tests sur vraie PostgreSQL 17.11 et Mailpit, web 93/93 tests, typechecks et builds réussis. La recette Docker locale et la nouvelle validation Apple sont consignées dans STATUS à leur achèvement.

## Qualification à terminer

Les corrections de cette reprise doivent encore compiler et passer sur les runners Apple. Sur appareil : démarrer maintenant depuis Aujourd'hui et le dossier, conserver une feuille lors d'une relecture réseau en échec, consulter les trajets et changer de filtre. Aucun essai physique GPS, batterie ou VoiceOver n'est déduit de la compilation ni du simulateur.
