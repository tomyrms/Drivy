import Foundation
import Testing
import UIKit
@testable import Drivy

struct SchoolObservationPictogramTests {
    /// Les titres que « Signaler » écrit pour le référentiel fourni aux écoles.
    @Test func everyTitleWrittenBySignalerHasItsOwnPictogram() {
        let expected: [(String, String?, SchoolObservationPictogram)] = [
            ("Maîtrise du véhicule", "vehicule", .vehicle),
            ("Observation et contrôles", "observation", .observation),
            ("Priorité à droite", "priorites", .rightPriority),
            ("Signalisation", "priorites", .signage),
            ("Céder le passage", "priorites", .giveWay),
            ("Intersections et giratoires", "intersections", .intersections),
            ("Vitesse", "vitesse", .speed),
            ("Placement sur la chaussée", "placement", .placement),
            ("Manœuvres", "manoeuvres", .manoeuvres),
            ("Stationnement", "parking", .manoeuvres),
            ("Autoroute", "autoroute", .motorway),
            ("Anticipation", "anticipation", .anticipation),
        ]
        for (title, key, theme) in expected {
            #expect(SchoolObservationPictogram(title: title, competencyKey: key) == theme, "\(title)")
            #expect(SchoolObservationPictogram(title: title) == theme, "\(title) sans compétence")
        }
    }

    @Test func competencyWinsOverAReviewedText() {
        #expect(SchoolObservationPictogram(title: "Trop vite à l’entrée du giratoire", competencyKey: "vitesse") == .speed)
        #expect(SchoolObservationPictogram(title: "Signalisation", competencyKey: "vitesse") == .speed)
    }

    @Test func aFreeNoteBorrowsNoPictogram() {
        #expect(SchoolObservationPictogram(title: "Bonne leçon dans l’ensemble") == nil)
        #expect(SchoolObservationPictogram(title: "Bonne leçon", competencyKey: "inconnue") == nil)
    }

    @Test func everyPictogramAndAppraisalHasAnAsset() {
        let names = SchoolObservationPictogram.allCases.map(\.glyph) + SchoolObservationStatus.allCases.map(\.glyph)
            + [DrivyObservationGlyph.moment]
        for glyph in names {
            guard case .asset(let name) = glyph else { Issue.record("\(glyph) n’est pas un dessin du catalogue"); continue }
            #expect(UIImage(named: name) != nil, "\(name)")
        }
    }
}
