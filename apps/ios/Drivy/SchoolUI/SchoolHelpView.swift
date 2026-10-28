import SwiftUI
import UIKit

/// Aide retrouvable depuis Paramètres. L’adresse vient de l’école ouverte ; aucune assistance n’est inventée.
struct SchoolHelpView: View {
    let workspace: SchoolWorkspace
    @Environment(\.openURL) private var openURL
    @State private var contactError: String?
    @State private var copied = false
    private let diagnostic = SchoolHelpDiagnostic.current

    private var isInstructor: Bool { workspace.membership?.roles.contains("INSTRUCTOR") == true }
    private var isLearner: Bool { workspace.membership?.roles.contains("LEARNER") == true }

    var body: some View {
        List {
            Section {
                explanation("Reprendre l’accueil", text: "Dans Profil → Mon profil, reprends l’accueil de l’école. Les étapes confirmées sont conservées.")
                if isInstructor || isLearner {
                    explanation("Retrouver un rendez-vous", text: isInstructor
                        ? "Ouvre Agenda puis la leçon pour retrouver l’élève, le lieu et les éléments à vérifier avant le départ."
                        : "Ouvre Leçons puis ton rendez-vous pour retrouver l’horaire, le moniteur et le lieu convenu.")
                } else {
                    explanation("Gérer l’école", text: "Depuis Profil, ouvre l’espace web pour retrouver le planning, les élèves et les réglages de l’école.")
                }
                if (isInstructor || isLearner), workspace.school?.modules.gpsEnabled == true {
                    explanation("Comprendre le suivi GPS", text: isInstructor
                        ? "L’appareil qui enregistre fournit les positions pendant la séance. L’élève choisit pour son compte ; l’autorisation de position de ton appareil se règle séparément."
                        : "L’appareil du moniteur fournit les positions pendant la séance. Dans Profil → Paramètres → Enregistrement GPS, retrouve ton choix et les informations de l’école. Refuser conserve ton compte, tes messages et tes rendez-vous.")
                }
                if isInstructor {
                    explanation("Terminer une leçon", text: "Terminer arrête la collecte sur l’appareil. Vérifie ensuite la fin de leçon et son bilan ; une demande en attente n’est pas encore confirmée par l’école.")
                    explanation("Compléter le bilan", text: "Retrouve les observations déjà saisies, ajoute une évaluation ou du texte si utile, puis vérifie « Ce que verra l’élève ». Une note pour toi reste privée.")
                } else if isLearner {
                    explanation("Lire un bilan", text: "Ouvre une leçon terminée pour retrouver le trajet, les observations et le bilan que le moniteur partage avec toi.")
                }
                explanation("Une demande reste en attente", text: "Utilise Vérifier sur la demande pour retrouver la réponse de l’école. Réessaie seulement quand l’écran le propose.")
            } header: { Text("Utiliser Drivy").drivyFormSectionHeader() }
                .drivyFormRows()

            Section {
                if let url = SchoolHelpContact.mail(workspace.school?.contactEmail) {
                    Button {
                        contactError = nil
                        openURL(url) { accepted in
                            if !accepted { contactError = "Aucune app de messagerie n’a pu être ouverte. Utilise l’adresse de l’école affichée ici." }
                        }
                    } label: {
                        Label("Contacter l’école", systemImage: "envelope")
                            .frame(minHeight: DrivyLayout.tapTarget)
                    }
                    .accessibilityIdentifier("help-contact-school")
                    Text(workspace.school?.contactEmail ?? "")
                        .textSelection(.enabled)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let contactError { DrivyFormMessage(text: contactError, tone: .warning) }
                } else {
                    Text("Le contact de l’école n’est pas disponible ici. Utilise ton moyen de contact habituel.")
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("help-contact-unavailable")
                }
            } header: { Text("Assistance").drivyFormSectionHeader() }
                .drivyFormRows()

            Section {
                LabeledContent("Version", value: diagnostic.version)
                LabeledContent("Build", value: diagnostic.build)
                LabeledContent("Système", value: diagnostic.system)
                Button {
                    UIPasteboard.general.string = diagnostic.text
                    copied = true
                    UIAccessibility.post(notification: .announcement, argument: "Diagnostic copié.")
                } label: {
                    Label("Copier le diagnostic", systemImage: "doc.on.doc")
                        .frame(minHeight: DrivyLayout.tapTarget)
                }
                .accessibilityHint("Copie seulement la version de Drivy, le build et le système affichés")
                .accessibilityIdentifier("help-copy-diagnostic")
                if copied { DrivyFormMessage(text: "Diagnostic copié.") }
            } header: { Text("Diagnostic").drivyFormSectionHeader() }
                .drivyFormRows()
                .accessibilityIdentifier("help-diagnostic-preview")
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .navigationTitle("Aide")
        .navigationBarTitleDisplayMode(.inline)
        .tint(DrivyTheme.accent)
    }

    private func explanation(_ title: String, text: String) -> some View {
        DisclosureGroup {
            Text(text)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, DrivySpacing.xs)
        } label: {
            Text(title).foregroundStyle(DrivyTheme.text)
        }
    }
}

/// Une adresse seule, pas des paramètres de message ni un destinataire supposé.
enum SchoolHelpContact {
    static func mail(_ address: String?) -> URL? {
        guard let address else { return nil }
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard value.utf8.count <= 254, parts.count == 2, !parts[0].isEmpty, parts[0].utf8.count <= 64,
              parts[0].first != ".", parts[0].last != ".", !parts[0].contains(".."),
              parts[0].allSatisfy({ $0.isLetter || $0.isNumber || ".!$'*+=^_`{|}~-".contains($0) }) else { return nil }
        let domain = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard domain.count >= 2, domain.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else { return nil }
        return SchoolContactLinks.mail(value)
    }
}

/// Liste fermée de métadonnées publiques. Ni le compte, ni l’école, ni le GPS ne sont accessibles ici.
struct SchoolHelpDiagnostic: Equatable, Sendable {
    let version: String
    let build: String
    let system: String

    var text: String { "Drivy\nVersion : \(version)\nBuild : \(build)\nSystème : \(system)" }

    @MainActor static var current: Self {
        .init(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Non renseignée",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Non renseigné",
            system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
    }
}
