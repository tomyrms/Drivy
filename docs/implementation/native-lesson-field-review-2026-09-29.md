# Leçon, historique et agenda — retour d’essai du 29 septembre 2026

Cette passe reprend le retour d’essai sur appareil. Elle applique la demande explicite de terminer sans confirmation des horaires, d’enregistrer un bilan vide ou partiel et de fermer le parcours après sa sauvegarde. Les textes du bilan deviennent facultatifs, conformément à cette décision ; le dossier de conception livré reste intact. R07 (permis), R15 (arrêt local avant constat), R17 (appréciations) et R45–R46 (replay et observations distinctes des niveaux) restent pris en compte avec la décision de partage du 28 septembre.

## Méthode et limites

Revue des sources avec les guides UI Skills `swiftui-ui-patterns` (état, sheets, navigation, formulaires), `better-writing`, `better-layout` et `better-accessibility`. Les contrôles natifs SwiftUI sont conservés : `Form`, `Button`, `Picker`, `Toggle`, `NavigationStack` et `NavigationSplitView`. Les recommandations DOM/ARIA des guides sont transposées aux noms accessibles, traits, contrôles natifs et tailles tactiles iOS, sans ajouter du code web.

Cette note rassemble la revue des sources et les vérifications Apple explicitement relevées ci-dessous. Elle ne constitue pas une preuve VoiceOver ou GPS physique. Les captures de la passe précédente ne qualifient pas les nouveaux parcours ; toute revue visuelle doit identifier ses propres fichiers et sa révision.

## Corrections

| Gravité | Source | Avant | Après | Pourquoi |
| --- | --- | --- | --- | --- |
| HIGH | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportView.swift`, `SchoolLessonCompletionSheet.swift` | Terminer ouvrait une confirmation avec deux dates ; l’arrêt et l’envoi du trajet restaient des étapes manuelles. | `finishForLesson` confirme l’arrêt local durable ; les heures proviennent de cet arrêt, sinon des captures connues et du planning. Le constat suit sans attendre le transfert. Seule l’exception permis ouvre une feuille. | Retirer la confirmation répétitive et respecter R15 sans laisser un transfert réseau bloquer la clôture. |
| HIGH | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift`, `SchoolLessonReportView.swift` | Enregistrer était désactivé si le bilan était vide et inchangé ; le succès ne fermait pas la leçon. | Les trois textes sont facultatifs. Le reçu de `SAVE_REPORT_DRAFT`, puis le retrait de la file chiffrée, déclenchent `reportSaveConfirmed`. Le contrôleur détache le trajet de l’interface et la feuille se ferme. | Un bilan vide est un choix valable ; aucune fermeture anticipée sur réponse incertaine. |
| HIGH | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift`, `apps/ios/Drivy/SchoolTrainingUI/SchoolTrainingWorkspace.swift` | Le replay n’était proposé que dans Trajets ; l’historique désactivait l’ouverture ADMIN. | Chaque capture reconstruite d’une leçon propose « Revoir le trajet ». L’historique ADMIN ouvre la leçon et ses captures sans demander le brouillon, le souhait, les observations privées ou les révisions réservées à la pédagogie. | Le replay reste accessible depuis la leçon, avec les droits relus au serveur et les notes privées protégées. |
| HIGH | `apps/ios/Drivy/SchoolAgendaUI/SchoolStartNowView.swift`, `apps/ios/Drivy/SchoolAPI/DrivyAPIClient.swift`, `SchoolModels.swift` | ADMIN + INSTRUCTOR pouvait choisir un élève affecté seulement à un autre moniteur. | La liste de départ demande `instructorMembershipId=self` ; les formations proposées ont `startNowBlockerCode=null`. Une liste vide indique la correction d’affectation à demander. Le décodeur explicite lit ce nouveau champ ; le premier essai Apple a détecté son omission. | Éviter de proposer une action que les droits métier refuseront, sans confondre accès administratif et affectation pédagogique. |
| HIGH | `apps/ios/Drivy/SchoolCaptureUI/SchoolCaptureLiveObservations.swift`, `SchoolObservationUI/SchoolObservationWorkspace.swift` | Sans GPS, la fermeture du choix de signal pouvait recharger la liste avant la confirmation réseau ; une demande déjà acquittée restait ensuite affichée en attente. | Le recorder avertit le workspace après la fin effective de l’envoi. La relecture a sa propre génération et un workspace invalidé reste fermé. | Réactiver l’ajout sans actualisation manuelle, conserver le même UUID et ne retirer la demande qu’après confirmation durable. |
| MEDIUM | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportView.swift`, `SchoolLessonCompletionSheet.swift` | Le tarif occupait une section dans le bilan. | L’action « Tarif » du menu ouvre une feuille séparée avec prix convenu et solde autorisé. | Garder le formulaire centré sur le bilan tout en conservant l’information financière. |
| MEDIUM | `apps/ios/Drivy/SchoolTrainingUI/SchoolTrainingView.swift`, `apps/ios/Drivy/SchoolLessonReportAPI/SchoolLessonReportModels.swift` | L’ancien intitulé pouvait être affiché depuis le référentiel ou une projection de progression. | « Anticipation » est utilisé dans les observations, les choix de niveau et la progression, avec compatibilité pour une ancienne projection. | Vocabulaire bref et constant, sans changer l’identifiant de la compétence. |
| MEDIUM | `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningView.swift`, `apps/ios/Drivy/SchoolInvitationsUI/SchoolInvitationsView.swift` | Les formulaires pouvaient s’étendre sur toute la largeur iPad ; Planning relisait son modèle à toute réapparition. | Largeur maximale 820 points, formulaire centré ; modèle Planning conservé lorsqu’il est déjà chargé. | Limiter la distance entre libellés et champs et préserver la saisie au retour d’une présentation. |

