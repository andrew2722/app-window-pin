import AppKit
import UniformTypeIdentifiers

/// Turns whatever was dropped on the panel into a `PanelContent`.
///
/// Kept separate from the view so the classification rules are testable and so
/// the panel does not grow pasteboard knowledge.
///
/// `@MainActor` because `NSItemProvider` comes straight off a SwiftUI drop and
/// carries no `Sendable` guarantee; the actual loading is still asynchronous, it
/// just resumes back here.
@MainActor
enum DropIntakeService {
    /// Pasteboard types the panel advertises. File URLs come first: a dragged
    /// file also carries a plain URL representation, and we want the file.
    static let acceptedTypes: [UTType] = [.fileURL, .url, .plainText, .utf8PlainText]

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"
    ]
    private static let mediaExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "mp3", "m4a", "wav", "aac", "flac", "aiff"
    ]

    /// Resolves the first item we understand. Returns `nil` when nothing in the
    /// drop is something the panel can show.
    static func content(from providers: [NSItemProvider]) async -> PanelContent? {
        for provider in providers {
            if let url = await loadFileURL(from: provider) {
                return content(forFile: url)
            }
        }
        for provider in providers {
            if let url = await loadWebURL(from: provider) {
                return .web(url)
            }
        }
        for provider in providers {
            if let text = await loadText(from: provider), !text.isEmpty {
                // A bare URL often arrives as plain text rather than a URL item.
                if let url = URL(string: text), isSafeWebURL(url) {
                    return .web(url)
                }
                return .text(text)
            }
        }
        return nil
    }

    /// Classifies a local file by extension, falling back to its type identifier.
    static func content(forFile url: URL) -> PanelContent {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf(url) }
        if imageExtensions.contains(ext) { return .image(url) }
        if mediaExtensions.contains(ext) { return .media(url) }

        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) { return .pdf(url) }
            if type.conforms(to: .image) { return .image(url) }
            if type.conforms(to: .audiovisualContent) { return .media(url) }
        }

        // Anything else readable as text becomes a note; otherwise show the path.
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return .text(text)
        }
        return .text(url.path)
    }

    // MARK: - Provider loading

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        guard let data = await loadData(from: provider, typeIdentifier: UTType.fileURL.identifier),
              let url = URL(dataRepresentation: data, relativeTo: nil),
              url.isFileURL else { return nil }
        return url
    }

    private static func loadWebURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        guard let data = await loadData(from: provider, typeIdentifier: UTType.url.identifier),
              let url = URL(dataRepresentation: data, relativeTo: nil),
              isSafeWebURL(url) else { return nil }
        return url
    }

    /// Only ordinary web addresses are allowed to reach the web view.
    ///
    /// A drag can carry any scheme it likes. `data:` in particular is loaded and
    /// executed by WebKit as a normal top-level navigation, which would let a
    /// dropped item render attacker-controlled markup inside the panel with no
    /// indication of where it came from.
    static func isSafeWebURL(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        for identifier in [UTType.utf8PlainText.identifier, UTType.plainText.identifier]
        where provider.hasItemConformingToTypeIdentifier(identifier) {
            if let data = await loadData(from: provider, typeIdentifier: identifier),
               let text = String(data: data, encoding: .utf8) {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// `loadDataRepresentation` is callback-based; this adapts it to `await`
    /// and guarantees the continuation resumes exactly once.
    private static func loadData(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
