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
            if model.isDropHighlighted { dropHighlight }
        }
        .animation(Theme.transition, value: model.isDropHighlighted)
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
        HStack(spacing: Theme.Space.s) {
            Image(systemName: model.content.symbolName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(model.content.label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Theme.Space.xs)

            if model.mirror.isMirroring {
                IconButton(symbol: "arrow.up.forward.app",
                           label: "Bring the real window to the front") {
                    model.goToMirroredWindow()
                }
            }

            IconButton(symbol: "macwindow.on.rectangle", label: "Mirror a window") {
                Task { await model.presentWindowChooser() }
            }

            if !model.content.isEmpty {
                IconButton(symbol: "xmark", label: "Clear the panel") {
                    Task { await model.clear() }
                }
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xs)
        .background(.bar)
    }

    /// Shown while a drag hovers the panel. A ring alone left the user guessing
    /// whether the panel would actually take what they were holding.
    private var dropHighlight: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.brand.opacity(0.12))
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            Label("Drop to open", systemImage: "arrow.down.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .background(Theme.brand, in: .capsule)
        }
        .padding(Theme.Space.xs)
        .transition(.opacity)
        .allowsHitTesting(false)
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
        VStack(spacing: Theme.Space.m) {
            IconTile(symbol: "arrow.down.doc", tint: Theme.brand, size: 52)

            VStack(spacing: Theme.Space.xs) {
                Text("Drop anything here")
                    .font(.headline)
                Text("A link, image, PDF, video or text.\nLinks stay interactive — you can click and type in them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xl)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .padding(Theme.Space.m)
        }
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
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.xs)
            .background(.black.opacity(0.6), in: .capsule)
            .padding(.bottom, Theme.Space.m)
    }

    /// Navigation failures get the same visible treatment as a failed image or
    /// a failed mirror, rather than leaving a blank page.
    private func webErrorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(Theme.danger)
            .lineLimit(2)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
    }

    /// Covers the mirror until the first frame arrives, and explains it if none
    /// ever does. Which case applies is decided by what macOS actually gives us,
    /// not by guessing up front whether the window is capturable.
    private func waitingOverlay(_ window: MirroredWindow) -> some View {
        VStack(spacing: Theme.Space.m) {
            if model.mirror.windowClosed {
                StatusMessage(symbol: "xmark.rectangle",
                              title: "That window has closed")
                Button("Pick another") { Task { await model.presentWindowChooser() } }
                    .controlSize(.small)
            } else if model.mirror.movedToAnotherDesktop {
                StatusMessage(
                    symbol: "rectangle.on.rectangle.slash",
                    title: "\(window.appName) isn't on this Desktop",
                    message: "macOS only draws the Desktop you're viewing, so there are no frames to mirror from here."
                )
                HStack(spacing: Theme.Space.s) {
                    Button("Show it") { Task { await model.reveal(window) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandFill)
                    Button("Pick another") { Task { await model.presentWindowChooser() } }
                }
                .controlSize(.small)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to \(window.appName)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func message(_ text: String) -> some View {
        StatusMessage(symbol: "exclamationmark.triangle", title: text, tint: Theme.danger)
            .padding(Theme.Space.xl)
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
                .padding(.horizontal, Theme.Space.m)
                .padding(.top, Theme.Space.m)
            }

            if !model.screenRecording.isAuthorized {
                permissionNotice
            } else if candidates.isEmpty {
                StatusMessage(symbol: "macwindow",
                              title: "No windows available to mirror")
                    .padding(Theme.Space.m)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(candidates) { candidate in
                            MirrorCandidateRow(candidate: candidate) {
                                Task { await model.mirror(candidate) }
                            }
                        }
                    }
                    .padding(Theme.Space.s)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                IconTile(symbol: "lock.shield.fill", tint: Theme.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Recording access needed")
                        .font(.callout.weight(.semibold))
                    Text("Required to mirror another app's window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.screenRecording.needsRelaunchNotice {
                Label("After enabling it, quit and reopen Window Pin — macOS only re-reads this permission at launch.",
                      systemImage: "arrow.clockwise.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.pin)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.pin.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.row))
            }

            HStack(spacing: Theme.Space.s) {
                Button("Open Settings") { model.screenRecording.openSettings() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brandFill)
                Button("Recheck") { Task { await model.presentWindowChooser() } }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
        .padding(Theme.Space.m)
    }
}

/// One mirrorable window in the chooser.
private struct MirrorCandidateRow: View {
    let candidate: MirroredWindow
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                if let image = AppIcon.forProcess(candidate.pid) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(candidate.appName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(candidate.displayTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: Theme.Space.xs)

                // Mirroring only produces frames for the Desktop being viewed,
                // so the ones that cannot work say so before they are picked.
                if !candidate.isOnActiveSpace {
                    Text("other Desktop")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .frame(height: Theme.rowHeight)
            .background(hovering ? Theme.surfaceHover : .clear,
                        in: .rect(cornerRadius: Theme.Radius.row))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.transition, value: hovering)
        .accessibilityLabel("Mirror \(candidate.appName), \(candidate.displayTitle)")
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
