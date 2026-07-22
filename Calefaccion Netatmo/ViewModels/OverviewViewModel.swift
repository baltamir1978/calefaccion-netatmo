//
//  OverviewViewModel.swift
//  Calefaccion Netatmo
//
//  Carga la topología y el estado en vivo de TODAS las casas para la pantalla de inicio,
//  y expone control directo (temperatura, modo) tratando cada casa como un único termostato.
//

import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class OverviewViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var state: LoadState = .loading
    private(set) var homes: [Home] = []
    private(set) var statuses: [String: HomeStatusHome] = [:]

    /// Último error de una acción de escritura (para mostrar aviso).
    var actionError: String?

    /// Overrides optimistas mientras el servidor confirma.
    private var localTargets: [String: Double] = [:]
    private var localModes: [String: ThermMode] = [:]

    /// Casas con una acción de escritura en curso.
    private(set) var busyHomeIds: Set<String> = []

    private var applyTasks: [String: Task<Void, Never>] = [:]

    let minTemp = 5.0
    let maxTemp = 30.0
    let step = 0.5

    // MARK: - Carga

    func load(using energy: EnergyService) async {
        state = .loading
        do {
            homes = try await energy.fetchHomes()
            await refreshStatuses(using: energy)
            state = .loaded
        } catch {
            state = .failed(Self.message(from: error))
        }
    }

    func refreshStatuses(using energy: EnergyService) async {
        for home in homes {
            do {
                let status = try await energy.fetchHomeStatus(homeId: home.id)
                statuses[home.id] = status
                if let mode = status.currentThermMode { localModes[home.id] = mode }
                // No pisar el objetivo local si el usuario está ajustando esa casa.
                if applyTasks[home.id] == nil,
                   let setpoint = roomStatus(for: home)?.thermSetpointTemperature, setpoint > 0 {
                    localTargets[home.id] = setpoint
                }
            } catch {
                // El error de una casa no debe tumbar el resto.
                continue
            }
        }
        updateSharedCache()
    }

    // MARK: - Lecturas derivadas

    /// Habitación que hace de termostato (la de la caldera). Toda la casa comparte esa temperatura.
    func thermostatRoom(for home: Home) -> Room? {
        home.heatingRooms.first
    }

    func roomStatus(for home: Home) -> RoomStatus? {
        if let room = thermostatRoom(for: home),
           let match = statuses[home.id]?.rooms?.first(where: { $0.id == room.id }) {
            return match
        }
        return statuses[home.id]?.rooms?.first { $0.thermMeasuredTemperature != nil }
    }

    func currentTemperature(for home: Home) -> Double? {
        roomStatus(for: home)?.thermMeasuredTemperature
    }

    func targetTemperature(for home: Home) -> Double? {
        localTargets[home.id] ?? roomStatus(for: home)?.thermSetpointTemperature
    }

    func currentMode(for home: Home) -> ThermMode {
        localModes[home.id] ?? statuses[home.id]?.currentThermMode ?? home.currentThermMode ?? .schedule
    }

    func isBoilerOn(for home: Home) -> Bool {
        statuses[home.id]?.modules?.contains { $0.boilerStatus == true } == true
    }

    func isReachable(for home: Home) -> Bool {
        roomStatus(for: home)?.reachable ?? true
    }

    func activeScheduleName(for home: Home) -> String? {
        home.selectedSchedule?.name
    }

    func isBusy(_ home: Home) -> Bool { busyHomeIds.contains(home.id) }

    func canControlTemperature(for home: Home) -> Bool { thermostatRoom(for: home) != nil }

    // MARK: - Acciones

    func setMode(_ mode: ThermMode, home: Home, using energy: EnergyService) async {
        let previous = currentMode(for: home)
        localModes[home.id] = mode
        await runAction(home: home, energy: energy, onFailure: { self.localModes[home.id] = previous }) {
            try await energy.setThermMode(homeId: home.id, mode: mode)
        }
    }

    /// Ajuste optimista del objetivo con aplicación diferida (debounce) para no saturar la API.
    func adjustTarget(by delta: Double, home: Home, using energy: EnergyService) {
        guard let room = thermostatRoom(for: home) else { return }
        let base = targetTemperature(for: home) ?? 20
        let newTarget = min(maxTemp, max(minTemp, base + delta))
        localTargets[home.id] = newTarget

        applyTasks[home.id]?.cancel()
        applyTasks[home.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            self.busyHomeIds.insert(home.id)
            do {
                try await energy.setRoomTemperature(homeId: home.id, roomId: room.id, temperature: newTarget)
            } catch {
                self.actionError = Self.message(from: error)
            }
            self.applyTasks[home.id] = nil
            self.busyHomeIds.remove(home.id)
            await self.refreshStatuses(using: energy)
        }
    }

    func resumeSchedule(home: Home, using energy: EnergyService) async {
        guard let room = thermostatRoom(for: home) else { return }
        await runAction(home: home, energy: energy) {
            try await energy.setRoomMode(homeId: home.id, roomId: room.id, mode: .home)
        }
    }

    // MARK: - Helpers

    private func runAction(
        home: Home,
        energy: EnergyService,
        onFailure: @escaping () -> Void = {},
        _ action: () async throws -> Void
    ) async {
        busyHomeIds.insert(home.id)
        do {
            try await action()
        } catch {
            onFailure()
            actionError = Self.message(from: error)
        }
        busyHomeIds.remove(home.id)
        await refreshStatuses(using: energy)
    }

    /// Vuelca casas + estado a la caché compartida y refresca los widgets.
    private func updateSharedCache() {
        let cachedHomes = homes.map {
            CachedHome(id: $0.id, name: $0.name, thermostatRoomId: thermostatRoom(for: $0)?.id)
        }
        var snapshots: [String: HomeSnapshot] = [:]
        for home in homes {
            snapshots[home.id] = HomeSnapshot(
                homeId: home.id,
                currentTemp: currentTemperature(for: home),
                targetTemp: targetTemperature(for: home),
                boilerOn: isBoilerOn(for: home),
                mode: currentMode(for: home).rawValue,
                updatedAt: Date()
            )
        }
        SharedStore.save(SharedCache(homes: cachedHomes, snapshots: snapshots))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func message(from error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
