//
//  RoomMeasure.swift
//  Calefaccion Netatmo
//
//  Modelos de la respuesta de `GET /api/getroommeasure` (histórico por habitación).
//  Se usa con optimize=false, que devuelve bloques con beg_time/step_time/value.
//

import Foundation

struct RoomMeasureResponse: Decodable {
    let body: [MeasureBlock]
    let status: String
}

struct MeasureBlock: Decodable {
    let begTime: TimeInterval
    let stepTime: TimeInterval?
    /// Cada elemento es una fila de valores (uno por `type` solicitado).
    let value: [[Double?]]
}

/// Tipo de dato solicitado a getroommeasure.
enum MeasureType: String {
    case temperature                 // temperatura de la habitación
    case sumBoilerOn = "sum_boiler_on"   // segundos con la caldera encendida (uso de calefacción)
}

/// Escala temporal de la medida.
enum MeasureScale: String, CaseIterable, Identifiable {
    case oneHour = "1hour"
    case threeHours = "3hours"
    case oneDay = "1day"
    case oneWeek = "1week"
    case oneMonth = "1month"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneHour: return "1 hora"
        case .threeHours: return "3 horas"
        case .oneDay: return "Día"
        case .oneWeek: return "Semana"
        case .oneMonth: return "Mes"
        }
    }
}

/// Punto ya procesado (fecha + valor) listo para graficar.
struct MeasurePoint: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let value: Double
}
