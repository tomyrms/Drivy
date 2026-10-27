import XCTest

/// Un appui pendant la présentation d'une feuille ou un défilement ne donne pas toujours le focus :
/// `typeText` échoue alors (« Neither element nor any descendant has keyboard focus ») ou ne saisit rien.
/// Avec `bottomOffset`, l'appui vise un point au-dessus du bas du cadre plutôt que son centre.
/// Sans focus après trois appuis, `typeText` signale lui-même l'échec.
@MainActor func focusForTyping(_ field: XCUIElement, at bottomOffset: CGVector? = nil) {
    let focused = NSPredicate(format: "hasKeyboardFocus == true")
    for _ in 0..<3 {
        if let bottomOffset {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(bottomOffset).tap()
        } else {
            field.tap()
        }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 2) == .completed { return }
    }
}
