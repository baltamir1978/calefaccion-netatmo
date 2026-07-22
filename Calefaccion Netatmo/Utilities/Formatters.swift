//
//  Formatters.swift
//  Calefaccion Netatmo
//

import Foundation

enum Formatters {
    /// "21.5°" o "--" si no hay valor.
    static func temperature(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f°", value)
    }

    /// Convierte segundos de caldera encendida en un texto legible (h/min).
    static func duration(seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }
}
