import SwiftUI
import UIKit

/// Cadrer la photo de profil avant tout envoi (#156) : le carré vu dans le cercle est exactement l’avatar envoyé.
/// Pincer ou le curseur pour zoomer (jusqu’à quatre fois), glisser pour déplacer ; l’image couvre toujours le cadre.
/// Rien ne part avant « Utiliser » ; « Annuler » garde la photo actuelle.
struct SchoolProfilePhotoCropView: View {
    /// L’image redressée et réduite par `SchoolProfilePhotoEncoder.uprightPreview`, à l’échelle 1 (points = pixels).
    let image: UIImage
    let confirm: (CGRect) -> Void
    let cancel: () -> Void
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat?
    @State private var offset: CGSize = .zero
    @State private var offsetAtGestureStart: CGSize?
    @State private var frameSide: CGFloat = 0

    private var pixelSize: CGSize { CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale) }

    var body: some View {
        NavigationStack {
            VStack(spacing: DrivySpacing.m) {
                GeometryReader { proxy in
                    let side = max(160, min(proxy.size.width, proxy.size.height) - 2 * DrivySpacing.l)
                    let scale = SchoolProfilePhotoEncoder.displayScale(imageSize: pixelSize, frameSide: side, zoom: zoom)
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: pixelSize.width * scale, height: pixelSize.height * scale)
                            .offset(clamped(offset, side: side))
                            .accessibilityHidden(true)
                        mask(side: side)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(drag(side: side).simultaneously(with: magnify(side: side)))
                    .onAppear { frameSide = side }
                    .onChange(of: side) { _, value in frameSide = value }
                }
                .background(Color.black)
                zoomControl
            }
            .background(DrivyTheme.canvas)
            .navigationTitle("Cadrer la photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: cancel)
                        .accessibilityIdentifier("photo-crop-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Utiliser") {
                        confirm(SchoolProfilePhotoEncoder.cropRect(imageSize: pixelSize, frameSide: frameSide, zoom: zoom,
                            offset: clamped(offset, side: frameSide)))
                    }
                    .disabled(frameSide <= 0)
                    .accessibilityIdentifier("photo-crop-confirm")
                }
            }
        }
        .tint(DrivyTheme.accent)
    }

    /// Le cercle de l’avatar sur un voile : ce qui reste clair est ce qui sera envoyé.
    private func mask(side: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.55))
            Circle().frame(width: side, height: side).blendMode(.destinationOut)
        }
        .compositingGroup()
        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1).frame(width: side, height: side))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Le curseur fait la même chose que le pincement, au doigt comme avec VoiceOver.
    private var zoomControl: some View {
        HStack(spacing: DrivySpacing.s) {
            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(DrivyTheme.muted)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { zoom }, set: { value in
                zoom = value
                offset = clamped(offset, side: frameSide)
            }), in: 1...SchoolProfilePhotoEncoder.maxZoom)
                .accessibilityLabel("Zoom")
                .accessibilityValue("\(Int((zoom * 100).rounded())) %")
                .accessibilityIdentifier("photo-crop-zoom")
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(DrivyTheme.muted)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: DrivyLayout.formColumn)
        .padding(.horizontal, DrivySpacing.l)
        .padding(.bottom, DrivySpacing.m)
    }

    private func clamped(_ value: CGSize, side: CGFloat) -> CGSize {
        SchoolProfilePhotoEncoder.clampedOffset(value, imageSize: pixelSize, frameSide: side, zoom: zoom)
    }

    private func drag(side: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = offsetAtGestureStart ?? clamped(offset, side: side)
                if offsetAtGestureStart == nil { offsetAtGestureStart = start }
                offset = clamped(CGSize(width: start.width + value.translation.width,
                                        height: start.height + value.translation.height), side: side)
            }
            .onEnded { _ in offsetAtGestureStart = nil }
    }

    private func magnify(side: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomAtGestureStart ?? zoom
                if zoomAtGestureStart == nil { zoomAtGestureStart = start }
                zoom = min(SchoolProfilePhotoEncoder.maxZoom, max(1, start * value.magnification))
                offset = clamped(offset, side: side)
            }
            .onEnded { _ in zoomAtGestureStart = nil }
    }
}
