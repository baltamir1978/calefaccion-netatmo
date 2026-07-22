//
//  SharedStore.swift
//  Calefaccion Netatmo
//
//  Datos compartidos entre la app y la extensión de widgets (App Group).
//  Las constantes deben coincidir EXACTAMENTE con las del target del widget.
//

import Foundation

enum SharedConfig {
    /// App Group activado en ambos targets (Signing & Capabilities).
    static let appGroup = "group.Altamirano.Calefaccion-Netatmo"
    /// Keychain access group compartido = TeamID + bundle base.
    static let keychainAccessGroup = "JKMR84FU58.Altamirano.Calefaccion-Netatmo"
}

/// Casa mínima para el selector del widget.
struct CachedHome: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let thermostatRoomId: String?
}

/// Estado resumido de una casa para pintar el widget al instante / offline.
struct HomeSnapshot: Codable, Hashable {
    let homeId: String
    let currentTemp: Double?
    let targetTemp: Double?
    let boilerOn: Bool
    let mode: String?
    let updatedAt: Date
}

struct SharedCache: Codable {
    var homes: [CachedHome]
    var snapshots: [String: HomeSnapshot]

    static let empty = SharedCache(homes: [], snapshots: [:])
}

/// Lee/escribe la caché en el contenedor del App Group. Si el App Group no está
/// disponible (entitlement no activado aún), las operaciones hacen no-op de forma segura.
enum SharedStore {
    private static let fileName = "widget-cache.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroup)?
            .appendingPathComponent(fileName)
    }

    static func load() -> SharedCache {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let cache = try? JSONDecoder().decode(SharedCache.self, from: data) else {
            return .empty
        }
        return cache
    }

    static func save(_ cache: SharedCache) {
        guard let fileURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
