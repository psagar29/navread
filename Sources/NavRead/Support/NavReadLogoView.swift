import AppKit
import SwiftUI

struct NavReadLogoMark: View {
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let image = NavReadLogo.templateImage {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: "book.pages")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
            }
        }
        .foregroundStyle(.primary)
        .frame(width: size, height: size)
        .accessibilityLabel("NavRead")
    }
}

enum NavReadLogo {
    static var templateImage: NSImage? {
        loadImage(named: "NavReadLogoTemplate", withExtension: "png", template: true)
    }

    static var appIconImage: NSImage? {
        loadImage(named: "AppIconBase", withExtension: "png", template: false)
    }

    private static func loadImage(named name: String, withExtension fileExtension: String, template: Bool) -> NSImage? {
        let bundles = [Bundle.main, Bundle.module]
        for bundle in bundles {
            guard let url = bundle.url(forResource: name, withExtension: fileExtension),
                  let image = NSImage(contentsOf: url) else { continue }
            image.isTemplate = template
            return image
        }
        return nil
    }
}
