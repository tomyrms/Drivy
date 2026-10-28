import XCTest
import SwiftUI
@testable import Drivy

/// Menu de sourdine (#168) et zones de toucher du fil (#142). Données synthétiques uniquement.
final class MessagingMuteMenuTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSameDayMuteNamesOnlyTheTime() {
        let label = MessagingMuteFormat.until(now.addingTimeInterval(3_600), now: now, calendar: calendar)
        XCTAssertTrue(label.hasPrefix("En sourdine jusqu'à "), label)
        XCTAssertFalse(label.contains("demain"), label)
    }

    func testNextDayMuteSaysTomorrow() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let label = MessagingMuteFormat.until(tomorrow, now: now, calendar: calendar)
        XCTAssertTrue(label.hasPrefix("En sourdine jusqu'à demain "), label)
    }

    func testLaterMuteNamesTheDate() {
        let later = calendar.date(byAdding: .day, value: 3, to: now)!
        XCTAssertTrue(MessagingMuteFormat.until(later, now: now, calendar: calendar).hasPrefix("En sourdine jusqu'au "))
    }

    func testDurationsAreDatedAndIncreasing() {
        let seconds = MessagingMuteFormat.durations.map(\.seconds)
        XCTAssertEqual(seconds, seconds.sorted())
        XCTAssertTrue(seconds.allSatisfy { $0 > 0 && $0 <= 24 * 3_600 }, "Aucune sourdine sans échéance")
    }

    func testHitAreaReachesTapTargetWithoutOverlappingNeighbours() {
        let chip = CGRect(x: 0, y: 0, width: 34, height: 34)
        let area = MessagingHitArea(dx: 1, minHeight: DrivyLayout.tapTarget).path(in: chip).boundingRect
        XCTAssertEqual(area.height, DrivyLayout.tapTarget, accuracy: 0.001)
        XCTAssertEqual(area.minX, -1, accuracy: 0.001)
        // Voisine posée 2 pt plus loin : les deux zones se touchent sans se recouvrir.
        let neighbour = MessagingHitArea(dx: 1, minHeight: DrivyLayout.tapTarget)
            .path(in: chip.offsetBy(dx: 36, dy: 0)).boundingRect
        XCTAssertLessThanOrEqual(area.maxX, neighbour.minX)
    }

    func testHitAreaNeverShrinksALargeControl() {
        let large = CGRect(x: 0, y: 0, width: 80, height: 60)
        XCTAssertEqual(MessagingHitArea(dx: 0, minHeight: DrivyLayout.tapTarget).path(in: large).boundingRect, large)
    }
}
