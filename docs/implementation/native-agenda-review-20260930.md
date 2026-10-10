# Revue native — agenda et accueil, 30 septembre 2026

## Périmètre et preuves

Revue de `SchoolAgendaUI/*.swift`, `SchoolUI/SchoolTodayView.swift`, `UI/DrivyComponents+Agenda.swift` et `UI/DrivyComponents+Accueil.swift`. Identité, couleurs et typographie natives conservées. Aucun changement d’API, de contrat de réservation, d’outbox ou de stockage. La limite du lieu des deux parcours correspond à celle de l’API : espaces périphériques retirés, puis 500 unités UTF-16 au maximum. Chaque workspace expose `meetingPointTooLong`, utilisé par sa validation et par le message visible.

Références lues : `AGENTS.md`, `COMMENCER_ICI.md`, F04–F07 de `planning-lecons.md`, R06–R16, contrats AP39–AP46, scénarios T017–T020 et T026–T027. Les décisions ultérieures sur le lieu facultatif et les préférences sont conservées.

Guides réellement lus : `ui-skills-root` (CLI `categories`, puis `list --category swiftui`), `swiftui-ui-patterns` et ses références Form, Controls, Theming et Async state ; `better-layout`, `better-typography`, `better-accessibility`. Application concrète : contrôles SwiftUI natifs, adaptation au contenu avec `ViewThatFits`, labels permanents, cibles d’au moins 44 points, chiffres tabulaires, erreurs visibles et saisie conservée. Les recommandations CSS ne sont pas transposées littéralement au natif.

Captures **avant modification** inspectées : planification iPhone/iPad clair de `artifacts/retours-20260930/visual/36723305491`, accueil iPhone/iPad clair de `native/36727211560/results/test-reports/.../attachments` (`ABB31BFF…png`, `9904A28A…png`). Ces captures utilisent des données synthétiques ; elles ne qualifient pas le rendu des corrections.

## Constats et corrections

| Gravité | Zone | Avant | Après |
| --- | --- | --- | --- |
| Moyenne | Agenda | Mois, retour à aujourd’hui et flèches toujours côte à côte ; CTA de planification à largeur intrinsèque, même en grande taille de texte. | En-tête sur deux lignes lorsqu’il manque de place ; CTA autorisé à revenir à la ligne ; flèches de 44 points conservées. |
| Moyenne | Lignes de leçon et accueil | Un lieu facultatif vide produit encore une ligne de texte et son espacement. | Lignes vides omises, nom et horaires conservés. |
| Moyenne | Planification | Durée et prix répétés dans le formulaire et la barre ; une section distincte seulement pour la fin prévue. | Durée regroupée avec la quantité ; prix total toujours visible dans la barre ; fin prévue avec le rendez-vous. Accord de déplacement et acceptation commerciale restent explicites. |
| Moyenne | Planification, démarrage immédiat | Lieu écrasé contre le label en taille d’accessibilité ; aucun message au-delà de sa limite. | Label au-dessus du champ aux tailles d’accessibilité, erreur à côté du champ lorsque la valeur normalisée dépasse la limite de l’API ; clavier refermable par défilement. |
| Moyenne | Démarrage immédiat | Une opération relue depuis l’outbox n’est affichée que si un message d’erreur existe ; champs encore modifiables pendant une demande en attente. | Demande en attente visible même sans erreur ; reprise seulement pour une commande de démarrage du même périmètre ; saisie bloquée pendant chargement, envoi ou attente. |
| Moyenne | Démarrage immédiat | Échec de lecture sans action de reprise ; formation unique présélectionnée invisible. | Relecture disponible lorsque le contexte manque, lieu saisi conservé pour le même élève ; formation unique affichée. |
| Moyenne | Accueil | Première lecture en erreur accompagnée de « Aucune leçon » ; CTA « Terminer » proposé à un lecteur non auteur. | L’erreur remplace le faux état vide ; terminaison affichée seulement au moniteur de la leçon. Le résumé reste ouvrable par les lecteurs autorisés. |
| Faible | Préférences | Message « enregistrées » visible après une nouvelle modification non enregistrée. | Message masqué tant que les valeurs diffèrent de celles relues. Injection d’outbox ajoutée à l’initialiseur pour les captures en mémoire. |
| Faible | Déplacement et annulation | Motif et accord encore éditables pendant la confirmation. | Même verrou de mutation que le reste du formulaire. |

Documents et composants d’accueil guidé inspectés : largeur de lecture bornée, texte sélectionnable pour les documents, labels permanents et taille de texte sémantique déjà présents ; pas de modification cosmétique supplémentaire.

