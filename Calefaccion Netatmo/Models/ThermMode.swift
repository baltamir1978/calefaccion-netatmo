//
//  ThermMode.swift
//  Calefaccion Netatmo
//
//  Modos del hogar y modos de setpoint por habitación de la API Energy.
//

import Foundation

/// Modo global del hogar (`POST /api/setthermmode`).
enum ThermMode: String, CaseIterable, Identifiable {
    case schedule
    case away
    case hg   // hors gel / antihielo (frost guard)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .schedule: return "Programación"
        case .away: return "Ausente"
        case .hg: return "Antihielo"
        }
    }

    var systemImage: String {
        switch self {
        case .schedule: return "calendar"
        case .away: return "figure.walk.departure"
        case .hg: return "snowflake"
        }
    }
}

/// Modo de temperatura por habitación (`POST /api/setroomthermpoint`).
enum SetpointMode: String {
    case manual   // fija una temperatura durante un tiempo
    case home     // vuelve a seguir la programación
    case max      // calienta al máximo
    case off      // apaga la habitación
}
