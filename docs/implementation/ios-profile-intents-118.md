# Profil personnel : intentions protégées et projection commune — #118

29 octobre 2026. Base de travail : `2d9a5f64`, lot iOS indépendant de l’EPIC #311.

## État réel avant ce lot

La PR #277 (`72cc7311`, intégration `e5166404`) avait livré l’aperçu photo dans Mon profil, la sérialisation texte/photo dans un éditeur et le dernier choix en mémoire. Le commentaire de #118 signalait encore le nom et les coordonnées confirmés seulement avant affichage ailleurs, ainsi que l’absence de file persistante. Ce lot traite ces restes natifs ; il ne recompte pas la première livraison.

Références relues : `COMMENCER_ICI.md`, identités/formations, synchronisation F12, R12, scénarios T045/T048/T066/T077 et `apps/api/contracts/self-profile.json`. Le profil personnel est une extension existante avec `If-Match`, **sans** contrat `operationId`/AP72. Les garanties de rejeu de la clôture de leçon ne lui sont pas attribuées.

## Résultat natif

- `SchoolWorkspace` conserve la personne et le profil confirmés séparément des intentions. `person`, `selfProfile`, les dossiers/listes du compte courant, `learnerName`, `displayName(for:)` et `photo(for:)` lisent une projection commune. Les versions, appartenances, droits et complétude scolaire restent confirmés. Les autres personnes ne reçoivent aucune valeur locale du compte.
- L’action Enregistrer conserve les champs validés avant de les afficher dans la projection commune. Le choix ou retrait de photo conserve l’intention avant son départ. La saisie encore en cours dans l’éditeur reste distincte d’une intention validée ; un ancien ACK ne remplace pas la saisie suivante.
- Le journal AES-GCM existant, avec clé Keychain, protection complète, écriture atomique et synchronisation du fichier/répertoire, est réutilisé. Portée : personne + URL d’API, indépendante de l’école sélectionnée. Aucun fichier photo temporaire en clair n’est ajouté. Deux photos bornées à 262 144 octets (celle partie et le dernier choix) tiennent sous la limite du coffre de 1 Mo ; le cadrage existant produit au plus 250 ko.
- La dernière intention et la requête remise au transport sont deux objets différents. Une seule file dans `SchoolWorkspace` ordonne les écritures du compte, y compris depuis plusieurs éditeurs. Une réponse enlève uniquement l’intention correspondante et préserve le choix plus récent.
- Après une réponse perdue, une relecture autorisée précède la reprise. État identique : réconciliation locale sans deuxième écriture. Version inchangée : requête initiale et `If-Match` initial peuvent être renvoyés. Version différente et état différent : conflit explicite, choix conservé, nouvelle validation humaine requise. Les UUID locaux ne sont jamais envoyés comme clés d’idempotence.
- Une relance restaure les choix après lecture du compte, sans envoi automatique. Mon profil présente Enregistrer ou Réessayer pour vérifier leur synchronisation, y compris lorsque la valeur serveur est déjà identique. Une panne de lecture du coffre interdit son remplacement ; une panne avant l’envoi empêche cet envoi. Si la suppression locale échoue après un vrai ACK, l’écran dit l’erreur et garde la réconciliation possible.
- Un changement de compte ou une révocation efface immédiatement les projections en mémoire. Une réponse tardive ne peut ni remplir la photo du nouveau compte ni réinitialiser sa session. Un ancien éditeur ne peut pas envoyer sous le nouveau compte. Un changement d’école conserve uniquement les intentions globales de la bonne personne ; les données scolaires suivent toujours leur portée.
- Une nouvelle version de photo évacue la photo confirmée obsolète avant sa relecture ; une panne de téléchargement laisse les initiales, pas un ancien avatar.

Les deux constructions réelles de `SchoolWorkspace` dans `DrivyApp.swift` fournissent l’URL de l’API. Les doublures existantes sans stockage restent utilisables en mémoire dans les tests.

## Raccords de présentation du lot intégré

Ce commit expose `hasPendingSelfProfile`, `selfProfileIntentError`, `profileAccountBaseURL`, `displayName(for:)` et `photo(for:)`. Le coordinateur et l’agent Messages réalisent séparément le badge inhabituel de l’en-tête et le raccord Messages, dans leurs fichiers réservés. `SchoolMyProfileView` prévient aussi avant de perdre un choix photo dont la persistance a échoué (`hasUnretainedPhoto`).

