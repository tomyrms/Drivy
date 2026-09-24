# Fonctionnalités prévues de Drivy

> Référence V3.13 · 20 septembre 2026 · [Index](README.md) · [Rapport de revue](06-gouvernance/audit-corrections-v3-14.md).

## Ce que signifie cette liste

**Il s’agit de la future application décrite, pas d’un inventaire de fonctions déjà développées.** Les 23 fonctions F01–F23 constituent le cœur proposé, livré par tranches G1 à G4 après prototype G0. Rien n’est déclaré testé sur l’app par la présente liste. Android vient plus tard ; les variantes et limites restent celles des spécifications liées.

Le catalogue technique existait déjà dans l’inventaire et la traçabilité. Cette vue regroupe les capacités pour décider et suivre le développement sans lire tout le contrat API. Les compléments de cette revue sont signalés ; les détails de réalisation et certaines règles commerciales restent proposés, pas automatiquement approuvés.

## Les 23 fonctions du cœur
| ID et fonction | Ce que l’utilisateur pourra faire | Limites et état de conception | Rôles et supports | Tranche |
|---|---|---|---|---|
| [F01 · Compte, connexion et écoles](03-fonctionnel/identites-formations.md#f01) | Créer/utiliser son identité via le fournisseur retenu, se connecter, changer d’école, retrouver ses rôles, se déconnecter et demander la suppression globale de son propre compte. | Suppression globale complétée V3.5 ; fournisseur et traitement opérationnel à valider. Pas de création publique automatique de toutes les écoles. | Élève, moniteur, ADMIN. App et web. | G1 (identité) / G4 (clôture) |
| [F02 · Dossier élève et invitation](03-fonctionnel/identites-formations.md#f02) | Inviter un élève, accepter l’invitation, retrouver et rechercher son dossier, éviter les doublons d’appartenance et gérer les personnes affectées. | Voir un élève ne donne pas tous les droits sur ses notes, ses fichiers ou d’autres écoles. | Personnel et élève invité. App, tablette et web. | G1 |
| [F03 · Formations et permis multiples](03-fonctionnel/identites-formations.md#f03) | Ouvrir plusieurs formations pour une même personne, choisir les catégories réellement proposées, affecter les moniteurs, vérifier permis et pièces, déclarer des formations déjà suivies ailleurs. | Justificatif téléchargé ≠ preuve approuvée. Référentiels réglementaires datés à qualifier par catégorie. | Élève et personnel habilité. App et web. | G1 |
| [F04 · Disponibilités et organisation](03-fonctionnel/planning-lecons.md#f04) | Définir les plages de travail, pauses, indisponibilités et fermetures ; contrôler les conflits et temps nécessaires entre engagements. | Le parc partagé de véhicules et l’agenda personnel externe ne sont pas inclus comme moteurs de réservation. | Personnel. App, tablette et web. | G2 |
| [F05 · Leçons individuelles](03-fonctionnel/planning-lecons.md#f05) | Planifier, déplacer et annuler une leçon ; choisir élève, formation, moniteur, durée, lieu et prestation ; gérer les conflits et les conditions commerciales. | Au pilote, création par personnel. L’élève consulte ; réservation autonome individuelle différée. | Personnel ; élève en consultation. App et web. | G2 |
| [F06 · Préparation pédagogique](03-fonctionnel/planning-lecons.md#f06) | Préparer quelques objectifs, lire les souhaits de l’élève, contrôler les préalables et disposer de repères manuels privés sur la carte. | Repères complétés V3.5 ; ce ne sont ni un trajet enregistré ni une bibliothèque de parcours réutilisables. | Moniteur ; souhaits côté élève. App, tablette et web. | G2 |
| [F07 · Constat de séance](03-fonctionnel/planning-lecons.md#f07) | Enregistrer réalisation, absence ou autre résultat, durée réelle utile et corrections motivées. | Le passage de l’heure ou la durée GPS ne prouvent pas la présence et ne pilotent pas seuls le prix. | Personnel habilité. App et web. | G2 |
| [F08 · Bilans et progression](03-fonctionnel/bilans-documents.md#f08) | Rédiger un bilan privé, évaluer les compétences, publier une version et des annotations textuelles avec ou sans trajet, puis préparer la suite. | Pas de note automatique calculée depuis le GPS. Une publication est une version précise, pas un brouillon partagé qui change silencieusement. | Moniteur et élève destinataire. App et web. | G2 |
| [F09 · Photos et documents](03-fonctionnel/bilans-documents.md#f09) | Importer volontairement une photo de profil, un permis ou un document utile, consulter les pièces autorisées, suivre l’envoi et la validation technique. | Photo de profil facultative ; validation technique READY distincte de validation métier. | Élève et personnel habilité. App, tablette et web. | G1–G2 |
| [F10 · Suivi des règlements](03-fonctionnel/paiements-communications.md#f10) | Consigner montants reçus, moyens de paiement déclarés, remboursements et corrections ; retrouver les soldes et obligations. | Journal interne, pas encaissement intégré TWINT/carte, ni facturation fiscale complète. | Personnel habilité ; élève sur son compte. App et web. | G2–G3 |
| [F11 · Notifications et contact](03-fonctionnel/paiements-communications.md#f11) | Recevoir les informations de service et consulter l’état réel dans Drivy ; accéder aux coordonnées de l’école et gérer les préférences prévues. | Push/email soumis aux canaux/préférences/capacités réelles. Pas de chat ni garantie de livraison d’un push. | Tous selon événement. App et web ; push natif à qualifier. | G1–G3 |
| [F12 · Continuité hors ligne limitée](03-fonctionnel/hors-ligne-vie-privee.md#f12) | Relire le cache autorisé, conserver les brouillons et commandes prévues, poursuivre une capture déjà autorisée dans ses limites puis synchroniser. | Pas de nouvelle réservation, inscription, paiement ou publication annoncée confirmée hors ligne. Le démarrage GPS totalement hors ligne reste hors du profil actuel. | Usages natifs concernés. iPhone/iPad ; web non assimilé à collecteur. | G2 |
| [F13 · Paramètres de l’école](03-fonctionnel/identites-formations.md#f13) | Définir identité, logo, contacts, catégories et paramètres métier retenus ; activer les modules utiles plutôt qu’imposer packs/cours à toutes les écoles. | Couleur d’accent scolaire libre non incluse au pilote, palette Drivy commune. Pas d’éditeur arbitraire de formulaires. | ADMIN et délégations explicites. Web prioritaire, app adaptée. | G1 |
| [F14 · Confidentialité, export et effacement](03-fonctionnel/hors-ligne-vie-privee.md#f14) | Demander l’accès ou l’effacement des données applicables, traiter les demandes scolaires et la suppression globale, appliquer les rétentions justifiées et révoquer les accès aux dérivés. | DM06 reste à qualifier avant diffusion ; archivage, clôture de formation et suppression ne sont pas synonymes. | Personne concernée ; responsables habilités. App et web. | G4, avant G5 public |
| [F15 · Enregistrement GPS facultatif](03-fonctionnel/gps-replay.md#f15) | Démarrer volontairement la collecte pour une leçon autorisée, pauser/reprendre selon les états, arrêter localement, conserver les points et gérer signal/interruption/transfert. | Un appareil collecteur, permissions et choix séparés. Pilote individuel voiture ; ni surveillance permanente ni trajectoires individuelles d’un groupe déduites du téléphone du moniteur. | Moniteur ; choix de l’élève. Swift natif iPhone/iPad. | G0 prototype / G2 parcours |
| [F16 · Carte, replay et observations](03-fonctionnel/gps-replay.md#f16) | Saisir pendant la leçon un repère ou une observation thème/statut, avec ou sans GPS ; retrouver ces observations dans le replay et publier une sélection relue dans le bilan, sans note automatique. | Une capture sélectionnée par bilan dans le contrat actuel ; assemblage de plusieurs captures, navigation guidée et miroir live non promis. | Moniteur et élève autorisé. App et consultation web selon droits. | G0 prototype / G2 parcours |
| [F17 · Prestations et packs composites](03-fonctionnel/catalogue-packs.md#f17) | Configurer prestations/prix de base/options, composer un pack, convenir explicitement du total, suivre les droits et consigner une prestation externe/examen remise, sans faux cours ni double paiement. | Catalogue/règles école versionnés ; acheter un pack ne réserve pas un cours. Vente enregistrée par personnel, paiement en ligne différé. | ADMIN/personnel ; élève en consultation. App et web. | G1 catalogue / G2–G3 usage |
| [F18 · Cours collectifs et inscriptions](03-fonctionnel/cours-collectifs.md#f18) | Créer une série avec toutes ses dates, lieu, formateur, langue et capacité ; publier, accepter inscription volontaire, reconfirmer, annuler, relever les présences et clôturer les droits jamais utilisés. | Complet signifie aucune place. Présence, financement et accomplissement distincts ; liste d’attente et rattrapage autonome différés. | Personnel et élèves éligibles. App, tablette et web. | G3 |
| [F19 · Calendrier d’offres et annonces ciblées](03-fonctionnel/calendrier-notifications.md#f19) | Afficher les cours proposés séparément des engagements, notifier les personnes concernées n’ayant pas accompli la formation, ouvrir le détail et s’inscrire explicitement. | Aucune inscription automatique ; refus d’annonce ne masque pas calendrier. Pas de ciblage site/langue déduit des données privées ; filtre de site non contractualisé au pilote. | Élève ; publication par école. App et web. | G3 |
| [F20 · Onboarding de l’école](03-fonctionnel/onboarding.md#f20) | Configurer progressivement catégories, prestations, organisation et modules ; vérifier ce qui est réellement prêt puis activer les capacités. | Provision initiale contrôlée ; pas besoin de configurer une fonction inutilisée pour commencer. | Responsable d’école. Web prioritaire et app. | G1 |
| [F21 · Onboarding élève et moniteur](03-fonctionnel/onboarding.md#f21) | Rejoindre la bonne école, renseigner identité et coordonnées utiles selon la finalité, déclarer formation, importer facultativement photo et reprendre entre supports. | Champs demandés au moment utile ; moniteur invité ne refait pas le setup ADMIN. GPS/photo/notifications indépendants. | Élève, moniteur invité. App et web. | G1 |
| [F22 · Gestion web et archivage](03-fonctionnel/gestion-web-archivage.md#f22) | Rechercher/filtrer les dossiers, consulter engagements et obligations, faire un aperçu avant archivage individuel ou groupé et restaurer dans les droits. | Fin d’un permis ≠ archive de toute la personne ; pas d’annulation silencieuse des engagements ou dettes ; accès web n’accorde pas ADMIN. | Personnel habilité. Web détaillé, app/tablette adaptée. | G4 |
| [F23 · Statistiques utiles](03-fonctionnel/statistiques.md#f23) | Consulter neuf indicateurs définis d’activité, cours, encaissements et dossiers à suivre ; filtrer les périodes et exporter sous habilitation. | Pas de bénéfice calculé sans charges, de classement pédagogique automatique, ni double comptage des paiements de packs. | ADMIN et personnes déléguées. Web prioritaire ; vues adaptées. | G4 |
## Lecture par utilisateur
**Moniteur :** préparer sa journée, ouvrir un élève et sa formation, préparer la leçon, enregistrer ou non, revoir le trajet, publier un bilan et suivre les engagements. Il dispose d’un contact école sans chat imposé ; ses délégations peuvent lui ouvrir gestion et statistiques dans son périmètre.
**Élève :** rejoindre l’école, compléter son profil et ses documents, voir ses prochaines leçons, ses bilans et trajets publiés, suivre sa formation et ses droits, consulter les cours disponibles puis s’y inscrire quand une place est confirmée. Il peut refuser le GPS sans perdre la leçon.
**Responsable d’école :** configurer l’organisation et les prestations, inviter l’équipe, gérer dossiers/planning/cours/packs, suivre règlements et indicateurs, attribuer des droits, traiter demandes et archivages. La vue de gestion ne donne pas automatiquement accès à toutes les notes privées ou à des données d’autres écoles.
## Support des plateformes
| Support | Prévu | Non promis |
|---|---|---|
| iPhone/iPad | Swift natif, UI adaptative, capture GPS et replay, agenda, dossiers, cours, onboarding et réglages autorisés | Support physique non démontré tant qu’aucun build/appareil n’a été qualifié |
| Web | Personnel : gestion détaillée ; élève : calendrier, cours, dossier, bilans et consultation autorisée | Capture GPS de fond du navigateur identique à l’app native, stockage hors ligne universel |
| Android | Client distinct prévu, contrats et jeux métier réutilisables ; qualification GA0 avant lancement | Disponibilité dès le pilote Apple, réutilisation automatique des vues SwiftUI |
Le ciblage iOS/iPadOS 26/27 est une étude/support à qualifier, pas une obligation validée que toutes les écoles possèdent un modèle récent. Les versions minimum, appareils et fournisseurs restent dans DM01–DM05.
## Extensions prévues, mais pas incluses dans le premier cœur
**U01 n’est plus une extension : le GPS et le replay ont été reclassés dans F15/F16.** Il reste douze entrées U02–U13 cadrées, sans date de disponibilité ni réalisation annoncée.
| Référence | Extension | Ce qui existe déjà sans elle |
|---|---|---|
| [U02](03-fonctionnel/extensions.md#u02) | Bibliothèque et partage d’itinéraires pédagogiques, transformation d’une leçon en modèle | Objectifs, repères manuels privés et replay de la leçon |
| [U03](03-fonctionnel/extensions.md#u03) | Messagerie intégrée | Notifications de service et coordonnées de l’école |
| [U04](03-fonctionnel/extensions.md#u04) | Réservation autonome des leçons individuelles | Planning personnel par moniteur et inscription autonome aux cours collectifs |
| [U05](03-fonctionnel/extensions.md#u05) | Paiement en ligne, factures légales, rapprochement et échéanciers avancés | Journal manuel des règlements et packs |
| [U06](03-fonctionnel/extensions.md#u06) | Analyses longitudinales et prévisions étayées | Neuf indicateurs opérationnels F23 |
| [U07](03-fonctionnel/extensions.md#u07) | SMS payants, relances financières et campagnes avancées | Canaux de service et préférences du cœur |
| [U08](03-fonctionnel/extensions.md#u08) | Automatisation réglementaire étendue cantons/catégories | Exigences, justificatifs et profils réellement approuvés |
| [U09](03-fonctionnel/extensions.md#u09) | Parc de véhicules partagé, remplacements complexes et groupes GPS | Sites/salles/formateurs des cours retenus |
| [U10](03-fonctionnel/extensions.md#u10) | Synchronisation agendas Apple/Google/CalDAV | Calendrier interne Drivy |
| [U11](03-fonctionnel/extensions.md#u11) | Déverrouillage biométrique de confort | Authentification et stockage protégé ; aucune permission par biométrie seule |
| [U12](03-fonctionnel/extensions.md#u12) | Optimisation/déduplication avancée des médias | Idempotence et intégrité indispensables des transferts existants |
| [U13](03-fonctionnel/extensions.md#u13) | Liste d’attente et rattrapage autonome par bloc | Affichage Complet et traitement par personnel |
## Exclusions explicites
X01 : scores d’aptitude automatiques. X02 : gamification sans besoin démontré. X03 : identité décorative héritée automatiquement. X04 : saisie obligatoire en mouvement. X05 : reconstruire l’ancienne app écran par écran. Les justifications restent dans les [exclusions](03-fonctionnel/extensions.md#x01). CarPlay, navigation guidée, surveillance continue, miroir live entre appareils et chatbot ne sont pas promis dans ce dossier.
## Limites à accepter ou revoir avant développement
| Choix actuel de conception | Effet concret | État |
|---|---|---|
| Démarrage GPS autorisé en ligne | Sans réseau initial, réaliser la leçon sans GPS ; une capture déjà autorisée peut continuer dans ses bornes | Recommandation existante, pas une nouvelle demande du porteur |
| Une capture sélectionnée par publication | Plusieurs captures séquentielles ne sont pas fusionnées automatiquement dans un même replay publié | Contrat actuel ; changement possible mais à spécifier |
| Profil GPS du pilote : leçon individuelle voiture | Les formations de permis restent multiples, mais la trace d’un moniteur ne prouve pas celle de chaque élève moto | Limite pédagogique et technique explicite |
| Bornes proposées de collecte/transfert/conservation | Les durées R42 et politiques de données doivent être approuvées avec les besoins réels | Propositions, jamais obligations légales implicites |
| Interface pilote en français | La langue annoncée d’un cours ne traduit pas l’interface ; autres langues UI demandent qualification | Périmètre actuel, à confronter aux écoles |
| Nom/logo/contact, accent commun | Pas de personnalisation libre du thème de chaque école | Clarification V3.5 sans nouvelle promesse graphique |
| Dernier administrateur et suppression globale | Traitement coordonné explicite, pas refus automatique ni transfert de propriété au support | Contrat écrit ; procédure et délai à valider avant publication |
## Fonctions dont la réalisation dépend encore de décisions
Le [registre courant](06-gouvernance/audit-corrections-v3-11.md#decisions) reste prioritaire pour le matériel/OS, le fournisseur d’identité, les politiques de clés, les profils de cours, les règles commerciales, les responsabilités et délais, les budgets et le lancement Android. Ces décisions ne sont pas des oublis de code à combler automatiquement par un agent. Le dossier ne prétend pas avoir obtenu des validations d’utilisateurs ou d’écoles.
**Vérification produit suivante :** une tranche Swift de bout en bout sur appareil, puis essais des cours/packs et du web sur le même backend. Des liens valides et un schéma qui refuse une requête ne prouvent ni la valeur pédagogique ni le fonctionnement de l’application.

## Niveau de préparation et décisions non transformées en exigences

Toutes les fonctions ci-dessus restent **prévues, non démontrées en application**. La V3.7 conserve ces compléments et précise F03/F18 (preuves et présences corrigées), F17 (régularisation des droits), F11 (routage push) et F15 (provenance des mesures). Le contrat décrit ces opérations ; aucun serveur ni client n’est déclaré compatible avant implémentation et recette.

| Proposition à arbitrer, et non décision du porteur | Ce qui est conservé maintenant | Dépendance pour changer |
|---|---|---|
| Démarrer le GPS seulement après autorisation en ligne | Profil actuel conservé, pas une limitation de Swift | Autorisation préémise, révocation et budgets hors ligne à spécifier et éprouver |
| Une capture sélectionnée par bilan | Publication versionnée d’une capture et textes autonomes | Agrégation de captures, consentements et purge transversale à concevoir |
| Accent Drivy commun | Nom/logo/contact configurables | Modèle de thème et contrastes avant personnalisation libre |
| Services examen/externes consignés après remise | Aucun faux cours ni réservation d’examen officiel | Agenda spécialisé et preuve réglementaire seulement après besoin validé |
| Frais conditionnels automatiquement déclenchés | Frais inclus décomposés, corrections manuelles F10 | Règles de déclenchement et conditions à valider, pas de facturation cachée |
| Préférences externes initialement désactivées | Centre interne et calendrier disponibles ; choix proposé en onboarding | Vérifier compréhension et usages avec moniteurs/élèves |
| Requalification tardive d’absence après libération du droit | Fait enregistré et suivi de droit séparé R109 ; AP201 pour résoudre | Politique de renonciation/habilitation et recette à approuver |

Ces limites ne suppriment aucune exigence de GPS, tablette ou cours volontaire. Les extensions U02–U13 restent différées ; les scores automatiques restent exclus. Les propositions nouvelles de prix et de clôture doivent être revues par l’école pilote, sans prétendre qu’une source commerciale en prouve les usages internes.

## Dépendances et degré de spécification

Le statut **cœur** indique une intention de livraison, pas une acceptation automatique de chaque option technique. Toutes les fonctions restent **NON IMPLÉMENTÉES / NON TESTÉES dans ce dossier**. Les 23 références contiennent des règles, données et critères de recette, mais les dépendances suivantes conditionnent leur finalisation :

| Groupe | Dépendances fonctionnelles | Points à résoudre ou à qualifier |
|---|---|---|
| F01–F03, F20–F21 | Identité, école, rôles, profils, invitation et justificatifs | Fournisseur d’identité, champs réellement nécessaires, préalables réglementaires, cas multi-écoles et dernier administrateur. |
| F04–F07 | F01–F03, F13, F17 et occupations | Durées, marge entre engagements, conditions de modification et véritables essais concurrents. |
| F08–F09, F15–F16 | Leçon/formation, documents, autorisation et publication versionnée | Annotation textuelle indépendante désormais contractée ; fonctionnement natif, bornes, interruption et capture unique à qualifier. |
| F10, F17 | Tarifs versionnés, compte, droits et événements réels | Prix de base/options et remise manuelle des services complétés ; règles d’école, frais automatiques conditionnels et gestion avancée d’examen non acquis. |
| F11, F18–F19 | Calendrier, éligibilité, capacités, droits, préférences | Clôture et correction tardive contractualisées ; régularisation du droit séparée, preuves de validation réexaminées. Politique proposée et essais réels requis. |
| F12–F14, F22 | Sessions, accès, caches, journaux et obligations | Hors-ligne limité, rétentions, mandat de suppression et procédures d’exploitation à éprouver. |
| F23 | Constat, présence, finance et droits d’accès | Mesures calculées uniquement lorsque leurs données sources existent ; aucun nouveau KPI déduit d’une remise de service. |

**Propositions non validées :** démarrage GPS avec autorisation en ligne, une capture par publication, palette commune au pilote, français initial, appareil individuel voiture pour la collecte, libération explicite des droits jamais consommés à la clôture et préférences externes initialement désactivées. Ce sont des choix de conception identifiés, non des exigences ajoutées au porteur. Le [registre d’arbitrages courant](06-gouvernance/audit-corrections-v3-11.md#decisions) explique leur conséquence.

<a id="compléments-métier-hérités-de-la-v37"></a>
## Preuves, corrections et cohérence métier
Les 23 fonctions gardent leur périmètre. Une présence peut maintenant être rectifiée même si le droit du pack rendu a déjà été utilisé ; un suivi distinct reste à régler par le responsable. Une validation de formation dépend de versions de preuves identifiables et repasse à vérifier si ces preuves changent. Le GPS ne récupère pas un ancien point comme départ de la nouvelle leçon. Le push natif suit l’installation et le compte courants ; le centre web n’est pas un nouveau service Web Push.

Ces corrections n’ajoutent ni décompte automatique depuis le GPS, ni note d’aptitude générée, ni fusion automatique de captures. **Choix R109 à approuver :** autoriser ADMIN à renoncer explicitement à consommer un droit sans remboursement d’argent. Les versions, matériel, règles suisses applicables, délais de suppression et budgets restent au registre. [Rapport V3.7](06-gouvernance/audit-corrections-v3-7.md).

## Design retenu et état des maquettes

La direction A **Cartographie native**, claire et bleue, est choisie par le porteur. Le [dossier DESIGN](DESIGN/README.md) contient palette claire/sombre, composants, cartographie, états et maquettes. Les 15 compositions illustrent certains écrans ; les autres conservent leurs spécifications et familles visuelles, sans prétendre être dessinés. Les 23 fonctions ne changent pas. Le contrat courant est 3.11.0 ; les règles d’école, les droits et les confirmations ne sont pas remplacés par les comportements simulés du prototype.

<a id="précision-de-couverture-v39"></a>
## Couverture visuelle et limites de preuve
Les 23 fonctions restent inchangées. La maquette « Mes leçons » complète la vue élève de F05 et la consultation de F08/F16 : aucun nouveau droit de démarrage GPS n’est accordé à l’élève. F08 dispose maintenant d’un formulaire illustré conforme aux trois textes et aux observations contextualisées déjà prévus. F15/F16 et F18/F19 reçoivent des corrections d’interaction, pas un nouveau moteur métier.

Une entrée de navigation indiquée « écran prévu, non illustré » dans la galerie ne retire pas la fonction du catalogue. La galerie illustre **16 références d’écran sur 49**, dans **15 compositions**, sans couvrir toutes leurs variantes ; les **33 autres** restent à dessiner. Le portail d’administration ne doit jamais être remplacé par une vue personnelle élève pour donner l’illusion que sa navigation est complète. [Couverture exacte](DESIGN/04-ecrans-reference.md).

<a id="compléments-v310-mêmes-fonctions-transitions-plus-précises"></a>
## Fichiers, exports et transitions natives
**F09/F13 :** fichier ou logo reçu, scellé, contrôlé puis disponible ; remplacement derrière un READY interdit. Reprise après timeout/expiration avec conservation du brouillon, sans promettre upload par morceaux pour les pièces. Les octets scellés et leurs dérivés sont supprimés selon politique et ne réapparaissent pas après un scan tardif.

**F14/F22/F23 :** exports de gestion CSV UTF-8 distincts des ZIP de données personnelles ; type, nom sûr, taille et hash à disponibilité réelle. Un ancien export peut devenir inaccessible si ses autorisations disparaissent. Une copie volontairement sauvegardée hors Drivy n’est pas révocable.

**F01/F12/F15 :** sessions réseau et credentials séparés, cache HTTP privé non persistant, couverture des scènes dans le sélecteur d’applications sans arrêter le collecteur GPS. Ce sont des exigences d’intégration à démontrer sur iPhone/iPad, pas de nouvelles captures ou fonctions déjà livrées.

Le catalogue conserve 23 fonctions et 49 références d’écran. Les nouvelles variantes de transfert/export sont spécifiées mais ne complètent pas automatiquement les 33 écrans non dessinés. Paramètres de décodage, fournisseur de stockage et durées d’intention/cleanup restent des décisions de réalisation identifiées, pas des règles d’école inventées.
