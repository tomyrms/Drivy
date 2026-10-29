import Foundation

struct SchoolPlanningPreferenceDraft: Equatable {
    let trainingCategoryCode: String
    let serviceProductKey: String
}

struct SchoolPlanningPreferenceConflict: Identifiable {
    let id = UUID()
    let local: SchoolPlanningPreferenceDraft
    let remote: SchoolPlanningDefaults
}

enum SchoolPlanningPreferenceFormat {
    static func product(_ product: SchoolServiceProduct) -> String {
        let duration = product.durationMinutes.flatMap { $0 > 0 ? SchoolCourseFormat.duration(minutes: $0) : nil }
            ?? "Durée indisponible"
        return "\(product.label) · \(duration) · \(SchoolCatalogFormatting.price(product.unitPriceCents))"
    }

    static func category(_ code: String) -> String { code.isEmpty ? "Aucune préférence" : "Permis \(code)" }

    static func product(key: String, in products: [SchoolServiceProduct]) -> String {
        guard !key.isEmpty else { return "Aucune préférence" }
        guard let product = products.first(where: { $0.productKey == key }) else { return "Tarif indisponible" }
        return Self.product(product)
    }
}
