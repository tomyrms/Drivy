import SwiftUI

/// A short task keeps its natural height. The sheet may grow, and its content
/// still scrolls when the keyboard, a small window or large text needs the room.
/// Put this inside the sheet's NavigationStack, then apply drivyFittedSheet to
/// that stack. Content owns its spacing; do not nest a Form or a lazy container.
struct DrivySheetScrollView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: DrivySheetContentHeight.self,
                                               value: geometry.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: DrivySheetViewportHeight.self,
                                       value: geometry.size.height)
            }
        }
    }
}

extension View {
    /// Measure the real content and navigation/header chrome, not a row count.
    /// Long content can scroll in the compact detent or be expanded by dragging.
    func drivyFittedSheet() -> some View { modifier(DrivyFittedSheet()) }
}

private struct DrivyFittedSheet: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var expanded = false

    // Presentation roles, not text/row heights. The system further clamps a
    // detent to the available window; no screen or device model is assumed.
    private let initialHeight: CGFloat = 320
    private let minimumHeight: CGFloat = 160
    private let maximumCompactHeight: CGFloat = 640

    private var fittedHeight: CGFloat {
        guard contentHeight > 0, viewportHeight > 0, containerHeight > 0 else { return initialHeight }
        let chrome = max(0, containerHeight - viewportHeight)
        return min(maximumCompactHeight, max(minimumHeight, ceil(contentHeight + chrome)))
    }

    private var compactDetent: PresentationDetent { .height(fittedHeight) }
    private var selection: Binding<PresentationDetent> {
        Binding {
            dynamicTypeSize.isAccessibilitySize || expanded ? .large : compactDetent
        } set: { value in
            expanded = value == .large
        }
    }

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(DrivySheetContentHeight.self) { contentHeight = $0 }
            .onPreferenceChange(DrivySheetViewportHeight.self) { viewportHeight = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { containerHeight = $0 }
            .frame(idealHeight: fittedHeight)
            .presentationSizing(.form.fitted(horizontal: false, vertical: true))
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [compactDetent, .large],
                                 selection: selection)
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
    }
}

private struct DrivySheetContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct DrivySheetViewportHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
