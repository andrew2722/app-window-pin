import AppKit
import CoreMedia
import CoreVideo
import Observation
import ScreenCaptureKit

/// One frame handed from ScreenCaptureKit's capture queue to the main thread.
///
/// `IOSurfaceRef` is safe to pass between threads — Core Animation is built on
/// exactly this handoff — but it carries no `Sendable` conformance, so the
/// promise is made explicit here rather than scattered at each call site.
struct MirrorFrame: @unchecked Sendable {
    let surface: IOSurfaceRef
}

/// Mirrors another application's window into a layer we own.
///
/// This is the piece that makes real always-on-top possible: instead of trying
/// to raise someone else's window (which macOS has no public API for), we show
/// a live copy inside our own panel, and our own window's level is ours to set.
///
/// ScreenCaptureKit is one-way, so interaction is rebuilt on top of it by
/// `MirrorInputForwarder`: keyboard always, clicks only when the user opts in.
@MainActor
@Observable
final class WindowMirrorService {
    private(set) var mirrored: MirroredWindow?
    private(set) var errorMessage: String?
    /// Set when the mirrored window is producing no frames and is not on the
    /// active Desktop — either it started that way, or it moved there. Without
    /// this the panel would show black, or a frozen image, with no explanation.
    private(set) var movedToAnotherDesktop = false
    /// False until the first frame arrives, so the panel can say "connecting"
    /// rather than showing an empty black rectangle.
    private(set) var hasReceivedFrame = false
    /// The window is gone entirely. Frames stop for this too, but unlike a
    /// Desktop change there is nothing to switch to.
    private(set) var windowClosed = false

    /// Owns the `CALayer` that frames are pushed into. Kept out of observation
    /// so 30 frames a second never trigger a SwiftUI re-render.
    @ObservationIgnored let renderer = MirrorRenderer()

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: MirrorStreamOutput?
    @ObservationIgnored private let sampleQueue = DispatchQueue(label: "com.windowpin.mirror.samples")
    @ObservationIgnored private var lastFrameDate = Date()
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    var isMirroring: Bool { mirrored != nil }

    /// Starts mirroring `window`. Replaces any mirror already running.
    func start(_ window: MirroredWindow) async {
        await stop()
        errorMessage = nil

        do {
            // `onScreenWindowsOnly: false` so a window on another Desktop can
            // still be resolved and the stream attempted. Whether frames
            // actually arrive is what the watchdog reports — refusing here would
            // pre-judge a decision that belongs to macOS.
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            guard let scWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
                errorMessage = "That window is no longer available."
                return
            }

            let configuration = SCStreamConfiguration()
            // Capture at the window's backing size so text stays sharp when the
            // panel is small; `scalesToFit` handles the panel's aspect ratio.
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            configuration.width = Int(scWindow.frame.width * scale)
            configuration.height = Int(scWindow.frame.height * scale)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.showsCursor = false
            configuration.scalesToFit = true
            configuration.queueDepth = 5

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

            let output = MirrorStreamOutput { [weak self] frame in
                Task { @MainActor in
                    guard let self else { return }
                    self.lastFrameDate = Date()
                    self.hasReceivedFrame = true
                    self.renderer.present(frame)
                }
            }
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()

            self.stream = stream
            self.output = output
            self.mirrored = window
            self.movedToAnotherDesktop = false
            self.windowClosed = false
            self.hasReceivedFrame = false
            self.lastFrameDate = Date()
            startWatchdog()
            renderer.setSourceSize(scWindow.frame.size)
            connectInput(to: window)
            // Route forwarded keys to this window rather than whichever one the
            // app used last. Best-effort and never activates the app.
            MirrorInputForwarder.focusWithoutActivating(windowID: window.windowID, pid: window.pid)
            Log.mirror.info("Mirroring \(window.appName, privacy: .public) window #\(window.windowID, privacy: .public)")
        } catch {
            // The overwhelmingly common failure is missing Screen Recording
            // permission, which surfaces here as a generic capture error.
            errorMessage = Self.describe(error)
            Log.mirror.error("Could not start mirror: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() async {
        watchdog?.cancel()
        watchdog = nil
        movedToAnotherDesktop = false
        hasReceivedFrame = false
        windowClosed = false
        guard let stream else {
            mirrored = nil
            return
        }
        self.stream = nil
        self.output = nil
        self.mirrored = nil
        renderer.view.onKey = nil
        renderer.view.onActivateRequest = nil
        renderer.clear()
        do {
            try await stream.stopCapture()
        } catch {
            Log.mirror.debug("stopCapture: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Notices when frames dry up. A window that moves to another Desktop stops
    /// being captured with no error from ScreenCaptureKit at all, so the only
    /// signal is the absence of frames.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let window = self.mirrored, !Task.isCancelled else { return }
                // Frame starvation alone means nothing — an idle window that
                // simply is not changing also stops producing frames.
                guard Date().timeIntervalSince(self.lastFrameDate) > 2 else {
                    self.movedToAnotherDesktop = false
                    self.windowClosed = false
                    continue
                }
                let closed = !WindowVisibility.exists(windowID: window.windowID)
                let moved = !closed && !WindowVisibility.isOnActiveSpace(windowID: window.windowID)
                if closed != self.windowClosed || moved != self.movedToAnotherDesktop {
                    self.windowClosed = closed
                    self.movedToAnotherDesktop = moved
                    Log.mirror.info("Mirror stalled — closed: \(closed, privacy: .public), other Desktop: \(moved, privacy: .public)")
                }
            }
        }
    }

    /// Hooks the renderer's input callbacks up to the mirrored window.
    private func connectInput(to window: MirroredWindow) {
        renderer.view.onKey = { event in
            MirrorInputForwarder.send(key: event, to: window.pid)
        }
        renderer.view.onActivateRequest = {
            MirrorInputForwarder.bringForward(windowID: window.windowID, pid: window.pid)
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamError.errorDomain,
           nsError.code == SCStreamError.userDeclined.rawValue {
            return "Screen Recording permission was declined."
        }
        return "Could not mirror that window: \(error.localizedDescription)"
    }
}

/// Receives sample buffers on ScreenCaptureKit's queue and forwards the
/// underlying surface. Deliberately does no image conversion — handing the
/// `IOSurface` straight to Core Animation avoids a per-frame copy.
private final class MirrorStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onFrame: @Sendable (MirrorFrame) -> Void

    init(onFrame: @escaping @Sendable (MirrorFrame) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // ScreenCaptureKit also emits "idle" and "blank" frames when nothing
        // changed; presenting those would blank the mirror.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }

        onFrame(MirrorFrame(surface: surface))
    }
}
