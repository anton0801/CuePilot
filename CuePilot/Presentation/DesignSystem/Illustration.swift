import SwiftUI
import UIKit

/// Names of the raster assets from the spec. Everything else (timers, text, charts, statuses) is drawn by UI.
enum ArtAsset {
    static let flickDirector = "cp_flick_director"       // CP04
    static let scriptCards = "cp_script_cards"           // CP05
    static let spotlight = "cp_spotlight"                // CP06
    static let stageTimer = "cp_stage_timer"             // CP07
    static let reviewMarker = "cp_review_marker"         // CP08
    static let notebook = "cp_rehearsal_notebook"        // CP09
    static let comparisonCards = "cp_comparison_cards"   // CP10

    static let onboardingSegments = "cp_onboarding_segments" // CP01 (webp)
    static let onboardingStage = "cp_onboarding_stage"       // CP02 (webp)
    static let onboardingReview = "cp_onboarding_review"     // CP03 (webp)
}

/// Decorative sprite at a fixed point size. Hidden from VoiceOver.
struct Illustration: View {
    let name: String
    let size: CGSize

    init(_ name: String, size: CGSize) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Group {
            if let image = UIImage(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                // Keeps layout stable if an asset is missing.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.paperShade)
                    .overlay(Image(systemName: "sparkles").foregroundColor(Palette.muted))
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// Loads a full-screen WebP background shipped as a bundle resource (UIImage decodes WebP from iOS 14).
enum BundleImage {
    private static var cache: [String: UIImage] = [:]

    static func webp(_ name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let path = Bundle.main.path(forResource: name, ofType: "webp"),
              let image = UIImage(contentsOfFile: path) else {
            return UIImage(named: name)
        }
        cache[name] = image
        return image
    }
}
