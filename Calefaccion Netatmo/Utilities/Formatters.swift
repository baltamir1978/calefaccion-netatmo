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

    /// Hora del día a partir de los minutos desde medianoche ("7:00", "11:30 PM"…),
    /// en el formato de 12/24 h que tenga configurado el sistema.
    static func timeOfDay(minutes: Int) -> String {
        let hour = minutes / 60
        let minute = minutes % 60
        // Fecha ficticia: solo interesa la hora, nunca se convierte de zona.
        let components = DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)
        guard let date = Calendar.current.date(from: components) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        return timeOfDayFormatter.string(from: date)
    }

    private static let timeOfDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }()

    /// Convierte segundos de caldera encendida en un texto legible (h/min).
    static func duration(seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }
}
