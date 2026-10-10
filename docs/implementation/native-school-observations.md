# Observations scolaires privées sur iPhone et iPad

Tranche AP161–164 : `SchoolObservationWorkspace`, `SchoolObservationView` et point d’entrée injectable `SchoolObservationEntryView(client:schoolWorkspace:lessonID:)`. L’entrée possède sa pile de navigation. L’agenda ouvre une route `.sheet(item:)` contenant le modèle complet dès le premier appui. Le serveur relit le rôle INSTRUCTOR, le moniteur désigné et son affectation actuelle ; ADMIN seul et l’élève ne voient pas ce carnet.

## Parcours livré

- Pendant une leçon planifiée, **Garder un repère maintenant** fige l’instant au geste, avant la saisie ou le réseau. Le commentaire est facultatif : sans texte saisi, le repère garde le libellé explicite « Moment à revoir », et une observation qualifiée le libellé réel de la compétence choisie. Ce libellé est montré avant confirmation. Aucune compétence ou appréciation n’est choisie automatiquement ; une observation qualifiée utilise une compétence réelle du référentiel de la formation et un statut Attention / À retravailler / Point positif. Une note de relecture après la leçon exige son propre texte.
- Un repère peut être précisé ensuite en désactivant le choix « repère simple », puis en choisissant compétence et statut. L’instant LIVE initial reste identique. Les nouvelles observations de cet écran n’ajoutent aucune ancre GPS ; modifier une observation déjà ancrée conserve uniquement les identifiants validés par le serveur.
- La liste privée relit toutes les pages bornées à 100 observations. Un échec du référentiel ne cache pas la liste et permet toujours un repère simple. L’absence affichée correspond uniquement à une lecture réussie.
- Après le constat de réalisation, les notes nouvelles sont des relectures REVIEW liées au brouillon propre courant. Les anciennes observations sont relues avec leur version mise à jour par AP49. Aucun bilan n’est publié et ces observations ne sont pas transmises à l’élève.
- Le retrait demande un motif et une confirmation distincte, puis la version exacte de l’observation. Une observation existante peut être modifiée avec If-Match ; un conflit ne remplace pas silencieusement la version ni le contenu.

## Persistance et droits

Toute nouvelle mutation persiste le corps et l’UUID dans `EncryptedSchoolCommandOutbox` avant le premier appel réseau. Elle relit ensuite la portée et la leçon avant émission : une perte de réseau pendant cette relecture conserve donc déjà l’intention chiffrée, sans annoncer un enregistrement serveur. Une reprise repasse par la même barrière de durabilité et conserve l’UUID, le corps, la route et la version. Un accusé vérifié est acquitté avant la garde de visibilité, afin qu’une fermeture tardive ne transforme pas le succès reçu en doublon potentiel.

La feuille de reprise montre le contenu, l’instant éventuel, la compétence, le statut, l’existence ou l’absence d’ancre et la référence. Vérifier AP72 ne dépend pas du chargement du référentiel ou de la liste. La reprise d’une ancienne portée n’est jamais renvoyée sous les nouveaux droits. Une demande d’un autre module interdit une seconde mutation, mais ne bloque pas la consultation du carnet.

Seul un refus métier explicite lors du premier envoi d’un UUID neuf permet de corriger la saisie. Les pertes de réponse, reprises, refus de droits et résultats incertains conservent l’intention. Un conflit après une reprise exige une vérification ; aucun nouveau UUID n’est créé automatiquement. Le changement de compte, d’école ou d’époque invalide la projection et ferme les feuilles enfant.

## Vérification et limites

Raccords et types relus statiquement sous Windows ; `git diff --check` exécuté. Aucun résultat de compilation Apple, d’essai iPhone/iPad ou d’accessibilité n’est revendiqué par cette note. Aucune nouvelle campagne de tests n’a été lancée pour cette tranche, conformément à la demande du porteur ; compilation groupée par le pilote du projet.

Les ancres nouvelles et le partage sélectif d’observations dans une révision de bilan ne sont pas activés ici. Le signalement reste utilisable sans GPS. Un brouillon indisponible bloque seulement l’ajout d’une note de relecture ; la liste reste consultable. Un refus de version conserve la saisie affichée pour relecture, mais aucune fusion automatique avec une modification distante n’est proposée.
