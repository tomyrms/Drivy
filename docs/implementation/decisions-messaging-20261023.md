# Messagerie : décisions du porteur du 23 octobre 2026

Réponses du porteur aux arbitrages regroupés de `messaging-20261023.md`. Elles remplacent les propositions correspondantes. Ce qui n'est pas tranché ci-dessous reste ouvert.

## 1. Chiffrement de bout en bout (#67)

Le porteur délègue le choix technique. Choix retenu : **protocole Matrix Olm/Megolm via `matrix-sdk-crypto` (Rust, implémentation `vodozemac`)**, appelé depuis Swift par ses liaisons UniFFI. Le transport reste l'API Drivy, pas un homeserver Matrix.

- Olm pour les sessions entre appareils, Megolm pour les conversations (privées et général). Rotation de la session de groupe à chaque départ d'un membre et périodiquement.
- Le serveur Drivy relaie : publication et requête des clés d'appareils, réclamation de clés à usage unique, messages d'appareil à appareil, enveloppes chiffrées. Il ne voit jamais le texte.
- Vérification croisée des appareils d'un même compte. Sauvegarde des clés chiffrée par une clé de récupération que seul l'utilisateur détient : un nouveau téléphone retrouve l'historique avec cette clé, sinon il ne lit que les messages postérieurs.
- Métadonnées visibles du serveur, acceptées : qui parle à qui, quand, taille, identifiants de mentions, réactions et réponses.
- Motifs : protocole audité, bibliothèque maintenue sous licence Apache-2.0, déjà prototypée (`prototypes/messaging-crypto`), même modèle que Element X.

## 2. Accès (#66/#69/#72)

- **Fin du lien** (fin d'affectation moniteur, départ de l'école, retrait du général) : la personne garde la lecture de l'historique **jusqu'au dernier message antérieur à la fin du lien**. Elle ne voit rien de ce qui suit et ne peut plus écrire. Les clés Megolm sont renouvelées à son départ.
- **Contacts privés d'un élève** : uniquement le ou les moniteurs qui lui sont attribués. Pas de contact administrateur dédié dans l'app.
- **Général** : chaque membre est affiché par **son nom et sa photo de profil** (si visible selon #64). Un appui ouvre son profil. Aucune autre donnée.
- **Arrivée** (décision coordinateur, comme WhatsApp) : un nouveau membre (entrée dans le général, nouveau moniteur attribué) ne voit que les messages postérieurs à son arrivée : `readable_after` = `last_sequence` de la conversation au moment de l'entrée. Même borne pour les réactions, sondages, votes et accusés de lecture.
- **Réintégration** : un administrateur du général peut réintégrer un membre retiré (`PUT /general/members/{personId}`). La personne ne voit que ce qui suit sa réintégration ; `membersEpoch` +1 (rotation Megolm).

## 3. Navigation (#66)

Validée : Messages en entrée secondaire, aucun onglet supprimé, et accès depuis la fiche élève.

## 4. Sondages (#73)

Comme WhatsApp : question et options, **choix unique par défaut, choix multiple activable** par le créateur, votes nominatifs visibles des participants, vote modifiable ou retirable. **Pas de date de clôture obligatoire.** Le créateur peut clore le sondage quand il veut. Aucun lien avec réservation ou inscription.

## 5. Modération (#77)

Comme les groupes WhatsApp :

- Le général a des **administrateurs de groupe**. Par défaut, les administrateurs de l'école. Un administrateur peut nommer ou retirer d'autres administrateurs de groupe et retirer un membre du général.
- Chacun peut **supprimer son message pour lui ou pour tout le monde**. Une suppression pour tout le monde laisse « Message supprimé » visible de tous. Un administrateur de groupe peut supprimer pour tout le monde le message d'un autre membre.
- Les **signalements vont aux administrateurs de l'école**. Le signalement ne transmet que les messages choisis par l'auteur du signalement, rechiffrés pour les administrateurs. Ces copies rechiffrées sont **conservées comme preuve** même si le message est ensuite supprimé pour tout le monde (décision coordinateur).

## 6. Données (#68)

- Notifications Apple : passage obligatoire par APNs, accepté. Le contenu des notifications ne contient pas le texte du message.
- Conservation, export et durée : non précisés. En attendant, l'historique est conservé tant que la conversation existe et la suppression pour tout le monde efface l'enveloppe côté serveur. Aucun délai automatique inventé.

## 7. Options (#75/#76)

À réaliser : **réactions, réponses citées, épinglage, recherche, accusés de lecture visibles**. La recherche se fait sur l'appareil, le serveur ne peut pas lire les messages.

**Photos et fichiers : hors périmètre**, à traiter dans une issue séparée.

Indicateur de saisie : non demandé, non réalisé.
