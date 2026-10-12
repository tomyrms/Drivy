import SwiftUI
import UIKit

/// Tab icon carrying the attention mark of a pending action: the Drivy accent disc enters the symbol's
/// top-trailing corner and bites it with its halo, as the ring of the « d » bites the trace in the logo.
/// The system tab bar gives no colour to a badge, so the icon is drawn here, once per state.
@MainActor enum DrivyTabIcon {
    /// The mark at the size of a tab symbol, from the approved concept « Morsure » (C): one disc size for every
    /// tab, its centre set in from the symbol's top-trailing corner so it enters the drawing, a halo that bites it.
    private static let disc: CGFloat = 3.6
    private static let halo: CGFloat = 5.2
    private static let inset: CGFloat = 3.2
    private static var cache: [String: UIImage] = [:]

    /// Selected: symbol and mark in the accent. At rest: the symbol in the tab bar's ink, the mark in the accent.
    static func image(systemName: String, selected: Bool, scheme: ColorScheme) -> Image {
        let key = "\(systemName):\(selected):\(scheme == .dark)"
        if let cached = cache[key] { return Image(uiImage: cached).renderingMode(.original) }
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let accent = UIColor(DrivyTheme.accent).resolvedColor(with: traits)
        let ink = (selected ? accent : UIColor.label.resolvedColor(with: traits))
        let configuration = UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        // The tab bar draws the filled variant of a symbol: the marked icon must not switch to outlines.
        let filled = UIImage(systemName: systemName + ".fill", withConfiguration: configuration)
        guard let symbol = (filled ?? UIImage(systemName: systemName, withConfiguration: configuration))?
                .withTintColor(ink, renderingMode: .alwaysOriginal) else { return Image(systemName: systemName) }
        let size = symbol.size
        let c = CGPoint(x: size.width - inset, y: inset)
        // The canvas grows by the same margin on every side, so the disc is never cut and the symbol keeps
        // the centre the tab bar gives it.
        let margin = ceil(max(0, halo - inset, halo - inset))
        let canvas = CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            symbol.draw(at: CGPoint(x: margin, y: margin))
            let center = CGPoint(x: c.x + margin, y: c.y + margin)
            // The halo removes the symbol around the disc: the bite.
            context.cgContext.setBlendMode(.clear)
            context.cgContext.fillEllipse(in: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2))
            context.cgContext.setBlendMode(.normal)
            accent.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: center.x - disc, y: center.y - disc, width: disc * 2, height: disc * 2))
        }.withRenderingMode(.alwaysOriginal)
        cache[key] = rendered
        return Image(uiImage: rendered).renderingMode(.original)
    }
}
