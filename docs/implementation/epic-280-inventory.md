# EPIC #280 — inventaire des vues et contrat de couverture

Établi le 28 octobre 2026 depuis la base auditée `e5166404ca06a7bd804ecf032f673a4afe790007`, puis révisé après intégration de #253 en `583d29980698dbeae713e0cd42df3b7578efda17`. Analyse du code courant, et non recette exécutée. Les 18 clés de `console/sections.ts` et les surfaces de `main.tsx` sont couvertes ci-dessous. Le manifeste associé contient 110 sous-vues explicitement identifiées, leurs actions et leurs propriétaires ; les états transversaux font partie de chacune, selon applicabilité.

La demande actuelle du porteur autorise l’implémentation sans validations intermédiaires et remplace les arrêts de validation visuelle des tickets. Elle conserve une confirmation finale avant production, puis son essai personnel avant les campagnes #309/#84. La présente analyse ne valide ni rendu ni fonctionnalité et ne clôture aucune issue.

## Références et portée

- `AGENTS.md`, `COMMENCER_ICI.md`, règles R01–R07, contrat API (enveloppe, école, idempotence, If-Match, dates civiles/montants), composants effectivement présents dans le client.
- `main.tsx` choisit compte/invitation, récupération, préférences, ouverture/opérateur et console via imports différés. `Console.tsx` distribue les 18 rubriques ; `route.ts` filtre les paramètres autorisés.
- La console reste réservée aux adhésions ADMIN courantes. Les droits pédagogiques, de catalogue/cours et d’accès aux trajets restent supplémentaires lorsqu’ils sont exigés par les contrôleurs/serveur. Une fixture directement rendue ne prouve pas qu’un élève ou moniteur peut ouvrir la console.
- Aucun chat web, capture/replay cartographique web, paiement en ligne, stockage privé hors ligne ou droit nouveau n’est ajouté pour remplir l’inventaire.

## Architecture cible

Navigation scolaire desktop latérale ; accès mobile par destinations nommées et contenu en une colonne. Les tâches quotidiennes sont Planning, Élèves et Équipe ; Formations et tarifs et Réglages gardent leurs destinations complètes. Le contexte école et le compte restent distincts. Les détails gardent un retour explicite, les formulaires longs une surface de page, les confirmations une surface adaptative courte. Le propriétaire W04 décide du dispositif final ; aucun écran n’est supprimé au motif qu’il est secondaire.

| Destination existante | Propriétaires | Conservation nécessaire |
|---|---|---|
| apercu | W10 #247, W11 #255 | Accueil actif, préparation, école inactive, guide catalogue seul |
| agenda | W12 #290, W13 #291, W21 #299, W22 #300 | Leçons et cours, détails, tous éditeurs et participants |
| disponibilites, absences | W14 #292 | Horaires, validité, absences, retraits |
| eleves | W15 #293, W16 #294 | Annuaire, profil, formations, permis, progression, bilans |
| equipe, invitations | W17 #295, W18 #296 | Accès, retrait, audiences, codes/liens, renouvellement/révocation |
| formations, offres, referentiels, procedures | W19 #297 | Permis/programmes, rubriques, création, versions, anciens liens |
| prestations, conditions | W20 #298 | Tarifs sans permis, conditions et versions historiques |
| trajets | W23 #301 | Liste autorisée, pagination, retour dossier ; sans faux replay |
| configuration, champs-profil | W24 #302 | Coordonnées, préparation, demandes et aperçu élève |
| confidentialite | W25 #303 | Textes, adoption et impacts, GPS et identité |
| signalements | W26 #304 | Ordre, visibilité, aperçu, réinitialisation, sauvegarde |
| accès hors console | W08 #288, W09 #289, W27 #305 | Connexion/code/inscription/invitation/récupération, opérateur, préférences |
| transversaux | W02–W07, W28–W31 | Tokens/primitives, navigation, états, mobile, sécurité, parité, preuves |

## Sous-vues, données et actions

