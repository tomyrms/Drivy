import SwiftUI
import UIKit

/// Tab icon carrying the attention mark of a pending action: the Drivy accent disc enters the symbol's
/// top-trailing corner and bites it with its halo, as the ring of the « d » bites the trace in the logo.
/// The system tab bar gives no colour to a badge, so the icon is drawn here, once per state.
@MainActor enum DrivyTabIcon {
    /// Proportions of the mark, from the 256 construction grid of the approved concept « Morsure » (C):
    /// centre at 85.6 % / 14.4 % of the symbol box, disc 13.5 %, halo 19 % of its width.
    private static let center = CGPoint(x: 0.856, y: 0.144)
    private static let disc: CGFloat = 0.135
    private static let halo: CGFloat = 0.19
    private static var cache: [String: UIImage] = [:]

    /// Selected: symbol and mark in the accent. At rest: the symbol in the tab bar's ink, the mark in the accent.
    static func image(systemName: String, selected: Bool, scheme: ColorScheme) -> Image {
        let key = "\(systemName):\(selected):\(scheme == .dark)"
        if let cached = cache[key] { return Image(uiImage: cached).renderingMode(.original) }
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let accent = UIColor(DrivyTheme.accent).resolvedColor(with: traits)
        let ink = (selected ? accent : UIColor.label.resolvedColor(with: traits))
        let configuration = UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration)?
                .withTintColor(ink, renderingMode: .alwaysOriginal) else { return Image(systemName: systemName) }
        let size = symbol.size, side = max(size.width, size.height)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            symbol.draw(at: .zero)
            let c = CGPoint(x: size.width * center.x, y: size.height * center.y)
            // The halo removes the symbol around the disc: the bite.
            context.cgContext.setBlendMode(.clear)
            context.cgContext.fillEllipse(in: CGRect(x: c.x - side * halo, y: c.y - side * halo, width: side * halo * 2, height: side * halo * 2))
            context.cgContext.setBlendMode(.normal)
            accent.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: c.x - side * disc, y: c.y - side * disc, width: side * disc * 2, height: side * disc * 2))
        }.withRenderingMode(.alwaysOriginal)
        cache[key] = rendered
        return Image(uiImage: rendered).renderingMode(.original)
    }
}
