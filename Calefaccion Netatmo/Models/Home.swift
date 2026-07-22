//
//  Home.swift
//  Calefaccion Netatmo
//
//  Modelos de la respuesta de `GET /api/homesdata` (topología del hogar).
//  El decodificador usa `.convertFromSnakeCase`, por eso las propiedades van en camelCase.
//

import Foundation

// MARK: - Respuesta homesdata

struct HomesDataResponse: Decodable {
    let body: HomesDataBody
    let status: String
}

struct HomesDataBody: Decodable {
    let homes: [Home]
}

// MARK: - Home

struct Home: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let country: String?
    let timezone: String?
    let rooms: [Room]
    let modules: [Module]
    let schedules: [HomeSchedule]?

    /// Modo global actual: "schedule" / "away" / "hg".
    let thermMode: String?

    /// Duración por defecto (minutos) de un ajuste manual de temperatura.
    let thermSetpointDefaultDuration: Int?

    var sortedRooms: [Room] { rooms.sorted { $0.name < $1.name } }
    var currentThermMode: ThermMode? { thermMode.flatMap(ThermMode.init(rawValue:)) }
    var selectedSchedule: HomeSchedule? { schedules?.first { $0.selected == true } }

    /// Habitaciones que participan en la calefacción (tienen termostato o válvula).
    /// Excluye las habitaciones que solo contienen estaciones meteorológicas u otros sensores.
    var heatingRooms: [Room] {
        let heatingRoomIds = Set(
            modules.filter { $0.isHeatingModule }.compactMap { $0.roomId }
        )
        let filtered = rooms.filter { heatingRoomIds.contains($0.id) }
        let result = filtered.isEmpty ? rooms : filtered
        return result.sorted { $0.name < $1.name }
    }

    static func == (lhs: Home, rhs: Home) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Room

struct Room: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String?
    let moduleIds: [String]?
}

// MARK: - Module (termostato, válvula, relé, estación meteo...)

struct Module: Decodable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String?
    let roomId: String?
    let bridge: String?

    /// Tipos de módulo que controlan la calefacción (termostato / válvula).
    /// El resto (NAMain, NAModule1-4 de la estación meteo, NAPlug/relé...) no son de calefacción.
    static let heatingTypes: Set<String> = ["NATherm1", "NATherm2", "NRV", "OTM", "BNS"]

    var isHeatingModule: Bool { Self.heatingTypes.contains(type) }
}

// MARK: - Horario / programación

struct HomeSchedule: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let selected: Bool?
    let type: String?
    let zones: [ScheduleZone]?
    let timetable: [TimetableEntry]?
    let awayTemp: Double?
    let hgTemp: Double?

    var displayName: String { name ?? "Horario" }
}

struct ScheduleZone: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let type: Int?
    let rooms: [ZoneRoomTemp]?

    /// Temperatura fijada para la habitación del termostato en esta zona.
    func temperature(forRoom roomId: String?) -> Double? {
        guard let roomId else { return rooms?.first?.thermSetpointTemperature }
        return rooms?.first { $0.id == roomId }?.thermSetpointTemperature
            ?? rooms?.first?.thermSetpointTemperature
    }
}

struct ZoneRoomTemp: Decodable, Hashable {
    let id: String
    let thermSetpointTemperature: Double?
}

struct TimetableEntry: Decodable, Hashable {
    let zoneId: Int
    let mOffset: Int?
}
