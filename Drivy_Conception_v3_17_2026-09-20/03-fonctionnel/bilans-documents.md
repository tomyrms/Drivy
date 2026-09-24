# Bilans, progression et documents

> Drivy · Dossier de conception 3.13 · 20 septembre 2026
> Statut : proposition de référence, à valider avant réalisation. [Index](../README.md).

## Retrouver les observations de la leçon

La saisie pédagogique n’est pas réservée au replay. Les observations LIVE prises sous F15/F16 existent avant le brouillon et sont rattachées par R15. Le bilan affiche leur thème/statut et instant, sans convertir ATTENTION ou le nombre d’événements en niveau de compétence. L’auteur qualifie ou écarte les repères puis choisit explicitement les versions à partager. Une observation arrivée après publication exige une correction relue. Voir [cycle canonique](gps-replay.md#saisie-pendant-lecon).

## Mode d’emploi

Les règles ne sont pas redéfinies ici : les identifiants R renvoient à leur [référence principale](regles-etats.md). Les séquences suivantes spécifient les fonctions du cœur proposé, avec préconditions, variantes, données et critères observables. L’[autorisation](roles-permissions.md) s’applique à tous les appels, même lorsqu’un bouton n’est pas affiché.

<a id="f08"></a>
## F08 · Bilan publié et progression contextualisée

**Besoins :** B02 B03. **Parcours :** [J03](../02-experience/parcours.md#j03), [J05](../02-experience/parcours.md#j05), [J06](../02-experience/parcours.md#j06). **Écrans :** [E08](../02-experience/ecrans.md#e08), [E09](../02-experience/ecrans.md#e09), [E15](../02-experience/ecrans.md#e15).

**Règles et dépendances :** [R06](regles-etats.md#r06), [R11](regles-etats.md#r11), [R17](regles-etats.md#r17), [R18](regles-etats.md#r18), [R19](regles-etats.md#r19), [R20](regles-etats.md#r20), [R33](regles-etats.md#r33). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Fournir à l’élève une restitution courte et utile, dont chaque évolution est reliée à une observation réellement publiée.

### Rôles, autorisations et préconditions

Leçon COMPLETED, moniteur désigné/affecté, référentiel versionné disponible. L’auteur édite son brouillon ; les autres membres ne reçoivent pas son texte par défaut. Aucun niveau n’est présélectionné.

### Parcours nominal et conséquences

Saisir ce qui a été travaillé, le constat et la prochaine étape. Pour les compétences effectivement observées, choisir un niveau textuel et un contexte ; les autres restent non observées. Prévisualiser exactement la version élève, vérifier les pièces READY, puis publier connecté. Le serveur crée une révision immuable et recalcule les compétences concernées. L’élève voit une date, un bilan, un contexte et la prochaine action, pas une moyenne.

### Variantes, interruptions et cas limites

Bilan incomplet : rester DRAFT, sans notification. Correction après partage : préparer une nouvelle révision, motif requis ; l’ancienne demeure consultable selon droits. Référentiel modifié : anciennes observations gardent leur libellé/version ; une migration de vocabulaire requiert correspondance validée. Un niveau ultérieur plus faible est possible : ce n’est pas une régression calculée automatiquement, mais une observation contextualisée. Souhait élève n’est pas modifiable par la publication du moniteur.

### Données, validations et cycle de vie

ReportDraft, ReportRevision, CompetencyObservation et TrainingProgressProjection. Échelle DISCOVERING / GUIDED / INDEPENDENT proposée, à valider avec les enseignants. NOT_OBSERVED est une absence d’observation. La projection conserve sourceLessonId, sourceRevisionId, observedAt et context.

### Erreurs, événements et reprise

422 REPORT_INCOMPLETE, 409 CURRICULUM_VERSION_MISMATCH, 412 VERSION_CONFLICT, 409 ATTACHMENT_NOT_READY. Une ancienne leçon reçue tard ne gagne pas simplement parce qu’elle est arrivée en dernier.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T029](../05-realisation/tests-recette.md#t029) | Un bilan a un point travaillé, un constat et une prochaine étape. | Il peut être publié sans noter toutes les compétences ni joindre de photo. |
| [T030](../05-realisation/tests-recette.md#t030) | Un bilan non publié existe sur le serveur. | L’élève ne voit ni son texte ni une progression qui en serait déduite. |
| [T031](../05-realisation/tests-recette.md#t031) | Un bilan ancien arrive après un bilan plus récent de la même compétence. | La projection conserve l’observation chronologiquement la plus récente. |
| [T032](../05-realisation/tests-recette.md#t032) | Un moniteur corrige une révision publiée. | Nouvelle révision et motif ; ancienne révision intacte et projection recalculée. |

<a id="f09"></a>
## F09 · Pièces utiles et transferts sûrs

**Besoins :** B02 B03 B05. **Parcours :** [J01](../02-experience/parcours.md#j01), [J07](../02-experience/parcours.md#j07). **Écrans :** [E10](../02-experience/ecrans.md#e10), [E20](../02-experience/ecrans.md#e20), [E08](../02-experience/ecrans.md#e08).

**Règles et dépendances :** [R01](regles-etats.md#r01), [R21](regles-etats.md#r21), [R22](regles-etats.md#r22), [R30](regles-etats.md#r30), [R33](regles-etats.md#r33). Les dépendances entre fonctions figurent dans la [roadmap](../05-realisation/roadmap-backlog.md).

### Objectif et limite

Joindre les pièces nécessaires à une formation ou un bilan sans créer un partage documentaire universel.

### Rôles, autorisations et préconditions

Utilisateur autorisé sur le dossier et finalité choisie. Formats pilote : JPEG, PNG et PDF ; convertir localement HEIC en JPEG avant envoi si disponible, sinon expliquer le format accepté. Aucun ZIP, fichier exécutable ou URL distante à faire télécharger par le serveur.

### Parcours nominal et conséquences

Choisir document/permis/photo de bilan, audience et rattachement. L’app affiche taille et état local. Créer une intention de dépôt, transférer dans une zone privée de quarantaine, confirmer l’intégrité, puis attendre contrôle du type réel et analyse. READY permet le rattachement visible. Le lecteur demande l’autorisation serveur avant chaque nouveau lien court ; il ne conserve pas une URL publique.

### Variantes, interruptions et cas limites

Permission photo refusée : choix via sélecteur de fichier ; aucune demande répétitive forcée. Réseau interrompu : pièce en attente, texte du bilan conservé. Fichier rejeté : motif de format ou sécurité adapté, pas un détail d’antivirus exploitable. Remplacement de permis : nouvelle pièce et nouveau contrôle, pas écrasement. Changement d’école pendant le transfert : opération liée à l’école d’origine, jamais réaffectée.

### Données, validations et cycle de vie

Document(id,schoolId,ownerProfileId,trainingId?,lessonId?,purpose,audience,status), UploadIntent, objet binaire privé, checksum, detectedMime, byteCount. Métadonnées EXIF de localisation retirées des images partagées. Le nom original est une étiquette nettoyée ; aucune déduplication inter-écoles.

### Erreurs, événements et reprise

413 FILE_TOO_LARGE, 415 FILE_TYPE_NOT_ALLOWED, 409 UPLOAD_NOT_COMPLETE, 409 ATTACHMENT_NOT_READY, 403 ACCESS_REVOKED. Un rejet de pièce n’est pas une raison pour supprimer le bilan texte.

### Critères d’acceptation

| Test | Situation | Résultat vérifiable |
|---|---|---|
| [T033](../05-realisation/tests-recette.md#t033) | Un fichier non-image porte extension .jpg et Content-Type image/jpeg. | Il n’atteint pas READY sur la seule foi de ces métadonnées. |
| [T034](../05-realisation/tests-recette.md#t034) | La connexion tombe pendant le dépôt. | La pièce reste en attente et peut être reprise ; aucune pièce fantôme visible. |
| [T035](../05-realisation/tests-recette.md#t035) | Un utilisateur connaît documentId d’une autre école. | Aucun lien de lecture ne lui est donné et le nom de fichier n’est pas révélé. |
| [T036](../05-realisation/tests-recette.md#t036) | Le texte est prêt, une photo ne l’est pas. | Publication possible après exclusion explicite de la photo ; aucun lien cassé présenté à l’élève. |

## Bilan associé au replay et preuves de cours

F08 peut publier une capture par le lien CapturePublication associé à la nouvelle ReportRevision. Les observations situées sont une collection distincte des évaluations qualitatives finales, afin de permettre plusieurs passages sur une même compétence. L’auteur choisit celles rendues publiques ; une mesure transférée ou une annotation sauvegardée ne devient pas visible automatiquement.

Un bilan peut être partagé sans attendre un transfert GPS. L’ajout ultérieur du trajet exige une nouvelle publication explicite, pas la mutation silencieuse de la révision déjà lue. Une trace partielle est annoncée comme telle. L’annotation peut rester textuelle sans géolocalisation ; le refus de capture ne retire aucune compétence du référentiel.

F09 gère également preuve de formation externe et justificatifs de présence collective, sous audience administrative habilitée. Un document READY signifie contrôlé techniquement, pas « exigence accomplie ». Les corrections de présence et l’attribution de COMPLETED/EXEMPT appartiennent au workflow F18. L’effacement des coordonnées et dérivés de trajet peut laisser la révision non géographique sous conservation justifiée, conformément à R19/R48.


## Profil et grands écrans V3

PROFILE_PHOTO est un purpose distinct de PERMIT, LESSON_SUPPORT et ADMINISTRATIVE. Il est lié au learnerId de l’école, facultatif, JPEG/PNG au maximum 2 MiB, sans trainingId/lessonId. Réutiliser intention de dépôt, quarantaine, décodage/réencodage, retrait EXIF, scan et publication READY de F09. Modifier profilePhotoDocumentId exige un document READY appartenant à ce dossier. Les téléchargements gardent l’autorisation ; LEARNER_SHARED signifie cet élève et le personnel habilité, pas toute la liste des élèves. Suppression de photo revient aux initiales, sans bloquer onboarding ni formation.

Sur tablette, documents et bilan disposent d’une composition liste/détail ou panneau de prévisualisation ; les actions critiques ne sont pas réduites à des menus minuscules. Une vue de présentation ne montre que les révisions publiées. Sur web, consulter/revoir reste soumis aux mêmes autorisations pédagogiques ; la gestion administrative ne donne pas accès aux notes privées.

## Annotations publiées sans trajet

Une annotation préparée sans position peut être sélectionnée en E08 et publiée avec `captureSelection=null`. [R46](regles-etats.md#r46) définit cette sélection et son snapshot `textObservations`. Le bilan élève la présente dans une section textuelle, sans carte vide imposée. Sélections de texte et de trajet sont indépendantes et explicites à chaque nouvelle publication ; aucune note privée n’est copiée parce qu’elle existe dans le brouillon.

Le service refuse une annotation d’une autre leçon, d’un autre auteur non habilité, ancrée au GPS dans cette sélection textuelle, ou de version modifiée depuis la revue. Pour partager autrement une remarque géolocalisée, le moniteur rédige et relit une annotation sans ancrage ; le logiciel ne retire pas silencieusement les coordonnées pour republier le reste. Un texte libre peut encore nommer un lieu : absence de champs GPS ne signifie ni anonymat ni exemption des règles d’effacement. Une purge de la trace seule n’efface pas automatiquement une note autonome légitimement conservée ; une demande visant les données personnelles du bilan la traite séparément.

## Pièce invalide, pièce remplacée et pièce purgée

Une invalidation métier d’un justificatif ne se limite pas au badge du fichier : les exigences qui en dépendent sont réexaminées selon [R110](regles-etats.md#r110). Remplacer une preuve sélectionnée exige un nouveau contrôle ; le fichier READY est seulement techniquement admissible. Une correction purement descriptive sans changement de preuve n’annule pas artificiellement tout le dossier.

Une suppression normale du fichier après le délai approuvé de conservation n’accuse pas la preuve d’être fausse. Le traitement doit distinguer invalider sa valeur, remplacer son contenu et purger ses octets ; seuls les reçus minimaux autorisés demeurent. Ne pas recopier le document ou ses coordonnées dans une nouvelle annexe pour échapper à la purge. Les bilans textuels et traces publiées continuent de suivre leur propre politique d’accès et d’effacement.

## Correspondance de l’édition et de l’aperçu avec le contrat

Le modèle d’écran matérialise séparément travail réalisé (`workedOn`), constat (`observationText`) et prochaine étape (`nextStep`). Le texte d’aide ou un commentaire GPS ne remplace pas l’un de ces champs. SaveDraftCommand admet les états de brouillon prévus ; les textes requis pour publier sont vérifiés selon [R18](regles-etats.md#r18). L’aperçu peut signaler les champs encore nécessaires, sans perdre la saisie.

Dans la liste de compétences, retirer un niveau retire l’entrée correspondante de `observations`. Ne pas transformer « Non observé » en quatrième valeur de `level`. Lorsque l’entrée existe, son contexte doit être renseigné et la limite de longueur conservée. La prévisualisation reprend les textes courants, les observations et toutes les sélections effectivement destinées à l’élève ; les champs privés non sélectionnés restent privés. Les valeurs sont rendues comme du texte, pas comme du balisage HTML exécutable.

La [maquette VIS07](../DESIGN/MAQUETTES.html#bilan) illustre maintenant ces champs et valide un DTO fictif contre le schéma hérité. Cela ne teste ni la publication transactionnelle, ni les versions concurrentes, ni une génération Swift. Le client doit maintenir le brouillon dans la portée de compte/école/leçon et réconcilier ses versions selon F12, pas le recréer depuis des valeurs d’exemple à chaque apparition d’écran.

## Transfert, remplacement et reprise clairement présentés

F09 suit le [scellement R22](../04-technique/fichiers-temps-communications.md#scellement-fichiers) : un contenu contrôlé ne peut pas être remplacé derrière le même document. « Envoyé » signifie transport terminé, « Vérification en cours » signifie QUARANTINED et « Document disponible » exige READY. La fiche montre un format détecté valide pour un READY ; un type inconnu n’est pas affiché comme PDF par défaut.

Une reprise est une nouvelle tentative du workflow, pas une garantie de conservation d’un pourcentage de PUT interrompu. Si l’ancien dépôt peut être finalisé, le retrouver sans doublon. Sinon, expliquer le nouveau dépôt et son nouvel identifiant ; conserver le texte et ne remplacer les références du brouillon que par action explicite. Réseau absent ou scanner indisponible n’efface ni photo déjà validée ni logo courant. Une suppression pendant contrôle empêche toute réapparition par un résultat de scanner tardif.
