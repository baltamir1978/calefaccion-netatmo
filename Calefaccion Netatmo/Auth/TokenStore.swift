//
//  TokenStore.swift
//  Calefaccion Netatmo
//
//  Almacén seguro (Keychain) para los tokens de OAuth de Netatmo.
//  Usa un access group compartido para que la extensión de widgets lea los mismos tokens.
//

import Foundation
import Security

/// Conjunto de tokens devuelto por el endpoint de OAuth.
struct TokenBundle: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    /// Margen de seguridad: se considera "por expirar" 2 minutos antes.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-120) }
}

/// Persistencia de `TokenBundle` en el Keychain como un único ítem.
struct TokenStore {
    private let service = "com.calefaccionnetatmo.oauth"
    private let account = "netatmo-tokens"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: SharedConfig.keychainAccessGroup,
        ]
    }

    func save(_ bundle: TokenBundle) {
        guard let data = try? JSONEncoder().encode(bundle) else { return }

        let query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func load() -> TokenBundle? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TokenBundle.self, from: data)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
