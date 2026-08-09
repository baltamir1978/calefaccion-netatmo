//
//  AppIntent.swift
//  CalefaccionWidget
//
//  Configuración del widget: selección de casa (lee la caché del App Group).
//

import WidgetKit
import AppIntents

struct HomeEntity: AppEntity {
    let id: String
    let name: String
    let thermostatRoomId: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Casa" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static var defaultQuery = HomeQuery()
}

struct HomeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HomeEntity] {
        allHomes().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HomeEntity] { allHomes() }

    /// Con varias casas no se preselecciona ninguna: elegir por el usuario es lo
    /// único seguro cuando el widget puede acabar calentando la casa equivocada.
    func defaultResult() async -> HomeEntity? {
        let homes = allHomes()
        return homes.count == 1 ? homes.first : nil
    }

    private func allHomes() -> [HomeEntity] {
        WidgetCache.load().homes.map {
            HomeEntity(id: $0.id, name: $0.name, thermostatRoomId: $0.thermostatRoomId)
        }
    }
}

/// Casa que muestra un widget o control, y por qué no hay ninguna si falta.
enum ResolvedHome {
    case home(WCachedHome)
    /// No hay sesión ni caché: hay que abrir la app.
    case noCache
    /// Hay varias casas y el widget aún no tiene una elegida.
    case needsChoice

    /// Regla común a todos los widgets: la configurada; si no hay, la única que
    /// exista; y si hay más de una, se pide elegir en vez de acertar por sorteo.
    static func resolve(configured: HomeEntity?) -> ResolvedHome {
        if let configured {
            return .home(WCachedHome(id: configured.id, name: configured.name,
                                     thermostatRoomId: configured.thermostatRoomId))
        }
        let homes = WidgetCache.load().homes
        if homes.isEmpty { return .noCache }
        if homes.count == 1, let only = homes.first { return .home(only) }
        return .needsChoice
    }
}

struct SelectHomeIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Elegir casa" }
    static var description: IntentDescription { "Selecciona la casa que muestra el widget." }

    @Parameter(title: "Casa")
    var home: HomeEntity?
}