## Inventaire des écrans relus

| Écran réel | Source principale | Contrôles de source | Rendu requis |
| --- | --- | --- | --- |
| Agenda semaine/jour | `SchoolAgendaUI/SchoolAgendaView.swift` | Flèches 44 pt nommées, date alternative en grandes polices, sélection annoncée, ligne ouvrant directement la leçon, erreur/reprise, filtre école/moniteur. | `agenda`, clair/sombre, iPhone/iPad et grande police. |
| Démarrer maintenant | `SchoolAgendaUI/SchoolStartNowView.swift` | Sélection autorisée, formation éligible, bouton occupé, erreur conservée, reprise même opération, fermeture seulement après réponse métier. | Capture de la sélection et des blocages d’affectation ; contrôle interactif. |
| Planifier / déplacer | `SchoolAgendaUI/SchoolPlanningView.swift` | Sections rendez-vous/prestation, prix et conditions, motif de déplacement, hint pour bouton indisponible, commande protégée, saisie stable. | `planning` ; déplacement et grande police à exercer séparément. |
| Annuler une leçon | `SchoolAgendaUI/SchoolPlanningView.swift` | Motif, action destructive nommée, confirmation de conséquence, fermeture après succès. | Annulation et erreur à exercer séparément. |
| Leçon planifiée | `SchoolLessonReportUI/SchoolLessonReportView.swift` | Objectifs, note privée, préparation GPS facultative, action Terminer sans horaires éditables. | `lesson-planned` et test `lesson-finish`. |
| Permis manquant à la clôture | `SchoolLessonReportUI/SchoolLessonCompletionSheet.swift` | Confirmation de permis par le compte habilité ou motif, aucune date inventée/saisie, contrôle de longueur, erreur persistante. | Exception permis à exercer ; pas couverte par `lesson-finish` dont le permis est validé. |
| Bilan auteur terminé | `SchoolLessonReportUI/SchoolLessonReportView.swift` | Trois textes facultatifs avec libellés permanents, sauvegarde vide, niveaux distincts des événements, conservation lors d’erreur, fermeture après reçu. | `lesson` + test de sauvegarde vide `lesson-finish`, grande police/clavier. |
| Leçon élève / moniteur non auteur / ADMIN | `SchoolLessonReportUI/SchoolLessonReportWorkspace.swift` | Lecture indépendante des métadonnées/captures et contenus pédagogiques ; aucun appel au brouillon privé non auteur. | Variantes de rôle à exercer ; test Swift ADMIN préparé. |
| Tarif | `SchoolLessonReportUI/SchoolLessonCompletionSheet.swift` | Feuille secondaire, valeurs issues des projections autorisées, bouton Fermer natif. | `lesson-tariff`, iPhone/iPad. |
| Historique de formation | `SchoolTrainingUI/SchoolTrainingView.swift`, `SchoolTrainingWorkspace.swift` | Groupes Prévues/Passées, ouverture de chaque leçon, pagination, relecture au retour sans effacer la liste, états de droits. | `learner`, ouverture historique → leçon → replay. |
| Progression | `SchoolTrainingUI/SchoolTrainingView.swift` | Pas de moyenne, niveau et contexte écrits, compétences non observées distinctes, lien vers la leçon source, menu si Dynamic Type accessible. | `progression`, clair/sombre et grande police. |
| Liste Élèves / recherche | `SchoolUI/SchoolBrowserView.swift` | Liste/split view natif, recherche effaçable en état vide, chargement et erreur distincts, pagination, noms de boutons. | `learners`, recherche vide et grande police. |
| Dossier à une ou plusieurs formations | `SchoolUI/SchoolBrowserView.swift` | Une formation ouvre directement l’historique ; plusieurs formations restent sélectionnables ; coordonnées en actions secondaires, cibles de contact 44 pt. | `learner`, variante plusieurs formations à exercer. |
| Invitations liste/détail | `SchoolInvitationsUI/SchoolInvitationsView.swift` | Split view, statut écrit + symbole, identité du code séparée du secret, commande incertaine avec reprise, actions destructives explicites. | `invitations`, sélection d’un détail sur iPhone/iPad. |
| Créer un code élève | `SchoolInvitationsUI/SchoolInvitationsView.swift` | Choix permis multiples et moniteur, dépendances indisponibles explicites, hint de sélection, bouton occupé, formulaire iPad borné. | `invitation-create`, clair/sombre et grande police. |
| Code créé | `SchoolInvitationsUI/SchoolInvitationsView.swift` | Code épelé pour VoiceOver, sélection/copie, annonce « Code copié », échéance, actions Partager/Copier explicites. | `invitation-code`, grande police ; partage/copie avec matériel réel. |
| Révoquer une invitation | `SchoolInvitationsUI/SchoolInvitationsView.swift` | Motif libellé, conséquence affichée, confirmation destructive, demande incertaine persistante. | Révocation et reprise à exercer séparément. |