Les routes courtes ci-dessous sont relatives à `/app/gestion/:schoolId/`. `all-console` désigne un état transversal de la console et `all` une surface globale. Les permissions et sources détaillées sont conservées dans [le manifeste JSON](epic-280-inventory.json). Chaque ligne requiert une preuve propre ou une limite explicitée ; un build vert n’est pas sa qualification.

| ID | Route/état | Sous-vue et actions conservées | Propriétaire |
|---|---|---|---|
| entry.login | `/app` | **Connexion** — Saisir e-mail et mot de passe ; ouvrir récupération ; choisir code | W08 #288 |
| entry.code | `/app` | **Code d’accès** — Saisir code ; vérifier type ; revenir connexion | W08 #288 |
| entry.register | `/app` | **Inscription après code/lien** — Saisir prénom, nom, e-mail, mot de passe ; créer compte ; compte existant | W08 #288 |
| entry.schools | `/app` | **Écoles liées** — Actualiser ; choisir école ; saisir code ; se déconnecter | W08 #288 |
| entry.no-school | `/app` | **Compte sans école** — Saisir code ; actualiser ; ouvrir invitation existante | W08 #288 |
| entry.invitation | `/app/invitation` | **Aperçu invitation** — Lire école, rôles, confidentialité, conservation ; confirmer ; changer compte | W08 #288 |
| entry.invitation-result | `/app/invitation` | **Acceptation et résultat incertain** — Rejoindre ; vérifier même opération ; annuler avant envoi ; ouvrir école | W08 #288 |
| entry.recover | `/app/recover` | **Récupération du compte** — Vérifier disponibilité ; réessayer ; ouvrir fournisseur identité ; revenir | W08 #288 |
| entry.opening | `/app/ouvrir` | **Ouverture école** — Nom école, coordonnées, responsable, fuseau, rôle moniteur ; créer ; vérifier résultat | W09 #289 |
| entry.opening-result | `/app/ouvrir` | **Reçu ouverture** — Ouvrir préparation ; reprendre résultat incertain ; changer compte | W09 #289 |
| entry.operator | `/app/operateur` | **Liens d’ouverture** — Créer lien/code ; copier ; lister ; révoquer lien disponible | W09 #289 |
| account.menu | `all` | **Menu du compte** — Écoles ; préférences ; déconnexion avec garde | W27 #305 |
| account.theme | `/app/preferences` | **Apparence personnelle** — Système, clair, sombre ; conserver seulement préférence neutre | W27 #305 |
| account.notifications | `/app/preferences` | **Préférences notifications** — Modifier choix ; vérifier incertitude ; renvoyer mêmes choix ; gérer conflit | W27 #305 |
| account.identity | `all` | **Confirmation identité** — Confirmer identité courante ; reconnexion ; annuler | W06 #286 |
| shell.choose | `/app/gestion` | **Choix école administrée** — Choisir école parmi adhésions ADMIN courantes | W04 #284 |
| shell.denied | `/app/gestion` | **Accès gestion refusé** — Retour écoles ; reconnexion ; pas de droit admin ajouté | W04 #284 |
| shell.navigation | `/app/gestion/:schoolId/:section` | **Navigation scolaire** — 5 espaces nommés ; sous-destinations ; recherche réglages ; changer école | W04 #284 |
| shell.pending | `all-console` | **Demandes à vérifier** — Vérifier reçu ; renvoyer même demande ; revenir ressource ; reconnexion | W07 #287 |
| shell.departure | `all-console` | **Sortie avec saisie** — Rester ; quitter sans enregistrer ; garder protection retour navigateur | W06 #286 |
| shell.load-failed | `all` | **Module non chargé** — Réessayer import ; garder lien invitation en mémoire | W07 #287 |
| shell.legacy | `offres,referentiels,procedures` | **Ancien lien** — Résoudre référence ; remplacer historique URL ; retour permis ; refus référence | W30 #308 |
| shell.unknown | `unknown` | **Route inconnue** — Comportement de parseConsoleRoute actuel: repli aperçu ; destination claire cible | W30 #308 |
| overview.active | `apercu` | **Accueil école active** — Planning quotidien ; prochaines actions réelles ; accès préparation distinct | W10 #247 |
| overview.archived | `apercu` | **École inactive** — Lire état réel ; conserver refus des écritures | W10 #247 |
| overview.readiness | `agenda` | **Première leçon** — Lire prochaine action serveur ; réduire ; ouvrir élève/invitation/planning | W10 #247 |
| setup.identity | `apercu` | **Préparation identité** — Nom école ; contacts ; fuseau ; sauvegarder brouillon ; suivant | W11 #255 |
| setup.privacy | `apercu` | **Préparation confidentialité** — Textes ; contact ; proposition adaptée ; précédent/suivant | W11 #255 |
| setup.profile | `apercu` | **Préparation informations élèves** — Choisir demandes et stade ; aperçu ; continuer | W11 #255 |
| setup.formations | `apercu` | **Préparation formations** — Choisir permis/programme ; adapter compétences/règles ; différer | W11 #255 |
| setup.pricing | `apercu` | **Préparation tarifs** — Durée ; prix réels ; conditions ; formations différées | W11 #255 |
| setup.review | `apercu` | **Revue et activation** — Relire effets ; retourner champ en erreur ; enregistrer ; activer explicitement | W11 #255 |
| setup.catalogue | `apercu?from=formations` | **Guide catalogue seul** — Formations/tarifs/revue ; retour catalogue sans réadopter textes | W11 #255 |
| agenda.week | `agenda` | **Planning semaine** — Changer période ; aujourd’hui ; filtre moniteur ; recherche ; lire leçons/cours | W12 #290 |
| agenda.day | `agenda` | **Planning jour/mobile** — Choisir jour ; lire rendez-vous ; conserver filtres ; ouvrir détail | W12 #290 |
| agenda.sources | `agenda` | **Sources partielles** — Recharger source en erreur ; ne pas confondre absence et indisponibilité | W12 #290 |
| lesson.detail | `agenda?lesson=:id` | **Fiche leçon** — Horaire ; moniteur ; lieu ; préparation ; dossier ; retour contexte | W13 #291 |
| lesson.create | `agenda?view=nouvelle` | **Planification leçon** — Élève/formation ; moniteur ; créneau ; durée ; lieu ; vérifier disponibilité ; confirmer | W13 #291 |
| lesson.edit | `agenda?lesson=:id` | **Déplacement leçon** — Modifier horaire/lieu/moniteur ; disponibilité ; relire et confirmer | W13 #291 |
| lesson.cancel | `agenda?lesson=:id` | **Annulation leçon** — Motif ; effets et confirmation ; garder conflit/refus dans contexte | W13 #291 |
| availability.list | `disponibilites` | **Horaires hebdomadaires** — Filtrer moniteur ; lire jours/périodes ; retour membre | W14 #292 |
| availability.create | `disponibilites` | **Ajouter horaire** — Jours multiples ; heures ; validité ; enregistrer | W14 #292 |
| availability.remove | `disponibilites` | **Retirer horaire** — Confirmer suppression versionnée ; garder engagements existants | W14 #292 |
| absence.list | `absences` | **Absences prévues** — Filtre moniteur ; lire intervalle fuseau école ; retour membre | W14 #292 |
| absence.create | `absences` | **Ajouter absence** — Début/fin ; motif ; enregistrer ; conflit planning | W14 #292 |
| absence.remove | `absences` | **Retirer absence** — Relire période ; confirmer retrait | W14 #292 |
| learners.list | `eleves` | **Annuaire élèves** — Actifs/archives/tous ; recherche nom/contact ; profil ; tri ; pagination | W15 #293 |
| learners.detail | `eleves?selection=:id` | **Fiche élève** — Identité distincte/homonymes ; coordonnées ; résumé ; retour liste/agenda/trajets | W15 #293 |
| learners.missing | `eleves?selection=:id` | **Sélection hors liste/absente** — Lire directement sélection autorisée ; réessayer ; retour sans faux dossier | W15 #293 |
| learners.profile | `eleves?selection=:id` | **Compléter profil** — Champs manquants selon politique ; pays/adresse ; revue ; enregistrement versionné | W15 #293 |
| learners.archive | `eleves?selection=:id` | **Archiver/restaurer dossier** — Motif ; avertissement ; confirmation ; retour état confirmé | W15 #293 |
| training.list | `eleves?selection=:id` | **Formations suivies** — Lire catégorie/statut/moniteurs/permis ; ouvrir suivi | W16 #294 |
| training.create | `eleves?selection=:id` | **Ouvrir formation** — Offre active admissible ; date début ; créer | W16 #294 |
| training.transition | `eleves?selection=:id` | **Changer état formation** — Pause/reprise/fin/annulation ; motif ; confirmer | W16 #294 |
| training.assignment | `eleves?selection=:id` | **Affectations moniteur** — Affecter moniteur actif ; terminer affectation ; confirmation versionnée | W16 #294 |
| training.permit | `eleves?selection=:id` | **Contrôle du permis** — Approuver/refuser ; catégorie et validité ; attestation/motif ; relire | W16 #294 |
| training.progress | `eleves?selection=:id` | **Progression compétences** — Lire niveaux présents ; données absentes explicites | W16 #294 |
| training.reports | `eleves?selection=:id` | **Bilans et leçon sélectionnée** — Filtrer année/mois ; développer bilan ; travail/observations/objectifs/compétences | W16 #294 |
| training.gps | `eleves?selection=:id` | **État accord GPS** — Lire accord/avis courant/refus ; pas d’activation implicite | W25 #303 |
| team.list | `equipe` | **Annuaire équipe** — Actifs/inactifs ; recherche ; tri ; pagination ; identité/homonymes | W17 #295 |
| team.detail | `equipe?selection=:id` | **Fiche membre** — Lire rôles ; disponibilités ; absences ; statut | W17 #295 |
| team.access | `equipe?selection=:id` | **Changer accès** — Rôles ; grants secondaires ; motif ; revue diff ; confirmer identité | W17 #295 |
| team.revoke | `equipe?selection=:id` | **Retirer accès** — Motif ; confirmation explicite ; protection dernier ADMIN/soi conservée | W17 #295 |
| invitations.learners | `invitations?audience=learners` | **Invitations élèves** — Recherche ; état ; sélection ; création permise selon options serveur | W18 #296 |
| invitations.team | `invitations?audience=team` | **Invitations équipe** — Recherche ; état ; détail ; droits ; disponibilité e-mail | W18 #296 |
| invitations.code | `invitations` | **Code élève** — Permis multiples ; moniteur ; revue ; créer code | W18 #296 |
| invitations.email | `invitations` | **Invitation par e-mail** — Adresse ; rôle(s) autorisés ; relire ; enregistrer pour envoi | W18 #296 |
| invitations.share | `invitations?selection=:id` | **Code/lien émis** — Afficher secret seulement réponse ; copier ; erreur copie ; code absent | W18 #296 |
| invitations.renew | `invitations?selection=:id` | **Renouvellement** — Relire invalidation ancien code/lien ; confirmer ; nouveau code | W18 #296 |
| invitations.revoke | `invitations?selection=:id` | **Révocation** — Motif ; confirmer ; conserver statut/expirée/acceptée | W18 #296 |
| formations.list | `formations` | **Catalogue permis** — Liste permis ; programmes ; prestations sans permis ; nouveau permis | W19 #297 |
| formations.general | `formations?category=:code&view=general` | **Fiche permis/programme** — Choisir programme ; infos ; modifier nom/durée/activation | W19 #297 |
| formations.competencies | `formations?category=:code&view=competences` | **Compétences** — Lire ; créer/modifier/réordonner ; enregistrer nouvelle version | W19 #297 |
| formations.rules | `formations?category=:code&view=deroulement` | **Déroulement et annulation** — Lire règles/sources ; adapter proposition ; modifier et relire | W19 #297 |
| formations.wizard | `formations?view=nouvelle` | **Préparer un permis avec le guide unique** — Étapes guide ; compétences/règles/tarifs ; revue ; création | W19 #297 |
| formations.history | `formations?category=:code&view=historique` | **Historique versions** — Programme/référentiel/procédure/tarif ; ouvrir ancienne référence | W19 #297 |
| formations.reference | `offres,referentiels,procedures?selection=:id` | **Référence historique** — Lire contenu/version/usages ; retrouver contexte courant sans réécrire historique | W19 #297 |
| pricing.list | `formations?category=:code&view=tarifs` | **Tarifs liés au permis** — Lire durée/prix/validité/état ; sélectionner version | W20 #298 |
| pricing.editor | `formations?category=:code&view=tarifs` | **Créer/modifier tarif** — Type, label, montant CHF, validité, conditions communes/spécifiques ; relire | W20 #298 |
| pricing.unscoped | `prestations` | **Prestations sans permis** — Liste ; création ; modification ; activation ; historique | W20 #298 |
| pricing.terms | `conditions` | **Conditions commerciales** — Archives versions ; lecture ; tarifs concernés ; nouvelle version via éditeur | W20 #298 |
| course.add | `agenda` | **Ajouter leçon/cours** — Menu ajouter selon capacités ; type de cours ; paramètres annulation | W21 #299 |
| course.editor | `agenda` | **Éditeur cours/série** — Type/titre/description/public/moniteur/lieu/capacité/séances ; revue | W21 #299 |
| course.publish | `agenda` | **Publication cours** — Résumé séances ; conditions ; capacité ; publier ou garder brouillon | W21 #299 |
| course.sheet | `agenda` | **Fiche cours publié** — Séances ; places ; horaires ; moniteurs ; sélection séance ; capacité | W21 #299 |
| course.changes | `agenda` | **Reports et annulations** — Reporter séance ; annuler séance/série ; motif ; confirmer | W21 #299 |
| course.policy | `agenda` | **Politique cours** — Adapter règle d’annulation ; confirmation et version | W21 #299 |
| course.roster | `agenda` | **Inscrits** — Lire participants ; ajouter élève ; annuler inscription ; raison | W22 #300 |
| course.waitlist | `agenda` | **Liste d’attente** — Lire rang/offre/expiration ; gérer entrée existante selon commande | W22 #300 |
| course.attendance | `agenda` | **Appel par séance** — Lire présence ; consigner/corriger ; provenance et état | W22 #300 |
| course.settlements | `agenda` | **Règlements** — Consigner paiement/retrait/correction append-only ; total vrai | W22 #300 |
| course.completion | `agenda` | **Validation cours** — Admissibilité ; validation motivée/correction ; historique conservé | W22 #300 |
| trips.global | `trajets` | **Inventaire trajets** — Liste autorisée ; recherche page ; filtres ; pagination curseur ; date/durée | W23 #301 |
| trips.learner | `trajets?learner=:id` | **Trajets élève** — Filtre élève ; historique borné explicite ; retour dossier/contexte | W23 #301 |
| settings.identity | `configuration` | **Coordonnées école** — Résumé ; éditer nom/contact ; enregistrer ; annuler | W24 #302 |
| settings.timezone | `configuration` | **Fuseau scolaire** — Lire fuseau de référence ; règles formulaire selon existant | W24 #302 |
| settings.activation | `configuration` | **Préparation école** — État ; ouvrir préparation ; pas de nouvelle readiness inventée | W24 #302 |
| settings.fields | `champs-profil` | **Informations élèves** — Résumé puis politique des champs ; exigence/stade/raison/explication | W24 #302 |
| settings.fields-preview | `champs-profil` | **Aperçu élève** — Lire rendu demandé à l’élève avant adoption | W24 #302 |
| settings.fields-adopt | `champs-profil` | **Publication des demandes** — Revue effets sur profils ; date d’effet ; confirmer | W24 #302 |
| privacy.texts | `confidentialite` | **Textes de l’école** — Notice, conservation, contact ; modifier ; réutiliser proposition | W25 #303 |
| privacy.impact | `confidentialite` | **Adopter textes** — Lire effet GPS et captures ; confirmer ; refus lecture impact ; conflit | W25 #303 |
| privacy.gps | `confidentialite` | **Option GPS scolaire** — Lire activé/désactivé ; identité ; effets ; confirmer bascule | W25 #303 |
| privacy.conditions | `confidentialite` | **Conditions versionnées** — Lire conditions/reçus selon surface présente ; conserver accès historique | W25 #303 |
| signals.list | `signalements` | **Ordre et visibilité** — Lire thèmes ; déplacer poignée/flèches ; masquer/afficher ; au moins un visible | W26 #304 |
| signals.preview | `signalements` | **Aperçu moniteur** — Lire ordre/visibilité ; pas de capture GPS depuis navigateur | W26 #304 |
| signals.reset | `signalements` | **Réinitialisation** — Ordre seul ou configuration ; annuler brouillon ; enregistrer explicitement | W26 #304 |
| signals.conflict | `signalements` | **Conflit/refus** — Recharger version ; conserver explication ; lecture seule | W26 #304 |

