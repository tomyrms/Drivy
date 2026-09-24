# Rôles, périmètres et changements d’accès

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Principes d’autorisation

Référence : [R01 à R04](regles-etats.md#r01), [R34](regles-etats.md#r34), [R36](regles-etats.md#r36), [R37](regles-etats.md#r37). Le modèle ne reprend pas un unique rôle par personne. L’appartenance est scolaire ; les rôles sont cumulables ; l’affectation pédagogique donne accès à une formation déterminée.

**ADMIN** gère l’école, les rendez-vous et les données administratives. **INSTRUCTOR** accompagne les formations qui lui sont affectées. **LEARNER** consulte et contribue à son propre parcours. Un administrateur également moniteur cumule les deux rôles, mais reste soumis à l’affectation pédagogique. Il n’existe pas de rôle parent ni secrétaire autonome au pilote ; les délégations de cours et catalogue ci-dessous sont incluses, sans partage de compte ni création d’un rôle parent.

Le support de la plateforme n’est pas administrateur permanent de toutes les écoles. Un accès exceptionnel nécessite demande motivée, durée limitée, approbation scolaire et trace. L’accès aux documents de permis et bilans n’est pas nécessaire pour diagnostiquer une simple erreur réseau.

## Matrice normative proposée

A = autorisé dans son école ; AF = formations affectées ; SOI = propres données ; N = interdit. « Administrer » ne signifie pas pouvoir lire tout contenu pédagogique.

| Action | ADMIN | INSTRUCTOR | LEARNER | Restriction supplémentaire |
|---|---|---|---|---|
| Lire identité et contact de l’école | A | A | A dans son école | Contact opérationnel scolaire ; pas un annuaire privé. |
| Lister les appartenances et grants (AP07) | A | N | N | Liste administrative ; les noms utiles du moniteur sont projetés avec les engagements autorisés. |
| Inviter personnel et attribuer rôles | A | N | N | Dernier ADMIN protégé. |
| Inviter un élève | A | A | N | Le moniteur n’attribue que LEARNER ; une affectation administrative explicite reste nécessaire avant accès au dossier (F02). |
| Modifier dossier administratif | A | AF, champs de contact utiles | SOI, coordonnées proposées | Identité OIDC et email via parcours vérifié distinct. |
| Ajouter une formation | A | AF sur dossier déjà autorisé | N | Offre activée et catégorie confirmée. |
| Affecter ou retirer un moniteur | A | N | N | Impact sur brouillons et leçons futures affiché. |
| Examiner pièce de permis | A | AF si habilitation permit_review | SOI en lecture | L’habilitation est un grant explicite, non un rôle implicite. |
| Approuver un contrôle de permis | A si permit_review | AF si permit_review | N | Motif et identité du contrôleur. |
| Lire planning école | A | Son planning ; occupation anonyme d’autres ressources | SOI | Les noms des autres élèves ne figurent pas dans les conflits. |
| Réserver, déplacer, annuler une leçon individuelle | A | Ses leçons et AF | N | Vérifier contraintes et version au serveur. |
| Saisir résultat et brouillon | Si aussi INSTRUCTOR et AF | Ses leçons et AF | N | Remplacement explicite possible. |
| Lire bilan publié | Seulement si INSTRUCTOR et AF | AF | SOI | Un droit administratif seul ne révèle pas le texte. |
| Lire brouillon | Auteur ou transfert explicite autorisé | Auteur | N | Pas de partage automatique à toute l’école. |
| Publier ou corriger un bilan | Si aussi INSTRUCTOR et AF | Auteur habilité/moniteur désigné | N | Une correction exige une nouvelle révision. |
| Saisir souhait de prochaine leçon | N sauf aussi LEARNER concerné | N, lecture AF seulement | SOI | Contribution élève séparée des objectifs du moniteur. |
| Déposer un document | A sur pièces administratives | AF | SOI | Audience et finalité obligatoires. |
| Lire document administratif restreint | A avec finalité | AF avec grant adapté | Son dépôt ou pièce partagée | Aucune lecture d’une pièce pédagogique par ADMIN seul. |
| Lire solde et journal de règlement | A | Ses leçons | SOI | Aucun journal global par ce droit ; métriques d’école seulement avec le grant financier distinct F23. |
| Enregistrer encaissement | A | Ses leçons si grant cash_record | N | Pas de paiement en ligne dans cette fonction. |
| Rembourser, corriger charge | A | N | N | Motif et contre-écriture. |
| Voir journal d’audit scolaire | A, sans texte sensible | Ses actions pertinentes | Ses changements visibles | Export d’audit limité par finalité. |
| Terminer/archiver une formation F03 | A | Demander via contact interne | N | Ne concerne que le permis choisi ; traiter ses engagements. |
| Archiver/restaurer le dossier F22 | A | MANAGE_LEARNER_ARCHIVES et affectation | N | Prévisualisation, blocages et conservation selon R87–R91. |
| Demander accès ou suppression de données | A pour l’école | SOI | SOI | Décision instruite, pas effacement immédiat. |

Les grants `permit_review` et `cash_record` sont des habilitations précises stockées dans l’appartenance. Ils n’élargissent jamais le périmètre AF ni ne transforment un moniteur en ADMIN.

## Cas multi-écoles et multi-rôles

La sélection d’école est persistée comme préférence locale, pas comme droit. Chaque changement recharge les autorisations et présente le nom de l’école dans l’en-tête. Un brouillon de l’école A ne suit pas l’utilisateur dans l’école B. Un moniteur également élève peut basculer entre son contexte de travail et son parcours personnel ; les contrôles serveur ne dépendent pas du mode affiché.

Aucune API ne permet à une école de savoir qu’un élève est inscrit ailleurs. Le pilote contrôle les collisions **au sein de l’école** seulement. Cette limite est affichée dans le paramétrage, particulièrement pour les moniteurs travaillant pour plusieurs établissements. Une garantie inter-écoles demanderait un service d’occupation anonyme et une analyse de confidentialité distincte.

## Retrait et remplacement

L’administration choisit la date effective et voit les leçons futures, les brouillons et les pièces dont l’accès changera. Un remplacement peut être limité à une formation et à une période. Avant de retirer un moniteur, traiter ses leçons futures par réaffectation ou annulation. Les brouillons appartiennent à l’école sur le plan documentaire selon contrat à valider, mais ne sont pas rendus lisibles automatiquement à toute l’équipe : un transfert de responsabilité motivé est enregistré.

Si la révocation est urgente, le serveur bloque immédiatement les nouvelles commandes ; les brouillons non envoyés deviennent un cas de récupération encadrée, pas une exportation libre par l’ancien membre. L’écran donne un contact et une référence technique non sensible. Le système ne prétend pas effacer instantanément un appareil hors connexion.

## Tests de permission obligatoires

Pour chaque route et chaque type de pièce : mêmes identifiants sous une autre école, membre retiré, même personne avec autre rôle, moniteur non affecté, élève frère/homonyme, compte multi-écoles. Vérifier refus de l’API, absence dans listes et recherches, absence dans synchronisation et refus du téléchargement, pas seulement bouton masqué. Un refus ne doit pas changer l’objet ni créer de notification métier.

## Capacités du cœur GPS, commercial et collectif

Les nouveaux grants portent exactement les noms ci-dessous. Ils sont stockés dans l’appartenance et contrôlés côté serveur ; ils n’élargissent pas les droits pédagogiques aux formations non affectées.

| Action | Personnel autorisé | Élève | Limite |
|---|---|---|---|
| Démarrer/arrêter GPS | INSTRUCTOR de la leçon et formation affectée | Peut refuser/demander arrêt sur sa leçon | Pas de capture automatique ni admin global. |
| Revoir une trace privée | Moniteur affecté et responsable du bilan | Non avant publication pédagogique, hors procédure d’accès F14 | Pas d’accès par seul grant de cours. |
| Lire replay publié | Affectation pédagogique autorisée | Son propre trajet | Publication et transfert distincts. |
| Déclarer son choix GPS | Moniteur enregistre le choix réellement exprimé ; élève pour lui-même | SOI | Révocation locale/serveur traitée selon R42. |
| Configurer produits/packs | CONFIGURE_CATALOG | Non | Prix versionnés, profils légaux non librement éditables. |
| Attribuer un achat/droit | SELL_SERVICES | Non | Conditions, bénéficiaire, audit et compte. |
| Publier/déplacer/annuler une série | MANAGE_COURSES | Non | Salle, formateur et inscrits contrôlés. |
| Inscription collective | MANAGE_COURSES pour demande réelle enregistrée | SOI, serveur arbitre | Même capacité et conditions pour tous les canaux. |
| Consulter liste des inscrits | MANAGE_COURSES ou formateur affecté | Non | Pas de GPS/progression de conduite par ce seul droit. |
| Marquer présences | TAKE_ATTENDANCE sur occurrences affectées | Non | Validation finale distincte. |
| Valider exigence/preuve externe | VALIDATE_REQUIREMENT | Déposer seulement | Pas de preuve créée par clic d’inscription. |
| Modifier un profil réglementaire | Responsable de configuration habilité hors exploitation courante | Non | Revue documentée avant APPROVED ; pas de contournement par un moniteur. |
| Acheter/lire un pack | SELL_SERVICES pour vente, finance selon grants existants | Lire ses droits et comptes | Encaissement en ligne hors pilote. |

Un ADMIN reçoit par configuration explicite les grants administratifs nécessaires ; il n’obtient jamais le grant de lecture de toutes les traces. Une personne peut gérer les sensibilisations sans être moniteur de conduite de tous les participants. Les notifications révèlent seulement ce que le destinataire peut déjà consulter.

Retrait de capacité : traitement des futures occurrences, des campagnes en attente, des captures actives et des inscriptions avant archivage ; pour une révocation urgente, refus serveur immédiat et limites hors connexion documentées. Chaque test de permission vérifie API, listes, synchro et téléchargements, pas uniquement la navigation.


## Grants et surfaces V3

Les rôles ADMIN, INSTRUCTOR et LEARNER restent inchangés. Un indépendant peut cumuler ADMIN/INSTRUCTOR. Un éventuel rôle de secrétariat distinct n’est pas ajouté sans besoin validé : la délégation passe par des grants limités et auditables. Les droits sont identiques via web, tablette et téléphone.

| Capacité | ADMIN | INSTRUCTOR seul | LEARNER |
|---|---|---|---|
| Configurer/activer l’école, politique de champs F20 | Oui, dans son école | Non | Non |
| Onboarding personnel F21 | Son propre parcours | Son propre parcours | Son propre dossier |
| Lire profil administratif détaillé | Besoin administratif, école | Élèves affectés et champs nécessaires | Ses propres champs |
| Archiver/restaurer F22 | Oui | MANAGE_LEARNER_ARCHIVES et affectation | Non ; demande de droits séparée |
| Activité non financière de toute l’école | Oui | VIEW_SCHOOL_METRICS | Non |
| Activité personnelle affectée | Si INSTRUCTOR, ou grant d’école | Oui, scope SELF | Non |
| Métriques financières d’école | Oui | VIEW_FINANCIAL_METRICS | Non ; comptes personnels F10 seulement |
| Export de gestion | EXPORT_MANAGEMENT et accès au jeu | Même règle, scope borné | Non ; export personnel F14 |
| Lire une trace privée de leçon | Pas par ADMIN seul | Affectation et droit pédagogique | Seulement publication autorisée |

L’ADMIN peut attribuer les nouveaux grants **MANAGE_LEARNER_ARCHIVES**, **VIEW_SCHOOL_METRICS**, **VIEW_FINANCIAL_METRICS**, **EXPORT_MANAGEMENT** ; l’attribution reste explicitement journalisée. Pour les administrateurs, le droit d’export est attribué explicitement (pas caché derrière un téléchargement générique). Retrait d’un grant invalide les résultats en mémoire, les jobs non achevés et les téléchargements correspondants. Les agrégats sans droit ne sont ni retournés à zéro ni cachés seulement par CSS.

Le dossier archivé garde le même périmètre de lecture publié lorsque Membership reste ACTIVE. Si Membership est REVOKED, R02/R34 s’appliquent indépendamment de l’état du dossier. L’identité globale et les autres écoles ne sont pas touchées.


<a id="identité-globale-et-protections-de-choix-v35"></a>
## Identité globale et protections de choix
AP193–AP197 sont propres à la personne courante et ne nécessitent pas une école active ; aucune délégation scolaire n’autorise la suppression de l’identité d’autrui. AP198 utilise un reçu de suivi distinct et non une session métier. Les opérations internes de traitement ont un compte de service à droits minimaux par tâche, audité ; le support n’est pas automatiquement ADMIN des écoles.

Pour AP153, le personnel peut consigner une demande verbale réelle mais ne peut pas lever un refus SELF applicable : [R101](regles-etats.md#r101). Pour le permis, READY ne prouve pas une validation humaine : [R07](regles-etats.md#r07).

<a id="actions-complétées-v36"></a>
## Droits sur les services et demandes globales
AP199 : ADMIN ou SELL_SERVICES dans son périmètre élève ; lecture de remise via AP113 pour le titulaire ou personnel habilité. Modifier le total exceptionnel d’une vente demande ADMIN, pas seulement SELL_SERVICES. AP138 : MANAGE_COURSES ou ADMIN pour clôturer ; si des droits inutilisés sont libérés, exiger aussi SELL_SERVICES ou ADMIN. TAKE_ATTENDANCE seul ne modifie pas les droits de pack.

AP200 : propriétaire de l’aperçu global uniquement, sans école sélectionnée ; aucun accès par rôle ADMIN d’une école. Toute commande scolaire mutante observe d’abord l’accès global des identités selon [l’ordre unique](../04-technique/transactions-v2.md#autorisation-et-commit). Les tâches internes mandatées pour conservation/effacement restent des chemins explicitement autorisés, pas des sessions de l’utilisateur révoqué.

<a id="délégations-et-nouvelles-corrections-v37"></a>
## Délégations, preuves et régularisations
TAKE_ATTENDANCE autorise le constat/correctif de présence sur le cours et son cycle, y compris quand R109 ouvre un suivi de droit ; ce grant ne permet pas de résoudre le suivi ni de débiter arbitrairement un lot. **Proposition pilote : AP201 réservé à ADMIN**, avec relecture des droits au commit. VALIDATE_REQUIREMENT permet AP122 sous le profil approuvé et les preuves exactes, indépendamment du statut financier. Ni SELL_SERVICES ni ADMIN ne créent une exemption pédagogique sans le rôle applicable.

Les mutations de preuve qui invalident une exigence sont effectuées sous un mandat serveur limité au traitement de cette dépendance ; elles conservent l’acteur et l’objet déclencheurs, sans fabriquer une action humaine de validation. Le worker de notifications vérifie le propriétaire de l’installation et ses routes scolaires ; il ne déduit pas la session à partir d’un token fournisseur.
