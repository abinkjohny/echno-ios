import Foundation
import Security

/// Stores the session in the Keychain.
///
/// Tokens are bearer credentials: anything holding them is the user until they
/// expire. That rules out `UserDefaults`, a plist or a file in the container,
/// all of which are readable from a backup or a jailbroken device.
///
/// Accessibility is `kSecAttrAccessibleAfterFirstUnlock`, deliberately not the
/// stricter `WhenUnlocked`: the app refreshes tokens from the background, where
/// the device may be locked, and `WhenUnlocked` would fail those reads and end
/// the session. `ThisDeviceOnly` keeps the item out of iCloud Keychain and off
/// any restored backup.
public actor KeychainTokenStore: TokenStoring {

    private let service: String
    private let account: String

    /// - Parameters:
    ///   - service: Keychain service name. Defaults to the app's bundle id so
    ///     two Echno builds on one device do not share a session.
    ///   - account: Distinguishes items within the service.
    public init(
        service: String = Bundle.main.bundleIdentifier ?? "com.tornotron.echno-ios",
        account: String = "keycloak-session"
    ) {
        self.service = service
        self.account = account
    }

    public func load() async throws -> TokenSet? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw AuthError.keychain(status) }
            // A stored blob that no longer decodes means the shape changed under
            // us. Drop it and make the user sign in rather than failing every
            // launch on the same unreadable item.
            guard let tokens = try? JSONDecoder().decode(TokenSet.self, from: data) else {
                Log.auth.warning("Stored session could not be decoded; clearing it")
                try await clear()
                return nil
            }
            return tokens
        case errSecItemNotFound:
            return nil
        default:
            throw AuthError.keychain(status)
        }
    }

    public func save(_ tokens: TokenSet) async throws {
        let data = try JSONEncoder().encode(tokens)

        // Update in place if the item exists; SecItemAdd would return
        // errSecDuplicateItem and the new tokens would be silently dropped.
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AuthError.keychain(addStatus) }
        default:
            throw AuthError.keychain(status)
        }
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        // Deleting something already gone is the desired end state, not an error.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Opts into the modern keychain on macOS too, so the same code path
            // and the same semantics apply when the tests run there.
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