| training.prerequisites | `eleves?selection=:id` | **Prérequis et faits de cours** — Sources/limites suisses ; validation interne distincte des présences ; droits cours séparés | W16 #294 |
| pricing.shared-terms | `conditions?selection=:id` | **Réviser les conditions communes** — Tarifs réellement concernés ; texte ; confirmation de portée ; nouvelles versions | W20 #298 |

## États à appliquer à la matrice

Lecture : initial, chargement, rempli, vide réel, partiel/tronqué, indisponible, refusé, ancien contexte. Écriture : saisie, erreur de champ, revue, annulation avant envoi, en cours, confirmée durablement, refus, conflit de version, résultat incertain, session expirée, droits/école modifiés. Navigation : lien profond, retour/avance, nouvel onglet, garde d’édition, retour bfcache, chunk indisponible.

Affichage après validation utilisateur : 320/375/390/430/768/1024/1440 px, portrait/paysage, clair/Soft Charcoal, texte long, clavier, zones sûres, zoom 200 %, reflow 400 %, mouvement réduit. Chromium/WebKit/Firefox desktop, Safari iOS et Chrome Android physiques seulement si réellement disponibles. Les tests non exécutés restent `NOT_EXECUTED` ; l’émulation ne qualifie aucun appareil.

## Entrée synthétique reproductible et captures W01

