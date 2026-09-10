import AVKit
import PDFKit
import SwiftUI

/// Contents of the floating panel: a drop zone that becomes whatever was
/// dropped into it.
struct PanelRootView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            // Also shown on the empty panel so a link can simply be typed in.
            if showsNavigationBar {
                WebNavigationBar(
                    session: model.web,
                    onSubmit: { Task { await model.submitAddress() } },
                    onMirrorInstead: {
                        Task { await model.presentWindowChooser(droppedURL: model.web.currentURL) }
                    }
                )
                Divider()
            }
            body(for: model.content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
        .overlay {
            if model.isDropHighlighted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(3)
            }
        }
        .onDrop(of: DropIntakeService.acceptedTypes,
                isTargeted: dropHighlightBinding) { providers in
            model.accept(providers: providers)
            return true
        }
    }

    private var showsNavigationBar: Bool {
        switch model.content {
        case .web, .empty: true
        default: false
        }
    }

    private var dropHighlightBinding: Binding<Bool> {
        @Bindable var model = model
        return $model.isDropHighlighted
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text(model.content.label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)

            if model.mirror.isMirroring {
                Button {
                    model.goToMirroredWindow()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Bring the real window to the front to interact with it")
            }

            Button {
                Task { await model.presentWindowChooser() }
            } label: {
                Image(systemName: "macwindow.on.rectangle")
            }
            .help("Mirror a window")

            if !model.content.isEmpty {
                Button {
                    Task { await model.clear() }
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help("Clear")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private func body(for content: PanelContent) -> some View {
        switch content {
        case .empty:
            dropZone
        case .image(let url):
            imageView(url)
        case .pdf(let url):
            PDFDocumentView(url: url)
        case .media(let url):
            VideoPlayer(player: AVPlayer(url: url))
        case .web:
            WebContentView(session: model.web)
                .overlay(alignment: .top) {
                    if let error = model.web.loadError { webErrorBanner(error) }
                }
        case .text(let text):
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        case .mirror:
            mirrorView
        case .chooseWindow(let candidates, let droppedURL):
            WindowChooserView(candidates: candidates, droppedURL: droppedURL)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Drop anything here")
                .font(.callout.weight(.medium))
            Text("A link, image, PDF, video, or text.\nLinks open here and stay interactive.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    @ViewBuilder
    private func imageView(_ url: URL) -> some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            message("Could not read that image.")
        }
    }

    @ViewBuilder
    private var mirrorView: some View {
        if let error = model.mirror.errorMessage {
            message(error)
        } else {
            MirrorSurfaceView(renderer: model.mirror.renderer)
                .overlay(alignment: .bottom) { keyboardHint }
                .overlay {
                    if let window = model.mirror.mirrored, !model.mirror.hasReceivedFrame {
                        waitingOverlay(window)
                    }
                }
        }
    }

    /// Keyboard forwarding is the non-obvious half of the feature, so the panel
    /// says so once instead of leaving the user to discover it.
    private var keyboardHint: some View {
        Text("Keys go through: space ← → f m · click to open the real window")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: .capsule)
            .padding(.bottom, 8)
    }

    /// Navigation failures get the same visible treatment as a failed image or
    /// a failed mirror, rather than leaving a blank page.
    private func webErrorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .lineLimit(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.18))
    }

    /// Covers the mirror until the first frame arrives, and explains it if none
    /// ever does. Which case applies is decided by what macOS actually gives us,
    /// not by guessing up front whether the window is capturable.
    private func waitingOverlay(_ window: MirroredWindow) -> some View {
        VStack(spacing: 10) {
            if model.mirror.windowClosed {
                Image(systemName: "xmark.rectangle")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("That window has closed")
                    .font(.callout.weight(.medium))
                Button("Pick another") { Task { await model.presentWindowChooser() } }
                    .font(.caption)
            } else if model.mirror.movedToAnotherDesktop {
                Image(systemName: "rectangle.on.rectangle.slash")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("\(window.appName) isn't on this Desktop")
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("macOS only draws the Desktop you're viewing, so there are no frames to mirror from here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Show it") { Task { await model.reveal(window) } }
                        .buttonStyle(.borderedProminent)
                    Button("Pick another") { Task { await model.presentWindowChooser() } }
                }
                .font(.caption)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to \(window.appName)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Picker shown after a URL drop, or when the user asks to mirror a window.
private struct WindowChooserView: View {
    let candidates: [MirroredWindow]
    let droppedURL: URL?

    @Environment(PanelModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let droppedURL {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Currently open")
                        .font(.caption.weight(.semibold))
                    Text(droppedURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Pick the browser window showing this page to mirror it, sessions and all:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            if !model.screenRecording.isAuthorized {
                permissionNotice
            } else if candidates.isEmpty {
                Text("No windows available to mirror.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(candidates) { candidate in
                            Button {
                                Task { await model.mirror(candidate) }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(candidate.appName)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(1)
                                        if !candidate.isOnActiveSpace {
                                            Text("not on this Desktop")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(.quaternary, in: .capsule)
                                        }
                                    }
                                    Text(candidate.displayTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Screen Recording access needed", systemImage: "lock.shield")
                .font(.caption.weight(.semibold))
            Text("Window Pin needs Screen Recording access to mirror another app's window.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.screenRecording.needsRelaunchNotice {
                Text("After enabling it, quit and reopen Window Pin — macOS only re-reads this permission at launch.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Open Settings") { model.screenRecording.openSettings() }
                Button("Recheck") { Task { await model.presentWindowChooser() } }
            }
            .font(.caption)
        }
        .padding(12)
    }
}

/// PDFKit wrapper — `PDFView` handles scrolling, zoom and multi-page on its own.
private struct PDFDocumentView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
