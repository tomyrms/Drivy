import SwiftUI

/// Défilement dont la hauteur suit celle du contenu, plafonnée par la place offerte : une carte courte reste
/// courte, une carte longue défile. Le contenu n'est instancié qu'une fois, la saisie en cours n'est donc jamais
/// réinitialisée quand le clavier réduit la place.
struct DrivyFittingScrollLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let scroll = subviews.first else { return .zero }
        let ideal = scroll.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let height = proposal.height.map { min(ideal.height, $0) } ?? ideal.height
        return CGSize(width: proposal.width ?? ideal.width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

struct DrivyFittingScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        DrivyFittingScrollLayout {
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
        }
    }
}

/// Carte modale centrée, à poser dans une présentation au fond transparent : l'écran d'origine reste visible et
/// atténué, la hauteur suit le contenu et ne dépasse jamais la zone sûre (clavier compris). En-tête et action
/// principale restent hors du défilement, sauf aux très grandes tailles de texte où l'action rejoint le défilement.
struct DrivyFloatingCard<Content: View, Footer: View>: View {
    let title: String
    var isClosable = true
    let close: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Fond atténué : un toucher à côté ne ferme rien, un geste de travers ne perd aucune saisie.
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                card
                    .frame(maxWidth: DrivyLayout.compactColumn)
                    .frame(maxHeight: max(proxy.size.height - 2 * DrivySpacing.m, 160))
                    .padding(.horizontal, DrivySpacing.m)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var footerStack: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) { footer }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous)
        let footerScrolls = typeSize.isAccessibilitySize
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: DrivySpacing.s) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Fermer", action: close)
                    .buttonStyle(.drivyText)
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .disabled(!isClosable)
                    .accessibilityIdentifier("floating-card-close")
            }
            .padding(.horizontal, DrivySpacing.m)
            .padding(.top, DrivySpacing.xs)
            DrivyFittingScroll {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    content
                    if footerScrolls { footerStack }
                }
                .padding(.horizontal, DrivySpacing.m)
                .padding(.vertical, DrivySpacing.xs)
            }
            if !footerScrolls {
                footerStack
                    .padding(.horizontal, DrivySpacing.m)
                    .padding(.top, DrivySpacing.xs)
                    .padding(.bottom, DrivySpacing.m)
            }
        }
        .background(DrivyTheme.canvas, in: shape)
        .overlay { shape.strokeBorder(contrast == .increased ? DrivyTheme.controlBorder : DrivyTheme.border,
                                      lineWidth: contrast == .increased ? 1 : 0.5) }
        .clipShape(shape)
        .drivyShadow()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { if isClosable { close() } }
    }
}
