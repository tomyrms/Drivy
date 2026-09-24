# Disponibilités, réservation, préparation et résultat

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Mode d’emploi

Les règles ne sont pas redéfinies ici : les identifiants R renvoient à leur [référence principale](regles-etats.md). Les séquences suivantes spécifient les fonctions du cœur proposé, avec préconditions, variantes, données et critères observables. L’[autorisation](roles-permissions.md) s’applique à tous les appels, même lorsqu’un bouton n’est pas affiché.

<a id="f04"></a>
## F04 · Disponibilités et temps de préparation

**Besoins :** B01 B04. **Parcours :** [J02](../02-experience/parcours.md#j02), [J04](../02-experience/parcours.md#j04). **Écrans :** [E12](../02-experience/ecrans.md#e12), [E05](../02-experience/ecrans.md#e05).

**Règles et dépendances :** [R08](regles-etats.md#r08), [R09](regles-etats.md#r09), [R10](regles-etats.md#r10), [R31](regles-etats.md#r31), [R35](regles-etats.md#r35). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Faire des propositions compatibles avec les horaires réels et les pauses, sans supposer qu’un espace vide est réservable.

### Rôles, autorisations et préconditions

Moniteur actif avec catégorie autorisée et paramètres d’école. Pour le pilote, les leçons restent dans une même journée locale. L’école choisit la durée proposée et le tampon, sans tarif installé silencieusement.

### Parcours nominal et conséquences

Définir des plages hebdomadaires locales puis les fermetures ponctuelles. Prévisualiser une semaine représentative. Les plages ouvertes sont traduites en instants pour la date demandée ; le moteur retranche occupation et fermetures. Le formulaire affiche la durée pédagogique et le tampon séparément. La commande finale de réservation recalculera tout, même si le créneau vient d’être proposé.

### Variantes, interruptions et cas limites

Congé chevauchant plusieurs jours : instants de début/fin ou dates civiles complètes selon le type, sans mélanger les deux formats. Fermeture sur une leçon existante : afficher les rendez-vous autorisés à déplacer, refuser l’ajout direct. Horaire ambigu au changement d’heure : choisir explicitement l’occurrence. Aucun moteur de trajet ne calcule un temps de déplacement au pilote ; tampon manuel assumé.

### Données, validations et cycle de vie

AvailabilityRule avec jours, localStart/localEnd, validFrom/validTo ; Closure avec intervalle UTC ; InstructorSchedulingSettings versionné. L’auteur et l’école sont obligatoires ; les raisons privées d’une indisponibilité ne sont pas montrées à l’élève.

### Erreurs, événements et reprise

422 INVALID_LOCAL_TIME, 422 AMBIGUOUS_LOCAL_TIME, 409 EXISTING_BOOKINGS, 422 INVALID_INTERVAL. Une erreur de disponibilité n’efface pas le formulaire. Un message distingue aucune plage ouverte et toutes les plages déjà occupées.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T013](../05-realisation/tests-recette.md#t013) | Une pause coupe une plage ouverte. | Aucun créneau proposé ou confirmé ne la recoupe, tampon inclus pour le moniteur. |
| [T014](../05-realisation/tests-recette.md#t014) | Un congé est ajouté sur une leçon future. | Refus atomique avec liste autorisée ; la leçon reste confirmée. |
| [T015](../05-realisation/tests-recette.md#t015) | Le personnel saisit une heure locale dans un saut d’heure. | Le serveur refuse et demande une autre heure, sans décaler silencieusement. |
| [T016](../05-realisation/tests-recette.md#t016) | Deux leçons sont adjacentes mais un tampon est configuré. | Le moniteur ne peut être réservé pendant le tampon ; l’élève n’est pas occupé par ce tampon. |

<a id="f05"></a>
## F05 · Réservation et modification fiable

**Besoins :** B01 B03 B04. **Parcours :** [J02](../02-experience/parcours.md#j02), [J04](../02-experience/parcours.md#j04). **Écrans :** [E03](../02-experience/ecrans.md#e03), [E04](../02-experience/ecrans.md#e04), [E05](../02-experience/ecrans.md#e05), [E14](../02-experience/ecrans.md#e14).

**Règles et dépendances :** [R06](regles-etats.md#r06), [R08](regles-etats.md#r08), [R09](regles-etats.md#r09), [R10](regles-etats.md#r10), [R11](regles-etats.md#r11), [R12](regles-etats.md#r12), [R13](regles-etats.md#r13), [R14](regles-etats.md#r14). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Créer un engagement clair sur un élève, une formation, un moniteur, une heure et un lieu, puis le modifier sans ambiguïté.

### Rôles, autorisations et préconditions

Personnel habilité ; formation ACTIVE ; moniteur affecté ; catalogue et prix confirmés. La vérification du permis peut être en attente mais elle doit être visible. Réservation connectée uniquement. Le prix est un montant convenu, pas un encaissement.

### Parcours nominal et conséquences

Depuis Planifier ou une formation, choisir élève/formation, moniteur, date, durée et lieu de rendez-vous textuel. Les créneaux sont des suggestions, non des réservations temporaires. Récapitulatif lisible, puis confirmer. Le serveur verrouille les ressources, vérifie droits et capacité, écrit la leçon et son occupation, l’opération et les avis. Le succès contient la version et l’heure confirmées. Déplacer utilise le même récapitulatif avant/après.

### Variantes, interruptions et cas limites

Deux agents choisissent la même heure : seul le gagnant confirme ; le second conserve ses valeurs et reçoit des alternatives. Retour réseau incertain après confirmation : rechercher l’opération avant toute nouvelle commande. Changement de formation après réservation : annuler et recréer, pour ne pas réinterpréter un historique. Le lieu peut être corrigé sans changer le créneau, mais déclenche un avis versionné. Le bouton élève « Contacter l’école » ne crée aucune réservation ni demande interne.

### Données, validations et cycle de vie

Lesson, Reservation pour moniteur et élève, point de rendez-vous textuel, plannedStart/plannedEnd, bufferMinutesSnapshot, priceCentsSnapshot, schoolPolicyVersion, version. Pas de coordonnées GPS requises ; un lien vers l’app cartographique externe peut être proposé après avertissement sur son fournisseur.

### Erreurs, événements et reprise

409 SLOT_CONFLICT (raison anonyme), 412 VERSION_CONFLICT, 422 TRAINING_NOT_ACTIVE, 422 INSTRUCTOR_NOT_ASSIGNED, 428 PRECONDITION_REQUIRED. Les indisponibilités privées ne sont jamais décrites par leur motif personnel.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T017](../05-realisation/tests-recette.md#t017) | Deux requêtes concurrentes prennent le même moniteur et la même heure. | Une seule leçon confirme ; pas de notification pour la requête refusée. |
| [T018](../05-realisation/tests-recette.md#t018) | Deux moniteurs réservent le même élève sur deux formations au même moment. | La seconde réservation est refusée au sein de l’école. |
| [T019](../05-realisation/tests-recette.md#t019) | Le nouveau créneau est pris au moment du commit. | Ancien rendez-vous et version restent inchangés, aucun avis de déplacement. |
| [T020](../05-realisation/tests-recette.md#t020) | La transaction réussit mais la réponse réseau est perdue. | La consultation/reprise de la même opération retrouve une seule leçon. |

<a id="f06"></a>
## F06 · Préparation et souhait de l’élève

**Besoins :** B01 B03. **Parcours :** [J03](../02-experience/parcours.md#j03), [J06](../02-experience/parcours.md#j06). **Écrans :** [E04](../02-experience/ecrans.md#e04), [E07](../02-experience/ecrans.md#e07), [E14](../02-experience/ecrans.md#e14).

**Règles et dépendances :** [R06](regles-etats.md#r06), [R07](regles-etats.md#r07), [R11](regles-etats.md#r11), [R17](regles-etats.md#r17), [R33](regles-etats.md#r33). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Passer du dernier bilan à un petit nombre d’objectifs concrets, sans transformer tout souhait de l’élève en programme validé.

### Rôles, autorisations et préconditions

Leçon PLANNED et formation visible. Moniteur affecté pour fixer les objectifs ; élève propriétaire pour saisir un souhait. La disponibilité hors ligne dépend de la projection préparée.

### Parcours nominal et conséquences

Afficher dernier bilan publié, prochaine étape et état du contrôle de permis. L’élève peut écrire un souhait dans un champ séparé. Le moniteur sélectionne ou saisit jusqu’à trois objectifs et précise le contexte prévu. Il confirme avoir vérifié les points administratifs nécessaires à l’arrêt. Cette préparation ne publie pas d’observation et ne présume pas que les exercices auront eu lieu.

### Variantes, interruptions et cas limites

Aucun bilan précédent : proposer de définir un premier objectif, pas une progression à zéro. Élève multi-permis : le souhait porte la formation et éventuellement la prochaine leçon. Annulation de la leçon : conserver le souhait de formation, marquer objectifs de cette leçon abandonnés sans les reporter automatiquement. Modification simultanée : versions séparées pour souhait et plan du moniteur afin d’éviter un conflit artificiel.

### Données, validations et cycle de vie

LessonPreparation, Goal(label,competencyVersionId optionnel,context), LearnerWish(trainingId,lessonId optionnel,text,version). Une sélection de compétence n’est pas une évaluation. La préparation n’est jamais appelée attestation légale de conduite.

### Erreurs, événements et reprise

422 TOO_MANY_GOALS, 412 VERSION_CONFLICT, 409 LESSON_CLOSED. L’app conserve le brouillon et explique si la leçon a changé. Aucun blocage par absence de GPS.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T021](../05-realisation/tests-recette.md#t021) | L’élève demande un exercice avant la leçon. | Le moniteur voit une proposition distincte, pas un objectif déjà validé. |
| [T022](../05-realisation/tests-recette.md#t022) | Aucun bilan n’existe encore. | État vide pédagogique, possibilité de préparer sans note artificielle. |
| [T023](../05-realisation/tests-recette.md#t023) | Une leçon préparée est annulée. | Les objectifs ne deviennent pas des observations ; le souhait de formation demeure. |
| [T024](../05-realisation/tests-recette.md#t024) | L’élève modifie son souhait tandis que le moniteur prépare. | Aucune écriture n’écrase le texte de l’autre, versions de ressources distinctes. |

<a id="f07"></a>
## F07 · Réalisation et correction du résultat

**Besoins :** B01 B02 B04 B06. **Parcours :** [J03](../02-experience/parcours.md#j03), [J05](../02-experience/parcours.md#j05). **Écrans :** [E04](../02-experience/ecrans.md#e04), [E08](../02-experience/ecrans.md#e08), [E17](../02-experience/ecrans.md#e17).

**Règles et dépendances :** [R07](regles-etats.md#r07), [R11](regles-etats.md#r11), [R12](regles-etats.md#r12), [R14](regles-etats.md#r14), [R15](regles-etats.md#r15), [R16](regles-etats.md#r16), [R23](regles-etats.md#r23), [R39](regles-etats.md#r39), [R40](regles-etats.md#r40). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Enregistrer la réalité d’une leçon après la conduite, sans dépendre d’un enregistrement live ni fabriquer un résultat quand l’heure passe.

### Rôles, autorisations et préconditions

Moniteur de la leçon affecté à la formation ; PLANNED pour la clôture nominale. Saisie à l’arrêt. Une date passée non renseignée n’est ni une absence ni une réalisation automatique.

### Parcours nominal et conséquences

Ouvrir la leçon, choisir « Faire le bilan », renseigner heures réelles et constat, puis enregistrer. Connecté, CompleteLesson crée résultat, brouillon et charge interne. Hors ligne natif, seule l’opération locale est mise en attente. Après confirmation, le moniteur peut encore travailler le brouillon avant publication. Le marquage NO_SHOW ou l’annulation suit une action distincte avec récapitulatif et motif.

### Variantes, interruptions et cas limites

Leçon effectuée malgré un contrôle de permis non résolu : enregistrer le fait avec anomalie et raison, avertir un responsable ; jamais faire passer la pièce à APPROVED pour permettre l’enregistrement. Durée très différente : demander une raison, mais garder prix convenu sauf correction explicite F10. Résultat erroné : CorrectOutcome avec compensation ; pas de bouton qui supprime la leçon.

### Données, validations et cycle de vie

Outcome, actualStart/actualEnd, anomalyFlags, correctionReason, ReportDraft, ChargeEntry et AuditEvent. La durée réelle sert au bilan ; le montant initial suit le prix convenu et non un calcul horaire implicite.

### Erreurs, événements et reprise

409 LESSON_OUTCOME_CONFLICT, 422 INVALID_ACTUAL_INTERVAL, 412 VERSION_CONFLICT, 409 FINANCIAL_RECONCILIATION_REQUIRED. Si la transaction échoue, rien de partiel n’est confirmé et le brouillon demeure local.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T025](../05-realisation/tests-recette.md#t025) | Une leçon prévue est réellement terminée. | Résultat, brouillon, charge et audit sont tous créés ou aucun ne l’est. |
| [T026](../05-realisation/tests-recette.md#t026) | L’heure de fin planifiée est dépassée sans action. | La leçon reste PLANNED avec résultat à renseigner, pas NO_SHOW automatique. |
| [T027](../05-realisation/tests-recette.md#t027) | Un appareil termine pendant qu’un autre annule. | Une seule commande de version courante réussit ; l’autre devient un conflit visible. |
| [T028](../05-realisation/tests-recette.md#t028) | Une leçon payée est déclarée réalisée à tort. | Correction bloquée tant que compensation financière et traitement du bilan ne sont pas explicités. |

## F07 · Matrice détaillée de correction d’un résultat

CorrectOutcome exige `reason`, version de leçon et version du compte financier. Il ne change jamais la formation ou la personne. ADMIN reste nécessaire ; si le bilan doit être retiré/corrigé, l’opération est approuvée par un moniteur affecté ayant l’habilitation de publication. La transaction n’est exécutée qu’une fois toutes les approbations obtenues. Le responsable peut être la même personne s’il cumule les droits.

| Résultat actuel | Résultat demandé | Préconditions et effet |
|---|---|---|
| COMPLETED | CANCELLED ou NO_SHOW | Retrait explicite du bilan publié, résolution des charges et remboursements, motif ; projection recalculée. |
| CANCELLED ou NO_SHOW | COMPLETED | Constat réel et heures, moniteur affecté, création d’un brouillon ; charge initiale seulement si aucune charge de réalisation n’existe déjà, sinon ajustement explicite. |
| CANCELLED, NO_SHOW ou COMPLETED | PLANNED | Nouveau créneau futur validé et occupation atomique ; retrait du résultat/bilan du parcours courant, conservation de l’historique ; rapprochement financier préalable. |
| CANCELLED | NO_SHOW | Rendez-vous historique terminé ; justification de la correction, aucune facturation implicite. |
| NO_SHOW | CANCELLED | Raison d’annulation corrigée, rapprochement des frais éventuels. |
| Même résultat | Même résultat | Correction ciblée des heures ou du motif par commande dédiée ; pas de nouvelle charge ni nouveau bilan automatiquement. |

Une correction concernant une ancienne leçon hors affectation actuelle est instruite par l’école, pas contournée par un rôle global. Les opérations composées ont un aperçu clair des conséquences. Si le remboursement ne peut pas être enregistré parce qu’il n’a pas réellement eu lieu, la correction reste un dossier en attente plutôt qu’une fausse écriture de remboursement.

## Intégration du GPS, des droits et des cours

Une leçon possède un mode commercial UNIT_PRICE ou ENTITLEMENT, un ServiceProductVersion et une quantité acceptée. La réservation d’un droit compatible est atomique avec les occupations ; si le créneau échoue, aucun droit n’est immobilisé. CompleteLesson consomme le HOLD et crée une charge nulle lorsque la prestation est déjà financée par un pack. Les prix, durées et quantités ne sont jamais déduits de la capture.

La préparation mène à [F15](gps-replay.md) avec choix explicite. Le début de capture ne change pas automatiquement le résultat Lesson ; une capture est une ressource autonome. L’arrêt local précède toujours la clôture, même si le réseau ne répond pas. Une capture manquante ou partielle ne bloque ni résultat ni bilan. Les horaires effectifs restent ceux de la séance, pas les bornes des points GPS.

Les collisions couvrent les engagements de cours collectifs et les leçons au sein de la même école. Une offre non inscrite ne bloque pas un élève ; un moniteur qui anime une occurrence n’est pas disponible pour une leçon au même moment. Le parcours autonome [F18](cours-collectifs.md) ne donne pas aux élèves le pouvoir de modifier leurs leçons individuelles au pilote.

<a id="revision-commerciale"></a>
## Révision commerciale d’une leçon encore planifiée

Le déplacement simple conserve durée, tarif et droits. Le changement de durée n’est pas un raccourci pour recalculer un tarif depuis le GPS : [R13](regles-etats.md#r13) exige une proposition commerciale explicite et cohérente avec la prestation.

AP42 accepte un bloc `commercialChange` contenant la sélection du service/lot/quantité, le prix convenu, la version du compte si un compte existe et un motif. L’accord est recueilli comme pour la réservation initiale. Le formulaire présente l’avant/après de durée, prix et droits. Sans ce bloc alors que la durée change : `LESSON_COMMERCIAL_CHANGE_REQUIRED` (422). Avant toute capture/constat, une leçon PLANNED peut être révisée ; après début effectif, utiliser le résultat et les corrections explicites existants, pas cette commande.

Le serveur relit produit, lot, compte et ancienne réservation. Il conserve une `LessonCommercialRevision` append-only, remplace le HOLD par des écritures compensées liées à l’opération et met à jour la projection de leçon. À financement ENTITLEMENT, la charge d’utilisation reste nulle ; la vente du pack n’est pas recomptée. Une baisse de charge sous l’encaissé net est refusée, elle ne fabrique pas un remboursement.

Si créneau, quantité, compte ou droits ont changé concurremment, l’ancienne leçon reste intégralement inchangée. Réduire ou déplacer un HOLD déjà honoré n’exige pas de nouveaux droits ; toute augmentation nette est contrôlée contre les droits réellement utilisables. `commercialRevisionVersion` démarre à 1 et distingue ces révisions de la version de publication du bilan.


<a id="préparation-cartographique-complétée-v35"></a>
## Repères cartographiques de préparation
F06 inclut les repères manuels de [R102](regles-etats.md#r102). La commande PreparationCommand et sa projection possèdent plannedWaypoints ; initialisation vide, remplacement versionné et distinction nette de la trace réelle. Le moniteur prépare à l’arrêt ou avant la leçon. La carte peut afficher les repères sans autorisation de localisation du téléphone. Les souhaits de l’élève restent des souhaits textuels, pas des permissions d’édition de la préparation privée. U02, bibliothèque d’itinéraires réutilisables, demeure différée.
