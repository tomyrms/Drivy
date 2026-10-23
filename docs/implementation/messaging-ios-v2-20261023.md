# Messagerie iOS v2 (#65) : décisions d'implémentation

Applique `decisions-messaging-20261023.md`. Contrat : `messaging-api-v2.md` (agent backend), aligné par DM le 23 octobre.

- **Contenu chiffré** : texte ou sondage encodés en JSON `{v:2,text|poll}` avant `MessagingCryptography.encrypt`. Les messages v1 (texte brut) restent lisibles. Question et libellés du sondage restent chiffrés. Le serveur ne voit que `optionCount`, `multiple` et les votes par indice (`o1` en local correspond à l'indice 0).
- **Déchiffrement** : `crypto.decrypt(message, scope:)` (interface de l'agent crypto). Aucune crypto implémentée ici.
- **Fin du lien** : `access {canWrite, readableUntilSequence}` de la page. Le client écarte tout message au-delà de la limite, tronque l'historique local, masque le composeur (« Lecture seule ») et refuse `enqueue`.
- **Suppression** : « pour moi » masque localement et efface l'historique local ; « pour tout le monde » (auteur ou administrateur du groupe) affiche « Message supprimé », l'enveloppe est jetée côté client.
- **Recherche** : `MessagingSealedHistory`, AES-GCM, clé Keychain `WhenUnlockedThisDeviceOnly`, protection `complete`, exclu de la sauvegarde, 3 000 messages par conversation. Si le stockage est indisponible, la recherche porte sur la mémoire de la session. Jamais de repli en clair.
- **Signalement** : sélection explicite des messages, rechiffrés via `MessagingReportSealing` (agent crypto) puis `POST reports`. Par défaut, l'implémentation est indisponible et le signalement échoue fermé.
- **Général** : membres avec nom et photo #64 (lue en mémoire via `SchoolWorkspace.loadPhoto`). Un appui ouvre un profil limité au nom et à la photo. Nommer ou retirer un admin et retirer un membre sont réservés aux admins du groupe ; l'interface masque, le serveur revalide.
- **Actions** : aucun état optimiste. Après chaque action, la conversation est relue.
- **Réactions** : liste fermée de six emojis, refusée localement hors liste.
- Hors périmètre : photos et fichiers, indicateur de saisie.
- Reste à faire : `GET conversations/{id}/changes?afterChange=N` (changeSequence) n'est pas encore consommé, la relecture complète en tient lieu. `GET reports/recipients` est pour l'agent crypto.

Tests : `DrivyTests/MessagingThreadTests.swift`, `DrivyUITests/MessagingThreadUITests.swift`. Écrits, **non exécutés** (#84, pas de runner Apple ici).
