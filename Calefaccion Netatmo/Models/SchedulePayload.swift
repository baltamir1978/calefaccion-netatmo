//
//  SchedulePayload.swift
//  Calefaccion Netatmo
//
//  Estructuras Encodable para `POST /api/synchomeschedule`. Se serializan con
//  keyEncodingStrategy = .convertToSnakeCase (therm_setpoint_temperature, zone_id, m_offset).
//

import Foundation

struct SyncZone: Encodable {
    let id: Int
    let type: Int
    let rooms: [SyncRoom]
}

struct SyncRoom: Encodable {
    let id: String
    let thermSetpointTemperature: Double
}

struct SyncTimetableEntry: Encodable {
    let zoneId: Int
    let mOffset: Int
}

/// Respuesta de `createnewhomeschedule`: trae el id del horario recién creado.
struct CreateScheduleResponse: Decodable {
    struct Body: Decodable { let scheduleId: String? }
    let status: String
    let body: Body?
}

/// Horario de partida para «Nuevo horario». Netatmo exige que un horario traiga
/// al menos las zonas de confort, noche, ausente y antihielo, y que el timetable
/// arranque en el minuto 0 de la semana; aquí se repite el mismo día siete veces.
enum ScheduleTemplate {
    /// Cambios de zona dentro de un día, en minutos desde medianoche.
    private static let dayChanges: [(minute: Int, zoneId: Int)] = [
        (390, Zone.comfort),   // 06:30
        (540, Zone.eco),       // 09:00
        (1020, Zone.comfort),  // 17:00
        (1380, Zone.night),    // 23:00
    ]

    /// Identificadores de zona, que coinciden con los que reparte Netatmo.
    enum Zone {
        static let comfort = 0
        static let night = 1
        static let away = 2
        static let frostGuard = 3
        static let eco = 4
    }

    static let comfortTemp = 20.0
    static let nightTemp = 17.0
    static let ecoTemp = 18.0
    static let awayTemp = 12.0
    static let frostGuardTemp = 7.0

    /// Las cinco zonas con la misma temperatura en todas las habitaciones indicadas.
    static func zones(roomIds: [String]) -> [SyncZone] {
        func zone(_ id: Int, _ type: Int, _ temp: Double) -> SyncZone {
            SyncZone(id: id, type: type,
                     rooms: roomIds.map { SyncRoom(id: $0, thermSetpointTemperature: temp) })
        }
        return [
            zone(Zone.comfort, 0, comfortTemp),
            zone(Zone.night, 1, nightTemp),
            zone(Zone.away, 2, awayTemp),
            zone(Zone.frostGuard, 3, frostGuardTemp),
            zone(Zone.eco, 5, ecoTemp),
        ]
    }

    /// Semana completa: empieza en noche a las 00:00 del lunes y repite el día tipo.
    static func timetable() -> [SyncTimetableEntry] {
        var entries = [SyncTimetableEntry(zoneId: Zone.night, mOffset: 0)]
        for day in 0..<7 {
            let base = day * ScheduleWeek.minutesPerDay
            for change in dayChanges {
                entries.append(SyncTimetableEntry(zoneId: change.zoneId, mOffset: base + change.minute))
            }
        }
        return entries
    }
}
