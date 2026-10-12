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

    /// La clé du thème suffit : le dessin ne dépend ni du texte relu, ni de la compétence, ni de l’affichage réglé.
    @Test func everyThemeKeyOfTheCatalogHasItsPictogram() {
        #expect(SchoolObservationPictogram.allCases.count == 15)
        for theme in SchoolObservationThemeCatalog.embedded {
            let pictogram = SchoolObservationPictogram(themeKey: theme.key, title: "Texte réécrit à la relecture")
            #expect(pictogram?.rawValue == theme.key, "\(theme.key)")
            #expect(pictogram?.glyph == .asset("Observation-\(theme.key)"), "\(theme.key)")
            // Sans clé, le titre de la tuile et sa compétence retrouvent le même dessin.
            #expect(SchoolObservationPictogram(title: theme.title, competencyKey: theme.competencyKeys[0])?.rawValue == theme.key, "\(theme.title)")
            #expect(SchoolObservationPictogram(title: theme.title)?.rawValue == theme.key, "\(theme.title) sans compétence")
        }
        #expect(SchoolObservationPictogram(themeKey: "braking", title: "Bonne anticipation", competencyKey: "anticipation") == .braking)
    }

    /// Observations enregistrées avant les clés, ou par une app sans réponse de l’école.
    @Test func observationsWithoutAKeyAreStillRecognised() {
        let expected: [(String, String?, SchoolObservationPictogram)] = [
            ("Clignotants", "observation", .indicators), ("Clignotant oublié en sortie de giratoire", "observation", .indicators),
            ("Distance de sécurité", "vitesse", .followingDistance), ("Freinage", "vehicule", .braking),
            ("Freinage tardif", nil, .braking), ("Changement de voie", "placement", .laneChange),
            ("Changement de voie sans contrôle", nil, .laneChange),
            // Une précision ne sort jamais de sa compétence : le texte relu ne déplace pas le thème.
            ("Freinage tardif avant le giratoire", "intersections", .intersections),
            ("Clignotant oublié", "vitesse", .speed), ("Distance de sécurité", "placement", .placement),
            ("Adaptation de la vitesse", "vitesse", .speed), ("Observation et contrôles", "observation", .observation),
        ]
        for (title, key, theme) in expected {
            #expect(SchoolObservationPictogram(title: title, competencyKey: key) == theme, "\(title)")
        }
        // Une clé inconnue de cette version ne casse rien : compétence et titre reprennent la main.
        #expect(SchoolObservationPictogram(themeKey: "tunnel", title: "Vitesse", competencyKey: "vitesse") == .speed)
        #expect(SchoolObservationPictogram(themeKey: "tunnel", title: "Note libre") == nil)
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
