# Messages iOS : états d’envoi et navigation des épingles (#237, #241)

29 octobre 2026. Base relue : `origin/master` `c94ec2bb`. Branche isolée : `codex/ios-messages-237-241`.

## État vérifié avant modification

Les cinq tickets [#237](https://github.com/tomyrms/Drivy/issues/237), [#238](https://github.com/tomyrms/Drivy/issues/238),
[#240](https://github.com/tomyrms/Drivy/issues/240), [#241](https://github.com/tomyrms/Drivy/issues/241) et
[#246](https://github.com/tomyrms/Drivy/issues/246) sont ouverts, sans commentaire au moment de cette lecture.
Les recherches de PR et l’historique des branches accessibles n’ont pas identifié de correctif dédié à ces tickets.
La lecture de `master` confirme les défauts ; les corrections voisines `c5bb2405` et `db855a85`, intégrées par #310,
portent sur d’autres critères de l’audit B et ne les résolvent pas.

| Ticket | Constat dans `master` | Décision du lot |
| --- | --- | --- |
| #237 | `failed`, `unconfirmed` et `uncertain` donnent tous `.error` à Exyte. Le texte secondaire les distingue déjà, mais l’icône et l’action VoiceOver permettent aussi de réessayer des refus nécessitant d’abord une correction. | Corriger maintenant. |
| #241 | L’appui ouvre l’épingle affichée puis incrémente l’index ; une nouvelle page ou un désépinglage peut également décaler la cible. | Corriger maintenant. |
| #238 | Les suppressions ne sont pas marquées destructrices afin de conserver la confirmation française Drivy. | Différé : examiner séparément les points de personnalisation Exyte, sans modifier la dépendance pour ce lot. |
| #240 | Recherche et pagination existent ; aucun filtre « Non lus ». Compteur optionnel, donc inconnu différent de zéro. | Lot fonctionnel séparé à prévoir avec pagination et état inconnu. |
| #246 | Les lignes montrent les identifiants ; le contrat des appareils ne fournit pas de nom/alias. | Différé : cadrer la source réelle du nom avant toute extension de contrat ou stockage. |

L’EPIC #311, ses tickets et les fichiers web/API/contrats/workflows/verrous restent hors du lot. Aucun déploiement requis.

## Comportement réalisé

### #237 : distinguer attente, résultat inconnu et refus

`MessagingSendPresentation` dérive icône, texte, annonce VoiceOver et possibilité de reprise de l’unique
`MessagingWorkspace.SendStatus`. La projection ne possède ni temporisateur, ni état réseau, ni seconde file.

- La coche Exyte « envoyé » exige toujours l’accusé serveur. Son indicateur d’envoi ne représente que `sending`/`slow`.
- En attente, hors connexion, confirmation attendue, résultat inconnu et refus n’utilisent plus `.error` dans Exyte.
  La ligne Drivy porte leur représentation réelle : horloge, absence de connexion, point d’interrogation ou échec.
  Un état inconnu ne montre ni coche de succès, ni animation d’envoi, ni bouton de renvoi caché dans une icône d’erreur.
- `unconfirmed` signifie que la requête attend encore sa réponse : « Confirmation en attente », sans deuxième reprise.
  `uncertain` signifie que la tentative s’est terminée sans résultat certain : « Non confirmé » et reprise explicite.
- Les refus qui exigent une correction préalable (accès, protection, appareils, conversation) ne proposent pas de
  reprise. La même garde s’applique aux actions VoiceOver et dans `MessagingWorkspace.retrySend`, y compris si une
  ancienne action reste visible. Une horloge d’envoi active interdit également la reprise concurrente.
- La reprise autorisée conserve `clientMessageID`, enveloppe chiffrée et époque. L’outbox, le protocole, les contrôles
  serveur et les identités de bulle sont conservés. Une réponse tardive confirme la même intention.
- La révision de rendu Exyte inclut les libellés/actions d’envoi : deux états sans coche ne restent pas confondus dans
  une cellule mise en cache.

### #241 : ouvrir l’épingle annoncée

Le bouton principal ouvre uniquement le message annoncé. Un bouton distinct « Message épinglé suivant » change
l’aperçu sans naviguer dans le fil ; VoiceOver peut aussi ajuster vers l’avant ou l’arrière. Le compteur appartient
au bouton principal. Chaque cible tactile mesure au moins 44 points.

La sélection repose sur l’UUID du message, jamais sur son index. Charger des épingles antérieures ou retirer une
autre épingle conserve la cible. Si elle disparaît, la sélection revient à une cible encore disponible ; une liste
vide efface la sélection. L’ouverture revérifie la présence de l’épingle dans le workspace, puis réutilise le saut
existant (`thread.jump`) et ses contrôles de contexte, sans copie durable de texte ni accusé de lecture par aperçu.
La hauteur du bandeau et l’espace réservé dans le fil suivent la même métrique Dynamic Type.

## Références relues

- `AGENTS.md` et `Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md`.
- `decisions-messaging-98-20261025.md`, `messaging-api-contract.md`, `messaging-durable-mutations-104-20261026.md`.
- `reprise-exyte-chat-182-20261027.md` : Exyte 3.3.0 verrouillé, IDs stables, état Drivy propriétaire et compilation avec accès Messages.
- Scénarios existants : `MessagingExyteThreadTests`, `MessagingOptimisticMutationTests`, `MessagingFeatureCheckUITests`.
- Skills utilisés : `ui-skills-root`, sélection CLI `swiftui` → `dimillian/swiftui-ui-patterns`, référence identités stables/performance.

## Vérification et livraison

Exécuté dans ce lot : lecture des diffs et `git diff --check`. Aucun test Swift, simulateur ou suite complète exécuté.
La compilation Release et l’IPA sont confiées au coordinateur ; ce document ne les déclare pas réussies.

Tests préparés, **NOT_EXECUTED** :

- `MessagingSendPresentationTests` : absence de faux envoi/échec/succès, refus non réessayables, états inconnus distincts.
- `MessagingPinnedSelectionTests` : ouverture stable, avance explicite, pagination, désépinglage et liste vide.
- `MessagingOptimisticMutationTests` : refus non réessayable par une autre action ; réponse lente toujours en vol,
  aucun nouvel envoi avant sa réponse ; reprise incertaine avec même identité, octets et époque.
- `MessagingFeatureCheckUITests.testOpeningAPinKeepsItsPreviewAndNextIsAnExplicitAction` : deux épingles synthétiques,
  ouverture de la cible annoncée et parcours explicite. La nouvelle option de fixture est limitée au simulateur DEBUG.

Essai IPA : ouvrir une conversation possédant plusieurs épingles, toucher l’aperçu puis parcourir la suivante ; vérifier
que l’aperçu correspond toujours au message ouvert. En connexion lente ou interrompue, comparer attente, résultat non
confirmé et refus ; une reprise ne doit pas créer de seconde bulle. Essayer texte agrandi et iPad.

L’IPA doit être construite avec `messaging_qualification=true` pour fournir l’accès Messages prévu par le projet.
Rendu sur appareil, VoiceOver physique et comportement réseau réel restent **NOT_EXECUTED**. Les tests ciblés puis la
campagne pertinente attendent le retour du porteur. Aucune fusion ni clôture d’issue dans ce lot.
