//
//  HomeDetailViewModel.swift
//  Calefaccion Netatmo
//
//  Detalle de una casa: cambiar el horario activo.
//

import Foundation
import Observation

@MainActor
@Observable
final class HomeDetailViewModel {
    var selectedScheduleId: String?
    var isSwitching = false
    var errorMessage: String?

    /// Batería de los módulos de calefacción de la casa (vacío si aún no se ha cargado el estado).
    private(set) var batteries: [ModuleBattery] = []

    private var didInit = false

    func prime(with home: Home) {
        guard !didInit else { return }
        didInit = true
        selectedScheduleId = home.selectedSchedule?.id ?? home.schedules?.first?.id
    }

    func loadBatteries(home: Home, using energy: EnergyService) async {
        guard let status = try? await energy.fetchHomeStatus(homeId: home.id) else { return }
        batteries = status.batteries(for: home)
    }

    func switchSchedule(to scheduleId: String, home: Home, using energy: EnergyService) async {
        let previous = selectedScheduleId
        selectedScheduleId = scheduleId
        isSwitching = true
        errorMessage = nil
        do {
            try await energy.switchSchedule(homeId: home.id, scheduleId: scheduleId)
        } catch {
            selectedScheduleId = previous
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isSwitching = false
    }
}
