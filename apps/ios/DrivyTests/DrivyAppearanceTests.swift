import Testing
import UIKit
@testable import Drivy

@MainActor
struct DrivyAppearanceTests {
    @Test func eachChoiceForcesItsStyleAndAutomaticFollowsTheSystem() {
        #expect(DrivyAppearance.automatic.interfaceStyle == .unspecified)
        #expect(DrivyAppearance.light.interfaceStyle == .light)
        #expect(DrivyAppearance.dark.interfaceStyle == .dark)
        #expect(DrivyAppearance.allCases.map(\.title) == ["Automatique", "Clair", "Sombre"])
    }

    @Test func theStoredChoiceSurvivesARelaunchAndDefaultsToAutomatic() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: DrivyAppearance.storageKey)
        defer { defaults.set(previous, forKey: DrivyAppearance.storageKey) }
        defaults.removeObject(forKey: DrivyAppearance.storageKey)
        #expect(DrivyAppearance.stored == .automatic)
        defaults.set("dark", forKey: DrivyAppearance.storageKey)
        #expect(DrivyAppearance.stored == .dark)
        defaults.set("sepia", forKey: DrivyAppearance.storageKey)
        #expect(DrivyAppearance.stored == .automatic)
    }

    @Test func aWindowTakesTheChoiceAndGoesBackToTheSystem() {
        let window = UIWindow(frame: .zero)
        DrivyAppearance.apply(.dark, to: window)
        #expect(window.overrideUserInterfaceStyle == .dark)
        DrivyAppearance.apply(.light, to: window)
        #expect(window.overrideUserInterfaceStyle == .light)
        DrivyAppearance.apply(.automatic, to: window)
        #expect(window.overrideUserInterfaceStyle == .unspecified)
    }
}