L’entrée Vite de développement est `/app/test/visual.html`. Elle importe les vrais composants et intercepte les requêtes avec des données synthétiques en mémoire, hors entrée de production. Les paramètres `page`, `shell=1`, `state`, `stress=1`, `volume=1`, `role`, `status`, `step`, `agenda` et `impact` composent les scénarios. La fixture change ensuite l’URL avec `history.replaceState` ; pour recommencer un scénario, ouvrir de nouveau son URL d’entrée. Aucun secret réel n’y est requis.

Pilotes à capturer AVANT modification et APRÈS intégration, à 390 et 1440 px :

1. Accueil : `?page=overview&shell=1` (préparation active actuelle), puis `?page=agenda&shell=1` pour l’accueil quotidien lié à #247 ; école neuve `?page=overview&shell=1&status=draft`.
2. Agenda : `?page=agenda&shell=1`, puis `&agenda=lesson-planning` pour leçons éditables.
3. Élève : `?page=learners&shell=1`, ouvrir un élève depuis la liste (aucun paramètre `learner-detail` n’existe).
4. Formulaire long : `?page=formation-new&shell=1`, ou guide `?page=overview&shell=1&status=draft&step=PRIVACY`.
5. Confirmation mobile : `?page=team&shell=1`, ouvrir un membre puis changement d’accès ; alternative primitive `?page=choices` puis dialogue.

