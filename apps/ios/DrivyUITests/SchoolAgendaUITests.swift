import XCTest

/// Parcours ciblé #144–#146 : vraies vues, lectures synthétiques, aucune écriture métier.
@MainActor final class SchoolAgendaUITests: XCTestCase {
    private let lessonID = "agenda-event-lesson-10000000-0000-4000-8000-000000000009"

    func testMixedDayUsesOneChronologyAndOpensTheLesson() {
        let app = launch("agenda-mixed")
        defer { app.terminate() }
        let morning = course(at: "09:00", in: app)
        let lesson = app.buttons[lessonID]
        let afternoon = course(at: "14:00", in: app)
        XCTAssertTrue(morning.waitForExistence(timeout: 20), app.debugDescription)
        reveal(afternoon, in: app)
        XCTAssertTrue(lesson.exists, app.debugDescription)
        XCTAssertLessThan(morning.frame.minY, lesson.frame.minY, app.debugDescription)
        XCTAssertLessThan(lesson.frame.minY, afternoon.frame.minY, app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "agenda-course-occurrence").count, 2)
        reveal(lesson, in: app)
        lesson.tap()
        XCTAssertTrue(app.navigationBars["Leçon"].waitForExistence(timeout: 15), app.debugDescription)
        let dossier = app.buttons["lesson-open-dossier"]
        XCTAssertTrue(dossier.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(dossier.label.contains("Camille Perret"), app.debugDescription)
        // La fixture est à 11 h aujourd'hui : son état dépend de l'heure du runner. Planifiée ou en cours, l'en-tête
        // ne dit rien (seul l'inhabituel s'écrit) ; passée, il dit « En attente » ou « À terminer ». Avant ce
        // correctif, le test échouait à chaque passage avant 11 h.
        let state = element("lesson-state", in: app)
        if state.exists {
            XCTAssertTrue(["En attente", "À terminer"].contains(state.label), app.debugDescription)
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "11:00", "12:00")).firstMatch.exists,
            app.debugDescription)
        app.navigationBars["Leçon"].buttons["Fermer"].tap()
        XCTAssertTrue(app.navigationBars["Leçon"].waitForNonExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.segmentedControls["agenda-display-mode"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons[lessonID].isHittable, app.debugDescription)
    }

    func testCollectiveOnlyDayIsCountedInWeekAndMonthAndOpensItsCourse() {
        let app = launch("agenda-mixed-month")
        defer { app.terminate() }
        let day = app.buttons[dayIdentifier(offset: 1)]
        XCTAssertTrue(day.waitForExistence(timeout: 20), app.debugDescription)
        waitForValue("1 séance collective", on: day, in: app)
        reveal(day, in: app)
        day.tap()
        let selected = element("agenda-selected-date", in: app)
        XCTAssertTrue(selected.waitForExistence(timeout: 10), app.debugDescription)
        let selectedLabel = selected.label
        let picker = app.segmentedControls["agenda-display-mode"]
        reveal(picker, in: app, upwards: false)
        picker.buttons["Semaine"].tap()
        let weekDay = app.buttons[dayIdentifier(offset: 1)]
        XCTAssertTrue(weekDay.waitForExistence(timeout: 10), app.debugDescription)
        waitForValue("1 séance collective", on: weekDay, in: app)
        XCTAssertEqual(element("agenda-selected-date", in: app).label, selectedLabel)
        XCTAssertFalse(app.buttons[lessonID].exists)
        let occurrence = course(at: "09:00", in: app)
        reveal(occurrence, in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "agenda-course-occurrence").count, 1)
        occurrence.tap()
        XCTAssertTrue(app.navigationBars["Cours collectif"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Sensibilisation"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    }

    func testEachOccurrenceOfTheSameSeriesOpensItsOwnSelectedSession() {
        let app = launch("agenda-mixed")
        defer { app.terminate() }
        for time in ["14:00", "09:00"] {
            let occurrence = course(at: time, in: app)
            XCTAssertTrue(occurrence.waitForExistence(timeout: 20), app.debugDescription)
            reveal(occurrence, in: app, upwards: time == "14:00")
            occurrence.tap()
            let selected = element("course-selected-occurrence", in: app)
            XCTAssertTrue(selected.waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertTrue(selected.label.contains(time), app.debugDescription)
            XCTAssertTrue(selected.isSelected, app.debugDescription)
            XCTAssertTrue(selected.isHittable, app.debugDescription)
            app.buttons["Fermer"].tap()
            XCTAssertTrue(app.segmentedControls["agenda-display-mode"].waitForExistence(timeout: 15), app.debugDescription)
        }
    }

    func testCourseFailureKeepsLessonsAndRetryRestoresTheMixedDay() {
        let app = launch("agenda-courses-error")
        defer { app.terminate() }
        let failure = element("agenda-courses-error", in: app)
        XCTAssertTrue(failure.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Cours non actualisés")).firstMatch.exists,
            app.debugDescription)
        XCTAssertTrue(app.buttons[lessonID].exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Aucun rendez-vous ce jour"].exists)
        let today = app.buttons[dayIdentifier(offset: 0)]
        waitForValue("Agenda incomplet", on: today, in: app)
        let retry = app.buttons["agenda-courses-retry"]
        reveal(retry, in: app)
        retry.tap()
        XCTAssertTrue(failure.waitForNonExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(course(at: "09:00", in: app).waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons[lessonID].exists)
        waitForValue("2 séances collectives", on: today, in: app)
    }

    func testRefreshFailureRetainsCoursesAndSelectionUntilRetry() {
        let app = launch("agenda-courses-stale")
        defer { app.terminate() }
        XCTAssertTrue(course(at: "09:00", in: app).waitForExistence(timeout: 20), app.debugDescription)
        let selectedLabel = element("agenda-selected-date", in: app).label
        let scroll = app.scrollViews.containing(.button, identifier: lessonID).firstMatch
        XCTAssertTrue(scroll.exists, app.debugDescription)
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.05, thenDragTo: end)
        let failure = element("agenda-courses-error", in: app)
        XCTAssertTrue(failure.waitForExistence(timeout: 15), app.debugDescription)
        let retainedRead = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Dernière lecture réussie")).firstMatch
        XCTAssertTrue(retainedRead.exists, app.debugDescription)
        let retainedDate = retainedRead.label.components(separatedBy: "Dernière lecture réussie").last!
        let wasInterrupted = retainedRead.label.contains("L’actualisation a été interrompue")
        XCTAssertEqual(element("agenda-selected-date", in: app).label, selectedLabel)
        XCTAssertTrue(course(at: "09:00", in: app).exists, app.debugDescription)
        XCTAssertTrue(app.buttons[lessonID].exists)
        let retry = app.buttons["agenda-courses-retry"]
        reveal(retry, in: app)
        retry.tap()
        let loading = element("agenda-courses-loading", in: app)
        let networkFailure = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
            "Cours non actualisés. Réessaie pour retrouver les cours de cette période.")).firstMatch
        // Si le geste a été annulé avant le transport, la première reprise consomme
        // la panne unique de la fixture. La transition doit être réelle, jamais un clic sans effet.
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !loading.exists && (!failure.exists || (wasInterrupted && networkFailure.exists))
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 15), .completed, app.debugDescription)
        if networkFailure.exists {
            XCTAssertTrue(wasInterrupted, app.debugDescription)
            XCTAssertTrue(networkFailure.label.hasSuffix(retainedDate), app.debugDescription)
            XCTAssertEqual(element("agenda-selected-date", in: app).label, selectedLabel)
            XCTAssertEqual(app.buttons.matching(identifier: "agenda-course-occurrence").count, 2)
            XCTAssertTrue(app.buttons[lessonID].exists, app.debugDescription)
            reveal(retry, in: app)
            retry.tap()
        }
        XCTAssertTrue(failure.waitForNonExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(loading.waitForNonExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(failure.exists, app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "agenda-course-occurrence").count, 2)
        XCTAssertEqual(element("agenda-selected-date", in: app).label, selectedLabel)
    }

    func testChangingPeriodDoesNotRetainCoursesOutsideItsScope() {
        let app = launch("agenda-mixed")
        defer { app.terminate() }
        XCTAssertTrue(course(at: "09:00", in: app).waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["agenda-next-period"].tap()
        XCTAssertTrue(app.staticTexts["Aucun rendez-vous ce jour"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "agenda-course-occurrence").count, 0)
        XCTAssertFalse(app.buttons[lessonID].exists)
        XCTAssertFalse(element("agenda-courses-error", in: app).exists)
    }

    private func launch(_ screen: String) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        XCTAssertTrue(app.segmentedControls["agenda-display-mode"].waitForExistence(timeout: 20), app.debugDescription)
        return app
    }

    private func course(at time: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "agenda-course-occurrence", time)).firstMatch
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func dayIdentifier(offset: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let date = calendar.date(byAdding: .day, value: offset, to: Date())!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "agenda-day-%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    private func waitForValue(_ text: String, on element: XCUIElement, in app: XCUIApplication) {
        let ready = expectation(for: NSPredicate(format: "value CONTAINS %@", text), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
}
