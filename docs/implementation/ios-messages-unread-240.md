# Messages : vue Non lus — 29 octobre 2026

Issue #240, branche `codex/ios-suite-19-20261029`. Complète #237/#241 déjà intégrées ; aucun changement serveur ou EPIC #311.

## Décisions

Le sélecteur Toutes / Non lus projette le compteur `unreadCount` autorisé de chaque conversation, Général compris. Il ne crée pas de compteur parallèle et n’envoie aucune commande de lecture. Les lectures inconnues restent dans « Lecture à vérifier », y compris le raccourci Général quand sa ligne serveur n’est pas chargée ; elles ne deviennent jamais zéro. Leur ligne et annonce accessible distinguent cet état.

La recherche combine titre/aperçu déchiffré déjà disponible et filtre. Elle reste limitée aux pages chargées. L’état partiel et le chargement manuel permettent de poursuivre sans boucle réseau automatique. Un résultat vide partiel n’annonce pas l’absence globale de non-lus. Le filtre, la recherche et la route gardent leurs états indépendants ; changer de filtre ne ferme pas la conversation sélectionnée sur iPad. Le passage à Toutes conserve la recherche.

Les mécanismes existants restent l’autorité : compteurs serveur, relecture multi-appareils, `applyConfirmedRead` après accusé serveur et nettoyage ciblé des seules notifications déjà confirmées lues. Le filtre n’appelle ni `markRead` ni `conversationViewed` ni une API Notifications.

Références : contrat courant `messaging-api-contract.md`, scénarios de lecture/notification #103 et pagination #167, règles de contexte R01/R02 et de confidentialité. Aucune autorisation déduite du filtre.

## Vérification

- Relecture de l’inbox, chargement paginé, fusion des bornes et confirmations ; `git diff --check`.
- Deux tests de projection préparés : compteur inconnu distinct de zéro ; recherche combinée aux compteurs et insensible aux accents.
- Fixture DEBUG simulateur `-messaging-ui-fixture -messaging-ui-rich -messaging-ui-unread-filter` : Général lu, Léa inconnue sur la première page, Marc non lu sur la deuxième. Test UI préparé pour filtre, état inconnu et recherche/pagination.
- Tests **non exécutés**, à lancer après validation de l’IPA. Cette fixture n’est pas livrée dans la Release.
- Recette physique restante : retour d’un fil lu, synchronisation autre appareil, recherche effacée, maintien du fil iPad lors d’un filtre, réseau en échec et reprise, grand texte et VoiceOver.
