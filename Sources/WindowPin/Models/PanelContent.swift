import CoreGraphics
import Foundation

/// A window being mirrored into the floating panel.
struct MirroredWindow: Identifiable, Hashable {
    let windowID: CGWindowID
    /// Owning process — where forwarded input is posted.
    let pid: pid_t
    let appName: String
    let title: String
    /// Size at capture time, used to keep the panel's aspect ratio honest.
    let size: CGSize
    /// Whether the window is on the Desktop the user is currently viewing.
    /// Mirroring only works when this is true — see `WindowVisibility`.
    var isOnActiveSpace: Bool

    var id: CGWindowID { windowID }

    var displayTitle: String {
        title.isEmpty ? appName : title
    }
}

/// What the floating panel is currently showing.
///
/// One panel holds one thing: dropping something new replaces what is there,
/// which is the behaviour a picture-in-picture window wants.
enum PanelContent {
    /// Nothing dropped yet — the panel shows its drop zone.
    case empty
    case image(URL)
    case pdf(URL)
    /// Video or audio, played with `AVKit`.
    case media(URL)
    case text(String)
    /// An interactive web page, loaded in our own web view.
    case web(URL)
    /// Live mirror of another application's window.
    case mirror(MirroredWindow)
    /// The user needs to pick a window to mirror. Reached either by dropping a
    /// URL (macOS hands over the address, not the window it came from) or by
    /// asking for the window picker directly.
    case chooseWindow(candidates: [MirroredWindow], droppedURL: URL?)

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    /// Short label for the panel's title bar.
    var label: String {
        switch self {
        case .empty: "Drop something"
        case .image(let url), .pdf(let url), .media(let url): url.lastPathComponent
        case .text: "Note"
        case .web(let url): url.host() ?? url.absoluteString
        case .mirror(let window): window.displayTitle
        case .chooseWindow: "Choose a window"
        }
    }
}
