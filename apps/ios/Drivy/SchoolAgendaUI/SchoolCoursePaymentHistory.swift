import SwiftUI

/// Les écritures confirmées, y compris annulées, restent identifiables. Leur correction conserve la feuille
/// motivée existante ; le menu ne prétend ni encaisser ni rembourser une opération bancaire.
struct SchoolCoursePaymentHistory: View {
    let model: SchoolCourseAttendanceWorkspace
    let row: SchoolCourseSheetRow
    @Binding var reversal: SchoolCourseReversal?
    @State private var correctionOrigin: UUID?
    @AccessibilityFocusState private var focusedPayment: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            ForEach(SchoolCoursePaymentHistoryRules.ordered(row.payments)) { payment in
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    HStack(alignment: .top, spacing: DrivySpacing.s) {
                        summary(payment)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityFocused($focusedPayment, equals: payment.id)
                        if payment.voidedAt == nil && !model.isVoiding(payment.id, in: row) {
                            Menu {
                                Button("Annuler l’enregistrement", systemImage: "arrow.uturn.backward", role: .destructive) {
                                    correctionOrigin = payment.id
                                    reversal = SchoolCourseReversal(kind: .payment(payment.id, payment.amountCents),
                                        enrollmentID: row.enrollmentId, learnerName: row.learnerDisplayName)
                                }
                                .accessibilityIdentifier("course-payment-void")
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(minWidth: DrivyLayout.tapTarget, minHeight: DrivyLayout.tapTarget)
                                    .contentShape(Rectangle())
                            }
                            .disabled(model.rights?.canRecordPayment != true)
                            .accessibilityLabel("Options du règlement de \(SchoolCatalogFormatting.price(payment.amountCents)), \(recordedDate(payment)), \(row.learnerDisplayName)")
                            .accessibilityIdentifier("course-payment-options-\(payment.id.uuidString)")
                        }
                    }
                    if let reason = SchoolCoursePaymentHistoryRules.voidReason(payment) {
                        DisclosureGroup("Motif d’annulation") {
                            Text(reason).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("course-payment-history-\(payment.id.uuidString)")
            }
        }
        .onChange(of: reversal?.id) { previous, current in
            if previous != nil, current == nil, let correctionOrigin {
                // L’écriture reste dans l’historique après annulation : le retour vise toujours son montant.
                focusedPayment = correctionOrigin
                self.correctionOrigin = nil
            }
        }
    }

    private func recordedDate(_ payment: SchoolCoursePayment) -> String {
        SchoolTrainingFormatting.instant(payment.recordedAt, zone: model.timeZone)
    }

    private func summary(_ payment: SchoolCoursePayment) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(SchoolCatalogFormatting.price(payment.amountCents))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(payment.voidedAt == nil ? DrivyTheme.text : DrivyTheme.muted)
            Text(recordedDate(payment)).font(.caption).foregroundStyle(DrivyTheme.muted)
            if let voidedAt = payment.voidedAt {
                Text("Annulé · \(SchoolTrainingFormatting.instant(voidedAt, zone: model.timeZone))")
                    .font(.caption).foregroundStyle(DrivyTheme.muted)
            } else if model.isVoiding(payment.id, in: row) {
                Label("Annulation en cours", systemImage: "clock")
                    .font(.caption).foregroundStyle(DrivyTheme.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum SchoolCoursePaymentHistoryRules {
    static func ordered(_ payments: [SchoolCoursePayment]) -> [SchoolCoursePayment] {
        payments.sorted {
            let first = SchoolLesson.date($0.recordedAt), second = SchoolLesson.date($1.recordedAt)
            if first != second { return (first ?? .distantPast) > (second ?? .distantPast) }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    static func voidReason(_ payment: SchoolCoursePayment) -> String? {
        guard payment.voidedAt != nil, let reason = payment.voidReason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else { return nil }
        return reason
    }
}