Les états erreur, chargement, vide et occupé sont inspectés dans les sources. Le clavier physique, l’ordre VoiceOver, la restitution vocale, les contrastes mesurés et le rendu à la plus grande police ne sont pas vérifiés par cette lecture.

## Vérifications et fixtures

- `SchoolLessonFinishTests.swift` : sept tests couvrent bilan vide, prochaine étape seule, contexte de compétence vide, reçu perdu puis vérifié sans second envoi, refus avec texte conservé, replay ADMIN sans lecture privée et filtre de départ. Le résultat intermédiaire Apple figure ci-dessous ; le dernier test et les corrections restent à qualifier dans le prochain run. Les projections API gardent `context` sous forme de chaîne, vide si omis ; la validation native suit cette règle. Le corps d’un bilan partagé masque chaque texte vide et affiche un seul état neutre si les trois sont vides.
- Les tests existants `SchoolLessonHubTests` couvrent heures natives, permis, conflit/relecture et confidentialité des textes. Ils restent nécessaires.
- `SchoolOfficeVisualReview.swift` n’est compilé qu’en DEBUG sur simulateur. Entrées `planning`, `invitations`, `invitation-create`, `lesson-tariff`, `lesson-finish`. Transport synthétique sans réseau ; commandes et reçus de clôture/sauvegarde isolés en mémoire. Le test UI peut constater la disparition de la feuille via `field-lesson-closed`.
- `git diff --check` exécuté sans erreur. La compilation Release de la première passe `f054bc6` a réussi dans le run IPA `36578201723`. Le run de tests `36578200981` a échoué avant exécution, sur les références d’acteur du harness DEBUG `SchoolFieldVisualReview` ; correction par la racine dans `d769e14`, dont les résultats figurent ci-dessous.

