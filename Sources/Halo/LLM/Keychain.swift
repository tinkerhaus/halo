import Foundation
import Security

/// Minimal Keychain access for API keys. A key is stored as a generic password
/// under the "Halo" service, keyed by a short `ref` you put in `config.yaml`
/// (`keyRef:`), so the secret itself never lives in the config file.
///
/// Add one from the command line:
///   security add-generic-password -s Halo -a <ref> -w <your-api-key>
/// …or programmatically via `Keychain.set(_:forRef:)` (for a future Settings UI).
enum Keychain {
    private static let service = "Halo"

    /// The stored key for `ref`, or nil if there isn't one. Whitespace-trimmed.
    static func string(forRef ref: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Store (or replace) the key for `ref`. Returns whether it succeeded.
    @discardableResult
    static func set(_ value: String, forRef ref: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]
        SecItemDelete(base as CFDictionary)                     // replace any existing entry
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
