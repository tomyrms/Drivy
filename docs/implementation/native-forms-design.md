# Planifier, rédiger et relire — hiérarchie native

Revue bornée du 24 septembre 2026, à partir des maquettes `06_planifier_light.png`, `07_rediger_light.png` et `08_apercu_light.png` de la conception 3.17.

Les trois écarts principaux étaient la confirmation de planning enfouie en bas du formulaire, la rédaction du bilan mêlée aux informations secondaires et un aperçu présenté comme un formulaire de gestion.

La reprise conserve les workspaces et leurs validations :

- **Planifier** sépare date et heure, garde la confirmation à l’écran et présente le résumé durée/horaire/prix. Une courte indication aide à trouver le prochain champ à compléter ; elle ne remplace ni `validBooking` ni la validation serveur. Les réglages secondaires restent disponibles en sections repliables.
- **Rédiger** place les trois textes du bilan avant le souhait et les informations de suivi. La limite de caractères ne prend de la place qu’à son approche. Les actions Enregistrer et Aperçu restent visibles, avec le statut du brouillon. Aucune sauvegarde ni publication implicite.
- **Aperçu élève** est une page de lecture, avec son état non publié et les actions Modifier et Publier. La publication conserve `canPublish` et la commande existante ; la préparation privée n’est pas insérée dans l’aperçu.

Le pied d’écran empile les actions aux tailles de texte d’accessibilité. Les dates de leçon suivent le fuseau scolaire et le format français. Cette reprise ne change pas les contrats, les droits, les prix ou les effets financiers.

Contrôle effectué : lecture des vues et des maquettes, contrôle du diff. Aucun nouveau rendu simulateur ni campagne fonctionnelle lancé pour ce lot. La compilation Apple du commit d’intégration reste nécessaire avant sa livraison ; aucune qualification physique n’en découle.
