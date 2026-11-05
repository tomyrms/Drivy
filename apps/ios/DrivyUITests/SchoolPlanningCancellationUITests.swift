import XCTest

/// Scénario explicite DEBUG simulateur, aucune identité réelle ni réseau.
@MainActor final class SchoolPlanningCancellationUITests: XCTestCase {
    func testCancelAtTokenKeepsTheForm() throws { try exercise(mode: "token") }
    func testCancelAtMeKeepsTheForm() throws { try exercise(mode: "me") }
    func testRemovalCanBeRetriedInLargeText() throws { try exercise(mode: "token", failsRemoval: true, largeText: true) }

    private func exercise(mode: String, failsRemoval: Bool = false, largeText: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Nettoyage régulier même après une assertion : ne pas laisser launch() du cas suivant
        // être le seul responsable de terminer cette instance. Aucun retry ne masque un incident.
        addTeardownBlock { @MainActor in
            if app.state != .notRunning { app.terminate() }
        }
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = "planning"
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH", "-planning-l2-cancellation-" + mode]
        if failsRemoval { app.launchArguments.append("-planning-l2-cancellation-storage-failure") }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.navigationBars["Planifier une leçon"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 5))
        let plan = app.buttons["planning-confirm"]
        let details = app.buttons["Détails du rendez-vous"]
        reveal(details, app: app, up: true)
        details.tap() // Un balayage ne développe pas le DisclosureGroup.
        let places = app.descendants(matching: .any).matching(identifier: "planning-meeting-point")
            .matching(NSPredicate(format: "elementType == %d OR elementType == %d",
                XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue))
        let place = places.firstMatch
        reveal(place, app: app, up: true)
        XCTAssertEqual(places.count, 1, "L’identifiant doit désigner un seul champ de saisie")
        let originalPlace = try XCTUnwrap(place.value as? String)
        let entered = " L2-" + mode + (failsRemoval ? "-retrait" : "-saisie")
        focusForTyping(place)
        place.typeText(entered)
        let editedPlace = try XCTUnwrap(place.value as? String)
        XCTAssertNotEqual(editedPlace, originalPlace)
        XCTAssertTrue(editedPlace.contains(entered), "La valeur doit provenir de la saisie réelle au clavier")
        // Le formulaire crée une leçon : Planifier confirme le tarif courant. Si une scène exige
        // un accord explicite, seul son contrôle réel peut le rétablir après la saisie du lieu.
        let agreement = app.switches["Le nouvel horaire est convenu"]
        if agreement.exists && agreement.value as? String == "0" {
            reveal(agreement, app: app, up: true)
            agreement.tap()
        }
        reveal(plan, app: app, up: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: plan)], timeout: 5), .completed)
        plan.tap()
        let cancel = app.buttons["planning-cancel-send"]
        reveal(cancel, app: app, up: false)
        XCTAssertEqual(cancel.label, "Annuler l’envoi")
        XCTAssertFalse(app.buttons["Annuler la leçon"].exists)
        XCTAssertTrue(app.buttons["Fermer"].isEnabled, "Fermer reste une action distincte du retrait")
        let witness = app.staticTexts["planning-l2-rendezvous"]
        let expectedReads = mode == "me" ? 1 : 0
        // Attend la frontière réelle : token = avant /me ; me = dans la lecture retenue.
        let waitingEvidence = "waiting-\(mode)|me=\(expectedReads)|mutations=0"
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", waitingEvidence), object: witness)], timeout: 5), .completed,
            "Le bouton disponible ne prouve pas que la retenue est atteinte")
        cancel.tap()
        let error = app.descendants(matching: .any)["planning-send-cancellation-error"].firstMatch
        if failsRemoval {
            XCTAssertTrue(error.waitForExistence(timeout: 5))
            XCTAssertTrue(cancel.isEnabled)
            cancel.tap()
        }
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "Seul le retrait réussi rend la saisie disponible")
        XCTAssertFalse(error.exists)
        XCTAssertTrue(app.navigationBars["Planifier une leçon"].exists)
        reveal(plan, app: app, up: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: plan)], timeout: 5), .completed)
        XCTAssertEqual(witness.label, "removed|me=\(expectedReads)|mutations=0")
        // La section explicitement ouverte doit rendre le vrai champ visible, pas seulement
        // une occurrence AX cachée ou le texte préchargé dans le modèle de fixture.
        reveal(place, app: app, up: false)
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(place.value as? String, editedPlace)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "L2 saisie conservée — fixture synthétique"
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool) {
        let form = app.collectionViews.firstMatch
        let window = app.windows.firstMatch
        for direction in [up, !up] {
            for _ in 0..<10 {
                if element.exists && element.isHittable { return }
                guard form.exists, window.exists else {
                    XCTFail("Le formulaire et sa fenêtre doivent être présents pour défiler")
                    return
                }
                let viewport = scrollViewport(form: form, window: window, app: app)
                guard !viewport.isNull, viewport.width >= 44, viewport.height >= 80 else {
                    XCTFail("Aucune zone de formulaire suffisante hors clavier et barres")
                    return
                }
                // Plusieurs repères du contenu : un titre de section peut rester fixé pendant le geste.
                let candidates = form.staticTexts.allElementsBoundByIndex
                    + form.textFields.allElementsBoundByIndex + form.textViews.allElementsBoundByIndex
                let anchors = Array(candidates.lazy.filter {
                    $0.frame.intersects(viewport) && !$0.label.isEmpty
                }.prefix(3)).map { (element: $0, label: $0.label, frame: $0.frame) }
                guard !anchors.isEmpty else {
                    XCTFail("Aucun repère de contenu visible pour vérifier le défilement")
                    return
                }
                let x = viewport.minX + viewport.width * 0.85
                let upper = viewport.minY + viewport.height * 0.2
                let lower = viewport.minY + viewport.height * 0.8
                let origin = window.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(CGVector(dx: x - window.frame.minX,
                    dy: (direction ? lower : upper) - window.frame.minY))
                let end = origin.withOffset(CGVector(dx: x - window.frame.minX,
                    dy: (direction ? upper : lower) - window.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: end)
                if element.exists && element.isHittable { return }
                let moved = anchors.contains { anchor in
                    !anchor.element.exists || anchor.element.label != anchor.label
                        || abs(anchor.element.frame.minY - anchor.frame.minY) > 1
                }
                // Bord atteint ou geste sans effet : ne pas compter dix gestes identiques comme un parcours.
                if !moved { break }
            }
        }
        XCTAssertTrue(element.exists && element.isHittable,
            "Le contrôle doit être matérialisé et atteignable après un défilement effectif du formulaire")
    }

    private func scrollViewport(form: XCUIElement, window: XCUIElement, app: XCUIApplication) -> CGRect {
        let bounds = form.frame.intersection(window.frame)
        guard !bounds.isNull, !bounds.isEmpty else { return .null }
        var top = bounds.minY
        var bottom = bounds.maxY
        for element in [app.navigationBars.firstMatch, app.staticTexts["planning-l2-rendezvous"]] {
            if element.exists, element.frame.intersects(bounds) { top = max(top, element.frame.maxY) }
        }
        for element in [app.keyboards.firstMatch, app.staticTexts["Rendu de contrôle · données fictives"],
                        app.buttons["planning-confirm"]] {
            if element.exists, element.frame.intersects(bounds), element.frame.minY > top {
                bottom = min(bottom, element.frame.minY)
            }
        }
        guard bottom > top else { return .null }
        // Marge de geste seulement, sans changer aucune dimension du produit.
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top).insetBy(dx: 8, dy: 8)
    }
}
