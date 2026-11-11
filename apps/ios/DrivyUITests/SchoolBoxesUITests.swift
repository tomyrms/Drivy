import XCTest

/// Boîtes de l'onglet Élèves (#447, #449) sur le vrai écran, serveur fictif en lecture seule sauf l'écran « learners-boxes-refresh » :
/// - 9 et 20 lignes, demandes ET examens : la liste complète s'ouvre, la dernière ligne arrive sur sa cible exacte (la fiche de la leçon
///   qui porte la demande ; l'examen de sa formation, parmi deux examens de la même formation dont aucun n'est le premier de la liste)
///   et le retour retrouve la liste dépliée. Le serveur fictif rend la première lecture des examens d'une formation avec retard : aucun
///   test ne défile à la main jusqu'à l'examen, il doit être là, visible, une fois la lecture arrivée ;
/// - un examen absent de sa formation est dit, sans en ouvrir un autre ;
/// - actualisation qui change les boîtes (retrait, ajout), une boîte en panne qui garde sa lecture puis reprend sur Réessayer pendant que
///   l'autre boîte aboutit ;
/// - un refus de demande confirmé dans la fiche de la leçon relit la boîte au retour, sans tirage.
@MainActor final class SchoolBoxesUITests: XCTestCase {
    /// Deux examens à renseigner de la même formation du dossier fictif ; 155 est la dernière ligne de la boîte.
    private let earlierExamIdentifier = "exam-actions-10000000-0000-4000-8000-000000000153"
    private let laterExamIdentifier = "exam-actions-10000000-0000-4000-8000-000000000155"

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

    /// Attend une condition de l'interface ; sondage court, sans durée fixe à attendre.
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<30 { app.swipeDown() }
    }

    /// Le geste part sous la barre de navigation (titre large et champ de recherche, y 62 à 176 sur iPhone) : parti de 15 % de la liste
    /// (y 131), il tombait dans le champ de recherche et ne tirait jamais la liste (runs 43020463769 et 43024752953 : aucune boîte
    /// relue). Lent, avec maintien, pour dépasser le seuil du tirer-pour-actualiser et s'y tenir.
    private func pullToRefresh(_ app: XCUIApplication) {
        scrollToTop(app)
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        let field = app.searchFields.firstMatch
        let bar = app.navigationBars.firstMatch
        let barBottom = max(field.exists ? field.frame.maxY : 0, bar.exists ? bar.frame.maxY : 0)
        let startY = barBottom > 0 ? barBottom + 10 - list.frame.minY : list.frame.height * 0.2
        let start = list.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.width * 0.5, dy: startY))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
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
        // Le bouton suit les huit premières lignes : la liste est paresseuse, il n'existe qu'une fois atteint.
        let toggle = app.buttons["pending-requests-expansion"]
        XCTAssertTrue(scrollTo(toggle, in: app), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "Liste réduite")
        XCTAssertFalse(row(app, "Élève demande", 9).exists, "La neuvième demande ne se voit qu'après le dépliage")
        toggle.tap()
        XCTAssertTrue(scrollTo(toggle, in: app), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "Liste complète")
        let last = row(app, "Élève demande", count)
        XCTAssertTrue(scrollTo(last, in: app), "Dernière demande inaccessible : \(app.debugDescription)")
        last.tap()
        // La cible : la fiche de la leçon qui porte la demande, sur le dossier de son élève.
        // La feuille de la leçon s'ouvre (liste paresseuse) : la carte de la demande se rejoint en défilant.
        XCTAssertTrue(app.descendants(matching: .any)["lesson-state"].waitForExistence(timeout: 40), app.debugDescription)
        XCTAssertTrue(scrollTo(app.descendants(matching: .any)["lesson-change-card"], in: app), app.debugDescription)
        // La liste de la feuille est défilée : on ferme par son bouton, un glissement ne ferait que remonter la liste.
        app.buttons["Fermer"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["learner-profile-first-name"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["learner-profile-first-name"].label.contains("Camille"), app.debugDescription)
        backToList(app)
        XCTAssertTrue(scrollTo(app.buttons["pending-requests-expansion"], in: app), app.debugDescription)
        XCTAssertEqual(app.buttons["pending-requests-expansion"].value as? String, "Liste complète", "Le retour a perdu le dépliage")
    }

    private func verifyExams(count: Int) {
        let app = launch("learners-boxes-\(count)")
        let toggle = app.buttons["pending-exams-expansion"]
        XCTAssertTrue(scrollTo(toggle, in: app), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "Liste réduite")
        toggle.tap()
        XCTAssertTrue(scrollTo(toggle, in: app), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "Liste complète")
        // Deux examens de la même formation : l'avant-dernière ligne, puis la dernière (jamais le premier de la formation).
        for (number, identifier) in [(count - 1, earlierExamIdentifier), (count, laterExamIdentifier)] {
            let line = row(app, "Élève examen", number)
            XCTAssertTrue(scrollTo(line, in: app), "Examen \(number) inaccessible : \(app.debugDescription)")
            line.tap()
            let dossier = app.scrollViews["learner-dossier"]
            XCTAssertTrue(dossier.waitForExistence(timeout: 30), app.debugDescription)
            XCTAssertTrue(app.descendants(matching: .any)["learner-profile-first-name"].waitForExistence(timeout: 30), app.debugDescription)
            XCTAssertTrue(app.descendants(matching: .any)["learner-profile-first-name"].label.contains("Camille"), app.debugDescription)
            // La première lecture des examens arrive avec retard : l'examen visé doit être là, visible, sans défilement manuel.
            let exam = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(exam.waitForExistence(timeout: 40), "Examen visé absent : \(app.debugDescription)")
            XCTAssertTrue(waitUntil(10) { exam.isHittable && dossier.frame.contains(exam.frame) },
                "L'examen visé n'est pas amené à l'écran : \(app.debugDescription)")
            XCTAssertFalse(app.descendants(matching: .any)["box-target-missing"].exists, "Message d'examen disparu à tort")
            backToList(app)
            XCTAssertTrue(scrollTo(app.buttons["pending-exams-expansion"], in: app), app.debugDescription)
            XCTAssertEqual(app.buttons["pending-exams-expansion"].value as? String, "Liste complète", "Le retour a perdu le dépliage")
        }
    }

    /// L'avant-avant-dernière ligne désigne un examen que la formation de l'élève ne liste pas : il est dit, aucun autre n'est ouvert.
    func testAnExamMissingFromItsTrainingIsSaidInsteadOfOpeningAnotherOne() {
        let app = launch("learners-boxes-9")
        let line = row(app, "Élève examen", 7)
        XCTAssertTrue(scrollTo(line, in: app), app.debugDescription)
        line.tap()
        XCTAssertTrue(app.descendants(matching: .any)["box-target-missing"].waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(app.scrollViews["learner-dossier"].exists, app.debugDescription)
    }

    // MARK: Actualisation, panne locale, traitement

    func testRefreshChangesTheBoxesAndAFailedBoxKeepsItsReadingUntilRetry() {
        let app = launch("learners-boxes-refresh")
        let requestsToggle = app.buttons["pending-requests-expansion"]
        XCTAssertTrue(scrollTo(requestsToggle, in: app), app.debugDescription)
        requestsToggle.tap()
        scrollToTop(app)
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
        XCTAssertTrue(scrollTo(toggle, in: app), app.debugDescription)
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
