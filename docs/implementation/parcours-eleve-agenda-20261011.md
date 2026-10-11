# Parcours de l’élève et agenda — troisième passe (11 octobre 2026)

Suite des [parcours terrain fluides](parcours-fluides-20261011.md), à la demande du porteur (« bah oui go »). Deux audits en lecture seule (parcours de l’élève, agenda du moniteur), corrections, puis relecture QA.

## Fiche de leçon (élève et moniteur)

- **Chargement** : la fiche enchaînait jusqu’à quatorze lectures l’une après l’autre (souhait, bilans, objectifs, brouillon, observations, solde, trajets, aperçu, partage, formation, référentiel, progression). Les lectures indépendantes partent désormais ensemble et l’écran n’est publié qu’une fois ; l’aperçu du trajet et le référentiel partent dès que ce dont ils dépendent arrive. Chaque lecture garde sa règle d’absence et son message.
- **Progression** : elle ne sert qu’au bilan que rédige le moniteur de la leçon ; l’élève ne la lit plus.
- **Souhait** : « Enregistrer le souhait » n’apparaît qu’après une modification (même règle que les objectifs).
- **Replay** : le détail d’une observation et la liste se remplacent en fondu ; « voir tout » glisse vers le trajet entier.
- **Historique de formation** : le bandeau « Chargement de l’historique… » ne s’allume plus quand il ne reste rien à lire.

## Agenda et planning (moniteur)

- **Écriture confirmée** : planifier, déplacer ou annuler ferme la feuille aussitôt ; elle relisait auparavant tout le planning (une douzaine de lectures) avant de se fermer, en changeant le formulaire sous les yeux. Rien ne change pendant la descente, un second envoi est refusé, et les autres écrans sont prévenus (`.drivyLessonsDidChange`). Un renvoi réussi ferme aussi la feuille.
- **Créneau** : après un créneau libre, retoucher l’horaire garde les sections (motif, accord, documents) et la barre ; seul le bouton attend la nouvelle vérification.
- **Semaines** : une semaine déjà lue s’affiche aussitôt (en mémoire seulement, par compte, droits, école, semaine et filtre ; oubliée à chaque leçon modifiée), puis se relit sans rien effacer. Le changement de jour ou de semaine se fait en fondu ; « Aujourd’hui » a une cible de 44 pt entière.

## Non traité (à décider ou mesurer)

- **Accord GPS hors leçon à venir** : sans leçon planifiée, l’élève n’a pas d’endroit où modifier son accord (voir plus bas).
- Replay qui relit ce que la fiche a déjà lu ; onglet Leçons de l’élève (plusieurs squelettes au premier lancement, lectures en série) ; progression publiée en plusieurs fois ; lectures du planning en parallèle et chargement léger pour l’annulation ; bouton « Planifier » de l’agenda qui peut passer sous le titre selon la longueur de la date.

## Accord GPS de l’élève (décision du porteur, 11 octobre 2026)

L’accueil promet à l’élève « Tu peux refuser ou modifier ton choix », mais rien ne lui permettait de le faire. Le porteur a retenu la proposition : la question se pose sous « Mon souhait », dans la fiche de sa prochaine leçon.

- **Où** : fiche de la prochaine leçon planifiée de l’élève (même règle que le souhait), seulement si l’école est active et enregistre des trajets.
- **Quoi** : la même question en ligne que chez le moniteur (`SchoolRecordingChoiceInline`), tutoyée : « Acceptes-tu le GPS ? », deux réponses de même poids, « Information et conservation ». Une fois répondu : « Accord GPS · Avec GPS / Sans GPS » et « Modifier ».
- **Enregistrement** : source `SELF`, rien de nouveau côté serveur. Le choix lu est celui qui vaut pour cette leçon ; la réponse est enregistrée au même niveau (le choix général, sauf choix propre à la leçon). Elle part aussitôt : file chiffrée, puis école. Pendant l’envoi, une attente remplace « Modifier » ; si l’école ne confirme pas, la réponse enregistrée revient avec la raison ; une demande incertaine se vérifie depuis « Accord GPS à vérifier ».
- **Règles serveur inchangées** : seul l’élève lève son refus `SELF` ; un refus de l’élève reste prioritaire sur un accord verbal.
- **Partagé** : le choix valable pour l’information actuelle de l’école est une seule règle (`validAnswer`) pour le démarrage immédiat, le départ planifié et l’élève. Une réponse envoyée aussitôt qui échoue affiche désormais sa raison même quand un choix était déjà enregistré (départ planifié compris).
- **Limite** : sans leçon planifiée, l’élève ne peut pas modifier son accord depuis l’app.

## Relecture QA (agent dédié)

Aucun défaut bloquant. Corrigés : l’annulation d’une leçon depuis le trajet ou la fiche se lit désormais à la fermeture du planning (la feuille se fermant dans le même tour que la confirmation, son contenu pouvait disparaître avant de l’observer, laissant le trajet d’une leçon annulée ouvert) ; plus aucune saisie ni envoi après une écriture confirmée (« Annuler la leçon » restait actif pendant la descente) ; le référentiel ne passe plus derrière l’aperçu du trajet ; une semaine déjà lue arrive dans le même fondu que le changement de date ; le fondu du replay ne ralentit plus la tête de lecture ; la vérification du créneau reste annoncée à VoiceOver. Laissés : les lectures parallèles de la fiche ne s’annulent pas avec la vue (rien n’est publié de travers, des requêtes partent pour rien) ; la planification prévient les autres écrans sans dire quelle leçon a changé.

## Vérification

IPA d’essai compilée sans avertissement Swift. Aucun test exécuté, à la demande du porteur ; un test du planning a été adapté au nouveau comportement (une annulation confirmée n’est plus suivie d’une relecture). Rien n’a été vu tourner.
