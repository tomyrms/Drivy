# Agenda et équipe natifs

## Références

Maquettes réellement ouvertes : `02_agenda_light.png`, `15_agenda_eleve_light.png`, `05_lecon_light.png`, `13_ecole_light.png`. Lecture de E03, E04, E16 et de la charte UI/UX. Le lot porte sur `SchoolAgendaView` et `SchoolMemberView` ; les clients, workspaces, routes atomiques et commandes serveur restent ceux de l’intégration.

## Agenda

Les leçons forment une liste chronologique séparée par des filets, avec horaire, élève disponible dans le périmètre, durée, état et rendez-vous. La colonne horaire n’a plus une largeur fixe de 52 points ; en taille d’accessibilité, elle passe au-dessus du reste. Les leçons annulées gardent leur état explicite.

La semaine conserve ses sept jours tant que chaque cible peut mesurer au moins 44 points. Le sélecteur natif de date prend le relais en largeur insuffisante ou en grand texte. Les dates utilisent le fuseau de l’école ; le jour sélectionné et la présence de leçons ont une description accessible. Une lecture inconnue n’est pas présentée comme une journée vide. L’état vide propose le jour suivant.

La fiche de leçon reprend des lignes date/horaire/durée/lieu/prix, avec valeurs empilées en grand texte. Les commandes et gardes restent les mêmes ; les mots du suivi se distinguent pour le moniteur et l’élève. Aucun faux bouton de capture scolaire n’est ajouté : ce raccord dépend de l’intégration du protocole de capture.

## Équipe

Le titre et le nom d’école suffisent à introduire la liste. Les personnes utilisent des lignes natives compactes, avec rôles et révocation lisibles. La recherche vide se distingue de l’absence de membres ; elle peut être effacée directement. Le mode d’ajout nomme son action réelle : attribuer le rôle Élève à un membre existant.

L’éditeur garde le motif visible et place sa confirmation en bas. Les gardes existantes restent autoritaires ; les explications des champs manquants accompagnent le bouton désactivé. Le formulaire est gelé pendant la reconnexion et l’envoi. Les reprises incertaines et la confirmation du retrait de son propre rôle administrateur sont conservées.

## Preuve

Relecture ciblée et `git diff --check`. Compilation Apple groupée à confirmer ; ces deux écrans n’ont pas encore de nouveau rendu simulateur ni de qualification VoiceOver/appareil physique. La revue catalogue/dossier/bilan est un autre périmètre.
