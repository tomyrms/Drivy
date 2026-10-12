import SwiftUI
import UIKit

/// Le thème choisi dans Paramètres, le même pour le moniteur et l’élève. Une seule source : la préférence locale
/// (`AppStorage`), posée comme style d’interface sur chaque fenêtre de l’app. Toutes les couleurs Drivy suivent
/// les traits de la fenêtre (`DrivyTheme`) : feuilles, menus, cartes MapKit et rideau de départ changent avec elle,
/// sans redémarrage. « Automatique » rend la main à iOS, qui suit alors ses propres changements d’apparence.
enum DrivyAppearance: String, CaseIterable, Identifiable, Sendable {
    case automatic, light, dark

    static let storageKey = "drivy.appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatique"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .automatic: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Le choix enregistré ; une valeur absente ou inconnue vaut « Automatique ».
    static var stored: DrivyAppearance {
        UserDefaults.standard.string(forKey: storageKey).flatMap(DrivyAppearance.init(rawValue:)) ?? .automatic
    }

    /// Pose le choix sur toutes les fenêtres ouvertes, celles des autres scènes de l’iPad comprises.
    @MainActor static func apply(_ appearance: DrivyAppearance) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { apply(appearance, to: window) }
        }
    }

    /// Une fenêtre créée plus tard (le rideau de départ) prend le choix enregistré dès sa création.
    @MainActor static func apply(_ appearance: DrivyAppearance = stored, to window: UIWindow) {
        guard window.overrideUserInterfaceStyle != appearance.interfaceStyle else { return }
        window.overrideUserInterfaceStyle = appearance.interfaceStyle
    }
}

/// « Apparence » dans les Paramètres des deux rôles : trois choix côte à côte, ou un menu en très grand texte.
struct DrivyAppearanceSection: View {
    @AppStorage(DrivyAppearance.storageKey) private var appearance: DrivyAppearance = .automatic
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Section {
            if typeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
                    .frame(minHeight: DrivyLayout.tapTarget)
            } else {
                picker.pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.vertical, DrivySpacing.xs)
            }
        } header: {
            Text("Apparence").drivyFormSectionHeader()
        }
        .drivyFormRows()
    }

    private var picker: some View {
        Picker("Thème", selection: $appearance) {
            ForEach(DrivyAppearance.allCases) { Text($0.title).tag($0) }
        }
        .accessibilityIdentifier("settings-appearance")
    }
}