Les autres pages sont indexées dans le champ `fixture` du JSON. La récupération n’a pas de rendu de revue dédié à ce SHA. `state=error`, `empty`, `slow`, `conflict`, `mutation-error`, `response-lost`, `readonly`, `forbidden` ne s’appliquent qu’aux branches explicitement interceptées dans `test/visual.tsx` : ne pas prétendre couvrir toutes les commandes par un même paramètre.

Captures avant/après exécutées dans `proofs/epic-280`, avec manifestes JSON et données synthétiques ; protocole dans [le reçu d'implémentation](epic-280-implementation.md). Elles montrent leurs états visibles seulement. Le champ `execution` du manifeste reste `NOT_EXECUTED` pour la qualification complète de chaque sous-vue, différée après l'essai personnel. Aucune capture du 14 octobre ne vaut preuve de la base du 28 octobre.

## Dépendances de travaux parallèles

- PR #278 (`2c15a061cedf93fabd4c86e8a0f0201b7aba6d86`), désormais intégrée via #253, couvre une partie de #247/#258 : accueil actif vers planning, préparation accessible dans réglages, première action réduite en mémoire et relecture avec planning. Elle modifie également la requête serveur : une leçon annulée ou une absence ne termine plus le guidage. Le coordinateur a intégré ces corrections avec la branche #253 ; cet inventaire ne constitue aucune preuve de leur exécution.
- PR #279 (`83aadc37fa02af5420a08e1f0e52178bfdf27ff7` lors de la lecture) porte #253, contrats de programme et préparation, règles d’annulation individuelles, GPS-only et plusieurs corrections natives/cours. Le web change `command-core.ts` et ajoute `common-lesson-rules.ts`. Ces évolutions sont intégrées en `583d2998` ; leur déploiement reste une étape séparée. Le guide a trois étapes principales avec identité/textes/champs accessibles depuis le résumé ; `formation-wizard.tsx` reste supprimé. Le nouveau dossier réutilise `learners/:learnerId/course-facts`, absent de la version API `a41cf64d` décrite en production. Le candidat exige donc cette API et sa politique d’audit additive ; voir la note de livraison.
- Les décisions S07/S14 ne bloquent pas les composants/prototypes synthétiques, mais un écran ne peut ni les inventer ni contourner un contrat absent. Conserver les capacités des services actuellement déployés ; vérifier toute nouvelle dépendance avant release.

## Composition réalisée par le lot catalogue/réglages

W19/W20 : catalogue recherché, rubriques compactes sur mobile, édition de tarif en page avec retour à la liste, conditions en liste filtrée puis détail complet, revue groupée des conditions communes. W24/W25 : coordonnées et fuseau réunis, informations élèves en résumé avant personnalisation, aperçus et textes intégraux dépliables, état GPS scolaire distinct de l’accord individuel. W26 : commandes de réinitialisation secondaires, aperçu dépliable, ligne tactile avec nom visible et alternatives Monter/Descendre conservées. Les contrats et payloads ne changent pas. Ces lignes sont `IMPLEMENTED_UNQUALIFIED` dans le JSON ; aucune preuve navigateur/physique n’est déduite du code.

## Propriétaires des chantiers transversaux

W01 #281 : cet inventaire, captures et pilotes. W02 #282 : tokens/typo/thèmes et DESIGN.md. W03 #283 : shadcn/Base UI et compilation Vite. W04 #284 : shell, routes, retour et contexte. W05 #285 : liste/table, recherche, filtres, pagination et détail. W06 #286 : champs, formulaires, revue/confirmation et focus. W07 #287 : états de lecture/commande. W28 #306 : mobile, clavier, reprise et zones sûres. W29 #307 : mesures et sécurité. W30 #308 : parité route, retrait de l’ancien rendu et rollback. W31 #309 : campagne complète après l’essai du porteur.

Le document de livraison associé détaille les contrôles minimum avant essai et le déploiement web isolé. Ce manifeste décrit la couverture à atteindre ; ses statuts ne doivent devenir `IMPLEMENTED`/`PASS` qu’après relecture du changement et exécution correspondante.
