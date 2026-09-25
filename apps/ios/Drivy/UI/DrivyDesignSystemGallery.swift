import SwiftUI

#if DEBUG && targetEnvironment(simulator)

/// Debug-only catalogue of the Cartographie native design system: every token
/// (colors, type roles, spacing, radii) and every shared component in its
/// states, on one scrolling page. Reached through the visual capture screen
/// `design-system`; never compiled into a device or release build.
/// All names and texts are fictitious samples: no real person, school or position.
struct DrivyDesignSystemGallery: View {
    @State private var selectedOption = 0

    init() {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                    colorsSection
                    typographySection
                    spacingSection
                    radiusSection
                    statusSection
                    rowsSection
                    statesSection
                    messagesSection
                    containersSection
                    selectionSection
                    buttonsSection
                    illustrationSection
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Système de design")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Tokens

    private var colorsSection: some View {
        GallerySection(title: "Couleurs") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DrivySpacing.s, alignment: .top)],
                      alignment: .leading, spacing: DrivySpacing.s) {
                ForEach(Self.swatches) { swatch in
                    ColorSwatch(swatch: swatch)
                }
            }
        }
    }

    private var typographySection: some View {
        GallerySection(title: "Typographie") {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                TypeSample(role: ".drivyScreenTitle", usage: "Nom ou date en tête d’un écran de détail") {
                    Text("Lundi 21 septembre").font(.drivyScreenTitle)
                }
                TypeSample(role: ".drivyTitle", usage: "Titre de feuille ou de carte") {
                    Text("Prochaine leçon").font(.drivyTitle)
                }
                TypeSample(role: ".drivySection", usage: "Titre de section") {
                    Text("Ensuite").font(.drivySection)
                }
                TypeSample(role: ".headline", usage: "Titre de ligne") {
                    Text("Séance de conduite").font(.headline)
                }
                TypeSample(role: ".body", usage: "Texte courant") {
                    Text("Le bilan reprend les observations de la leçon.").font(.body)
                }
                TypeSample(role: ".subheadline", usage: "Méta d’une ligne") {
                    Text("Permis B · 1 h 30").font(.subheadline)
                }
                TypeSample(role: ".footnote / .caption", usage: "Aide et précisions") {
                    Text("Enregistré sur cet appareil.").font(.footnote)
                }
                TypeSample(role: ".monospacedDigit()", usage: "Horaires, durées, prix") {
                    Text("08:30 – 10:00").font(.headline.monospacedDigit())
                }
            }
        }
    }

    private var spacingSection: some View {
        GallerySection(title: "Espacements") {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                ForEach(Self.spacings, id: \.name) { item in
                    HStack(spacing: DrivySpacing.s) {
                        Text("\(item.name) · \(Int(item.value))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(DrivyTheme.text)
                            .frame(minWidth: 72, alignment: .leading)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(DrivyTheme.accent)
                            .frame(width: item.value, height: DrivySpacing.s)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var radiusSection: some View {
        GallerySection(title: "Rayons") {
            HStack(alignment: .top, spacing: DrivySpacing.m) {
                ForEach(Self.radii, id: \.name) { item in
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        RoundedRectangle(cornerRadius: item.value, style: .continuous)
                            .fill(DrivyTheme.surfaceMuted)
                            .overlay {
                                RoundedRectangle(cornerRadius: item.value, style: .continuous)
                                    .strokeBorder(DrivyTheme.controlBorder, lineWidth: 1)
                            }
                            .frame(height: 64)
                            .accessibilityHidden(true)
                        Text("\(item.name) · \(Int(item.value))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Components

    private var statusSection: some View {
        GallerySection(title: "États") {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                ForEach(Self.tones, id: \.name) { item in
                    HStack(spacing: DrivySpacing.s) {
                        DrivyStatusBadge(title: item.name, symbol: item.symbol, tone: item.tone)
                        DrivyStatusDot(title: item.dotTitle, tone: item.tone)
                    }
                }
                DrivyStatusBadge(title: "Pastille sans symbole")
                DrivyContextHeader(context: "École de conduite (exemple)", detail: "Lundi 21 septembre")
                HStack(spacing: DrivySpacing.m) {
                    DrivyAvatar(name: "Camille Martin", size: 36)
                    DrivyAvatar(name: "Camille Martin")
                    DrivyAvatar(name: "Camille Martin", isSelected: true)
                    DrivyAvatar(name: "Jean-Luc Perret", size: 60)
                }
            }
        }
    }

    private var rowsSection: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            DrivySectionHeader(title: "En-tête avec action", actionTitle: "Tout voir") {}
            DrivyRowGroup(title: "Lignes de navigation") {
                DrivyNavigationRow(title: "Profil de l’élève", detail: "Permis B · 12 leçons", symbol: "person.crop.circle") {}
                DrivyNavigationRow(title: "Documents", symbol: "doc.text",
                                   badge: DrivyStatusBadge(title: "À compléter", symbol: "exclamationmark.circle", tone: .warning)) {}
                DrivyNavigationRow(title: "Ligne sans symbole") {}
            }
            DrivyRowGroup(title: "Libellé et valeur") {
                DrivyKeyValueRow(title: "Catégorie", value: "Permis B")
                DrivyKeyValueRow(title: "Durée", value: "1 h 30", symbol: "clock", numeric: true)
                DrivyKeyValueRow(title: "Lieu de départ", value: "Place de la Gare, devant l’entrée principale")
            }
            DrivyRowGroup(title: "Colonne horaire") {
                HStack(spacing: DrivySpacing.m) {
                    DrivyTimeColumn(start: "08:30", end: "10:00")
                    Text("Leçon de conduite").font(.headline).foregroundStyle(DrivyTheme.text)
                }
                .padding(.vertical, DrivySpacing.s)
                HStack(spacing: DrivySpacing.m) {
                    DrivyTimeColumn(start: "14:00", end: nil)
                    Text("Sans heure de fin").font(.headline).foregroundStyle(DrivyTheme.text)
                }
                .padding(.vertical, DrivySpacing.s)
            }
        }
    }

    private var statesSection: some View {
        GallerySection(title: "Vide, chargement, erreur") {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                DrivyEmptyState(title: "Aucune leçon ce jour",
                                message: "Les leçons planifiées par l’école apparaîtront ici.",
                                symbol: "calendar",
                                actionTitle: "Voir la semaine") {}
                DrivyEmptyState(title: "État vide sans action",
                                message: "Rien à faire ici pour le moment.")
                DrivyLoadingState(title: "Chargement de l’agenda…")
                SchoolErrorNotice(message: "L’agenda n’a pas pu être chargé. Vérifiez la connexion puis réessayez.") {}
                SchoolErrorNotice(message: "Erreur sans reprise possible.")
                InlineErrorView(message: "L’observation n’a pas encore été enregistrée.") {}
            }
        }
    }

    private var messagesSection: some View {
        GallerySection(title: "Messages en ligne") {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                DrivyInlineMessage(text: "Bilan partagé avec l’élève.")
                DrivyInlineMessage(text: "Le profil est à compléter avant la prochaine leçon.", tone: .warning)
                DrivyInlineMessage(text: "L’invitation n’a pas été envoyée.", tone: .danger)
                DrivyInlineMessage(text: "La séance reste sur cet appareil.", tone: .accent)
                DrivyInlineMessage(text: "Information neutre.", tone: .neutral)
                StorageCaption(message: "Chiffré et enregistré sur cet appareil.")
            }
        }
    }

    private var containersSection: some View {
        GallerySection(title: "Carte et panneau") {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                DrivyCard {
                    VStack(alignment: .leading, spacing: DrivySpacing.s) {
                        DrivyStatusBadge(title: "Prochaine", symbol: "clock", tone: .accent)
                        Text("Leçon de conduite").font(.drivyTitle).foregroundStyle(DrivyTheme.text)
                        Text("08:30 – 10:00 · Place de la Gare")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(DrivyTheme.muted)
                        Button("Commencer la séance") {}
                            .buttonStyle(DrivyPrimaryButtonStyle())
                    }
                }
                DrivyPanel {
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        Text("Panneau").font(.headline).foregroundStyle(DrivyTheme.text)
                        Text("Bloc groupé sur une page de lecture, même anatomie que la carte.")
                            .font(.subheadline)
                            .foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var selectionSection: some View {
        GallerySection(title: "Sélection") {
            VStack(spacing: DrivySpacing.s) {
                ForEach(Self.options.indices, id: \.self) { index in
                    Button {
                        selectedOption = index
                    } label: {
                        HStack(spacing: DrivySpacing.m) {
                            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                Text(Self.options[index].title).font(.headline).foregroundStyle(DrivyTheme.text)
                                Text(Self.options[index].detail).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            }
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DrivySpacing.xs)
                            DrivySelectionMark(isSelected: selectedOption == index)
                        }
                    }
                    .buttonStyle(DrivySelectionCardStyle(isSelected: selectedOption == index))
                }
            }
        }
    }

    private var buttonsSection: some View {
        GallerySection(title: "Boutons") {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                Button("Action principale") {}
                    .buttonStyle(DrivyPrimaryButtonStyle())
                Button("Action principale désactivée") {}
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(true)
                Text("Une action désactivée est toujours accompagnée de sa raison.")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Action secondaire") {}
                    .buttonStyle(DrivySecondaryButtonStyle())
                Button("Action secondaire désactivée") {}
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .disabled(true)
                DrivyRetryButton {}
                Button {
                } label: {
                    VStack(spacing: DrivySpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .accessibilityHidden(true)
                        Text("Tuile de signalement")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(DrivyTheme.warning)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .padding(DrivySpacing.s)
                    .background(DrivyTheme.warningSurface,
                                in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                }
                .buttonStyle(DrivyTileButtonStyle())
            }
        }
    }

    private var illustrationSection: some View {
        GallerySection(title: "Carte et tracé") {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous)
                        .fill(DrivyTheme.surfaceMuted)
                    DrivyRouteGlyph()
                        .padding(DrivySpacing.l)
                    Button {
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DrivyTheme.accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .drivyMapControl(in: Circle())
                    .accessibilityLabel("Suivre la position")
                    .padding(DrivySpacing.s)
                }
                .frame(height: 180)
                Text("Tracé schématique : illustration, jamais une position enregistrée. Liquid Glass réservé aux commandes posées sur la carte.")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Sample data

    private static let swatches: [GallerySwatch] = [
        GallerySwatch(name: "canvas", role: "Fond des formulaires", color: DrivyTheme.canvas),
        GallerySwatch(name: "surface", role: "Page de lecture", color: DrivyTheme.surface),
        GallerySwatch(name: "surfaceMuted", role: "Remplissage discret", color: DrivyTheme.surfaceMuted),
        GallerySwatch(name: "text", role: "Texte principal", color: DrivyTheme.text),
        GallerySwatch(name: "muted", role: "Texte secondaire", color: DrivyTheme.muted),
        GallerySwatch(name: "accent", role: "Action, lien", color: DrivyTheme.accent),
        GallerySwatch(name: "accentPressed", role: "Action appuyée", color: DrivyTheme.accentPressed),
        GallerySwatch(name: "onAccent", role: "Texte sur accent", color: DrivyTheme.onAccent),
        GallerySwatch(name: "accentSoft", role: "Sélection", color: DrivyTheme.accentSoft),
        GallerySwatch(name: "success", role: "Succès", color: DrivyTheme.success),
        GallerySwatch(name: "successSurface", role: "Fond succès", color: DrivyTheme.successSurface),
        GallerySwatch(name: "warning", role: "Alerte", color: DrivyTheme.warning),
        GallerySwatch(name: "warningSurface", role: "Fond alerte", color: DrivyTheme.warningSurface),
        GallerySwatch(name: "danger", role: "Erreur", color: DrivyTheme.danger),
        GallerySwatch(name: "dangerSurface", role: "Fond erreur", color: DrivyTheme.dangerSurface),
        GallerySwatch(name: "border", role: "Filet", color: DrivyTheme.border),
        GallerySwatch(name: "controlBorder", role: "Bord de contrôle", color: DrivyTheme.controlBorder),
        GallerySwatch(name: "disabledText", role: "Texte désactivé", color: DrivyTheme.disabledText),
        GallerySwatch(name: "disabledSurface", role: "Fond désactivé", color: DrivyTheme.disabledSurface),
        GallerySwatch(name: "route", role: "Tracé", color: DrivyTheme.route),
        GallerySwatch(name: "routeHalo", role: "Halo du tracé", color: DrivyTheme.routeHalo),
    ]

    private static let spacings: [GalleryMetric] = [
        GalleryMetric(name: "xxs", value: DrivySpacing.xxs),
        GalleryMetric(name: "xs", value: DrivySpacing.xs),
        GalleryMetric(name: "s", value: DrivySpacing.s),
        GalleryMetric(name: "m", value: DrivySpacing.m),
        GalleryMetric(name: "l", value: DrivySpacing.l),
        GalleryMetric(name: "xl", value: DrivySpacing.xl),
        GalleryMetric(name: "xxl", value: DrivySpacing.xxl),
    ]

    private static let radii: [GalleryMetric] = [
        GalleryMetric(name: "field", value: DrivyRadius.field),
        GalleryMetric(name: "content", value: DrivyRadius.content),
        GalleryMetric(name: "mapPanel", value: DrivyRadius.mapPanel),
    ]

    private static let tones: [GalleryTone] = [
        GalleryTone(name: "Brouillon", dotTitle: "En attente", symbol: "doc", tone: .neutral),
        GalleryTone(name: "En cours", dotTitle: "GPS actif", symbol: "record.circle", tone: .accent),
        GalleryTone(name: "Partagé", dotTitle: "Enregistré", symbol: "checkmark.circle.fill", tone: .success),
        GalleryTone(name: "À compléter", dotTitle: "Signal faible", symbol: "exclamationmark.triangle.fill", tone: .warning),
        GalleryTone(name: "Annulée", dotTitle: "Hors ligne", symbol: "xmark.octagon.fill", tone: .danger),
    ]

    private static let options: [GalleryOption] = [
        GalleryOption(title: "Permis B manuel", detail: "Option sélectionnée"),
        GalleryOption(title: "Permis B automatique", detail: "Option non sélectionnée"),
    ]
}

private struct GalleryMetric {
    let name: String
    let value: CGFloat
}

private struct GalleryTone {
    let name: String
    let dotTitle: String
    let symbol: String
    let tone: DrivyTone
}

private struct GalleryOption {
    let title: String
    let detail: String
}

private struct GallerySwatch: Identifiable {
    let name: String
    let role: String
    let color: Color
    var id: String { name }
}

private struct GallerySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            DrivySectionHeader(title: title)
            content
        }
    }
}

private struct ColorSwatch: View {
    let swatch: GallerySwatch

    var body: some View {
        HStack(spacing: DrivySpacing.s) {
            RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
                .fill(swatch.color)
                .overlay {
                    RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
                        .strokeBorder(DrivyTheme.border, lineWidth: 1)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(swatch.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                Text(swatch.role)
                    .font(.caption)
                    .foregroundStyle(DrivyTheme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct TypeSample<Sample: View>: View {
    let role: String
    let usage: String
    @ViewBuilder let sample: Sample

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            sample
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(role) · \(usage)")
                .font(.caption)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#endif
