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

    func defaultResult() async -> HomeEntity? { allHomes().first }

    private func allHomes() -> [HomeEntity] {
        WidgetCache.load().homes.map {
            HomeEntity(id: $0.id, name: $0.name, thermostatRoomId: $0.thermostatRoomId)
        }
    }
}

struct SelectHomeIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Elegir casa" }
    static var description: IntentDescription { "Selecciona la casa que muestra el widget." }

    @Parameter(title: "Casa")
    var home: HomeEntity?
}
