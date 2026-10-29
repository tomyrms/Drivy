# Aujourd’hui : rendez-vous mixtes — #207

29 octobre 2026, base `c94ec2bb`. Issue ouverte et sans commentaire ; aucun commit/PR de réalisation correspondant trouvé. Le panneau lisait seulement les leçons individuelles alors que l’agenda possède déjà `SchoolAgendaEvent` et `SchoolAgendaCourses`.

## Réalisation

- Réutilisation de la lecture et de la projection Agenda : occurrences publiées attribuées au moniteur, dans le jour du fuseau scolaire. Une offre élève, une proposition de liste d’attente, un brouillon ou une annulation ne deviennent pas un rendez-vous.
- Priorité explicite : leçon de la capture connue, leçon commencée aujourd’hui, leçon commencée un jour précédent, cours actuellement en cours, prochain rendez-vous chronologique, puis leçon manquée non commencée.
- Les autres engagements restent ouvrables, première ligne directe puis dépliage local. Une leçon ancienne montre sa date. Les cours écoulés sans action requise ne concurrencent plus le prochain rendez-vous.
- La fiche de cours existante reçoit l’ID exact d’occurrence. Participants/appel restent gérés par les droits et horaires existants du détail. Aucune action GPS de cours.
- Un cours futur conserve aussi « Démarrer une leçon » en action secondaire : le moniteur peut lancer une leçon individuelle immédiate. Un cours en cours ne propose pas ce raccourci. Le serveur continue à contrôler les conflits du planning.
- Les lectures leçons/cours sont indépendantes. Échec ou borne de 200 cours restent signalés ; une source seule ne prouve pas une journée vide. Les résultats sont isolés par compte, appartenance, époque, école, rôles, fuseau et jour. Un refus d’accès efface le contenu et relit les droits.

DA : `DrivyMapDock`, `DrivyLessonRow`, couleurs/espacements Drivy, feuille de détail existante et `DisclosureGroup` SwiftUI. Aucune dépendance. Règles R62/R64, cours-collectifs, calendrier-notifications et contrats AP145–AP151 consultés ; l’adaptateur courant `SchoolCourseClient` reste la source d’intégration, sans changement du contrat canonique.

## Vérification et recette

`git diff --check` exécuté. Tests ciblés préparés dans `SchoolTodayAppointmentsTests` : cours seul/occurrence exacte, mixte chronologique, leçon active/ancienne/capture prioritaire, attribution/draft/annulation/espace élève, jour scolaire autour de minuit et changement d’heure. **NOT_EXECUTED** : tests, compilation Apple et recette visuelle (réservés au coordinateur et à la validation de l’IPA finale).

À essayer sur l’IPA : journée de cours seul, journée mixte, leçon ancienne non terminée, ouvrir l’appel de la seconde occurrence puis revenir ; panne de chaque source séparément ; changement d’école/de droits ; grand texte et VoiceOver. Le rappel d’historique garde sa limite existante de cinq pages et sa gestion existante des erreurs ; il ne revendique pas l’exhaustivité de tout l’historique. L’espace élève conserve son parcours personnel d’inscriptions ; ce panneau terrain ne lit pas les publications comme engagements élèves.

Périmètre iOS seulement. Ni web/EPIC #311, ni API, ni workflows, ni déploiement, ni fusion. Aucun test complet lancé.
