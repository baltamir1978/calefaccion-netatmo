//
//  AppSettings.swift
//  Calefaccion Netatmo
//
//  Ajustes de la app: credenciales de Netatmo Connect (Keychain) y preferencias (UserDefaults).
//

import Foundation
import Observation
import Security

// MARK: - Credenciales de la app Netatmo Connect

struct NetatmoCredentials: Codable, Equatable {
    var clientID: String
    var clientSecret: String
    var redirectURI: String

    /// Esquema del callback derivado de la redirect URI (parte antes de "://").
    var callbackScheme: String {
        guard let range = redirectURI.range(of: "://") else { return redirectURI }
        return String(redirectURI[..<range.lowerBound])
    }

    var isComplete: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
            && !redirectURI.trimmingCharacters(in: .whitespaces).isEmpty
            && clientID != "TU_CLIENT_ID"
            && clientSecret != "TU_CLIENT_SECRET"
    }

    /// Valores por defecto embebidos en NetatmoConfig.
    static var fallback: NetatmoCredentials {
        NetatmoCredentials(
            clientID: NetatmoConfig.clientID,
            clientSecret: NetatmoConfig.clientSecret,
            redirectURI: NetatmoConfig.redirectURI
        )
    }
}

// MARK: - Almacén de credenciales (Keychain, access group compartido con el widget)

private struct CredentialsStore {
    private let service = "com.calefaccionnetatmo.credentials"
    private let account = "netatmo-credentials"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: SharedConfig.keychainAccessGroup,
        ]
    }

    func save(_ credentials: NetatmoCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
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

    func load() -> NetatmoCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(NetatmoCredentials.self, from: data)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// MARK: - Ajustes observables

@MainActor
@Observable
final class AppSettings {
    /// Credenciales efectivas (guardadas o, en su defecto, las de NetatmoConfig).
    private(set) var credentials: NetatmoCredentials

    /// Duración (minutos) de un ajuste manual de temperatura. 0 = usar la de Netatmo.
    var defaultManualDurationMinutes: Int {
        didSet { defaults.set(defaultManualDurationMinutes, forKey: Keys.duration) }
    }

    /// Casas ocultas en la pantalla de inicio.
    var hiddenHomeIds: Set<String> {
        didSet { defaults.set(Array(hiddenHomeIds), forKey: Keys.hiddenHomes) }
    }

    private let store = CredentialsStore()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let duration = "defaultManualDurationMinutes"
        static let hiddenHomes = "hiddenHomeIds"
    }

    init() {
        credentials = store.load() ?? .fallback
        defaultManualDurationMinutes = defaults.integer(forKey: Keys.duration)
        hiddenHomeIds = Set(defaults.stringArray(forKey: Keys.hiddenHomes) ?? [])
    }

    var hasValidCredentials: Bool { credentials.isComplete }

    func updateCredentials(_ new: NetatmoCredentials) {
        credentials = new
        store.save(new)
    }

    func setHome(_ homeId: String, hidden: Bool) {
        if hidden { hiddenHomeIds.insert(homeId) } else { hiddenHomeIds.remove(homeId) }
    }

    /// Momento de fin (epoch) para un ajuste manual, o nil si se usa la duración de Netatmo.
    func manualEndTime(from now: Date = Date()) -> TimeInterval? {
        guard defaultManualDurationMinutes > 0 else { return nil }
        return now.addingTimeInterval(TimeInterval(defaultManualDurationMinutes * 60)).timeIntervalSince1970
    }
}
