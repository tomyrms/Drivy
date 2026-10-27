# Lots 5 à 8 de l'audit UX (27-28 octobre 2026)

Branche `claude/audit-ux-lots-5-8`, empilée sur `claude/audit-ux-lots-2-4`. Code iOS seulement : contrats existants, aucune migration, rien à déployer.

## Lot 5 : agenda et planification

| Ticket | Après |
|---|---|
| #148 A19 | Le mois affiché en tête de l'agenda est un bouton (chevron) qui ouvre « Aller à une date » : calendrier natif dans le fuseau de l'école, date affichée préremplie, « Annuler » ne change rien, « Afficher » ouvre le jour dans l'affichage en cours (semaine ou mois), filtres conservés. |
| #149 A20 | Pendant « Recherche du prochain créneau libre… », bouton « Choisir moi-même » : la date et l'heure s'ouvrent aussitôt sur l'horaire en place. Une proposition arrivée ensuite est ignorée (`startChosenByUser`) ; la vérification du créneau et les règles serveur ne changent pas. |
| #150 A21 | Les trois blocages (aucune formation active, aucun moniteur affecté, aucune disponibilité) disent qui peut agir et proposent une sortie : « Ouvrir sur le web » (portail de gestion) pour l'administration, « Contacter l'école » (coordonnées publiées par l'école) sinon. Au retour dans l'app, la planification est relue sans perdre la saisie. Environnement `schoolPlanningHelp` posé par l'accueil. |

## Lot 6 : cours collectifs

| Ticket | Après |
|---|---|
| #159 A35 | Champ « Langue » dans l'éditeur iOS : Non précisée, Français, Allemand, Italien, Anglais (même liste que le web et le contrat). Une valeur reçue inconnue est gardée telle quelle. |
| #160 A36 | « Nouveau type » ouvre une petite feuille : nom et description (bornes 120 et 2 000 caractères du serveur). Annuler revient au cours ; le type créé est choisi ; même opération rejouée après une réponse perdue. |
| #161 A40 | La ligne « Prévenir des prochaines sessions » existe toujours : chargement, état connu, ou « Suivi des prochaines sessions indisponible » avec « Réessayer ». Aucune bascule avant que l'état soit connu. |

## Lot 7 : bilan et trajets

| Ticket | Après |
|---|---|
| #164 A43 | Les trajets d'une leçon se nomment « 14:05 · 32 min » (plus « Partiel » ou un autre état inhabituel), dans le menu de la carte et dans les liens de repli. Le numéro ne s'ajoute que si deux trajets se lisent pareil ; VoiceOver lit « trajet 2, commencé à 14:05, 32 minutes ». |
| #165 A44 | La section « Partage » du récapitulatif devient « Ce que verra l'élève » : le bilan (comme avant), puis trajet visible ou pour moi, observations visibles et gardées, objectifs, note pour moi. Lu dans les réglages de partage déjà chargés ; rien n'est publié ; sans réglage lu, « visibilité à vérifier ». Tests `SchoolReportFlowTests` ajoutés. |

## Lot 8 : Messages hors fil

| Ticket | Après |
|---|---|
| #166 A45 | Avec le général présent, l'état vide dit « Aucune conversation privée » (sous la ligne du général) ; « Aucune conversation » est réservé à l'absence réelle. Test UI `MessagingThreadUITests` adapté. |
| #167 A46 | En recherche, « Chercher dans plus de conversations » charge la page suivante ; sans résultat alors qu'il reste des pages : « Aucun résultat parmi les conversations chargées ». Aucun index serveur du texte. |
| #171 A56 | Recherche des membres du général (sans casse ni accents), total exact en en-tête (« 3 sur 12 membres »), repère « Réf. » pour les homonymes, retirés filtrés aussi (administrateur seulement). |
| #176 A02 | Pour un compte de plusieurs écoles : nom de l'école en sous-titre de Messages et sous le titre du général, tiré de la portée qui a composé l'entrée. |

#174 (A59) : sans objet depuis #51, le web planifie les leçons.

## Vérification

- Compilation par l'IPA d'essai ; aucun test lancé avant l'essai du porteur.
- À rejouer ensuite : `MessagingThreadUITests`, `SchoolReportFlowTests`, `SchoolReportFlowUITests`, et la suite métier `all`.
- `navigationSubtitle` (iOS 26) n'est vu que sur appareil ; VoiceOver et iPad à vérifier à l'œil.
