import Foundation

/// Formats de date des écrans de terrain, créés une fois par modèle et par fuseau (pas un formateur par ligne).
@MainActor enum SchoolDateFormat {
    private static var formatters: [String: DateFormatter] = [:]

    static func time(_ date: Date, zone: String) -> String { formatter(format: "HH:mm", zone: zone).string(from: date) }
    static func template(_ template: String, _ date: Date, zone: String) -> String {
        formatter(template: template, zone: zone).string(from: date)
    }

    private static func formatter(format: String? = nil, template: String? = nil, zone: String) -> DateFormatter {
        let key = "\(format ?? "")|\(template ?? "")|\(zone)"
        if let cached = formatters[key] { return cached }
        let value = DateFormatter()
        value.locale = Locale(identifier: "fr_CH")
        value.timeZone = TimeZone(identifier: zone) ?? .current
        if let format { value.dateFormat = format }
        if let template { value.setLocalizedDateFormatFromTemplate(template) }
        formatters[key] = value
        return value
    }
}
