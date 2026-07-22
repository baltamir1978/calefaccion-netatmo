//
//  HomeStatus.swift
//  Calefaccion Netatmo
//
//  Modelos de la respuesta de `GET /api/homestatus` (estado en vivo del hogar).
//

import Foundation

// MARK: - Respuesta homestatus

struct HomeStatusResponse: Decodable {
    let body: HomeStatusBody
    let status: String
}

struct HomeStatusBody: Decodable {
    let home: HomeStatusHome
}

struct HomeStatusHome: Decodable {
    let id: String
    /// Modo global actual si la API lo incluye aquí: "schedule" / "away" / "hg".
    let thermMode: String?
    let rooms: [RoomStatus]?
    let modules: [ModuleStatus]?

    var currentThermMode: ThermMode? { thermMode.flatMap(ThermMode.init(rawValue:)) }
}

// MARK: - Estado de habitación

struct RoomStatus: Decodable, Identifiable, Hashable {
    let id: String
    let reachable: Bool?
    let anticipating: Bool?

    /// 0 = cerrado, 100 = totalmente abierto (válvulas).
    let heatingPowerRequest: Int?

    let thermMeasuredTemperature: Double?
    let thermSetpointTemperature: Double?

    /// "home", "manual", "hg", "away", "off", "max"...
    let thermSetpointMode: String?
    let thermSetpointEndTime: TimeInterval?
    let openWindow: Bool?

    /// `true` si la habitación está demandando calor ahora mismo.
    var isHeating: Bool { (heatingPowerRequest ?? 0) > 0 }
}

// MARK: - Estado de módulo

struct ModuleStatus: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let reachable: Bool?
    let firmwareRevision: Int?
    let rfStrength: Int?
    let wifiStrength: Int?
    let batteryLevel: Int?
    let batteryState: String?

    /// Estado de la caldera (termostato NATherm1): `true` = encendida.
    let boilerStatus: Bool?
    let bridge: String?
}
