import SwiftUI

extension MessagingReportStatus {
    fileprivate var tone: DrivyTone {
        switch self {
        case .open: .warning
        case .handled: .success
        case .dismissed: .neutral
        }
    }

    /// Verbe de l'action qui mène à ce statut depuis un autre.
    fileprivate var actionTitle: String {
        switch self {
        case .open: "Rouvrir"
        case .handled: "Marquer comme traité"
        case .dismissed: "Classer sans suite"
        }
    }

    fileprivate var actionSymbol: String {
        switch self {
        case .open: "arrow.uturn.backward"
        case .handled: "checkmark.circle"
        case .dismissed: "archivebox"
        }
    }
}

/// Signalements d'abus des conversations de l'école, pour ses administrateurs seulement (#77).
struct MessagingReportInboxView: View {
    let model: MessagingReportInboxModel

    var body: some View {
        List {
            if let failure = model.failure {
                Section {
                    VStack(alignment: .leading, spacing: DrivySpacing.s) {
                        Label(failure.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(DrivyTheme.text)
                        Button("Réessayer") { Task { await model.load() } }
                            .frame(minHeight: DrivyLayout.tapTarget)
                    }
                    .accessibilityIdentifier("messaging.reports.error")
                }
            }
            if model.reports.isEmpty && !model.loading && model.failure == nil {
                DrivyEmptyState(title: "Aucun signalement", symbol: "checkmark.shield")
                    .drivyClearRow()
                    .accessibilityIdentifier("messaging.reports.empty")
            }
            ForEach(model.reports) { report in
                NavigationLink {
                    MessagingReportDetailView(model: model, reportID: report.id)
                } label: {
                    row(report)
                }
                .drivyPlainRows()
                .accessibilityIdentifier("messaging.reports.row.\(report.id.uuidString.lowercased())")
            }
            if model.nextCursor != nil {
                Button("Charger plus") { Task { await model.load(more: true) } }
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .disabled(model.loading)
                    .accessibilityIdentifier("messaging.reports.more")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.surface.ignoresSafeArea())
        .overlay {
            if model.loading && model.reports.isEmpty { ProgressView("Chargement") }
        }
        .navigationTitle("Signalements")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    private func row(_ report: MessagingReportRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(report.reporterName ?? "Signalement")
                    .font(.body)
                    .foregroundStyle(DrivyTheme.text)
                Text(summary(report))
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                // La date a sa propre ligne : sur la même ligne que le décompte, elle se coupait au milieu
                // (« 31 / oct. 2026 à 9:36 ») dès que le statut prenait sa place à droite.
                Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
            }
            Spacer(minLength: DrivySpacing.xs)
            DrivyStatusBadge(title: report.status.title, tone: report.status.tone)
        }
        .frame(minHeight: DrivyLayout.tapTarget)
        .accessibilityElement(children: .combine)
    }

    private func summary(_ report: MessagingReportRecord) -> String {
        let count = report.items.count
        let messages = count == 1 ? "1 message" : "\(count) messages"
        return "\(messages) · \(kindTitle(report.conversationKind))"
    }
}

private func sentence(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

private func kindTitle(_ kind: String?) -> String {
    switch kind {
    case "GENERAL": "général"
    case "PRIVATE": "conversation privée"
    default: "conversation"
    }
}

/// Un signalement : les messages choisis (déchiffrés ici), le statut et son historique.
struct MessagingReportDetailView: View {
    let model: MessagingReportInboxModel
    let reportID: UUID

    private var report: MessagingReportRecord? { model.reports.first { $0.id == reportID } }

    var body: some View {
        List {
            if let report {
                Section {
                    labeled("Signalé par", report.reporterName ?? "Personne de l'école")
                    labeled("Conversation", sentence(kindTitle(report.conversationKind)))
                    labeled("Date", report.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                .drivyPlainRows()
                Section("Messages signalés") {
                    if let lines = model.lines[report.id] {
                        ForEach(lines) { line in lineView(line) }
                    } else {
                        ProgressView("Déchiffrement")
                            .accessibilityIdentifier("messaging.reports.decrypting")
                    }
                }
                .drivyPlainRows()
                Section("Statut") {
                    labeled("Statut actuel", report.status.title)
                        .accessibilityIdentifier("messaging.reports.status")
                    if let failure = model.statusFailures[report.id] {
                        Text(failure == .stateConflict ? "Le statut a changé sur un autre appareil. La liste est actualisée."
                                                        : failure.localizedDescription)
                            .foregroundStyle(DrivyTheme.danger)
                            .accessibilityIdentifier("messaging.reports.status.error")
                    }
                    ForEach(MessagingReportStatus.allCases.filter { $0 != report.status }, id: \.self) { status in
                        Button {
                            Task { await model.setStatus(report, to: status) }
                        } label: {
                            Label(status.actionTitle, systemImage: status.actionSymbol)
                        }
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .disabled(model.changing.contains(report.id))
                        .accessibilityIdentifier("messaging.reports.set.\(status.rawValue.lowercased())")
                    }
                }
                .drivyPlainRows()
                if !report.history.isEmpty {
                    Section("Historique") {
                        ForEach(report.history) { event in
                            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                Text("\(event.from.title) vers \(event.to.title)")
                                    .foregroundStyle(DrivyTheme.text)
                                Text("\(event.actorName ?? "Administrateur") · \(event.at.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.subheadline)
                                    .foregroundStyle(DrivyTheme.muted)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .drivyPlainRows()
                }
            } else {
                DrivyEmptyState(title: "Signalement introuvable", symbol: "exclamationmark.bubble")
                    .drivyClearRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.surface.ignoresSafeArea())
        .navigationTitle("Signalement")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reportID) {
            if let report { await model.open(report) }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(DrivyTheme.muted)
            Spacer(minLength: DrivySpacing.s)
            Text(value).foregroundStyle(DrivyTheme.text).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func lineView(_ line: MessagingReportLine) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(line.senderName ?? "Auteur inconnu")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
            if let text = line.text {
                Text(text).foregroundStyle(DrivyTheme.text)
            } else {
                Text(line.unreadable ?? "Ce message ne peut pas être lu sur cet appareil.")
                    .foregroundStyle(DrivyTheme.muted)
            }
            if let date = line.date {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(DrivyTheme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("messaging.reports.line.\(line.id.uuidString.lowercased())")
    }
}
