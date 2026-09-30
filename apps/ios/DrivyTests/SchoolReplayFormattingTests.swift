import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolReplayFormattingTests {
    @Test func replayUsesTheLessonZoneIncludingSeasonalOffset() throws {
        let summer = try #require(SchoolLesson.date("2026-09-21T07:00:00Z"))
        let winter = try #require(SchoolLesson.date("2026-01-21T07:00:00Z"))
        let summerLabel = try #require(SchoolReplayFormatting.startLabel(summer, lessonTimeZone: "Europe/Zurich"))
        let winterLabel = try #require(SchoolReplayFormatting.startLabel(winter, lessonTimeZone: "Europe/Zurich"))
        let utcLabel = try #require(SchoolReplayFormatting.startLabel(summer, lessonTimeZone: "UTC"))
        #expect(summerLabel.hasSuffix("09:00"))
        #expect(winterLabel.hasSuffix("08:00"))
        #expect(utcLabel.hasSuffix("07:00"))
    }

    @Test func replayKeepsTheLessonCivilDayAcrossMidnight() throws {
        let instant = try #require(SchoolLesson.date("2026-09-21T23:30:00Z"))
        let label = try #require(SchoolReplayFormatting.startLabel(instant, lessonTimeZone: "Europe/Zurich"))
        #expect(label.hasPrefix("22 "))
        #expect(label.hasSuffix("01:30"))
    }

    @Test func missingDateOrZoneDoesNotInventALocalTime() throws {
        let instant = try #require(SchoolLesson.date("2026-09-21T07:00:00Z"))
        #expect(SchoolReplayFormatting.startLabel(instant, lessonTimeZone: nil) == nil)
        #expect(SchoolReplayFormatting.startLabel(instant, lessonTimeZone: "Invalid/Zone") == nil)
        #expect(SchoolReplayFormatting.startLabel(nil, lessonTimeZone: "Europe/Zurich") == nil)
    }
}
