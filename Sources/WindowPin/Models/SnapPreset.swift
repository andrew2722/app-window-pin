import CoreGraphics
import Foundation

/// Where on the display a snapped window sits.
enum PositionPreset: String, CaseIterable, Codable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .center: "Center"
        }
    }
}

/// How large a snapped window is.
///
/// The percentage cases describe *width* only and take the full usable height,
/// which is the behaviour people expect from half/third-screen snapping.
enum SizePreset: Codable, Hashable, CaseIterable, Identifiable {
    case widthFraction(CGFloat)
    /// A tall, narrow window — the shape the "companion window" use case wants.
    case portrait
    /// Keep whatever size the window currently has; only move it.
    case custom

    static var allCases: [SizePreset] {
        [.widthFraction(0.25), .widthFraction(0.33), .widthFraction(0.5), .portrait, .custom]
    }

    /// Default portrait footprint, clamped to the display at layout time.
    static let portraitSize = CGSize(width: 420, height: 700)

    var id: String { label }

    var label: String {
        switch self {
        case .widthFraction(let fraction): "\(Int((fraction * 100).rounded()))% width"
        case .portrait: "Portrait"
        case .custom: "Custom"
        }
    }

    /// Fits the segmented control, where the full label would be truncated.
    var shortLabel: String {
        switch self {
        case .widthFraction(let fraction): "\(Int((fraction * 100).rounded()))%"
        case .portrait: "Portrait"
        case .custom: "Custom"
        }
    }
}
