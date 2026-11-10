import XCTest

/// Boîtes de l'onglet Élèves (#447, #449) sur le vrai écran, serveur fictif en lecture seule sauf l'écran « learners-boxes-refresh » :
/// - 9 et 20 lignes, demandes ET examens : la liste complète s'ouvre, la dernière ligne arrive sur sa cible exacte (la fiche de la leçon
///   qui porte la demande ; la section Progression de la formation qui porte l'examen) et le retour retrouve la liste dépliée ;
/// - actualisation qui change les boîtes (retrait, ajout), une boîte en panne qui garde sa lecture puis reprend sur Réessayer pendant que
///   l'autre boîte aboutit ;
/// - un refus de demande confirmé dans la fiche de la leçon relit la boîte au retour, sans tirage.
@MainActor final class SchoolBoxesUITests: XCTestCase {
    private let targetExamIdentifier = "exam-10000000-0000-4000-8000-000000000153"

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }

    private func row(_ app: XCUIApplication, _ prefix: String, _ number: Int) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(prefix) \(number),")).firstMatch
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<30 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<30 { app.swipeDown() }
    }

    private func pullToRefresh(_ app: XCUIApplication) {
        scrollToTop(app)
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
    }

    private func backToList(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable { back.tap() }
    }

    // MARK: 9 et 20 lignes

    func testNineRequestsAreAllReachableAndTheLastOneOpensItsLesson() { verifyRequests(count: 9) }
    func testTwentyRequestsAreAllReachableAndTheLastOneOpensItsLesson() { verifyRequests(count: 20) }
    func testNineExamsAreAllReachableAndTheLastOneOpensItsTrainingExam() { verifyExams(count: 9) }
    func testTwentyExamsAreAllReachableAndTheLastOneOpensItsTrainingExam() { verifyExams(count: 20) }

    private func verifyRequests(count: Int) {
        let app = launch("learners-boxes-\(count)")
        let toggle = app.buttons["pending-requests-expansion"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "Liste réduite")
        XCTAssertFalse(row(app, "Élève demande", 9).exists, "La neuvième demande ne se voit qu'après le dépliage")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Liste complète")
        let last = row(app, "Élève demande", count)
        XCTAssertTrue(scrollTo(last, in: app), "Dernière demande inaccessible : \(app.debugDescription)")
        last.tap()
        // La cible : la fiche de la leçon qui porte la demande, sur le dossier de son élève.
        XCTAssertTrue(app.descendants(matching: .any)["lesson-change-card"].waitForExistence(timeout: 40), app.debugDescription)
        app.swipeDown()
        XCTAssertTrue(app.descendants(matching: .any)["learner-profile-first-name"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["learner-profile-first-name"].label.contains("Camille"), app.debugDescription)
        backToList(app)
        XCTAssertTrue(app.buttons["pending-requests-expansion"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(app.buttons["pending-requests-expansion"].value as? String, "Liste complète", "Le retour a perdu le dépliage")
    }

    private func verifyExams(count: Int) {
        let app = launch("learners-boxes-\(count)")
        let toggle = app.buttons["pending-exams-expansion"]
        XCTAssertTrue(scrollTo(toggle, in: app), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "Liste réduite")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Liste complète")
        let last = row(app, "Élève examen", count)
        XCTAssertTrue(scrollTo(last, in: app), "Dernier examen inaccessible : \(app.debugDescription)")
        last.tap()
        // La cible : la section Progression de la formation de l'examen, avec cet examen.
        XCTAssertTrue(app.scrollViews["learner-dossier"].waitForExistence(timeout: 30), app.debugDescription)
        let exam = app.descendants(matching: .any)[targetExamIdentifier]
        XCTAssertTrue(scrollTo(exam, in: app) || exam.waitForExistence(timeout: 30), "Examen visé introuvable : \(app.debugDescription)")
        backToList(app)
        XCTAssertTrue(scrollTo(app.buttons["pending-exams-expansion"], in: app), app.debugDescription)
        XCTAssertEqual(app.buttons["pending-exams-expansion"].value as? String, "Liste complète", "Le retour a perdu le dépliage")
    }

    // MARK: Actualisation, panne locale, traitement

    func testRefreshChangesTheBoxesAndAFailedBoxKeepsItsReadingUntilRetry() {
        let app = launch("learners-boxes-refresh")
        let requestsToggle = app.buttons["pending-requests-expansion"]
        XCTAssertTrue(requestsToggle.waitForExistence(timeout: 30), app.debugDescription)
        requestsToggle.tap()
        XCTAssertTrue(row(app, "Élève demande", 1).exists, app.debugDescription)

        pullToRefresh(app)
        // Les demandes ont changé ailleurs : la première est retirée, une dixième arrive.
        let tenth = row(app, "Élève demande", 10)
        XCTAssertTrue(scrollTo(tenth, in: app), "Nouvelle demande absente : \(app.debugDescription)")
        scrollToTop(app)
        XCTAssertFalse(row(app, "Élève demande", 1).exists, "Demande retirée encore affichée : \(app.debugDescription)")

        // La boîte des examens a échoué à cette actualisation : lecture précédente conservée, erreur et Réessayer.
        let retry = app.buttons["pending-exams-retry"]
        XCTAssertTrue(scrollTo(retry, in: app), "Réessayer absent : \(app.debugDescription)")
        XCTAssertFalse(app.buttons["pending-requests-retry"].exists, "La boîte des demandes n'a pas échoué")
        let kept = row(app, "Élève examen", 1)
        XCTAssertTrue(scrollTo(kept, in: app), "Lecture précédente des examens perdue : \(app.debugDescription)")

        XCTAssertTrue(scrollTo(retry, in: app))
        retry.tap()
        let expansion = app.buttons["pending-exams-expansion"]
        XCTAssertTrue(scrollTo(expansion, in: app), app.debugDescription)
        expansion.tap()
        XCTAssertTrue(scrollTo(row(app, "Élève examen", 10), in: app), "Examens relus absents : \(app.debugDescription)")
        XCTAssertFalse(app.buttons["pending-exams-retry"].exists, "L'erreur persiste après la reprise : \(app.debugDescription)")
        XCTAssertFalse(row(app, "Élève examen", 1).exists, "Examen retiré encore affiché : \(app.debugDescription)")
    }

    func testAConfirmedRefusalRereadsTheBoxOnReturnWithoutPulling() {
        let app = launch("learners-boxes-refresh")
        let toggle = app.buttons["pending-requests-expansion"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), app.debugDescription)
        toggle.tap()
        let last = row(app, "Élève demande", 9)
        XCTAssertTrue(scrollTo(last, in: app), app.debugDescription)
        last.tap()
        XCTAssertTrue(app.buttons["lesson-change-refuse"].waitForExistence(timeout: 40), app.debugDescription)
        app.buttons["lesson-change-refuse"].tap()
        let send = app.buttons["lesson-change-refuse-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 20), app.debugDescription)
        send.tap()
        XCTAssertTrue(app.buttons["lesson-change-refuse"].waitForNonExistence(timeout: 20), "Refus non confirmé : \(app.debugDescription)")
        app.swipeDown()
        backToList(app)
        // Aucun tirage : la demande traitée a disparu de la boîte.
        let gone = NSPredicate(format: "label BEGINSWITH %@", "Élève demande 9,")
        let query = app.buttons.matching(gone).firstMatch
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: query)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 20), .completed, "La boîte n'a pas été relue : \(app.debugDescription)")
    }
}
