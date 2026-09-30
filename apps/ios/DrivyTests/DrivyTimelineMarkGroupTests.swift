import Foundation
import Testing
@testable import Drivy

@MainActor
struct DrivyTimelineMarkGroupTests {
    private func mark(_ offset: TimeInterval) -> DrivyTimelineMark {
        DrivyTimelineMark(id: UUID(), offset: offset, symbol: "bookmark", tone: .neutral, label: "Repère")
    }

    @Test func closeObservationsKeepTheirInstantsAndIndependentMenuChoices() {
        let marks = [mark(0), mark(1), mark(5), mark(60), mark(100)]
        let groups = DrivyTimelineMarkGroup.groups(marks, duration: 100, width: 240)
        #expect(groups.first?.marks == Array(marks.prefix(3)))
        #expect(groups.flatMap(\.marks) == marks)
        #expect(groups.first?.position == 0)
        #expect(groups.last?.position == 240)
        #expect(zip(groups, groups.dropFirst()).allSatisfy { pair in pair.1.position - pair.0.position >= 48 })
    }

    @Test func resizingChangesOnlyGroupingAndNeverMovesTheRecordedInstants() {
        let marks = [mark(0), mark(10), mark(50), mark(60), mark(100)]
        let narrow = DrivyTimelineMarkGroup.groups(marks, duration: 100, width: 240)
        let wide = DrivyTimelineMarkGroup.groups(marks, duration: 100, width: 600)
        #expect(narrow.count < wide.count)
        #expect(narrow.flatMap(\.marks) == wide.flatMap(\.marks))
        for group in wide {
            // Keep both operands CGFloat: #expect can select AnyHashable equality
            // for a heterogeneous CGFloat/Double comparison (swiftlang/swift#91221).
            let expectedPosition = CGFloat(group.marks[0].offset / 100) * 600
            #expect(group.position == expectedPosition)
        }
    }

    @Test func zeroDurationAndIdenticalInstantsRemainSelectable() {
        let marks = [mark(0), mark(0), mark(0)]
        let groups = DrivyTimelineMarkGroup.groups(marks, duration: 0, width: 240)
        #expect(groups.count == 1)
        #expect(groups.first?.marks == marks)
        #expect(groups.first?.position == 0)
        #expect(DrivyTimelineMarkGroup.groups([], duration: 0, width: 0).isEmpty)
    }
}
