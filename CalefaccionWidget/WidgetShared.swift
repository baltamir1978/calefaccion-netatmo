//
//  WidgetShared.swift
//  CalefaccionWidget
//
//  Núcleo autocontenido del widget: lee tokens/credenciales del Keychain compartido y la caché
//  del App Group (mismas claves/rutas que la app), y hace las llamadas mínimas a la API Energy.
//

import Foundation
import Security

enum WidgetConfig {
    static let appGroup = "group.Altamirano.Calefaccion-Netatmo"
    static let keychainAccessGroup = "JKMR84FU58.Altamirano.Calefaccion-Netatmo"
    static let apiBase = URL(string: "https://api.netatmo.com")!
    static let scope = "read_thermostat write_thermostat"
}

// MARK: - Modelos espejo (mismas formas Codable que la app)

struct WTokenBundle: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-120) }
}

struct WCredentials: Codable {
    var clientID: String
    var clientSecret: String
    var redirectURI: String
}

struct WCachedHome: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let thermostatRoomId: String?
}

struct WHomeSnapshot: Codable, Hashable {
    let homeId: String
    let currentTemp: Double?
    let targetTemp: Double?
    let boilerOn: Bool
    let mode: String?
    let updatedAt: Date
}

struct WSharedCache: Codable {
    var homes: [WCachedHome]
    var snapshots: [String: WHomeSnapshot]
    static let empty = WSharedCache(homes: [], snapshots: [:])
}

// MARK: - Caché (App Group)

enum WidgetCache {
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetConfig.appGroup)?
            .appendingPathComponent("widget-cache.json")
    }

    static func load() -> WSharedCache {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let cache = try? JSONDecoder().decode(WSharedCache.self, from: data)
        else { return .empty }
        return cache
    }

    /// Anota el modo recién aplicado para que el interruptor del Centro de Control
    /// no se quede en el estado antiguo hasta el próximo refresco de la app.
    static func updateMode(homeId: String, mode: String) {
        var cache = load()
        guard let previous = cache.snapshots[homeId] else { return }
        cache.snapshots[homeId] = WHomeSnapshot(
            homeId: previous.homeId,
            currentTemp: previous.currentTemp,
            targetTemp: previous.targetTemp,
            boilerOn: previous.boilerOn,
            mode: mode,
            updatedAt: previous.updatedAt
        )
        guard let fileURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Keychain compartido

enum WidgetKeychain {
    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: WidgetConfig.keychainAccessGroup,
        ]
    }

    private static func load<T: Decodable>(_ type: T.Type, service: String, account: String) -> T? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func loadTokens() -> WTokenBundle? {
        load(WTokenBundle.self, service: "com.calefaccionnetatmo.oauth", account: "netatmo-tokens")
    }

    static func loadCredentials() -> WCredentials? {
        load(WCredentials.self, service: "com.calefaccionnetatmo.credentials", account: "netatmo-credentials")
    }

    static func saveTokens(_ bundle: WTokenBundle) {
        guard let data = try? JSONEncoder().encode(bundle) else { return }
        let query = baseQuery(service: "com.calefaccionnetatmo.oauth", account: "netatmo-tokens")
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

// MARK: - Cliente mínimo de la API

struct WLiveStatus {
    let currentTemp: Double?
    let targetTemp: Double?
    let boilerOn: Bool
    let mode: String?
}

struct WidgetNetatmoClient {
    enum WError: Error { case notAuthenticated, http(Int), invalid }

    private let session = URLSession(configuration: .default)
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    // Token válido, refrescando si hace falta.
    func validToken() async throws -> String {
        guard let tokens = WidgetKeychain.loadTokens() else { throw WError.notAuthenticated }
        if !tokens.isExpired { return tokens.accessToken }
        guard let creds = WidgetKeychain.loadCredentials() else { throw WError.notAuthenticated }
        let refreshed = try await refresh(tokens.refreshToken, creds: creds)
        WidgetKeychain.saveTokens(refreshed)
        return refreshed.accessToken
    }

    private func refresh(_ refreshToken: String, creds: WCredentials) async throws -> WTokenBundle {
        var request = URLRequest(url: WidgetConfig.apiBase.appendingPathComponent("oauth2/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": creds.clientID,
            "client_secret": creds.clientSecret,
        ]).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let token = try decoder.decode(WTokenResponse.self, from: data)
        let expiresIn = token.expiresIn ?? token.expireIn ?? 10800
        return WTokenBundle(accessToken: token.accessToken, refreshToken: token.refreshToken,
                            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)))
    }

    // Estado en vivo de la casa (habitación del termostato).
    func fetchStatus(homeId: String, roomId: String?) async throws -> WLiveStatus {
        let token = try await validToken()
        var components = URLComponents(url: WidgetConfig.apiBase.appendingPathComponent("api/homestatus"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "home_id", value: homeId)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try decoder.decode(WStatusResponse.self, from: data)
        let rooms = decoded.body.home.rooms ?? []
        let room = rooms.first { $0.id == roomId } ?? rooms.first { $0.thermMeasuredTemperature != nil }
        let boilerOn = (decoded.body.home.modules ?? []).contains { $0.boilerStatus == true }
        return WLiveStatus(currentTemp: room?.thermMeasuredTemperature,
                           targetTemp: room?.thermSetpointTemperature,
                           boilerOn: boilerOn,
                           mode: decoded.body.home.thermMode)
    }

    // Fija temperatura manual con fin (endtime epoch en segundos).
    func setRoomTemperature(homeId: String, roomId: String, temp: Double, endtime: TimeInterval) async throws {
        let token = try await validToken()
        var request = URLRequest(url: WidgetConfig.apiBase.appendingPathComponent("api/setroomthermpoint"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "home_id": homeId,
            "room_id": roomId,
            "mode": "manual",
            "temp": String(format: "%.1f", temp),
            "endtime": String(Int(endtime)),
        ]).data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    // Modo global de la casa: "schedule" (programación), "away" (ausente) o "hg" (antihielo).
    func setThermMode(homeId: String, mode: String) async throws {
        let token = try await validToken()
        var request = URLRequest(url: WidgetConfig.apiBase.appendingPathComponent("api/setthermmode"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(["home_id": homeId, "mode": mode]).data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    private static func formEncode(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }
}

// MARK: - Respuestas mínimas

private struct WTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let expireIn: Int?
}

private struct WStatusResponse: Decodable { let body: WStatusBody }
private struct WStatusBody: Decodable { let home: WStatusHome }
private struct WStatusHome: Decodable {
    let rooms: [WStatusRoom]?
    let modules: [WStatusModule]?
    let thermMode: String?
}
private struct WStatusRoom: Decodable {
    let id: String
    let thermMeasuredTemperature: Double?
    let thermSetpointTemperature: Double?
}
private struct WStatusModule: Decodable { let boilerStatus: Bool? }