## Invariants et vérification

- Les créations, déplacements et annulations appellent toujours les mêmes commandes et validations du workspace. Aucun succès ajouté avant réponse durable.
- Le lieu reste facultatif. Documents commerciaux, procédure, annulation, prix total, quantité et confirmations restent accessibles.
- Les autorisations d’affichage améliorent le parcours ; le serveur reste seul décideur. Une opération d’un autre type n’obtient pas un bouton de reprise de démarrage.
- Contrôle `git diff --check` exécuté sans erreur. Aucun test miroir ajouté pour les changements de disposition.
- Deux tests métier ciblés ajoutés aux suites existantes `SchoolPlanningDefaultsTests` et `SchoolStartNowClientTests` : précondition d’un modèle éligible vérifiée, puis lieu vide/facultatif, espaces seuls, 500 ASCII, 500 ASCII entourés d’espaces, 250 emoji acceptés ; 501 ASCII et 251 emoji refusés. Aucun envoi de commande n’est nécessaire pour ces vérifications locales. Exécution sur Apple à qualifier.
- Revue croisée : la reprise après échec du stockage relit désormais les affectations sans conserver une ancienne sélection active. Le chargement vide immédiatement élèves et formations, puis revalide l’ancien élève dans la réponse actuelle avant de relire ses formations. Un troisième test couvre la disparition de cet élève alors que deux autres restent proposés ; la commande demeure indisponible et aucune écriture n’est envoyée.
- **Non vérifié ici** : compilation Swift, interaction avec Dynamic Type sur appareil/simulateur, clavier iPad et VoiceOver. Windows ne fournit pas le compilateur Apple ; compilation et captures confiées à la racine sur le runner Apple. La lecture visuelle des captures après correction, y compris AX3, est consignée ci-dessous.

À recontrôler dans les fixtures : agenda en taille AX avec date longue ; démarrage avec une formation, plusieurs formations, lieu long et demande en attente ; planning quantité supérieure à un ; lecture des documents ; préférences modifiées après sauvegarde ; accueil élève avec leçon passée et lecture en erreur. Les cas d’annulation active doivent toujours conserver le hook d’arrêt de capture avant la commande.

## Limites relevées hors corrections de présentation

La journée d’accueil est chargée à l’entrée et à la fermeture de ses feuilles ; le minuteur recalcule l’état visuel mais ne recharge pas automatiquement une nouvelle journée à minuit. Les disponibilités ne sont pas éditables dans ce formulaire natif et renvoient explicitement vers le web. Ces constats ne sont pas annoncés comme des capacités nouvelles.

## Revue visuelle des captures après correction

Les dix PNG originaux suivants ont été ouverts individuellement avec `view_image`, sans montage, retouche ni rotation, depuis `artifacts/native-ui-20260930/journeys/`. Ils montrent les fixtures synthétiques en portrait, thème clair, taille de texte standard. Le rendu ci-dessous qualifie uniquement le contenu visible des images ; aucune interaction ni lecture VoiceOver n’a été exécutée pendant cette revue.

| Fichier exact | Observation visuelle |
| --- | --- |
| `iPhone-home-tabs-light-synthetic.png` | État « Position indisponible » lisible, sans indicateur de chargement ; carte de leçon, statut inhabituel, action « Terminer la leçon » et onglets visibles. |
| `iPad-home-tabs-light-synthetic.png` | Même état sans position ; panneau de leçon de largeur bornée, action et accès aux leçons du jour entièrement visibles. Le grand espace libre correspond à la zone de carte indisponible. |
| `iPhone-agenda-light-synthetic.png` | Mois, sept jours, filtre d’école, planification et trois premières leçons lisibles. La quatrième ligne continue sous la barre d’onglets translucide ; une capture statique ne qualifie pas son accès après défilement. |
| `iPad-agenda-light-synthetic.png` | Sept jours et quatre leçons visibles, heures/noms/statuts alignés, « Planifier une leçon » entièrement affiché ; aucun chevauchement ni chargement visible. |
| `iPhone-planning-light-synthetic.png` | Sélection élève/formation, rendez-vous et fin prévue lisibles. Barre fixe avec durée, date, prix, explication et confirmation entièrement visible. Le titre « Le tarif » commence sous le pli : tarif, acceptation et documents nécessitent une revue après défilement. |
| `iPad-planning-light-synthetic.png` | Formulaire complet, quantité/durée, acceptation explicite, liens de documents et barre de confirmation visibles. Bouton désactivé accompagné de son motif ; aucun texte tronqué. |
| `iPhone-planning-settings-light-synthetic.png` | Deux préférences chargées à « Aucune »/« Aucun », labels complets, « Enregistrer » désactivé sans changement. Le reste de la surface est vide, sans erreur ni chargement. |
| `iPad-planning-settings-light-synthetic.png` | Même état cohérent ; grande surface libre entre les deux champs et l’action fixe. Aucun contenu ou bouton coupé visible. |
| `iPhone-start-now-light-synthetic.png` | Élève et formation présélectionnés visibles, lieu explicitement facultatif et valeur complète ; action « Démarrer maintenant » entièrement visible et active. |
| `iPad-start-now-light-synthetic.png` | Même contenu sans troncature ; grande surface libre sous les trois champs, action fixe entièrement visible. |

