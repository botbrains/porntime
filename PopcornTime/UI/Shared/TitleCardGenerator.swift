
import UIKit

/// Generates styled placeholder images with the title text rendered on a gradient background.
/// Used as a fallback when no poster/thumbnail is available from the Jackett feed.
enum TitleCardGenerator {

    /// Generates a title card image with the given title text.
    ///
    /// - Parameters:
    ///   - title: The text to display on the card.
    ///   - size: The desired image size. Defaults to a typical poster aspect ratio.
    /// - Returns: A rendered `UIImage` with the title on a gradient background.
    static func generateTitleCard(for title: String, size: CGSize = CGSize(width: 150, height: 225)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let cgContext = context.cgContext

            // Draw gradient background using a stable color derived from the title
            let hue = CGFloat(abs(title.hashValue) % 360) / 360.0
            let topColor = UIColor(hue: hue, saturation: 0.5, brightness: 0.35, alpha: 1.0)
            let bottomColor = UIColor(hue: hue, saturation: 0.6, brightness: 0.2, alpha: 1.0)

            let colors = [topColor.cgColor, bottomColor.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: size.width / 2, y: 0),
                    end: CGPoint(x: size.width / 2, y: size.height),
                    options: []
                )
            }

            // Draw a subtle film-strip icon at the top
            let iconSize: CGFloat = min(size.width, size.height) * 0.2
            let iconRect = CGRect(
                x: (size.width - iconSize) / 2,
                y: size.height * 0.15,
                width: iconSize,
                height: iconSize
            )
            if let filmIcon = UIImage(systemName: "film") {
                let tinted = filmIcon.withTintColor(UIColor.white.withAlphaComponent(0.3), renderingMode: .alwaysOriginal)
                tinted.draw(in: iconRect)
            }

            // Draw the title text centered in the card
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byWordWrapping

            let fontSize: CGFloat = min(size.width * 0.12, 18)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraphStyle
            ]

            let textInset: CGFloat = size.width * 0.1
            let textRect = CGRect(
                x: textInset,
                y: size.height * 0.35,
                width: size.width - (textInset * 2),
                height: size.height * 0.55
            )

            let nsTitle = title as NSString
            nsTitle.draw(in: textRect, withAttributes: attributes)

            // Draw a subtle bottom bar with seed/size hint area
            let barHeight: CGFloat = size.height * 0.08
            let barRect = CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight)
            UIColor.black.withAlphaComponent(0.3).setFill()
            cgContext.fill(barRect)
        }
    }
}
