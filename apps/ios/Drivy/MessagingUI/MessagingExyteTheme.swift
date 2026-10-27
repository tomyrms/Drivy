import ExyteChat
import SwiftUI

/// Thème Exyte raccordé aux tokens Drivy (#182) : aucune couleur de démonstration de la bibliothèque.
/// Les bulles restent dessinées par Drivy ; ces couleurs couvrent le fond de liste, le menu et les reprises internes.
extension ChatTheme {
    static var drivy: ChatTheme {
        ChatTheme(colors: ChatTheme.Colors(
            mainBG: DrivyTheme.canvas,
            mainTint: DrivyTheme.accent,
            mainText: DrivyTheme.text,
            mainCaptionText: DrivyTheme.muted,
            messageMyBG: DrivyTheme.accentSoft,
            messageReadStatus: DrivyTheme.accent,
            messageMyText: DrivyTheme.text,
            messageMyTimeText: DrivyTheme.textTertiary,
            messageFriendBG: DrivyTheme.surfaceRaised,
            messageFriendText: DrivyTheme.text,
            messageFriendTimeText: DrivyTheme.textTertiary,
            messageSystemBG: DrivyTheme.surfaceMuted,
            messageSystemText: DrivyTheme.text,
            messageSystemTimeText: DrivyTheme.textTertiary,
            inputBG: DrivyTheme.surfaceMuted,
            inputText: DrivyTheme.text,
            inputPlaceholderText: DrivyTheme.muted,
            inputSignatureBG: DrivyTheme.surfaceMuted,
            inputSignatureText: DrivyTheme.text,
            inputSignaturePlaceholderText: DrivyTheme.muted,
            menuBG: DrivyTheme.surfaceRaised,
            menuText: DrivyTheme.text,
            menuTextDelete: DrivyTheme.danger,
            statusError: DrivyTheme.danger,
            statusGray: DrivyTheme.muted,
            sendButtonBackground: DrivyTheme.accentFill,
            recordDot: DrivyTheme.danger))
    }
}

/// Libellés internes d'Exyte en français. Les entrées média, GIF, audio et position ne sont jamais proposées.
extension ChatLocalization {
    static var drivy: ChatLocalization {
        ChatLocalization(
            inputPlaceholder: "Message",
            signatureText: "Légende",
            cancelButtonText: "Annuler",
            recentToggleText: "Récents",
            waitingForNetwork: "En attente de connexion",
            recordingText: "Enregistrement…",
            replyToText: "Réponse à")
    }
}
