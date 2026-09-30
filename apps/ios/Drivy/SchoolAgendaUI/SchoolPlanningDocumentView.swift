import SwiftUI

struct SchoolPlanningDocument: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

struct SchoolPlanningDocumentView: View {
    let document: SchoolPlanningDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DrivySpacing.m)
            }
            .frame(maxWidth: SchoolFormLayout.maxWidth)
            .frame(maxWidth: .infinity)
            .background(DrivyTheme.canvas)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        .tint(DrivyTheme.accent)
    }
}
