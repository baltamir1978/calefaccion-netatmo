//
//  ConsumptionViewModel.swift
//  Calefaccion Netatmo
//

import Foundation
import Observation

@MainActor
@Observable
final class ConsumptionViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var state: LoadState = .loading
    private(set) var points: [MeasurePoint] = []
    var scale: MeasureScale = .oneDay
    var measureType: MeasureType = .sumBoilerOn

    func load(home: Home, room: Room, using energy: EnergyService) async {
        state = .loading
        let end = Date()
        let begin = end.addingTimeInterval(-windowSeconds)
        do {
            points = try await energy.fetchRoomMeasure(
                homeId: home.id,
                roomId: room.id,
                type: measureType,
                scale: scale,
                dateBegin: begin,
                dateEnd: end
            )
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Ventana temporal a solicitar según la escala.
    private var windowSeconds: TimeInterval {
        switch scale {
        case .oneHour: return 60 * 60 * 24            // último día en pasos de 1h
        case .threeHours: return 60 * 60 * 24 * 3
        case .oneDay: return 60 * 60 * 24 * 14         // 2 semanas en pasos diarios
        case .oneWeek: return 60 * 60 * 24 * 7 * 12
        case .oneMonth: return 60 * 60 * 24 * 365
        }
    }

    /// Valor listo para mostrar (segundos -> texto para caldera).
    func displayValue(_ value: Double) -> String {
        switch measureType {
        case .sumBoilerOn: return Formatters.duration(seconds: value)
        case .temperature: return Formatters.temperature(value)
        }
    }
}
