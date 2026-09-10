import Foundation
import os

/// Shared loggers. Categories mirror the service that emits them so `log stream
/// --predicate 'subsystem == "com.windowpin.app"'` stays readable.
enum Log {
    private static let subsystem = "com.windowpin.app"

    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    static let pin = Logger(subsystem: subsystem, category: "pin")
    static let observer = Logger(subsystem: subsystem, category: "observer")
    static let screen = Logger(subsystem: subsystem, category: "screen")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let mirror = Logger(subsystem: subsystem, category: "mirror")
    static let panel = Logger(subsystem: subsystem, category: "panel")
}
