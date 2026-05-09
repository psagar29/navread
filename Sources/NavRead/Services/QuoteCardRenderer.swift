import AppKit
import Foundation

enum QuoteCardFormat: String, CaseIterable, Identifiable {
    case square
    case story
    case landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square: "Square"
        case .story: "Story"
        case .landscape: "Landscape"
        }
    }

    var size: NSSize {
        switch self {
        case .square: NSSize(width: 1080, height: 1080)
        case .story: NSSize(width: 1080, height: 1920)
        case .landscape: NSSize(width: 1600, height: 900)
        }
    }
}

enum SocialShareDestination: String, CaseIterable, Identifiable {
    case system
    case x
    case whatsapp
    case instagram
    case youtube
    case messages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Share Sheet"
        case .x: "X / Twitter"
        case .whatsapp: "WhatsApp"
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .messages: "Messages"
        }
    }

    var icon: String {
        switch self {
        case .system: "square.and.arrow.up"
        case .x: "xmark"
        case .whatsapp: "message"
        case .instagram: "camera"
        case .youtube: "play.rectangle"
        case .messages: "bubble.left.and.bubble.right"
        }
    }
}

enum QuoteCardRenderer {
    static func render(quote: Quote, book: Book, format: QuoteCardFormat) -> URL? {
        do {
            try LibraryPaths.ensure()
            let image = drawCard(quote: quote, book: book, format: format)
            guard let png = pngData(from: image) else { return nil }
            let url = LibraryPaths.cards.appendingPathComponent("\(quote.id.uuidString)-\(format.rawValue).png")
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func render(savedQuote: SavedQuote, format: QuoteCardFormat) -> URL? {
        do {
            try LibraryPaths.ensure()
            let image = drawCard(savedQuote: savedQuote, format: format)
            guard let png = pngData(from: image) else { return nil }
            let url = LibraryPaths.cards.appendingPathComponent("saved-\(savedQuote.id.uuidString)-\(format.rawValue).png")
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func drawCard(quote: Quote, book: Book, format: QuoteCardFormat) -> NSImage {
        let size = format.size
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()

        let inset = size.width * 0.07
        let cardRect = NSRect(
            x: inset,
            y: inset,
            width: size.width - inset * 2,
            height: size.height - inset * 2
        )
        let radius = size.width * 0.045
        let path = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
        NSColor(white: 0.965, alpha: 1).setFill()
        path.fill()
        NSColor(white: 0, alpha: 0.14).setStroke()
        path.lineWidth = 2
        path.stroke()

        let inner = cardRect.insetBy(dx: size.width * 0.06, dy: size.width * 0.06)
        drawBrand(in: inner, size: size)

        let quoteFontSize = fontSize(for: quote.text, format: format)
        let quoteRect = NSRect(
            x: inner.minX,
            y: inner.minY + inner.height * 0.32,
            width: inner.width,
            height: inner.height * 0.48
        )
        draw(
            text: quote.text.quoted,
            in: quoteRect,
            font: NSFont(descriptor: NSFontDescriptor.preferredFontDescriptor(forTextStyle: .title1).withDesign(.serif) ?? NSFontDescriptor(), size: quoteFontSize) ?? .systemFont(ofSize: quoteFontSize, weight: .semibold),
            color: .black,
            alignment: .left,
            lineHeight: quoteFontSize * 1.18
        )

        let meta = [
            book.displayTitle,
            book.displayAuthor,
            quote.pageLocator
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " / ")
        draw(
            text: meta,
            in: NSRect(x: inner.minX, y: inner.minY + inner.height * 0.16, width: inner.width * 0.78, height: 80),
            font: .systemFont(ofSize: size.width * 0.026, weight: .semibold),
            color: NSColor.black.withAlphaComponent(0.78),
            alignment: .left,
            lineHeight: size.width * 0.035
        )

        draw(
            text: "Saved with NavRead",
            in: NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: 48),
            font: .systemFont(ofSize: size.width * 0.018, weight: .medium),
            color: NSColor.black.withAlphaComponent(0.48),
            alignment: .left,
            lineHeight: size.width * 0.024
        )

        return image
    }

    private static func drawCard(savedQuote: SavedQuote, format: QuoteCardFormat) -> NSImage {
        let size = format.size
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()

        let inset = size.width * 0.07
        let cardRect = NSRect(
            x: inset,
            y: inset,
            width: size.width - inset * 2,
            height: size.height - inset * 2
        )
        let radius = size.width * 0.045
        let path = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
        NSColor(white: 0.965, alpha: 1).setFill()
        path.fill()
        NSColor(white: 0, alpha: 0.14).setStroke()
        path.lineWidth = 2
        path.stroke()

        let inner = cardRect.insetBy(dx: size.width * 0.06, dy: size.width * 0.06)
        drawBrand(in: inner, size: size)

        let quoteFontSize = fontSize(for: savedQuote.text, format: format)
        let quoteRect = NSRect(
            x: inner.minX,
            y: inner.minY + inner.height * 0.32,
            width: inner.width,
            height: inner.height * 0.48
        )
        draw(
            text: savedQuote.text.quoted,
            in: quoteRect,
            font: NSFont(descriptor: NSFontDescriptor.preferredFontDescriptor(forTextStyle: .title1).withDesign(.serif) ?? NSFontDescriptor(), size: quoteFontSize) ?? .systemFont(ofSize: quoteFontSize, weight: .semibold),
            color: .black,
            alignment: .left,
            lineHeight: quoteFontSize * 1.18
        )

        let meta = savedQuote.attribution
        draw(
            text: meta,
            in: NSRect(x: inner.minX, y: inner.minY + inner.height * 0.16, width: inner.width * 0.78, height: 80),
            font: .systemFont(ofSize: size.width * 0.026, weight: .semibold),
            color: NSColor.black.withAlphaComponent(0.78),
            alignment: .left,
            lineHeight: size.width * 0.035
        )

        draw(
            text: "Saved with NavRead",
            in: NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: 48),
            font: .systemFont(ofSize: size.width * 0.018, weight: .medium),
            color: NSColor.black.withAlphaComponent(0.48),
            alignment: .left,
            lineHeight: size.width * 0.024
        )

        return image
    }

    private static func drawBrand(in rect: NSRect, size: NSSize) {
        draw(
            text: "NavRead",
            in: NSRect(x: rect.minX, y: rect.maxY - 58, width: rect.width, height: 58),
            font: .systemFont(ofSize: size.width * 0.028, weight: .bold),
            color: NSColor.black.withAlphaComponent(0.86),
            alignment: .left,
            lineHeight: 42
        )
    }

    private static func draw(
        text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment,
        lineHeight: CGFloat
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = max(0, lineHeight - font.pointSize)
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .kern: 0
            ]
        )
        attributed.draw(in: rect)
    }

    private static func fontSize(for text: String, format: QuoteCardFormat) -> CGFloat {
        let base: CGFloat
        switch format {
        case .square: base = 58
        case .story: base = 66
        case .landscape: base = 54
        }
        if text.count > 420 { return base * 0.66 }
        if text.count > 280 { return base * 0.78 }
        if text.count > 160 { return base * 0.9 }
        return base
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private extension String {
    var quoted: String {
        "\"\(self)\""
    }
}