Approve pour la revue des sources de ce périmètre uniquement. Captures et interactions Apple de la nouvelle passe : Not verified à la rédaction. Essai physique GPS/batterie/VoiceOver : Not verified.

## Résultat intermédiaire Apple `d769e14`

Le run `36578697029` compile les cibles natives et exécute les tests sur simulateur. Les résumés téléchargés dans `artifacts/review-20260929/native-field-tests/d769/test-reports/` comptent **165 tests iPhone : 162 réussis, 3 échecs, 0 ignoré**, et **7 tests iPad : 6 réussis, 1 échec, 0 ignoré**. Aucun échec attendu n’est déclaré. Le run global est en échec et ne qualifie pas la version finale.

Les cinq scénarios de bilan présents dans cette révision passent : sauvegarde vide, prochaine étape seule, reçu perdu puis vérifié sans second PUT, refus conservant le texte et replay ADMIN sans lecture pédagogique privée. Le scénario départ échoue et détecte une vraie omission : `SchoolTraining.init(from:)` ne décodait pas `startNowBlockerCode`. Le correctif lit ce champ facultatif explicitement ; il reste à revérifier sur Apple.

Les deux autres causes concernent les serveurs synthétiques des essais : le test unitaire des thèmes omettait les clés nullables requises `startedOn`, `closedOn` et `nextCursor` ; le test UI de qualification utilisait un statut HTTP 200 au POST alors que le client exige le 201 contractuel. Ce dernier échec apparaît sur les deux formats. Les réponses des fixtures ont été corrigées sans assouplir le client métier. Le test UI consentement et documents à la demande ainsi que la clôture avec bilan vide passent sur les deux formats dans cette révision.

Deux tests supplémentaires de réponse différée vérifient le rafraîchissement automatique des observations sans GPS et le maintien de l’invalidation après changement d’accès. Ces tests, le contexte d’appréciation vide et les correctifs ci-dessus attendent le résultat du prochain run Apple. Les captures des écrans restent évaluées séparément des tests.

## Rendus Office `ed56802` — 14 PNG inspectés

Le run `36580005091` a réussi. Les 14 PNG originaux, téléchargés dans `artifacts/review-20260929/office-visual/36580005091/`, ont tous été ouverts individuellement, sans retouche. La [preuve avec empreintes](proofs/ui-office-renders-ed568-20260929.json) distingue le constat et le correctif encore à recapturer.

| Écrans | Formats et apparence | Constat visuel |
| --- | --- | --- |
| `planning` | iPhone + iPad, clair | Formulaire lisible, valeurs sélectionnées visibles ; action indisponible accompagnée du motif d’acceptation manquante. Sur iPad, prestation et conditions sont visibles dans la colonne centrée. Valeurs secondaires trop pâles : correction ci-dessous. |
| `invitations` | iPhone + iPad, clair | Trois lignes lisibles ; Utilisé et Expiré combinent texte et symbole. Split view iPad avec invitation à sélectionner, sans détail privé affiché avant sélection. |
| `invitation-create` | iPhone + iPad, clair | Permis et moniteur lisibles ; action Créer le code entièrement visible. Formulaire iPad centré. |
| `lesson-planned` | iPhone + iPad, clair | Objectifs, action d’observation et bouton Terminer lisibles. Badge À terminer cohérent avec la date passée ; aucun bloc « Aucun trajet en cours ». |
| `lesson` | iPhone + iPad, clair | Revoir le trajet reste visible avec la carte synthétique fragmentée ; partage identifiable ; Enregistrer le bilan entièrement visible. Sur iPad, les trois textes sont visibles et ne débordent pas. Le bas du formulaire iPhone nécessite de défiler et n’est pas qualifié par cette seule image. |
| `lesson-tariff` | iPhone + iPad, clair | Deux valeurs isolées dans la feuille secondaire, sans occupation du bilan. Contraste insuffisant des valeurs, corrigé dans les sources. |
| `lesson-finish` | iPhone + iPad, clair | Présentation initiale réelle de la feuille ; commande Terminer visible dans sa zone sûre. La capture ne simule pas l’appui : le succès et la fermeture viennent du test UI distinct. |