Pour Messages, utiliser la référence vivante à `SchoolWorkspace` uniquement lorsque personne, API et portée scolaire courante correspondent à la session Messages. `displayName(for:)` retourne `nil` pour un tiers. Pour le compte connecté, une photo `nil` peut signifier un retrait : ne jamais retomber alors sur une ancienne photo du cache Messages. Le texte chiffré des messages et l’identité OIDC ne sont pas modifiés.

## Vérification

`git diff --check` exécuté. Relecture des appels et du contrat effectuée. Aucun test ni build Apple exécuté dans ce worktree Windows ; la compilation et les contrôles Apple ciblés sont pris en charge dans la branche d’intégration. Aucune grande suite, aucun push, déploiement ou changement web/API/CI/STATUS dans ce lot.

`SchoolSelfProfileIntentTests` prépare dix contrôles : projection commune et saisie après ACK ; texte/photo/retrait ordonnés ; réponse perdue avec GET en panne puis relance ; conflit inter-appareils ; panne de persistance avant envoi et après ACK ; réponse tardive et ancien éditeur après changement de compte ; coffre réel, deux photos maximales, isolation API/personne et mauvaise clé ; dossier fraîchement relu après `/me` plus récent que le profil complet ; GET de l’éditeur en panne avec coordonnées déjà connues ; retrait non conservé devant un ancien ACK photo. Les deux tests photo existants de `SchoolWorkspaceTests` restent pertinents. **Tous ces nouveaux tests sont non exécutés à cette étape.**

## Recette à effectuer sur l’IPA intégrée

1. Retarder le réseau : valider nom/contact, vérifier nom local et badge en attente dans Profil, dossier et Messages. Avant l’ACK, saisir une autre valeur dans Mon profil : elle doit rester après l’ACK du premier envoi.
2. Pendant l’envoi du texte, choisir une photo puis la retirer : le dernier retrait doit rester visible ; aucun ACK ancien ne doit remettre l’avatar. Vérifier l’ordre et les versions sur les doublures ciblées, sans données de personnes dans les logs.
3. Couper la réponse après écriture, puis couper aussi le GET : aucun second PATCH aveugle ni faux succès. Rétablir le réseau, relancer avec le même compte et réessayer : état identique réconcilié sans écriture supplémentaire.
4. Faire une modification depuis un autre appareil : le conflit conserve les valeurs locales ; les valeurs relues servent de référence après revue explicite. Retenter sur cette nouvelle référence, sans modifier les coordonnées de connexion.
5. Simuler une erreur du coffre : le départ est bloqué si la persistance initiale échoue ; le texte reste dans l’éditeur. Une erreur de nettoyage après ACK conserve l’intention et propose une reprise. Vérifier que la mauvaise clé n’écrase jamais le fichier.
6. Changer d’école puis de compte pendant une requête photo suspendue : même compte/même API garde son intention globale ; un autre compte ne lit ni n’envoie cette intention. Relâcher l’ancienne réponse et vérifier les initiales et le nom du nouveau compte.

## Limites honnêtes

Le serveur nettoie les segments de métadonnées JPEG. Après réponse perdue, si les octets relus ne correspondent pas exactement au choix local, l’app demande une revue au lieu d’inventer une preuve de succès ; un nouvel envoi explicitement validé peut être nécessaire. Aucun moteur de tâche de fond ni reprise automatique au seul retour réseau n’est ajouté.

La frappe non validée du formulaire n’est pas assimilée à une intention envoyable ; le dialogue existant de fermeture protège ce brouillon de session. Les choix validés sont journalisés. La fermeture forcée avant une persistance réussie, le disque physiquement plein, Keychain après verrouillage, VoiceOver, Dynamic Type, latence réelle et essais multi-appareils attendent qualification. Aucune preuve physique ni parité web n’est revendiquée.

## Résultat Apple sur la branche d’intégration

Le [run 40960532711](https://github.com/tomyrms/Drivy/actions/runs/40960532711), SHA `cec9a058e8d2196a6e28e26986e195e33b617719`, a exécuté les dix tests ci-dessus sur simulateur iPhone 17 Pro : 10 réussis, zéro échec/ignoré. La première compilation de la cible de test avait échoué sur une expansion de macro `#expect(allSatisfy(\.isEmpty))` ; calculer le booléen avant l’assertion corrige uniquement le test. Le code produit est identique à celui de l’IPA 447 (`633f20d3`). Aucun essai physique ni grande suite déduit de ce résultat.
