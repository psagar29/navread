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
    private static let resourceBundleName = "NavRead_NavRead.bundle"

    static var templateImage: NSImage? {
        loadImage(named: "NavReadLogoTemplate", withExtension: "png", template: true)
    }

    static var appIconImage: NSImage? {
        loadImage(named: "AppIconBase", withExtension: "png", template: false)
    }

    private static func loadImage(named name: String, withExtension fileExtension: String, template: Bool) -> NSImage? {
        for bundle in candidateBundles {
            guard let url = bundle.url(forResource: name, withExtension: fileExtension),
                  let image = NSImage(contentsOf: url) else { continue }
            image.isTemplate = template
            return image
        }
        return nil
    }

    private static var candidateBundles: [Bundle] {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let sidecarCandidates = [
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
            executableURL.deletingLastPathComponent().appendingPathComponent(resourceBundleName)
        ].compactMap { $0 }

        var bundles = [Bundle.main]
        var seenPaths = Set(bundles.map(\.bundlePath))

        for url in sidecarCandidates {
            guard let bundle = Bundle(url: url), seenPaths.insert(bundle.bundlePath).inserted else { continue }
            bundles.append(bundle)
        }

        return bundles
    }
}
