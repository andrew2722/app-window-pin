import CoreGraphics
import Foundation

/// What survives a relaunch: which app/window was pinned, the frame it was
/// held at, and the presets the user last chose.
///
/// Deliberately holds no live references — a saved configuration is a *hint*
/// for re-finding a window, never something that can be acted on directly.
struct PinConfiguration: Codable, Equatable {
    var bundleIdentifier: String?
    var appName: String
    var title: String
    /// Frame in AppKit coordinates.
    var frame: CGRect
    var displayUUID: String?
    var position: PositionPreset?
    var size: SizePreset
    /// Whether a pin was active when the app last quit. Used only to offer
    /// restoring it — never to move a window automatically at launch.
    var wasPinned: Bool
}

/// Reads and writes the saved configuration as JSON in Application Support.
///
/// A single small file is easier to inspect and delete than `UserDefaults`
/// entries, which matters for a utility that manipulates other people's windows.
enum PinStore {
    private static let directoryName = "WindowPin"
    private static let fileName = "pin-configuration.json"

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func load() -> PinConfiguration? {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let configuration = try JSONDecoder().decode(PinConfiguration.self, from: data)
            Log.store.info("Loaded saved pin for \(configuration.appName, privacy: .public)")
            return configuration
        } catch {
            // A corrupt or outdated file must never stop the app from starting.
            Log.store.error("Could not read saved pin: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func save(_ configuration: PinConfiguration) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: fileURL, options: .atomic)
        } catch {
            Log.store.error("Could not save pin: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
