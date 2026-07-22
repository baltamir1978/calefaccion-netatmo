//
//  ScheduleEditViewModel.swift
//  Calefaccion Netatmo
//
//  Edición de las temperaturas de un horario (sin tocar las horas).
//

import Foundation
import Observation

@MainActor
@Observable
final class ScheduleEditViewModel {
    struct EditableZone: Identifiable {
        let id: Int      // zone.id
        let name: String
        let original: Double
    }

    struct Change: Identifiable {
        let id = UUID()
        let label: String
        let from: Double
        let to: Double
    }

    private(set) var zones: [EditableZone] = []
    var zoneTemps: [Int: Double] = [:]
    var awayTemp: Double = 12
    var hgTemp: Double = 7

    var isSaving = false
    var errorMessage: String?

    let minTemp = 5.0
    let maxTemp = 30.0
    let step = 0.5

    private var originalAway: Double = 12
    private var originalHg: Double = 7
    private var didPrime = false

    // MARK: - Inicialización

    func prime(schedule: HomeSchedule, thermostatRoomId: String?) {
        guard !didPrime else { return }
        didPrime = true

        awayTemp = schedule.awayTemp ?? zoneTemperature(schedule, type: 2, roomId: thermostatRoomId) ?? 12
        hgTemp = schedule.hgTemp ?? zoneTemperature(schedule, type: 3, roomId: thermostatRoomId) ?? 7
        originalAway = awayTemp
        originalHg = hgTemp

        var built: [EditableZone] = []
        for zone in schedule.zones ?? [] where zone.type != 2 && zone.type != 3 {
            let temp = zone.temperature(forRoom: thermostatRoomId) ?? 20
            zoneTemps[zone.id] = temp
            built.append(EditableZone(id: zone.id, name: Self.name(for: zone), original: temp))
        }
        zones = built.sorted { $0.id < $1.id }
    }

    // MARK: - Ajustes

    func temperature(forZone id: Int) -> Double { zoneTemps[id] ?? 20 }

    func adjustZone(_ id: Int, by delta: Double) {
        zoneTemps[id] = clamp((zoneTemps[id] ?? 20) + delta)
    }

    func adjustAway(by delta: Double) { awayTemp = clamp(awayTemp + delta) }
    func adjustHg(by delta: Double) { hgTemp = clamp(hgTemp + delta) }

    private func clamp(_ value: Double) -> Double { min(maxTemp, max(minTemp, value)) }

    // MARK: - Diff

    func changes() -> [Change] {
        var list: [Change] = []
        for zone in zones {
            let now = zoneTemps[zone.id] ?? zone.original
            if now != zone.original {
                list.append(Change(label: zone.name, from: zone.original, to: now))
            }
        }
        if awayTemp != originalAway { list.append(Change(label: "Ausente", from: originalAway, to: awayTemp)) }
        if hgTemp != originalHg { list.append(Change(label: "Antihielo", from: originalHg, to: hgTemp)) }
        return list
    }

    var hasChanges: Bool { !changes().isEmpty }

    // MARK: - Guardar

    func save(homeId: String, schedule: HomeSchedule, thermostatRoomId: String?, using energy: EnergyService) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await energy.syncScheduleTemperatures(
                homeId: homeId,
                schedule: schedule,
                thermostatRoomId: thermostatRoomId,
                zoneTemps: zoneTemps,
                awayTemp: awayTemp,
                hgTemp: hgTemp
            )
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - Helpers

    private func zoneTemperature(_ schedule: HomeSchedule, type: Int, roomId: String?) -> Double? {
        schedule.zones?.first { $0.type == type }?.temperature(forRoom: roomId)
    }

    /// Nombre legible de una zona: usa el de Netatmo o uno por tipo.
    private static func name(for zone: ScheduleZone) -> String {
        if let name = zone.name, !name.isEmpty { return name }
        switch zone.type {
        case 0: return "Confort"
        case 1: return "Noche"
        case 4: return "Confort +"
        case 5: return "Eco"
        default: return "Zona \(zone.id)"
        }
    }
}
