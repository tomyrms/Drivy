# Lot 1 de l'audit UX : navigation et paramètres (#133 à #138)

27 octobre 2026, branche `claude/lot1-navigation-parametres`, partie de `master` `b090f2d`. Lot validé par le porteur parmi la liste des tickets d'audit non commencés (#132). Code iOS seulement : aucun contrat, aucune migration, rien à déployer.

## Ce qui change

| Ticket | Avant | Après |
|---|---|---|
| #133 A01 | L'onglet Messages disparaissait pendant un trajet, les onglets suivants changeaient de place. | L'onglet reste à sa place. Pendant un trajet, il affiche « Messages en pause » et « Revenir au trajet ». La liste, le fil et la saisie ne sont pas construits. VoiceOver annonce « En pause pendant le trajet ». Les accès contextuels (« Envoyer un message » du dossier) restent retirés pendant le trajet, comme avant. |
| #134 A03 | « Changer d'école » du compte quittait l'école tout de suite et ouvrait l'écran de choix. La barre ouvrait une feuille. | Les deux ouvrent la même feuille « Changer d'école », école ouverte cochée. Fermer ou reprendre l'école ouverte ne vide rien. Dans les onglets, la ligne ouvre la feuille de l'accueil, qui survit à la reconstruction des onglets. Dans la feuille « Compte », la ligne présente la même feuille et ne ferme « Compte » qu'après un vrai changement. Retrait pendant un trajet inchangé. |
| #135 A04 | Menu « Plus » de Messages avec une seule entrée « Réglages ». | Engrenage direct « Paramètres de Messages » (un appui). Page titrée « Paramètres de Messages ». |
| #136 A05 | Préférences de leçon en feuille, Signalements en page, sans règle écrite. | Règle écrite ci-dessous ; les deux parcours la suivent déjà, Notifications la suit aussi. |
| #137 A06 | Ligne « Leçons » dans le Profil du moniteur. | « Historique des leçons », même titre sur la page ouverte. L'onglet Leçons de l'élève ne change pas. |
| #138 A07 | Notifications seulement dans Mon profil, désactivées dès qu'un champ était modifié. | Ligne « Notifications » dans Paramètres, élève comme moniteur et administration, vers la même `SchoolNotificationSettingsView`. L'ancien accès de Mon profil est retiré. |

## Règles retenues

**Vocabulaire (#135).** « Paramètres » désigne tout ce qui se règle dans Drivy. « Réglages » est réservé à l'app Réglages d'iOS, dont c'est le nom officiel (« Ouvrir Réglages »). Deux boutons qui ouvraient Réglages sous d'autres libellés et un message d'erreur (« Les réglages GPS de l'école ») ont été alignés.

**Ouverture des pages (#136).** Un formulaire qui s'enregistre par un bouton, avec sa saisie protégée à la fermeture, s'ouvre en feuille : Mon profil, Préférences de leçon. Une page où chaque choix s'applique aussitôt est poussée dans la pile, avec le retour : Notifications, Signalements, Paramètres de Messages, Trajets. Une tâche courte et isolée reste une feuille : Changer d'école, Rejoindre une école. Préférences de leçon reste donc une feuille : la pousser exigerait de bloquer le retour par glissement pour ne pas perdre un brouillon.

## Fichiers

- `SchoolUI/SchoolHomeView.swift` : onglet Messages stable, `SchoolMessagesPausedView`.
- `SchoolUI/SchoolAccountComponents.swift`, `SchoolUI/SchoolBrowserView.swift` : `SchoolChangeSchoolRow`, rappel `didChangeSchool` du sélecteur.
- `SchoolUI/SchoolProfileTabView.swift`, `SchoolLessonHistoryUI/SchoolLessonHistoryView.swift` : historique des leçons.
- `SchoolUI/SchoolStaffSettingsView.swift`, `SchoolUI/SchoolLearnerSettingsView.swift`, `SchoolUI/SchoolLearnerProfileTab.swift`, `SchoolProfileUI/SchoolNotificationSettingsView.swift`, `SchoolProfileUI/SchoolMyProfileView.swift` : Notifications dans Paramètres.
- `MessagingUI/MessagingViews.swift`, `MessagingUI/MessagingKeyBackupView.swift` : engrenage direct.
- Tests UI adaptés : `MessagingKeyBackupUITests`, `MessagingOwnDevicesUITests`, `MessagingThreadUITests` (plus de menu « Plus »), `NativeNavigationTests` (titre « Historique des leçons »).

## Vérification

- Aucun compilateur Swift sur cette machine : la compilation passe par l'IPA d'essai sur GitHub Actions. L'IPA ne compile pas la cible de tests.
- Tests métier et UI non lancés avant l'essai du porteur, à sa demande. Ensuite : tests UI ciblés (`NativeNavigationTests`, `MessagingKeyBackupUITests`, `MessagingOwnDevicesUITests`, `MessagingThreadUITests`).
- Aucun test UI ne couvre encore l'onglet Messages pendant un trajet (fixture de trajet à construire), ni le changement d'école depuis la ligne du compte. À vérifier à l'œil sur l'IPA : iPhone et iPad, clair et sombre, VoiceOver.
