import AppKit
import SwiftUI

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: value).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255.0
        let green = Double((int >> 8) & 0xFF) / 255.0
        let blue = Double(int & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    /// Lighter variant for light mode accents
    func lightened(by amount: Double = 0.3) -> Color {
        let nsColor = NSColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: Double(hue), saturation: Double(saturation) * 0.7, brightness: min(1, Double(brightness) + amount))
    }

    /// Darker variant for dark mode accents
    func darkened(by amount: Double = 0.2) -> Color {
        let nsColor = NSColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: Double(hue), saturation: min(1, Double(saturation) * 1.2), brightness: max(0, Double(brightness) - amount))
    }
}

extension NSImage {
    func averageHex() -> String {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return "#6C7A58"
        }

        let width = max(1, bitmap.pixelsWide)
        let height = max(1, bitmap.pixelsHigh)
        let stepX = max(1, width / 18)
        let stepY = max(1, height / 18)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var count: CGFloat = 0

        for x in stride(from: 0, to: width, by: stepX) {
            for y in stride(from: 0, to: height, by: stepY) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                count += 1
            }
        }

        guard count > 0 else { return "#6C7A58" }
        let r = Int((red / count) * 255)
        let g = Int((green / count) * 255)
        let b = Int((blue / count) * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension DateFormatter {
    static let navReadShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
