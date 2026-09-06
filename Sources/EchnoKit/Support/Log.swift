import OSLog

/// Structured logging.
///
/// Wraps `os.Logger` so log lines land in Console.app and in a sysdiagnose under
/// the right subsystem and category.
///
/// - Important: never log a token, a JWT claim set, or a request body. Use
///   ``redacted(_:)`` for anything that might carry one.
public enum Log {

    private static let subsystem = "com.tornotron.echno-ios"

    /// Networking: requests, responses, retries.
    public static let network = Logger(subsystem: subsystem, category: "network")

    /// Auth: sign-in, refresh, keychain, session lifetime.
    public static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Stores: cache reads/writes, invalidation.
    public static let store = Logger(subsystem: subsystem, category: "store")

    /// UI: navigation and presentation.
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Elides all but the first and last few characters of a sensitive value,
    /// so a log line can identify *which* token without leaking it.
    public static func redacted(_ value: String, keeping visible: Int = 4) -> String {
        guard value.count > visible * 2 else { return "***" }
        return "\(value.prefix(visible))…\(value.suffix(visible))"
    }
}
