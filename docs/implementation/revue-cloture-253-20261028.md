# Revue de clôture — #253 et 15 corrections UX

Revue du 28 octobre 2026. Comparaison du point de référence `master` demandé, `e5166404ca06a7bd804ecf032f673a4afe790007`, avec `36d75142af3ef9de7e8568f42e66feacfcf07b8e` sur `codex/simplification-253`. Complément : correctifs S10/#262, #224 et test #235 relus dans l’arbre de travail après cette comparaison, avant leur commit ; leurs preuves d’exécution doivent porter leur propre SHA.

Le porteur a refusé de prolonger le travail par de nouveaux prototypes, puis accepté l’essai global et demandé les tests/corrections avant clôture. Cette note apporte la comparaison de sources S01/S20 maintenant vérifiable ; elle ne prétend pas avoir existé avant l’implémentation. Les prototypes abandonnés de `s01-premier-usage/` sont exclus. Aucun entretien chronométré, nombre de retours observés, capture d’écran ou résultat physique n’est reconstitué.

## Nature des preuves

| Preuve | État et portée |
|---|---|
| Lecture avant/après et comptages de cette note | **PASS documentaire** : objets Git et sources relus ; aucune suite exécutée pour rédiger cette note. |
| Essai global du porteur | Retour accepté dans la conversation de livraison. Ne prouve pas séparément chaque cas limite de la matrice. |
| IPA initiale | [Preuve build 441](preuve-ipa-253-uxb-20261028.md), SHA `77306e9882216688b3250c77f72047619c42ad04` ; compilation et intégrité, pas tests métier. |
| Web/API et remise à zéro | [Reçu d’exploitation](deploiement-reset-253-20261028.md), SHA `a41cf64d153252dc133a60f29755f0685516be8f`. L’intervention autorisée ne qualifie pas le parcours. |
| Tests unitaires Swift après essai | **PASS**, [run 40739178690](https://github.com/tomyrms/Drivy/actions/runs/40739178690), SHA `36d75142af3ef9de7e8568f42e66feacfcf07b8e` : 1 087 tests, aucun ignoré, selon le reçu de l’agent de vérification. Statut GitHub `completed/success` relu. Ce run précède les correctifs horloge #224 et preuve de lecture #235. |
| Autres contrôles après essai | Le [reçu de qualification](qualification-253-uxb-20261028.md) relie les résultats à leurs SHA : API 796, web 423, navigateur 162 contrôles, Swift corrigé 1 091 tests ; UI initiale 16/16 sur chaque appareil, puis cours corrigés 7/7 sur chaque appareil. Tous PASS, sans test ignoré. |
| GPS obligatoire avec vrais élèves | **BLOCKED** : [décision S14](donnees-et-gps-253-20261028.md). La configuration de qualification reste vide en exploitation. |
| Batterie, provenance GPS réelle, délai de retrait distant, VoiceOver physique | **NOT_EXECUTED par cette revue**. Ne pas déduire ces résultats d’une compilation, d’un simulateur ou du retour global. |

## S01 — carte des parcours et réutilisations

Les routes web ci-dessous sont relatives à `/app/gestion/:schoolId/`. Les chemins API sont relatifs à `/v1/schools/:schoolId/`. Les autorisations restent celles du serveur ; une destination visible ne constitue pas une permission.

| Étape / rôle | Avant `e5166404` | Livraison comparée et source de vérité |
|---|---|---|
| Préparer l’école / administration | `apercu` ouvre `SchoolSetupGuide` en DRAFT ; étapes confidentialité et profil dans la progression principale. | Même guide, même brouillon. Permis → prix/règles → résumé ; identité, confidentialité et politique des champs réouvrables. `setup-draft`, `templates`, `preview`, `PUT setup-draft`, `POST setup-draft/complete` conservent versions, revue et reçu. |
| Ajouter une formation / personnel habilité | `formations?view=nouvelle` utilise `FormationWizard` à quatre étapes ; le guide existe aussi via `apercu?from=formations`. | Les deux entrées réutilisent `SchoolSetupGuide catalogueOnly`. `formation-wizard.tsx` supprimé ; aucune deuxième file de commandes. Les autres éditions versionnées du catalogue restent dans la fiche. |
| Travail quotidien / administration et moniteur | Une école active sur `apercu` reçoit la préparation de l’école. | École active : redirection vers `agenda`, contexte de rendez-vous conservé ; préparation volontaire via `apercu?from=configuration`. École archivée : consultation explicitement distinguée. `overview.tsx`, `navigation.ts`, `route.ts`. |
| Premier élève / administration | Invitations, dossiers et prochaines actions existent. | Réutilisation de `invitations`, `eleves` et `setup-draft/next-actions`. L’action de planification ouvre `agenda?view=nouvelle&learner=…`. Une lecture échouée ne devient pas « tout prêt ». |
| Rejoindre / élève | `SchoolAccessWorkspace` gère code, compte et connexion. | Même parcours ; changement de code et récupération conservent l’intention. `SchoolOnboardingView` propose le choix GPS personnel ; le personnel ne répond pas à la place de l’élève. |
| Préparer et démarrer / moniteur | Agenda, dossier, contrôle du permis et `lessons/start-now` ou `lessons/:lessonId/start`. | Planification réutilisée. En qualification GPS_REQUIRED : préparation PLANNED puis `POST lessons/:lessonId/captures` démarre atomiquement. Ancien départ refusé au serveur ; LEGACY reste explicite pour la compatibilité. |
| Séance → bilan → lecture / moniteur puis élève | Live Map, observations protégées, arrêt, brouillon, bilan et replay existent. | Live conservé ; bilan montre d’abord les compétences liées à la leçon et laisse les autres accessibles. `lessons/:lessonId/complete`, `report-drafts/:draftId`, publication et replay réutilisés. Observation, compétence évaluée et note privée restent distinctes. |

Les comptes cumulant ADMIN/INSTRUCTOR gardent l’entrée terrain de l’école active et l’accès au bureau selon leurs droits. Les états DRAFT/ACTIVE/ARCHIVED, refus/report GPS, lecture impossible, réponse de commande inconnue et reprise de brouillon ont des branches explicites ; leurs contrôles runtime figurent dans la matrice. Les textes et prix propres à l’école ne sont pas inventés pour terminer le parcours.

Sources : [guide](../../apps/web/client/console/school-setup.tsx), [modèle du guide](../../apps/web/client/setup-model.ts), [navigation](../../apps/web/client/console/navigation.ts), [accueil](../../apps/web/client/console/overview.tsx), [formations](../../apps/web/client/console/formations.tsx), [routes BFF](../../apps/web/server/school-routes.ts), [départ API](../../apps/api/src/lessons.ts), [capture API](../../apps/api/src/captures.ts).

### Comptages reproductibles, sans mesure de temps

Scénario comparable : identité scolaire déjà valide, nouveaux permis issus des modèles, un tarif par permis, sans exception ni ancien tarif à reprendre. « Visible » signifie hors `<details>` fermés dans le JSX, pas une mesure de pixels. Un champ prérempli reste une donnée obligatoire au serveur ; il ne représente pas forcément une nouvelle saisie ou un clic.

| Mesure dans les sources | Avant | Après |
|---|---:|---:|
| Étapes de navigation du guide, avec une formation | 6 | 3 |
| Première étape effective après identité valide | PRIVACY, puis 5 étapes jusqu’au résumé | FORMATIONS, puis 3 étapes jusqu’au résumé |
| Éditeurs distincts pour la création initiale et l’ajout d’une formation | 2 | 1 |
| Étapes de l’ajout d’une formation par `formations?view=nouvelle` | 4 | 3 |
| Champs nom/catégorie visibles après sélection d’un modèle | 2 par permis | 0 ; 2 disponibles à la demande |
| Contrôles visibles de tarification d’un nouveau permis | 6 par permis : durée, prix, date, annulation, conditions, inclusion | 2 par permis : durée, prix ; puis 2 réponses communes, ou 3 avec délai CONTACT |
| Réglages des champs élèves affichés d’emblée dans leur éditeur | 4 sélecteurs pour les champs autres que prénom/nom | 0 sélecteur d’emblée ; les 4 restent dans « Adapter » |
| Prix, annulation, conditions initialement vides à résoudre pour N nouveaux permis | 3N champs : prix + 2 textes par permis | N prix + 2 réponses communes ; +1 délai si CONTACT |
| Deux permis, même hypothèse | 6 champs initialement vides | 4, ou 5 avec CONTACT |
| Un seul permis, même hypothèse | 3 champs initialement vides | 3, ou 4 avec CONTACT : aucune baisse universelle revendiquée |
| Inclusion du nouveau tarif dans la confirmation | `apply: false`, sélection supplémentaire nécessaire | `apply: true` ; retrait toujours possible |
| Adoption finale | 1 confirmation explicite | 1 confirmation explicite conservée |

Les réponses communes sont la marche à suivre en cas d’annulation et le moment/moyen de paiement ; CONTACT demande aussi le délai de l’école. L’ancien bouton d’insertion d’exemple pouvait remplir les textes : le comptage des champs vides n’est donc pas un minimum de gestes humains. Date du jour, durée proposée, catégorie, nom et programme restent préparés et contrôlables. Les règles communes suppriment surtout la répétition entre permis ; elles ne diminuent pas systématiquement le nombre de réponses pour un seul permis.

Ce comptage exclut les inconnues de confidentialité/conservation, les adaptations du programme, la création du compte et les exigences spécifiques au dossier. Leur nombre dépend de la situation réelle. Un élément de conservation « à compléter » empêche toujours l’adoption. Le nombre total de décisions, le temps gagné, les erreurs et demandes d’aide n’ont pas été mesurés avec un participant.

Vérification : `git show e5166404:apps/web/client/setup-model.ts`, les fonctions `FormationStep`, `PricingStep`, `ProfileStep` et `SetupReview` aux deux révisions, puis `contentIssues` dans [school-onboarding-model.ts](../../apps/api/src/school-onboarding-model.ts). Le nombre d’étapes n’est pas le nombre total d’écrans possibles : les éditeurs et erreurs restent accessibles.

## S20 — comparaison de la séance sur les mêmes scénarios

Le choix a été de conserver le live existant. Les objets Git sont identiques avant/après : `SchoolCaptureLiveView.swift` = `f6e60fcf39a0b898a9010bd35edf768fd740d96d` ; `SchoolCaptureLiveMap.swift` = `77661ffb636265a7f5f286101b1176adcc8e32a9`. `git diff e5166404 36d75142 -- <ces deux chemins>` est vide. C’est une preuve de réutilisation du code, pas une capture runtime ni une qualification physique.

| Scénario comparable | Comportement conservé, vérifié dans la source |
|---|---|
| Capture en cours, observation | Carte et état ; `Signaler` dominant, observations via le mécanisme protégé existant. Identifiant `capture-signal-observation`. |
| Pause puis reprise | `Pause` au second rang ; `Reprendre` devient dominant en pause. Activation issue du contrôleur, pas d’un succès visuel anticipé. |
| Fin de séance, réseau lent | `Terminer la leçon` visible, confirmation ; arrêt local demandé avant la suite du bilan. Échec de conservation et réponse serveur restent distingués. |
| Perte de signal ou incident | État d’attente, absence de position et erreurs visibles ; aucune position inventée pour alléger l’écran. |
| iPad, grande taille, notes/clavier | Branches de disposition et actions existantes conservées. Leur présence dans le code ne prouve pas la lisibilité runtime ni VoiceOver. |

Source : [SchoolCaptureLiveView.swift](../../apps/ios/Drivy/SchoolCaptureUI/SchoolCaptureLiveView.swift). Les entrées de départ et la politique GPS changent ; leur régression relève de S17–S19. Le replay et le bilan changent séparément. Il n’existe pas de nouvelle interface live parallèle à qualifier en remplacement. Les captures avant/après et l’essai chronométré ne sont pas disponibles dans cette note ; l’acceptation du porteur porte sur l’essai global fourni.

## Matrice des 24 sujets

« Implémenté » décrit ce que la revue de source établit. La clôture requiert les contrôles pertinents réussis et leur reçu ; aucune case n’est fermée par ce document. Un audit documentaire peut se terminer avec une décision BLOCKED sur la mise en service, sans être une fonction inachevée.

| Sujet | Livraison / limite factuelle | Contrôle ou condition de clôture |
|---|---|---|
| S01 #254 | Carte et comparaison source ci-dessus ; nouveau prototype écarté à la demande du porteur. | Conserver la distinction revue rétrospective / conception antérieure ; aucun temps gagné inventé. |
| S02 #255 | Guide unique, trois étapes, reprise, résumé et erreurs ; prix réel requis. | Onboarding PostgreSQL/web : reprise, adoption, versions, conflit, erreur et école existante. |
| S03 #247 | Entrée active agenda ; préparation DRAFT et consultation ARCHIVED distinctes. | Rôles seuls/cumulés, contexte des liens, petites largeurs ; pas de capacité déduite du seul rôle UI. |
| S04 #256 | Invitation, changement de code, compte existant et récupération réutilisés. | Code expiré, réponse perdue, reprise et envoi explicite ; pas de doublon. |
| S05 #257 | Aperçu minimal des informations et politique par étape. | Champs requis/facultatifs, lecture échouée et droits ; aucune collecte générale ajoutée. |
| S06 #258 | Prochaine action issue de l’état réel ; rendez-vous annulé non assimilé à un rendez-vous prêt. | Premier parcours et états manquants ; erreur ≠ préparation terminée. |
| S07 #259 | Matrice des catégories, références et lacunes datées. Audit documentaire terminable. | OAC consolidée/directive asa non intégralement qualifiées ; couverture partielle explicite, pas de certification. |
| S08 #260 | 17 références pédagogiques distinctes ; 15 proposées pour les leçons pratiques, G/M séparés. | Clés/provenance/personnalisation ; statut NOT_QUALIFIED. Offre théorique collective G/M non préparée automatiquement. |
| S09 #261 | Différences consultables, ajouts validés, versions/histoire préservées. | Conflits, idempotence, anciens dossiers ; évolution réglementaire complexe et transfert de dossiers non automatisés. |
| S10 #262 | Raccord complémentaire API/BFF/UI relu : FIRST_AID/AWARENESS par clé stable, validation interne, présences seules et inconnus distincts. | 4 tests PG PASS dans 40742565492 : révocation, droits dossier + cours, école étrangère et cours homonyme personnalisé. Aucune certification ni validité calculée depuis `validatedAt`. Transition VD annoncée possible, à vérifier. |
| S11 #263 | Premier tarif permis/durée/prix ; date scolaire préparée, pas de fin imposée. | CHF exact, absence ≠ zéro, bornes et historique. |
| S12 #264 | Questions communes et échéance individuelle ; collectifs et règle propre séparés. | Délai exact, changement d’heure, ancienne procédure inconnue ; migration additive déployée selon le reçu. |
| S13 #265 | Référence commune, impact, conflits et versions ; bornes des conditions conservées. | Groupe complet, exception, version périmée, idempotence ; cas futur/expiré sans fin de produit. |
| S14 #266 | Cartographie et décision par traitement, lacunes nommées. Audit terminable avec BLOCKED. | Identité/rôles exploitant, conservation/effacement, nécessité GPS, mineurs/salariés, AIPD et retrait distant restent à qualifier avant usage réel obligatoire. |
| S15 #267 | Propositions factuelles et adoption distincte des choix personnels. | Inconnues bloquantes, modification/version et résumé ; texte préparé ≠ texte adopté. |
| S16 #268 | Choix personnel dans l’accueil ; refus/report préservent compte et rendez-vous. | Compte élève, notice/version, réponse inconnue ; pas de permission GPS demandée à l’appareil élève non source. |
| S17 #269 | Préparation puis départ atomique par capture ; vieux endpoints refusés si GPS_REQUIRED. | PostgreSQL et natif : reprise, double appui, absence/refus et fenêtre ; activation réelle toujours BLOCKED. |
| S18 #270 | Choix réutilisé, version de l’accord, retrait prioritaire et baux conservés. | Multi-appareils, acceptation périmée, hors ligne/reprise ; arrêt distant instantané non promis. |
| S19 #271 | Incidents et traces partielles conservés ; source moniteur explicite. | Permission/réseau/upload ; GPS_REQUIRED limité à B/BE en qualification, source moto non assimilée à l’élève. |
| S20 #272 | Live identique, preuve source et scénarios ci-dessus. | Contrôles Apple de la disposition/actions ; aucune mesure GPS/batterie ou VoiceOver physique déduite. |
| S21 #273 | Bilan avec observations et compétences liées ; autres compétences accessibles. | Brouillon, sauvegarde tardive, historique, multi-écoles, visibilité élève et note privée. |
| S22 #274 | Aide courte et contact scolaire réel ; diagnostic copié explicitement. | Accessibilité, erreurs, absence de contact ; aucun service d’assistance ou envoi inventé. |
| S23 #275 | Assistant séparé retiré ; route et guide réutilisés. | Routes/liens/fixtures ; API/historique et LEGACY conservés pour leur compatibilité nécessaire. |
| S24 #276 | Artefact, recette, essai accepté et contrôles après essai. | Rattacher résultats exacts par SHA, corriger les échecs ; distinguer fusion, déploiement et qualification. |

## Matrice des 15 corrections UX

| Issue | Livraison / cas déterminant | Preuve à rattacher |
|---|---|---|
| #221 | Langue réellement configurée dans fiche et récapitulatif ; absence/code inconnu sans français inventé. | Tests langue/version et rendu accessible. |
| #222 | Offres et prochain cours visibles ensemble ; plusieurs offres comptées. | Offres + inscription, expiration, lien correct et grands textes. |
| #223 | Confirmation de refus et sortie d’attente ; conséquences distinctes. | Annuler sans mutation, double appui/réponse perdue et expiration concurrente. |
| #224 | Correctif complémentaire relu : ancre serverTime à réception, progression monotone ; fiche, liste et commande utilisent cette référence. Le RTT complet n’est pas ajouté une seconde fois. | Tests métier PASS sur `94348f6f`, run 40742298060 : décalage ±2 jours, échéance exacte, relecture échouée et confirmation tardive. Aucune action automatique. Le serveur décide la commande ; pas de preuve visuelle d'une expiration sur appareil. |
| #225 | Titre du cours, séance dans l’appel, portée série des règlements/validations. | Sélection, fuseau, titre long, mode et droits. |
| #226 | « Enregistrer un règlement » ; nom accessible de l’élève. | Ouvrir/annuler sans paiement ; montant confirmé distinct du pending. |
| #233 | États du tracé expliqués à la demande ; mesuré/ajusté/partiel distincts. | Panne/reprise, maintien des lacunes GPS et confidentialité. |
| #234 | Texte entier depuis la sélection ; ouverture suspend le lecteur. | Longue note, fermeture, caméra/instant conservés, iPad/grands textes. |
| #235 | Sélection manuelle suspend la lecture ; `selectObservation` réutilisé par la vue et le test complémentaire relus. | `SchoolReplayReadingTests` PASS sur `94348f6f`, run 40742298060 : pause, instant et longue note stables, puis reprise vers l’observation suivante. Preuve métier du lecteur, pas VoiceOver ou GPS physique. |
| #236 | Recherche/filtre partagé rail, liste, carte et chronologie d’observations. | Horodatage réel, couverture partielle, effacement du filtre sans déplacement temporel. |
| #239 | Cause connue expliquée, code dans le détail ; aucun repli en clair. | Cause inconnue, D-NOKEY, refus/révocation et confidentialité du diagnostic. |
| #242 | Contraintes du sondage liées aux règles effectives et champs visités. | Vide/longueur/doublon, ajout/suppression, focus et saisie conservée après erreur. |
| #243 | Confirmation d’abandon, geste protégé, saisie conservée si échec. | Formulaire intact, choix multiple seul, pending et absence de second sondage. |
| #244 | Recherche locale/partielle, état de lecture et réponses périmées distingués. | Frappe rapide, stockage inaccessible, changement de conversation et suppression. |
| #245 | Extrait centré, casse/accents et graphèmes conservés en mémoire. | Fin de message, emoji, répétitions, résultat supprimé ; ni index clair ni logs de contenu. |

## Conditions du reçu final

Les deux écarts fonctionnels relevés, raccord des faits S10 et horloge #224, disposent de correctifs relus sans autre défaut démontré dans cette revue statique. L’accès aux faits exige d’abord un dossier visible puis le compte élève concerné ou le droit de gestion des cours ; aucune RLS élargie. `validatedAt` reste une validation interne et les présences ne sont pas converties en certificat. La référence d’horloge utilise l’enveloppe serveur et une durée monotone, sans addition du temps aller/traitement qui provoquerait une expiration prématurée. Le test #235 passe par la même fonction de sélection que la vue.

Les compléments ont leurs preuves propres : S10 sur `4a1a6885`, horloge et lecture sur `94348f6f`, conformément au [reçu de qualification](qualification-253-uxb-20261028.md). Ils ne sont pas déduits de l'ancienne IPA ou des 1 087 tests Swift précédents. Les autres lignes décrivent les contrôles pertinents et les limites qui demeurent ; aucune qualification physique exhaustive n'est revendiquée sous couvert de clôture.

S07 peut se terminer avec sa couverture partielle documentée, S14 avec ses blocages précis. Clore ces livrables ne transforme pas leurs conclusions en feu vert. Le reçu final de #253 doit conserver les limites, les liens de tests/artefacts, le résultat du retour du porteur et la réalité de la fusion/déploiement. Cette note ne ferme aucune issue et n’exécute aucune opération de production.
