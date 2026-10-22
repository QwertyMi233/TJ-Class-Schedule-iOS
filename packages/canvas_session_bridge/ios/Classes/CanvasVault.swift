import Foundation
import Security

final class CanvasVault {
    private static let lock = NSRecursiveLock()
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "icu.tjschedule.canvas-session",
        kSecAttrAccount as String: "state-v1"
    ]

    func read() throws -> [String: Any] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = item as? Data,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CanvasFailure("secure_or_config_failed")
        }
        return value
    }

    func update(_ change: (inout [String: Any]) throws -> Void) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var state = try read()
        try change(&state)
        let data = try JSONSerialization.data(withJSONObject: state)
        var attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            attributes.merge(query) { _, value in value }
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw CanvasFailure("secure_or_config_failed") }
        } else if status != errSecSuccess { throw CanvasFailure("secure_or_config_failed") }
    }

    func clear() throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CanvasFailure("secure_or_config_failed") }
    }
}

struct CanvasFailure: Error {
    let code: String
    init(_ code: String) { self.code = code }
}

func canvasMatches(_ record: [String: Any]?, _ config: [String: Any]) -> Bool {
    guard let record = record else { return false }
    return ["tokenId", "accountId", "purpose"].allSatisfy { key in
        guard let first = record[key] as? String, let second = config[key] as? String else { return false }
        return first == second
    }
}
