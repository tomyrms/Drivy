# Contenu et états · Dire exactement ce qui se passe

> Référence 3.16 · [Accueil design](README.md) · [Critères anti-slop](../02-experience/qualite-ui-ux-anti-slop.md).

## Voix proposée

Français clair, phrases courtes, vocabulaire stable. Tutoiement côté élève selon la proposition existante ; libellés impersonnels d’action côté personnel (« Publier le bilan », « Archiver le dossier ») pour ne pas mélanger plusieurs tons. L’école ne peut pas remplacer librement les textes de sécurité ou les messages de confirmation. Le nom du produit est toujours « Drivy ».

Les titres décrivent la tâche : « Prochaine leçon », « Toutes les dates », « À travailler ensuite ». Éviter les slogans à chaque écran, les faux encouragements, les majuscules décoratives et les icônes qui remplacent le texte. Les dates fictives des maquettes sont explicitement annoncées et ne représentent pas l’offre d’une école réelle.

## Premier niveau et détails

La capture montre le nom de l’élève, une durée et « GPS actif », « GPS en pause », « GPS arrêté » ou « Sans GPS » selon l’état réel. Ces formes courtes ne fusionnent pas collecte, transfert et publication. « Hors ligne · envoi en attente » et « Envoi en échec » restent visibles quand nécessaires.

Le panneau Signaler affiche le moment et « Privé ». Les catégories portent un nom court et explicite. Le statut est une ligne : « Attention », « À retravailler », « Point positif ». Une seule instruction, « Le choix enregistre. », explique la conséquence. Le nom accessible de chaque ligne inclut « enregistrer l’observation privée ». Aucun chevron droit n’annonce une navigation sur ces actions d’enregistrement immédiat. La suppression éventuelle de l’instruction commune demande une preuve de compréhension, pas une préférence pour un écran vide.

Après ajout, thème et statut suffisent avec « Privé » et une action « Annuler ». En cas de correction, Annuler restaure l’état précédent au lieu de supprimer l’observation d’origine. Une erreur d’écriture de repère reste explicite, dans le panneau ou près de l’action ; elle ne déclenche pas de succès. La liste permet de corriger ultérieurement ; un toast qui disparaît n’est pas le seul accès. Les explications sur l’instant figé, le stockage et la publication restent dans l’aide. Les avertissements propres au prototype demeurent à l’extérieur de l’écran simulé.

## Matrice des messages

| Situation connue | Message de référence proposé | Action ou information utile | Interdit |
|---|---|---|---|
| Capture autorisée mais aucune mesure admise | En attente de position | État local ; possibilité d’arrêter | Montrer une ancienne position comme début |
| Capture locale active | Enregistrement en cours | Pause / Arrêter ; durée GPS | « Synchronisé » comme unique état |
| Capture en pause | Enregistrement en pause | Reprendre / Arrêter | Suggérer que la carte mesure toujours |
| Arrêt local, envoi restant | Enregistrement arrêté. Envoi en attente. | Données conservées sur cet appareil selon état réel | « Leçon terminée » déduit de l’arrêt |
| Aucun point acquis | Aucun point enregistré | Continuer le bilan sans trajet | Carte inventée et succès de qualité |
| Séance volontairement sans GPS | Sans enregistrement GPS | Objectifs et bilan normalement accessibles | « Profil incomplet », rouge d’erreur |
| Brouillon local | Sur cet appareil · non partagé | Reprise du brouillon | « Sauvegardé » sans destination |
| Bilan publié confirmé | Bilan partagé | Date/version et destinataire | Révéler les notes privées restantes |
| Trajet partagé retiré | Trajet indisponible | Bilan textuel autorisé, sans miniature | Récupérer la vue privée par un ancien lien |
| Offre vue mais non réservée | Disponible · Non inscrit | Toutes les dates, places connues | « Votre cours » avant inscription |
| Confirmation non terminée | Confirmation en cours | Demande conservée, état à vérifier | « Inscrit » à la fin d’une animation |
| Inscription confirmée | Inscrit | Dates ajoutées aux engagements | Confetti, message éphémère seul |
| Plus de place | Complet | Autres cours ; calendrier conservé | Inscription ou liste d’attente automatique |
| Déplacement à accepter | Dates modifiées · À reconfirmer | Avant/après et action explicite | Effacer la place silencieusement |
| Pièce reçue | Vérification technique en cours | Suivi d’envoi | « Permis validé » |
| Exigence pédagogique à réexaminer | Preuve à vérifier | Motif et traitement autorisé | « Formation jamais suivie » déduit du statut |
| Solde de droit non utilisable | Droits restants · utilisation suspendue | Motif financier et contact utile | Afficher le solde comme librement utilisable |
| Archive | Dossier archivé | Historique selon droits ; restauration habilitée | « Compte supprimé » |
| Suppression demandée | Demande reçue | Étapes/délai connus et suivi | « Compte supprimé » avant traitement |
| Réseau absent sur inscription | Connexion nécessaire pour confirmer | Dernière actualisation, pas de place locale | Désactiver tout le calendrier |

