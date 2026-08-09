//
//  HomeDetailViewModel.swift
//  Calefaccion Netatmo
//
//  Detalle de una casa: horario activo y gestión de horarios (crear, duplicar,
//  renombrar, borrar). Mantiene su propia copia de la casa porque cualquiera de
//  esas operaciones cambia la lista de horarios que devuelve homesdata.
//

import Foundation
import Observation

@MainActor
@Observable
final class HomeDetailViewModel {
    /// Copia recargable de la casa. La que llega por navegación se queda congelada.
    private(set) var home: Home
    var selectedScheduleId: String?
    var isSwitching = false
    var errorMessage: String?

    /// Operación de horarios en curso (crear, renombrar…): bloquea la sección entera.
    private(set) var isWorking = false

    /// Batería de los módulos de calefacción de la casa (vacío si aún no se ha cargado el estado).
    private(set) var batteries: [ModuleBattery] = []

    private var didInit = false

    init(home: Home) {
        self.home = home
    }

    var schedules: [HomeSchedule] { home.schedules ?? [] }

    /// Horario que se muestra y se edita: el marcado en la vista, el activo o el primero.
    var editableSchedule: HomeSchedule? {
        schedules.first { $0.id == selectedScheduleId }
            ?? home.selectedSchedule
            ?? schedules.first
    }

    func prime() {
        guard !didInit else { return }
        didInit = true
        selectedScheduleId = home.selectedSchedule?.id ?? schedules.first?.id
    }

    func loadBatteries(using energy: EnergyService) async {
        guard let status = try? await energy.fetchHomeStatus(homeId: home.id) else { return }
        batteries = status.batteries(for: home)
    }

    func switchSchedule(to scheduleId: String, using energy: EnergyService) async {
        let previous = selectedScheduleId
        selectedScheduleId = scheduleId
        isSwitching = true
        errorMessage = nil
        do {
            try await energy.switchSchedule(homeId: home.id, scheduleId: scheduleId)
            await reload(using: energy)
        } catch {
            selectedScheduleId = previous
            errorMessage = Self.message(from: error)
        }
        isSwitching = false
    }

    // MARK: - Gestión de horarios

    /// `true` si el horario se puede borrar: Netatmo no deja quitar el activo ni el último.
    func canDelete(_ schedule: HomeSchedule) -> Bool {
        schedules.count > 1 && schedule.id != selectedScheduleId
    }

    func createSchedule(named name: String, using energy: EnergyService) async {
        await run(using: energy) { [home] in
            try await energy.createSchedule(home: home, name: name)
        }
    }

    func duplicateSchedule(_ schedule: HomeSchedule, named name: String, using energy: EnergyService) async {
        await run(using: energy) { [home] in
            try await energy.duplicateSchedule(homeId: home.id, schedule: schedule, name: name)
        }
    }

    func renameSchedule(_ schedule: HomeSchedule, to name: String, using energy: EnergyService) async {
        await run(using: energy) { [home] in
            try await energy.renameSchedule(homeId: home.id, scheduleId: schedule.id, name: name)
        }
    }

    func deleteSchedule(_ schedule: HomeSchedule, using energy: EnergyService) async {
        await run(using: energy) { [home] in
            try await energy.deleteSchedule(homeId: home.id, scheduleId: schedule.id)
        }
    }

    /// Nombre propuesto al duplicar, evitando repetir uno que ya exista.
    func copyName(for schedule: HomeSchedule) -> String {
        let base = String(localized: "Copia de \(schedule.displayName)")
        let taken = Set(schedules.compactMap(\.name))
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    /// Vuelve a traer la topología para que la lista de horarios refleje el cambio.
    func reload(using energy: EnergyService) async {
        guard let refreshed = try? await energy.fetchHomes().first(where: { $0.id == home.id }) else { return }
        home = refreshed
        if selectedScheduleId == nil || !schedules.contains(where: { $0.id == selectedScheduleId }) {
            selectedScheduleId = refreshed.selectedSchedule?.id ?? schedules.first?.id
        }
    }

    // MARK: - Helpers

    private func run(using energy: EnergyService, _ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do {
            try await action()
            await reload(using: energy)
        } catch {
            errorMessage = Self.message(from: error)
        }
        isWorking = false
    }

    private static func message(from error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
