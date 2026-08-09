//
//  BatteryStatus.swift
//  Calefaccion Netatmo
//
//  Nivel de batería de un módulo de calefacción (termostato o válvula),
//  normalizado a 4 barras para el indicador de la interfaz.
//

import Foundation

/// Nivel de batería en 4 escalones. `low` es el aviso de batería baja.
enum BatteryLevel: Int, Comparable, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    case full = 4

    /// Número de barras encendidas (de 4).
    var bars: Int { rawValue }

    /// `true` cuando conviene avisar al usuario de que cambie las pilas.
    var isLow: Bool { self == .low }

    var displayName: String {
        switch self {
        case .low: String(localized: "Batería baja")
        case .medium: String(localized: "Batería media")
        case .high: String(localized: "Batería alta")
        case .full: String(localized: "Batería llena")
        }
    }

    static func < (lhs: BatteryLevel, rhs: BatteryLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Mapea el `battery_state` de la API ("full", "high", "medium", "low", "very_low"...).
    init?(state: String?) {
        switch state?.lowercased() {
        case "max", "full": self = .full
        case "high": self = .high
        case "medium": self = .medium
        case "low", "very_low": self = .low
        default: return nil
        }
    }

    /// Deriva el nivel del `battery_level` en mV cuando la API no manda `battery_state`.
    /// Los umbrales dependen del tipo de módulo (el termostato usa 3 AAA, las válvulas 2 AA).
    init?(millivolts: Int?, moduleType: String?) {
        guard let millivolts, millivolts > 0 else { return nil }
        let thresholds: (full: Int, high: Int, medium: Int)
        switch moduleType {
        case "NRV":
            thresholds = (3200, 2700, 2400)   // válvula
        default:
            thresholds = (4100, 3600, 3300)   // termostato NATherm1 y similares
        }
        switch millivolts {
        case thresholds.full...: self = .full
        case thresholds.high...: self = .high
        case thresholds.medium...: self = .medium
        default: self = .low
        }
    }
}

/// Batería de un módulo concreto, lista para mostrar.
struct ModuleBattery: Identifiable, Hashable {
    let id: String
    let name: String
    let level: BatteryLevel

    var isLow: Bool { level.isLow }
}

extension ModuleStatus {
    /// Nivel de batería del módulo, o `nil` si va conectado a la red o no lo reporta.
    var battery: BatteryLevel? {
        BatteryLevel(state: batteryState) ?? BatteryLevel(millivolts: batteryLevel, moduleType: type)
    }
}

extension HomeStatusHome {
    /// Batería de cada módulo de calefacción que la reporta, de menos a más carga.
    func batteries(for home: Home) -> [ModuleBattery] {
        let statusById = Dictionary(
            (modules ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return home.modules
            .filter(\.isHeatingModule)
            .compactMap { module in
                guard let level = statusById[module.id]?.battery else { return nil }
                return ModuleBattery(id: module.id, name: module.displayName(in: home), level: level)
            }
            .sorted { $0.level == $1.level ? $0.name < $1.name : $0.level < $1.level }
    }
}

extension Module {
    /// Nombre legible del módulo: el suyo, el de su habitación o su tipo.
    func displayName(in home: Home) -> String {
        if let name, !name.isEmpty { return name }
        if let roomId, let room = home.rooms.first(where: { $0.id == roomId }) { return room.name }
        return type == "NRV" ? String(localized: "Válvula") : String(localized: "Termostato")
    }
}