## Règles d’interaction

Une donnée absente autorisée s’affiche « Non renseigné » ; une donnée interdite est omise. Zéro est un nombre, pas une manière de masquer une erreur. Une capacité inconnue indique qu’elle doit être actualisée avant inscription. Le prix convenu et les dates relues priment sur la dernière variante affichée au catalogue.

Les erreurs sont proches de leur cause, puis résumées en tête d’un formulaire long. Le focus mène à la première erreur pertinente. Un toast peut confirmer une action secondaire mais ne remplace pas une preuve de publication, une confirmation de place ou un message de purge.

Les bandeaux permanents restent réservés aux situations qui durent et nécessitent une décision. Une notification technique de chaque point GPS ou de chaque caractère saisi ferait perdre la hiérarchie des alertes.

## Données fictives et démonstration

Le prototype utilise **École Horizon**, Emma Laurent, Noé Martin et d’autres données créées pour la mise en page. Ni les cours, ni les paiements, ni les trajets ne viennent d’une école réelle. « 09:32 » ou « 28 min » sont des valeurs de scène, pas des traces collectées. Le site ne demande pas de mot de passe, de paiement ou de permission de localisation.

Les boutons qui font avancer une démo ne sont pas un service métier. Le bandeau « Maquette · données fictives » reste visible en dehors des écrans. Un état peut être choisi dans l’outil de revue afin de comparer les cas ; ce sélecteur de scénario n’existera pas dans Drivy.

## Formats

Heures locales de l’école avec fuseau dans les contextes nécessaires, format 24 h proposé pour fr-CH. Dates explicites pour une série ; pas « la semaine prochaine » comme unique information. Montants en CHF avec deux décimales quand utiles, sans convertir les centimes en flottants comptables. Capacités : « 3 places restantes » ; un nombre n’a jamais besoin de clignoter pour être compréhensible.

Toutes les chaînes doivent pouvoir être localisées plus tard ; pas de largeur fixe calculée sur les seules phrases françaises. Le prototype ne constitue pas une traduction ni une validation légale des conditions d’école.

<a id="microtextes-ajoutés-lors-du-contrôle-v39"></a>
## Microtextes des états de reprise et de conflit
| Situation | Formulation de référence | Distinction préservée |
|---|---|---|
| Capture déjà ouverte | « Retrouver la capture » | Retour à un état existant, pas nouveau démarrage |
| Constat manquant avant aperçu | « Ajoute un constat de la séance. » | Brouillon conservé ; aperçu avant partage incomplet |
| Niveau retiré | « Non observé : aucun niveau transmis. » | Absence d’observation, pas note zéro |
| Réponse de réservation inconnue | « Résultat inconnu. La même demande reste à vérifier. » | Ni confirmation, ni refus, ni nouvelle intention |
| Lacune du replay | « Aucune position mesurée pendant cette interruption. » | La durée passe, mais aucun déplacement n’est inventé |
| Dossier retiré des résultats | « Aucun dossier sélectionné. » | Filtre conservé, anciennes actions retirées |
| Lien vers une vue non dessinée | « Écran prévu, non illustré » | Notice de galerie uniquement, pas état normal de l’application |

L’expression « conservé en mémoire pendant cette visite » appartient à la **galerie documentaire**. Le vrai client utilisera les états de persistance de F12 et ne parlera de sauvegarde sur appareil qu’après commit local. Changement de compte ou d’école : aucune donnée personnelle ne reste présentée dans le nouveau périmètre sous prétexte de conserver les saisies.

## Pièces et exports : états de confiance

« Dépôt à vérifier » après timeout n’équivaut pas à un rejet ; « Nouveau dépôt nécessaire » explique une URL expirée sans octets finalisables. Le brouillon reste conservé. Après transport : « Vérification technique en cours », puis seulement « Document disponible ». READY n’affiche jamais « Permis validé ».

Pour un export READY : type CSV ou ZIP conforme à la finalité, taille et date de disponibilité. Après perte de droits : « Cet export n’est plus accessible. Une nouvelle génération est nécessaire. » Pas de succès ni fichier vide inventé. Avant sauvegarde/partage externe, signaler que cette copie ne pourra pas être retirée par Drivy. Ces variantes complètent les écrans spécifiés ; elles ne sont pas prétendues simulées dans les quinze compositions actuelles.
