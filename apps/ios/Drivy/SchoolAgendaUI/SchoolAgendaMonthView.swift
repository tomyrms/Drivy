import SwiftUI

/// Leçons d’un jour, sans texte : celles qui ont lieu, celles annulées ou manquées.
struct SchoolAgendaDaySummary: Equatable, Sendable {
    var active = 0
    var closed = 0
    var courseActive = 0
    var courseClosed = 0
    var courseDraft = 0
    var isComplete = true

    static let empty = SchoolAgendaDaySummary()

    var lessonCount: Int { active + closed }
    var courseCount: Int { courseActive + courseClosed + courseDraft }
    var total: Int { lessonCount + courseCount }
    var marks: [SchoolAgendaDayMark] {
        SchoolAgendaMonth.marks(active: active + courseActive, closed: closed + courseClosed, provisional: courseDraft)
    }
    /// Des événements visibles, jamais une promesse de disponibilité.
    var spokenCount: String {
        var parts: [String] = []
        if lessonCount > 0 { parts.append(lessonCount == 1 ? "1 leçon" : "\(lessonCount) leçons") }
        if courseCount > 0 { parts.append(courseCount == 1 ? "1 séance collective" : "\(courseCount) séances collectives") }
        if courseDraft > 0 { parts.append(courseDraft == 1 ? "dont 1 brouillon" : "dont \(courseDraft) brouillons") }
        if courseClosed > 0 { parts.append(courseClosed == 1 ? "dont 1 séance annulée" : "dont \(courseClosed) séances annulées") }
        if !isComplete { parts.append("Agenda incomplet") }
        return parts.joined(separator: ", ")
    }
}

/// Marques d’activité d’un jour, communes à la semaine et au mois : un point plein par leçon,
/// un point évidé pour une leçon annulée ou manquée, un trait allongé au-delà de trois.
/// La forme change, pas seulement la couleur ; la ligne garde sa hauteur même vide.
struct SchoolAgendaDayDots: View {
    let marks: [SchoolAgendaDayMark]
    /// Sur l’aplat du jour choisi : l’encre passe en blanc.
    var onFill = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeInk: Color { onFill ? DrivyTheme.onAccent : DrivyTheme.accent }
    private var closedInk: Color { onFill ? DrivyTheme.onAccent : DrivyTheme.muted }

    var body: some View {
        HStack(spacing: DrivySpacing.xxs) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                markView(mark)
            }
        }
        .frame(height: 5)
        // Les marques arrivent avec la lecture sans clignoter : un fondu bref.
        .animation(DrivyMotion.feedback(reduceMotion), value: marks)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func markView(_ mark: SchoolAgendaDayMark) -> some View {
        switch mark {
        case .active:
            Circle().fill(activeInk).frame(width: 5, height: 5)
        case .closed:
            Circle().strokeBorder(closedInk, lineWidth: 1).frame(width: 5, height: 5)
        case .provisional:
            Rectangle().strokeBorder(closedInk, lineWidth: 1).frame(width: 5, height: 5)
        case .more:
            Capsule().fill(activeInk).frame(width: 11, height: 5)
        }
    }
}

/// Le mois de l’agenda : sept colonnes, lundi d’abord, six semaines toujours (la hauteur ne saute
/// jamais d’un mois à l’autre). Aujourd’hui en bleu, le jour choisi plein, comme la bande de la semaine.
/// Un glissement horizontal change de mois ; les flèches de l’en-tête font de même pour VoiceOver.
struct SchoolAgendaMonthGrid: View {
    let calendar: Calendar
    let selectedDate: Date
    /// Sens du dernier changement de mois : +1, le mois suivant arrive par la droite.
    let step: Int
    let summary: @MainActor (Date) -> SchoolAgendaDaySummary
    let select: @MainActor (Date) -> Void
    let moveMonth: @MainActor (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var monthStart: Date { SchoolAgendaMonth.startOfMonth(for: selectedDate, calendar: calendar) }

    var body: some View {
        VStack(spacing: DrivySpacing.xxs) {
            weekdayHeader
            ZStack(alignment: .top) {
                page
                    .id(monthStart)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .padding(DrivySpacing.xxs)
        .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content + DrivySpacing.xxs))
        .contentShape(Rectangle())
        .simultaneousGesture(swipe)
        // La grille est un sélecteur : le même léger retour que la bande de la semaine.
        .sensoryFeedback(.selection, trigger: selectedDate)
        // Sept colonnes ne s’élargissent pas : au-delà, la grille grandit en hauteur seulement
        // et chaque jour garde sa lecture complète (VoiceOver, loupe des grands caractères).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agenda-month-grid")
    }

    /// Initiales des jours, lundi d’abord, dans la langue du calendrier de l’école.
    private var weekdayHeader: some View {
        HStack(spacing: DrivySpacing.xxs) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, DrivySpacing.xs)
        .accessibilityHidden(true)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let first = (calendar.firstWeekday - 1 + 7) % 7
        return Array(symbols[first...] + symbols[..<first])
    }