**MEDIUM, contraste corrigé dans les sources, rendu après correction en attente.** Dans `iPhone-lesson-tariff-light-synthetic.png`, les pixels pleins du montant CHF 95.00 sont `#8A8A8E` sur `#FFFFFF`, soit **3,4389:1**, sous 4,5 pour ce texte de taille courante. Les valeurs de `LabeledContent` utilisaient le gris système. Les deux valeurs Tarif et les sept valeurs Planning (y compris déplacement) emploient désormais explicitement `DrivyTheme.muted`, token déjà mesuré à 6,3066:1 sur la surface claire. La recherche dans les sources de ce périmètre ne trouve pas d’autre `LabeledContent`. Aucun texte ni structure n’a changé.

Aucun autre défaut bloquant de mise en page n’est observé sur ces 14 vues initiales. Cela ne qualifie pas les états hors écran, le clavier, les grandes polices, les variantes sombres ni les interactions non exécutées.

## Rendus du suivi `ed56802` — 16 PNG inspectés

Le run `36580009494` a réussi. Les 16 PNG originaux dans `artifacts/review-20260929/office-visual/36580009494/` ont tous été ouverts individuellement ; la [preuve avec empreintes](proofs/ui-home-renders-ed568-20260929.json) en conserve le compte et les limites. Au total, cette revue a inspecté **30 PNG originaux** de ces deux runs, représentant 15 entrées de rendu sur iPhone et iPad en clair.

| Écrans | Constat sur les deux formats |
| --- | --- |
| `home-tabs` | Carte chargée, commande Terminer lisible dans la carte de leçon, accès Leçons du jour et onglets visibles. Le fond cartographique n’est pas une preuve de position GPS acquise. |
| `agenda` | Semaine, jour sélectionné, horaires, noms et états lisibles ; Planifier et Toute l’école accessibles dans le rendu. La liste iPhone continue sous la barre d’onglets, comme une liste défilante native ; les lignes plus basses ne sont pas intégralement vérifiées. |
| `learners` | Recherche, quatre élèves fictifs et commande d’invitation visibles. Split view iPad lisible avec l’état Sélectionnez un élève. |
| `learner` | Historique dans la navigation Élèves ; groupes Prévues et Passées cohérents ; ouverture de leçon indiquée par chevrons ; Planifier reste entièrement visible. La date de la leçon à terminer passe sur deux lignes sur iPhone sans être tronquée. |
| `dossier` | Même historique dans la présentation Formation ; titre et fermeture visibles, colonne iPad centrée. |
| `progression` | Compétence observée, niveau textuel, contexte et date lisibles ; compétences non vues distinctes, sans moyenne. Le rendu montre le composant ; l’ouverture de la leçon source n’est pas exécutée par cette capture. |
| `trips` | Trois états synthétiques lisibles : trajet disponible, Partiel et Supprimé. Les états inhabituels combinent texte et symbole ; pas de chevron sur le trajet supprimé. |
| `invitation-code` | Code fictif entier, durée et commandes Partager/Copier visibles, colonne bornée sur iPad. Le composant est rendu isolément ; la feuille de partage et le presse-papiers ne sont pas exercés. |

Aucun défaut bloquant de mise en page n’est observé sur ces 16 vues initiales. Aucun résultat de navigation tactile, grande police, mode sombre, clavier ou VoiceOver n’est déduit de ces seules images.
