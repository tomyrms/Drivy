# Reprise : lots de l'audit UX (#132), 27 octobre 2026

## Demande du porteur

Lister les issues ouvertes jamais commencées, proposer des lots, réaliser ceux qu'il valide, lui donner une IPA sans lancer les tests ; après son essai, tests ciblés, fusion dans master, déploiement seulement si nécessaire.

## État

| Lot | Tickets | Branche | État |
|---|---|---|---|
| 1 navigation et paramètres | #133 à #138 | `claude/lot1-navigation-parametres` (`db82402`) | Validé à l'essai par le porteur (IPA build 413). Tests UI ciblés lancés : run 40594859821. |
| 2 écrans vides et dossier | #139, #140, #154 | `claude/audit-ux-lots-2-4` (`c314c52`) | Compilé. En attente d'essai. |
| 3 liste des élèves | #151, #152, #153 | `claude/audit-ux-lots-2-4` (`3b6ff2e`) | En attente d'essai. |
| 4 Mon profil | #155 à #158 | `claude/audit-ux-lots-2-4` (`e1a5d5d`) | Compilé. En attente d'essai. |
| 5 agenda et planification | #148, #149, #150 | — | Proposé, non validé. |
| 6 cours collectifs | #159, #160, #161 | — | Proposé, non validé. |
| 7 bilan et trajets | #164, #165 | — | Proposé, non validé. |
| 8 messagerie hors fil | #166, #167, #171, #176 | — | Proposé, non validé. |
| à fermer | #174 | — | Sans objet depuis #51 (le web planifie les leçons). |

IPA livrées au porteur : branche d'intégration `claude/integration-lots-1-4-20261027` = lots 1 à 4 + `claude/182-exyte-chat` (PR #184, autre session), compilée avec `-f messaging_qualification=true`.

## Hors de ces lots

- #142, #168, #177 : fil de discussion réécrit par la PR #184 ; à faire après sa fusion.
- #108 à #131 (réactivité globale), #52 et #54 (nouvelles fonctions à cadrer), #97, #45, #63, #55 et #84 (campagnes finales).

## Fusion prévue

1. Après l'essai : tests UI ciblés (`NativeNavigationTests`, `MessagingKeyBackupUITests`, `MessagingOwnDevicesUITests`, `MessagingThreadUITests`, `SchoolEntryTests`, `DossierRefreshTests`) et tests métier (`SchoolProfilePhotoCropTests` et la suite `all`).
2. PR de `claude/lot1-navigation-parametres` puis de `claude/audit-ux-lots-2-4` vers master. Ne pas fusionner la branche d'intégration : elle contient la PR #184 d'une autre session.
3. iOS seulement : aucun déploiement homelab.

## Pour Codex

« Lis docs/implementation/reprise-audit-ux-lots-20261027.md et les quatre notes audit-ux-lot*/navigation-parametres-lot1, puis reprends à l'étape de fusion ou au lot suivant validé par le porteur. »
