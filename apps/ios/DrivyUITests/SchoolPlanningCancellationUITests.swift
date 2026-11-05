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
        try reveal(details, app: app, up: true)
        details.tap() // Un balayage ne développe pas le DisclosureGroup.
        let places = app.descendants(matching: .any).matching(identifier: "planning-meeting-point")
            .matching(NSPredicate(format: "elementType == %d OR elementType == %d",
                XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue))
        let place = places.firstMatch
        try reveal(place, app: app, up: true)
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
            try reveal(agreement, app: app, up: true)
            agreement.tap()
        }
        try reveal(plan, app: app, up: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: plan)], timeout: 5), .completed)
        let cancel = app.buttons["planning-cancel-send"]
        let witness = app.staticTexts["planning-l2-rendezvous"]
        let expectedReads = mode == "me" ? 1 : 0
        let waitingEvidence = "waiting-\(mode)|me=\(expectedReads)|mutations=0"
        let plannedAt = ProcessInfo.processInfo.systemUptime
        print("L2 Planifier : t=0")
        plan.tap()
        // Observer la frontière avant le parcours, puis la relire juste avant le retrait.
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", waitingEvidence), object: witness)], timeout: 5), .completed,
            "Le bouton disponible ne prouve pas que la retenue est atteinte")
        print("L2 waiting : +\(ProcessInfo.processInfo.systemUptime - plannedAt)s, \(waitingEvidence)")
        let reached = try reveal(cancel, app: app, up: false)
        print("L2 Annuler hittable : +\(ProcessInfo.processInfo.systemUptime - plannedAt)s")
        // Le même instantané que le dernier geste évite trois nouvelles traversées AX.
        XCTAssertEqual(reached.first { $0.identifier == "planning-cancel-send" && $0.elementType == .button }?.label, "Annuler l’envoi")
        XCTAssertFalse(reached.contains { $0.elementType == .button && $0.label == "Annuler la leçon" })
        XCTAssertEqual(reached.first { $0.elementType == .button && $0.label == "Fermer" }?.isEnabled, true,
            "Fermer reste une action distincte du retrait")
        XCTAssertEqual(witness.label, waitingEvidence, "Le retrait doit être cliqué pendant la retenue réelle")
        let clickElapsed = ProcessInfo.processInfo.systemUptime - plannedAt
        XCTAssertLessThan(clickElapsed, 25, "Le parcours ne doit pas consommer la borne de la fixture")
        print("L2 clic Annuler : +\(clickElapsed)s, \(waitingEvidence)")
        cancel.tap()
        print("L2 retour du clic : +\(ProcessInfo.processInfo.systemUptime - plannedAt)s")
        let error = app.descendants(matching: .any)["planning-send-cancellation-error"].firstMatch
        if failsRemoval {
            XCTAssertTrue(error.waitForExistence(timeout: 5))
            try reveal(cancel, app: app, up: true)
            XCTAssertTrue(cancel.isEnabled)
            print("L2 réessai du retrait : +\(ProcessInfo.processInfo.systemUptime - plannedAt)s")
            cancel.tap()
        }
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "Seul le retrait réussi rend la saisie disponible")
        XCTAssertFalse(error.exists)
        XCTAssertTrue(app.navigationBars["Planifier une leçon"].exists)
        try reveal(plan, app: app, up: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: plan)], timeout: 5), .completed)
        XCTAssertEqual(witness.label, "removed|me=\(expectedReads)|mutations=0")
        // La section explicitement ouverte doit rendre le vrai champ visible, pas seulement
        // une occurrence AX cachée ou le texte préchargé dans le modèle de fixture.
        try reveal(place, app: app, up: false)
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(place.value as? String, editedPlace)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "L2 saisie conservée — fixture synthétique"
        capture.lifetime = .keepAlways
        add(capture)
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool) throws -> [any XCUIElementSnapshot] {
        let window = app.windows.firstMatch
        // Inclure les fenêtres clavier dans le même relevé, même si UIKit les sépare du Form.
        var snapshot = try app.snapshot()
        var nodes = descendants(of: snapshot)
        if element.exists && element.isHittable { return nodes }
        var movedForm = false
        for direction in [up, !up] {
            for attempt in 0..<10 {
                let form = try XCTUnwrap(nodes.first { $0.elementType == .collectionView },
                    "Le formulaire doit être présent pour défiler")
                let windowSnapshot = try XCTUnwrap(nodes.first { $0.elementType == .window })
                let content = descendants(of: form)
                let viewport = scrollViewport(form: form, window: windowSnapshot, nodes: nodes)
                guard !viewport.isNull, viewport.width >= 44, viewport.height >= 80 else {
                    XCTFail("Aucune zone de formulaire suffisante hors clavier et barres")
                    return nodes
                }
                // Un seul instantané AX : ces lectures de frames/labels sont maintenant locales.
                // Repère unique dans le contenu, proche du centre, plutôt qu'un en-tête fixé en haut.
                let anchors = content.filter {
                    [.staticText, .textField, .textView].contains($0.elementType)
                        && !$0.label.isEmpty && $0.frame.intersects(viewport)
                }.sorted { abs($0.frame.midY - viewport.midY) < abs($1.frame.midY - viewport.midY) }
                let selectedAnchor = anchors.first { candidate in
                    content.filter { sameAnchor($0, candidate) }.count == 1
                }
                if selectedAnchor == nil {
                    attachMissingAnchor(snapshot: snapshot, nodes: nodes, content: content,
                        form: form, window: windowSnapshot, viewport: viewport,
                        up: direction, attempt: attempt + 1)
                }
                let anchor = try XCTUnwrap(selectedAnchor,
                    "Aucun repère unique de contenu visible pour vérifier le défilement")
                let interactiveTypes: [XCUIElement.ElementType] = [
                    .textField, .textView, .secureTextField, .button, .switch, .slider,
                    .picker, .pickerWheel, .datePicker, .stepper, .segmentedControl, .link
                ]
                let controls = content.filter { interactiveTypes.contains($0.elementType) }
                    .map { $0.frame.insetBy(dx: -2, dy: -2) }
                // Chercher une gouttière dont tout le trajet évite les contrôles, champ actif compris.
                // Alterner les deux bords si un geste est absorbé, sans inverser aussitôt le sens.
                let xs = attempt.isMultiple(of: 2)
                    ? [viewport.minX + 4, viewport.maxX - 4, viewport.midX]
                    : [viewport.maxX - 4, viewport.minX + 4, viewport.midX]
                let upper = viewport.minY + 4
                let lower = viewport.maxY - 4
                let x = try XCTUnwrap(xs.first { x in
                    let lane = CGRect(x: x - 2, y: upper, width: 4, height: lower - upper)
                    return !controls.contains { $0.intersects(lane) }
                }, "Aucune gouttière vérifiée hors contrôles interactifs : ne pas envoyer un geste aveugle")
                let startPoint = CGPoint(x: x, y: direction ? lower : upper)
                let endPoint = CGPoint(x: x, y: direction ? upper : lower)
                let origin = window.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(CGVector(dx: startPoint.x - windowSnapshot.frame.minX,
                    dy: startPoint.y - windowSnapshot.frame.minY))
                let end = origin.withOffset(CGVector(dx: endPoint.x - windowSnapshot.frame.minX,
                    dy: endPoint.y - windowSnapshot.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: end)
                snapshot = try app.snapshot()
                nodes = descendants(of: snapshot)
                let nextForm = try XCTUnwrap(nodes.first { $0.elementType == .collectionView })
                let nextAnchor = descendants(of: nextForm).first { sameAnchor($0, anchor) }
                let moved = nextAnchor.map { abs($0.frame.minY - anchor.frame.minY) > 1 } ?? true
                movedForm = movedForm || moved
                print("L2 geste \(direction ? "haut" : "bas") \(attempt + 1)/10 : \(startPoint) -> \(endPoint), zone=\(viewport), repère=\(anchor.label), avant=\(anchor.frame), après=\(String(describing: nextAnchor?.frame)), mouvement=\(moved)")
                if element.exists && element.isHittable {
                    XCTAssertTrue(movedForm, "Atteindre le contrôle après des gestes exige un mouvement réel du formulaire")
                    return nodes
                }
            }
        }
        XCTFail("Le contrôle doit être matérialisé et atteignable après au plus vingt gestes du formulaire")
        return nodes
    }

    /// Uniquement au refus, dans la scène L2 synthétique lancée par exercise ; jamais de requête AX.
    private func attachMissingAnchor(snapshot: any XCUIElementSnapshot, nodes: [any XCUIElementSnapshot],
                                     content: [any XCUIElementSnapshot], form: any XCUIElementSnapshot,
                                     window: any XCUIElementSnapshot, viewport: CGRect, up: Bool, attempt: Int) {
        #if DEBUG && targetEnvironment(simulator)
        let nodeLimit = 200
        let contextLimit = 8
        let stringLimit = 256 // Scalaires Unicode, pas de chaîne arbitrairement longue.
        var truncatedStrings = 0
        var omittedScalars = 0
        func quoted(_ text: String) -> String {
            let count = text.unicodeScalars.count
            if count > stringLimit {
                truncatedStrings += 1
                omittedScalars += count - stringLimit
            }
            let prefix = text.unicodeScalars.prefix(stringLimit).map { String($0) }.joined()
            let escaped = prefix.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"" + escaped + "\""
        }
        var paths: [String] = []
        func collectPaths(_ parent: any XCUIElementSnapshot, path: String) {
            for (index, child) in parent.children.enumerated() {
                guard paths.count < nodeLimit else { return }
                let childPath = path + "/\(index)"
                paths.append(childPath)
                collectPaths(child, path: childPath)
            }
        }
        collectPaths(form, path: "Form") // Même préordre que descendants(of:).
        var candidates = 0
        var uniqueCandidates = 0
        var details: [String] = []
        for (index, node) in content.enumerated() {
            let typeAccepted = [XCUIElement.ElementType.staticText, .textField, .textView].contains(node.elementType)
            let labelAccepted = !node.label.isEmpty
            let intersects = node.frame.intersects(viewport)
            // Calcul sur tout content, même pour les lignes non émises ou hors viewport.
            let matches = content.filter { sameAnchor($0, node) }.count
            let candidate = typeAccepted && labelAccepted && intersects
            if candidate { candidates += 1 }
            if candidate && matches == 1 { uniqueCandidates += 1 }
            if index < nodeLimit {
                let path = index < paths.count ? paths[index] : "chemin local absent"
                details.append("index=\(index) path=\(quoted(path)) type=\(node.elementType.rawValue) id=\(quoted(node.identifier)) label=\(quoted(node.label)) frame=\(node.frame) typeOK=\(typeAccepted) labelOK=\(labelAccepted) intersects=\(intersects) sameAnchorCount=\(matches) candidate=\(candidate)")
            }
        }
        var lines = [
            "L2 synthétique — repère refusé, aucun verdict modifié ; aucune value collectée.",
            "direction=\(up ? "haut" : "bas") gesteÀPréparer=\(attempt)/10",
            "descendants=\(content.count) candidats=\(candidates) candidatsUniques=\(uniqueCandidates)",
            "snapshotFrame=\(snapshot.frame) selectedFormFrame=\(form.frame) selectedWindowFrame=\(window.frame) viewport=\(viewport)",
            "limites: descendants=\(nodeLimit), nœudsParRôle=\(contextLimit), scalairesParChaîne=\(stringLimit)",
            "Détail Form, préordre (les comptes ci-dessus ne sont pas tronqués):"
        ] + details
        var omittedContextNodes = 0
        func context(_ role: String, matching predicate: (any XCUIElementSnapshot) -> Bool) {
            let matches = nodes.enumerated().filter { predicate($0.element) }
            lines.append("\(role): count=\(matches.count)" + (matches.isEmpty ? " ABSENT des données locales" : ""))
            omittedContextNodes += max(0, matches.count - contextLimit)
            for (index, node) in matches.prefix(contextLimit) {
                lines.append("nodes[\(index)] type=\(node.elementType.rawValue) id=\(quoted(node.identifier)) label=\(quoted(node.label)) frame=\(node.frame)")
            }
        }
        context("fenêtres") { $0.elementType == .window }
        context("formulaires") { $0.elementType == .collectionView }
        context("navigation") { $0.elementType == .navigationBar }
        context("clavier") { $0.elementType == .keyboard }
        context("footer") { $0.label == "Rendu de contrôle · données fictives" }
        context("témoin") { $0.identifier == "planning-l2-rendezvous" }
        // Cible du refus Q9 ; ne pas résoudre element pour identifier la requête appelante.
        context("cible Q9 planning-confirm") { $0.identifier == "planning-confirm" }
        let omittedNodes = max(0, content.count - nodeLimit) + omittedContextNodes
        lines.append("troncature: nœudsOmis=\(omittedNodes), chaînesTronquées=\(truncatedStrings), scalairesOmis=\(omittedScalars)")
        lines.append(omittedNodes > 0 || truncatedStrings > 0
            ? "LIMITE DIAGNOSTIQUE : détail tronqué, comptes complets ; échec conservé."
            : "Détail complet dans les limites ; échec conservé.")
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        #else
        let attachment = XCTAttachment(string: "LIMITE DIAGNOSTIQUE : capture réservée à DEBUG simulateur ; échec conservé.")
        #endif
        attachment.name = "L2 — snapshot local au refus du repère (sans value)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("L2 pièce locale demandée ; si absente du résultat, preuve indisponible ; échec inchangé.")
    }

    private func descendants(of snapshot: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
        snapshot.children.flatMap { [$0] + descendants(of: $0) }
    }

    private func sameAnchor(_ lhs: any XCUIElementSnapshot, _ rhs: any XCUIElementSnapshot) -> Bool {
        lhs.elementType == rhs.elementType && lhs.identifier == rhs.identifier && lhs.label == rhs.label
    }

    private func scrollViewport(form: any XCUIElementSnapshot, window: any XCUIElementSnapshot,
                                nodes: [any XCUIElementSnapshot]) -> CGRect {
        let bounds = form.frame.intersection(window.frame)
        guard !bounds.isNull, !bounds.isEmpty else { return .null }
        var top = bounds.minY
        var bottom = bounds.maxY
        let confirmInForm = descendants(of: form).contains { $0.identifier == "planning-confirm" }
        for node in nodes where node.frame.intersects(bounds) {
            if node.elementType == .navigationBar || node.identifier == "planning-l2-rendezvous" {
                top = max(top, node.frame.maxY)
            } else if node.elementType == .keyboard || node.label == "Rendu de contrôle · données fictives"
                        || (!confirmInForm && node.identifier == "planning-confirm") {
                if node.frame.minY > top { bottom = min(bottom, node.frame.minY) }
            }
        }
        guard bottom > top else { return .null }
        // Marge de geste seulement, sans changer aucune dimension du produit.
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top).insetBy(dx: 8, dy: 8)
    }
}
