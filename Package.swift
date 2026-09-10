// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WindowPin",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WindowPin",
            path: "Sources/WindowPin",
            linkerSettings: [
                // These frameworks are reached through SwiftUI wrappers whose
                // superclasses are Objective-C classes (`AVPlayerView`,
                // `PDFView`, `WKWebView`). A Swift `import` alone does not
                // always pull the framework in, and when it does not the app
                // dies at runtime the moment the view is first built:
                //
                //   failed to demangle superclass of VideoPlayerView from
                //   mangled name 'So12AVPlayerViewC'
                //
                // Nothing catches that at compile time, so link them explicitly.
                .linkedFramework("AVKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("PDFKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("ScreenCaptureKit")
            ]
        )
    ]
)