Aucun défaut bloquant de rendu n’est constaté sur ces dix images. La densité des formulaires courts sur iPad demeure faible : les champs occupent toute la largeur et l’action reste en bas, avec un grand espace entre les deux. Ce constat de disposition ne prouve pas une perte de contenu et n’a entraîné aucune modification du produit pendant la revue.

Limites : ces images ne montrent pas les menus ouverts, le clavier, les sections secondaires dépliées, les documents, les erreurs de stockage, une demande en attente ou une préférence modifiée. Le harnais de capture attend la fenêtre et dix secondes avant ces écrans, sans assertion de leur contenu prêt (`VisualOrientationTests.swift:35–45`, voie `simctl` dans `capture-screens.sh`) ; un succès de capture seul n’est donc pas une qualification fonctionnelle. La lecture des dix PNG confirme ici un contenu chargé et aucune erreur de fixture visible.

### Grand texte AX3

Six PNG supplémentaires de `artifacts/native-ui-20260930/large-text/` ont ensuite été ouverts individuellement avec `view_image`, toujours sans transformation. Ils sont annoncés par la campagne en AX3 et mode sombre. **Les trois images iPhone montrent pourtant un fond clair** : leurs noms de fichiers ne suffisent pas à qualifier le thème sombre. Les trois images iPad montrent bien le thème sombre.

| Fichier exact | Observation visuelle |
| --- | --- |
| `iPhone-agenda-dark-synthetic.png` | Défaut confirmé : le label du sélecteur de date se découpe en « Cho / isir / un / jour », comprimé par la date restée à droite. Le mois et les flèches passent bien sur deux lignes ; la planification reste lisible. |
| `iPad-agenda-dark-synthetic.png` | Label/date lisibles sur une ligne, actions et leçons visibles, aucun chargement ni troncature dans la zone affichée. |
| `iPhone-planning-dark-synthetic.png` | Défaut confirmé : le résumé de confirmation tronque l’heure en « 50 min · jeu. 1 oct. · 1… ». Sa grande barre fixe occupe le milieu de la capture et réduit fortement l’espace du formulaire ; une ligne « Date » est visible sous elle avant le pied synthétique. La confirmation revient à la ligne mais son texte demeure complet. |
| `iPad-planning-dark-synthetic.png` | Labels et valeurs empilés, résumé/date/prix entiers, motif d’indisponibilité et confirmation visibles. Les sections tarif/documents sont sous le pli. |
| `iPhone-start-now-dark-synthetic.png` | Labels et valeurs empilés, lieu sur deux lignes sans troncature, action complète sur deux lignes. Aucun chargement ni erreur visible. Le rendu est clair malgré le nom du fichier. |
| `iPad-start-now-dark-synthetic.png` | Labels et valeurs empilés et entièrement lisibles ; lieu et action restent sur une ligne, aucune troncature ni erreur visible. |

Les deux défauts iPhone ont été signalés immédiatement à la racine avant toute modification, puis corrigés après coordination : label séparé du contrôle de date aux tailles d’accessibilité, avec son nom accessible conservé ; résumé autorisé à prendre sa hauteur complète ; récapitulatif, motif d’indisponibilité et confirmation rendus dans une dernière section du formulaire aux tailles AX. La barre fixe reste utilisée aux tailles standard. Les mêmes contenus, commande, validation et identifiant de confirmation sont réutilisés ; les erreurs et demandes en attente restent en tête du formulaire. `git diff --check` des deux vues est sans erreur. Ces corrections nécessitent une nouvelle compilation et de nouvelles captures : les six images décrivent leur état antérieur.

Le pied synthétique est lui aussi agrandi ; cette capture seule ne permet pas de séparer tous ses effets de ceux du conteneur produit. Une variante de planification réellement défilée et une application explicite du thème sont préparées par la racine pour poursuivre la revue.
