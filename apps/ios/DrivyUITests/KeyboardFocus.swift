import XCTest

/// Un appui pendant la présentation d'une feuille ou un défilement ne donne pas toujours le focus :
/// `typeText` échoue alors (« Neither element nor any descendant has keyboard focus ») ou ne saisit rien.
/// Sans focus après trois appuis, `typeText` signale lui-même l'échec.
@MainActor func focusForTyping(_ field: XCUIElement) {
    let focused = NSPredicate(format: "hasKeyboardFocus == true")
    for _ in 0..<3 {
        field.tap()
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 2) == .completed { return }
    }
}
