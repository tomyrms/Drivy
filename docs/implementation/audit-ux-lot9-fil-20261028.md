# Lot 9 de l'audit UX : fil de discussion (#142, #168, #177)

28 octobre 2026, branche `claude/audit-ux-lot9-fil`, partie de `master` `b57a8d6` (fil Exyte de #184 compris). Code iOS seulement : aucun contrat, aucune migration, rien à déployer.

## #142 A13 : zones d'appui, mesurées dans le code

| Commande | Avant | Après |
|---|---|---|
| Pastilles de réaction (bulle de réponse) | ≈ 34 pt, chevauchées d'un cinquième : l'appui au bord pouvait viser la voisine | Côte à côte (2 pt), appui sur 44 pt de haut sans largeur ajoutée ; bande et bulle à la même place |
| Coche d'erreur de la bulle de réponse | 40 × 10 pt | Zone d'appui agrandie de 17 pt de chaque côté, libellé VoiceOver « Réessayer l'envoi » |
| « Modification non confirmée/conservée · Réessayer », refus sous un message | ≈ 16 pt de haut | Zone agrandie de 14 pt de chaque côté, sans agrandir la ligne |
| « Sourdine non confirmée · Réessayer » du bandeau | ≈ 16 pt | Même agrandissement |

Les pastilles des bulles ordinaires d'Exyte gardent la bande transparente posée en #182. Aucune mesure sur appareil : à vérifier à l'œil.

## #168 A52 : menu de sourdine

Le menu Options ne propose plus que l'action de l'état affiché : « Mettre en sourdine une heure », ou « Réactiver les notifications » avec « En sourdine jusqu'à 14:05 ». La demande en cours prime sur l'état serveur connu (`displayedMutedUntil`), comme le bandeau, qui affiche lui aussi l'heure de fin. L'icône de sourdine de la liste suit la même valeur. Aucune nouvelle durée, aucune sémantique serveur ajoutée.

## #177 A12 : consulter, réessayer, masquer

- Refus de l'école sous un message (conflit, conversation fermée, participants changés) : l'appui ouvre un menu avec l'explication ; « Actualiser la conversation » pour un conflit ; « Masquer » à part. L'intention est déjà retirée : aucun renvoi proposé.
- Absence de confirmation : inchangé, « Réessayer » renvoie la même intention (#104).
- Envoi en échec : « Échec » ouvre l'explication. « Réessayer » n'est proposé que si le même envoi peut aboutir (panne, réponse illisible, participants changés, conflit) ; accès retiré, conversation fermée, appareils en trop ou protection absente n'ont pas de renvoi aveugle (`MessagingFailure.allowsSameSendRetry`).
- Erreur d'action du bandeau : le texte se lit, une croix « Masquer l'erreur » le retire ; toucher le texte ne fait plus rien.

## Vérification

- Compilation par l'IPA d'essai ; tests non lancés avant l'essai du porteur.
- À rejouer ensuite : `MessagingLatencyUITests` (refus de réaction, identifiant `messaging.mutation.rejected` conservé), `MessagingThreadUITests`, `MessagingFeatureCheckUITests`.
