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
