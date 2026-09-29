# Revue de chaque écran natif — 29 septembre 2026

Cette revue porte sur l’application Swift iPhone/iPad reliée à l’école. La console web d’administration et l’ancien laboratoire G0 ne sont pas des écrans de cette app. Elle répond au retour terrain du porteur et à sa demande explicite d’appliquer UI Skills.

## Guides réellement installés et utilisés

Dix skills sont installés dans `C:/Users/jtoma/.codex/skills/` avec le programme officiel `skill-installer` : `ui-skills-root`, `improve-ui`, `swiftui-ui-patterns`, `better-accessibility`, `better-colors`, `better-layout`, `better-typography`, `better-ui`, `better-writing`, `interaction-design`. Le catalogue `ui-skills@0.2.4` et sa catégorie SwiftUI ont été interrogés. Ce sont des guides de conception et de revue ; ils n’ajoutent pas une dépendance React à l’app native.

Sources : [UI Skills](https://www.ui-skills.com/), [SwiftUI UI Patterns](https://github.com/Dimillian/Skills/tree/main/swiftui-ui-patterns), [Better Skills](https://github.com/jakubkrehel/skills/tree/main/skills), [Interaction Design](https://github.com/wshobson/agents/tree/main/plugins/ui-design/skills/interaction-design). Les prescriptions web sont adaptées aux contrôles natifs SwiftUI, aux tailles en points, à Dynamic Type et à VoiceOver. Les tokens Drivy sont conservés. Le mandat de correction du porteur autorise l’implémentation au-delà de la seule revue.

Méthode : inventaire des routes actives ; lecture des vues et états ; correction des défauts établis ; compilation Apple ; tests de mutations et de gestes ; rendus synthétiques des vrais composants. Chaque preuve indique sa source. Les captures ne prouvent ni le GPS physique, ni l’autonomie, ni une navigation VoiceOver réellement exécutée.

## Inventaire et rapports détaillés

| Écran ou famille active | Variantes examinées | Guides principaux | Rapport |
| --- | --- | --- | --- |
| Connexion | initiale, attente, erreur, configuration absente | SwiftUI async-state, écriture, accessibilité | [Compte et entrée](ui-review-account-20260929.md) |
| Compte, choix d’école et verrouillage | connecté, contenu masqué, déverrouillage et erreur | SwiftUI sheets, accessibilité, layout | [Compte et entrée](ui-review-account-20260929.md) |
| Rejoindre une école | code et lien, aperçu, erreur, demande en attente, confirmation | formulaires, écriture, états asynchrones | [Compte et entrée](ui-review-account-20260929.md) |
| Profil et onboarding élève | profil/erreur, accueil, informations, formation, GPS, relecture, prêt | formulaires, layout, typographie | [Compte et entrée](ui-review-account-20260929.md) |
| Aujourd’hui et démarrage immédiat | élève affecté, non affecté, aucune leçon | SwiftUI navigation, écriture, UI | [Leçons et suivi](native-lesson-field-review-2026-09-29.md) |
| Agenda et planification | vide, liste, formulaire, indisponibilité | layout, formulaires, accessibilité | [Leçons et suivi](native-lesson-field-review-2026-09-29.md) |
| Élèves, dossier et formations | liste, détail, historique, progression et source | navigation, typographie, layout | [Leçons et suivi](native-lesson-field-review-2026-09-29.md) |
| Leçon et bilan | planifiée, réalisée, fin, permis, tarif, texte vide | sheets, écriture, interaction | [Leçons et suivi](native-lesson-field-review-2026-09-29.md) |
| Invitations | liste, création, résultat code | formulaires, écriture, accessibilité | [Leçons et suivi](native-lesson-field-review-2026-09-29.md) |
| Accord GPS et documents | choix initial/existant, notice, conservation, envoi incertain | sheets, écriture, accessibilité | Détail ci-dessous |
| Préparation du trajet | accord absent/refusé, permission, diagnostic, reprise | async-state, écriture, UI | Détail ci-dessous |
| Trajet en cours | première position, enregistrement, pause, erreur, arrêt durable | interaction, layout, accessibilité | Détail ci-dessous |
| Signalement | thèmes, statut explicite, attente/erreur, avec et sans GPS | grids, sheets, interaction | Détail ci-dessous |
| Observations et édition | liste, repère, type et statut, note privée, reprise | écriture, formulaires, accessibilité | Détail ci-dessous |
| Trajets et replay | historique, carte, liste, sélection, lacune GPS, grandes tailles | layout, couleurs, accessibilité | Détail ci-dessous et [composants](ui-review-shared-20260929.md) |
| Composants partagés | boutons, erreurs, champs, cartes, badges, transport replay | couleurs, typographie, accessibilité | [Composants et mesures](ui-review-shared-20260929.md) |

## Capture, signalement et replay : corrections

| Gravité | Emplacement | Avant | Après | Pourquoi / guide |
| --- | --- | --- | --- | --- |
| HIGH | `SchoolCaptureUI/SchoolLiveObservationSheet.swift`, `SchoolCaptureAPI/SchoolCaptureLiveObservations.swift` | Le geste rapide créait un statut générique sans choix préalable de situation. | **Signaler → type → statut explicite → écriture chiffrée → fermeture.** Tuiles Priorité à droite, Signalisation, Céder le passage et Vitesse lorsque le référentiel scolaire les décrit ; pas de compétence inventée. Même feuille dans les observations sans GPS. | Interaction Design : progression explicite, action liée à l’intention ; SwiftUI grids et sheet(item:). |
| HIGH | `SchoolCaptureUI/SchoolRecordingChoiceView.swift` | Notice développée et confirmations successives. | Avec GPS et Sans GPS enregistrent puis ferment. Deux liens ouvrent les documents complets. Un renvoi n’existe qu’en cas d’enregistrement incertain. | Better Writing/UI : contenu secondaire à la demande ; pas de succès avant confirmation durable. |
| HIGH | `SchoolCaptureUI/SchoolCaptureLiveView.swift` | Fin, transfert et finalisation demandaient plusieurs commandes. | Une commande Terminer la leçon ; arrêt local durable puis synchronisation automatique et bilan. Une panne conserve une action Réessayer. | Interaction Design / async-state : gérer la tâche et son erreur au lieu de faire piloter le protocole. |
| HIGH | `SchoolCaptureCore/` | Une indisponibilité GPS temporaire ou un silence arrêtaient définitivement la collecte. | Acquisition maintenue, cause d’erreur explicite, aucune position créée pour masquer l’attente. | État réel et retour actionnable. [Analyse technique](native-capture-field-corrections.md). |
| MEDIUM | `SchoolCaptureUI/SchoolCaptureReplayView.swift` | Repères rapides lisibles surtout par leur statut et leur heure. | Type lisible dans les puces, la liste et le détail ; statut séparé avec texte et pictogramme. | Better Writing et accessibilité : reconnaître la situation sans dépendre uniquement de la couleur. |
| MEDIUM | `SchoolCaptureUI/SchoolCapturePreparationView.swift` | Refus sauvegardé conservant la préparation ouverte. | Après choix Sans GPS, retour à la leçon ; après Avec GPS, poursuite du départ déjà demandé. | Interaction : fermeture du parcours après son résultat. |
| MEDIUM | `SchoolCaptureUI/SchoolCaptureLiveView.swift`, `SchoolLiveObservationSheet.swift` | Commandes susceptibles de se comprimer en grandes tailles. | Défilement, boutons empilés en taille d’accessibilité, grille à une colonne et cibles d’au moins 44 points. | Better Layout / Typography / Accessibility. |
| MEDIUM | `UI/DrivyComponents+Seance.swift` | Piste non jouée peu contrastée ; transport trop large en compact ; ajustement VoiceOver sans pause. | Contraste opaque, composition qui s’adapte, même arrêt de lecture que le glissement. | Mesures et détails dans la revue des composants. |

Les données de signalement sont horodatées à l’ouverture du geste, avant le choix des boutons. Annuler le type ne crée pas d’observation. Le statut ne sélectionne jamais implicitement une compétence. Le replay conserve les anciens repères génériques comme tels ; aucune situation passée n’est inventée.

## Vérifications

Revue source exécutée. Les rapports Apple, captures examinées et leurs commits sont à compléter après fin de la campagne en cours. **Not verified** : VoiceOver et clavier physique, première acquisition GPS réelle, interruptions/batterie et utilisation simultanée sur les appareils du porteur. L’iPad a une autorisation d’essai serveur ; cela ne remplace pas ces mesures.

La qualification complète d’accessibilité reste ouverte. Aucune approbation n’est étendue aux états ou gestes non exécutés.
