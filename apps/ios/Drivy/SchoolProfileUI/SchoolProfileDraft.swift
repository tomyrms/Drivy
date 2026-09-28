import Foundation

struct SchoolProfileDraft: Equatable {
    var firstName = ""
    var lastName = ""
    var birthDate = ""
    var contactEmail = ""
    var contactPhone = ""
    var hasAddress = false
    var address = SchoolPostalAddress(line1: "", line2: nil, postalCode: "", locality: "", countryCode: "")

    init() {}
    init(_ profile: SchoolAdministrativeProfile) {
        firstName = profile.firstName ?? ""; lastName = profile.lastName ?? ""
        birthDate = Self.displayDate(profile.birthDate)
        contactEmail = profile.contactEmail ?? ""; contactPhone = profile.contactPhone ?? ""
        if let value = profile.postalAddress { hasAddress = true; address = value }
    }

    func rebased(on profile: SchoolAdministrativeProfile, changedKeys: Set<String>) -> SchoolProfileDraft {
        var value = SchoolProfileDraft(profile)
        if changedKeys.contains("firstName") { value.firstName = firstName }
        if changedKeys.contains("lastName") { value.lastName = lastName }
        if changedKeys.contains("birthDate") { value.birthDate = birthDate }
        if changedKeys.contains("contactEmail") { value.contactEmail = contactEmail }
        if changedKeys.contains("contactPhone") { value.contactPhone = contactPhone }
        if changedKeys.contains("postalAddress") { value.hasAddress = hasAddress; value.address = address }
        return value
    }

    func changes(from original: SchoolAdministrativeProfile, allowed: Set<SchoolProfileField>) -> [String: SchoolProfileValue] {
        let baseline = SchoolProfileDraft(original)
        var fields: [String: SchoolProfileValue] = [:]
        func text(_ field: SchoolProfileField, _ value: String, _ previous: String) {
            guard allowed.contains(field), value != previous else { return }
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            fields[field.rawValue] = clean.isEmpty ? .null : .text(clean)
        }
        text(.firstName, firstName, baseline.firstName); text(.lastName, lastName, baseline.lastName)
        text(.contactEmail, contactEmail, baseline.contactEmail); text(.contactPhone, contactPhone, baseline.contactPhone)
        if allowed.contains(.birthDate), birthDate != baseline.birthDate {
            fields[SchoolProfileField.birthDate.rawValue] = Self.civilDate(birthDate).map(SchoolProfileValue.text) ?? .null
        }
        if allowed.contains(.postalAddress), hasAddress != baseline.hasAddress || (hasAddress && address != baseline.address) {
            fields[SchoolProfileField.postalAddress.rawValue] = hasAddress ? .address(address) : .null
        }
        // A photo cannot be fabricated from an arbitrary UUID. Upload is a separate document workflow.
        return fields
    }

    func isValid(allowed: Set<SchoolProfileField>, timeZone: String) -> Bool {
        if allowed.contains(.firstName), firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || firstName.unicodeScalars.count > 150 { return false }
        if allowed.contains(.lastName), lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lastName.unicodeScalars.count > 150 { return false }
        if allowed.contains(.contactEmail), !contactEmail.isEmpty {
            let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            if email.unicodeScalars.count > 254 || email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) == nil { return false }
        }
        if allowed.contains(.contactPhone), contactPhone.unicodeScalars.count > 32 { return false }
        if allowed.contains(.postalAddress), hasAddress && !address.isValid { return false }
        if allowed.contains(.birthDate), !birthDate.isEmpty {
            guard let value = Self.civilDate(birthDate) else { return false }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: timeZone)
            formatter.dateFormat = "yyyy-MM-dd"
            if value > formatter.string(from: Date()) { return false }
        }
        return true
    }
    static func civilDate(_ value: String) -> String? {
        guard value.range(of: "^[0-9]{2}\\.[0-9]{2}\\.[0-9]{4}$", options: .regularExpression) != nil else { return nil }
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian); parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "dd.MM.yyyy"; parser.isLenient = false
        guard let date = parser.date(from: value), parser.string(from: date) == value else { return nil }
        parser.dateFormat = "yyyy-MM-dd"; return parser.string(from: date)
    }
    static func displayDate(_ value: String?) -> String {
        guard let value else { return "" }
        let parts = value.split(separator: "-")
        guard parts.count == 3 else { return "" }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }
}

struct SchoolProfilePolicyDraft {
    var effectiveFrom = Date()
    var included: Set<SchoolProfileField> = [.firstName, .lastName]
    var rules: [SchoolProfileRule] = SchoolProfileField.allCases.map { field in
        SchoolProfileRule(field: field, requirement: field.isName ? .required : .optional,
            stage: field.isName ? .join : .optional,
            purposeCode: field.purposes[0],
            explanation: "")
    }
    var selectedRules: [SchoolProfileRule] { rules.filter { included.contains($0.field) } }
    var isValid: Bool {
        included.contains(.firstName) && included.contains(.lastName) && selectedRules.allSatisfy(\.isValid)
    }
}