    private var page: some View {
        let days = SchoolAgendaMonth.gridDays(for: selectedDate, calendar: calendar)
        return VStack(spacing: DrivySpacing.xxs) {
            ForEach(Array(stride(from: 0, to: days.count, by: 7)), id: \.self) { offset in
                HStack(spacing: DrivySpacing.xxs) {
                    ForEach(days[offset..<min(offset + 7, days.count)], id: \.self) { day in
                        dayButton(day)
                    }
                }
            }
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(day)
        let inMonth = SchoolAgendaMonth.isSameMonth(day, selectedDate, calendar: calendar)
        let daySummary = summary(day)
        return Button { select(day) } label: {
            SchoolAgendaMonthDayCell(number: String(calendar.component(.day, from: day)),
                isSelected: selected, isToday: today, isInMonth: inMonth, marks: daySummary.marks)
        }
        .buttonStyle(AgendaDayButtonStyle())
        // « Aujourd’hui » ne se lit pas qu’à la couleur du chiffre.
        .accessibilityLabel(label(for: day, today: today))
        .accessibilityValue(daySummary.spokenCount)
        .accessibilityIdentifier(SchoolAgendaMonth.dayIdentifier(day, calendar: calendar))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityShowsLargeContentViewer()
    }

    private func label(for day: Date, today: Bool) -> String {
        let date = SchoolDateFormat.template("EEEE d MMMM", day, zone: calendar.timeZone.identifier)
        return today ? "Aujourd’hui, \(date)" : date
    }

    /// Le mois suivant glisse à peine depuis son côté et apparaît en fondu ; l’ancien s’efface sur place.
    /// La sortie ne dépend pas du sens : elle reste juste quand on change de direction.
    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .offset(x: CGFloat(step) * 28).combined(with: .opacity), removal: .opacity)
    }

    /// Glissement franchement horizontal : le défilement vertical de la page reste libre.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                moveMonth(dx < 0 ? 1 : -1)
            }
    }
}

/// Un jour de la grille : même famille que la bande de la semaine (chiffre, marques, aplat du jour choisi).
/// Les jours des mois voisins restent lisibles et touchables, en encre secondaire.
private struct SchoolAgendaMonthDayCell: View {
    let number: String
    let isSelected: Bool
    let isToday: Bool
    let isInMonth: Bool
    let marks: [SchoolAgendaDayMark]
    /// 44 pt au moins avec le texte par défaut ; grandit avec la taille du texte.
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 48

    private var numberInk: Color {
        if isSelected { return DrivyTheme.onAccent }
        if isToday { return DrivyTheme.accent }
        return isInMonth ? DrivyTheme.text : DrivyTheme.textTertiary
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
        VStack(spacing: DrivySpacing.xxs) {
            Text(number)
                .font(.body.weight(isSelected || isToday ? .bold : .regular).monospacedDigit())
                .foregroundStyle(numberInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            SchoolAgendaDayDots(marks: marks, onFill: isSelected)
        }
        .frame(maxWidth: .infinity, minHeight: max(height, DrivyLayout.tapTarget))
        .background(isSelected ? DrivyTheme.accentFill : Color.clear, in: shape)
        .contentShape(shape)
    }
}
