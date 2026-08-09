//
//  EnergyService.swift
//  Calefaccion Netatmo
//
//  Fachada de la API Energy de Netatmo. Traduce llamadas de alto nivel
//  (leer casas, ajustar temperatura, cambiar modo...) a peticiones concretas.
//

import Foundation
import Observation

@MainActor
@Observable
final class EnergyService {
    private let client: NetatmoAPIClient
    private let settings: AppSettings

    init(authManager: AuthManager, settings: AppSettings) {
        self.client = NetatmoAPIClient(authManager: authManager)
        self.settings = settings
    }

    // MARK: - Lectura

    /// Topología completa de todas las casas del usuario.
    func fetchHomes() async throws -> [Home] {
        let response: HomesDataResponse = try await client.get(NetatmoEndpoint.homesData)
        return response.body.homes
    }

    /// Estado en vivo de una casa concreta.
    func fetchHomeStatus(homeId: String) async throws -> HomeStatusHome {
        let response: HomeStatusResponse = try await client.get(
            NetatmoEndpoint.homeStatus,
            query: ["home_id": homeId]
        )
        return response.body.home
    }

    // MARK: - Escritura

    /// Fija una temperatura manual en una habitación.
    /// - Parameter endTime: epoch en segundos hasta cuándo mantenerla. Si es nil se usa la
    ///   duración por defecto configurada en Ajustes (o la de Netatmo si es 0).
    func setRoomTemperature(
        homeId: String,
        roomId: String,
        temperature: Double,
        endTime: TimeInterval? = nil
    ) async throws {
        var form: [String: String] = [
            "home_id": homeId,
            "room_id": roomId,
            "mode": SetpointMode.manual.rawValue,
            "temp": String(format: "%.1f", temperature),
        ]
        if let endTime = endTime ?? settings.manualEndTime() {
            form["endtime"] = String(Int(endTime))
        }
        let _: APIStatusResponse = try await client.post(NetatmoEndpoint.setRoomThermpoint, form: form)
    }

    /// Cambia el modo de una habitación (p.ej. volver a la programación con `.home`).
    func setRoomMode(homeId: String, roomId: String, mode: SetpointMode) async throws {
        let form: [String: String] = [
            "home_id": homeId,
            "room_id": roomId,
            "mode": mode.rawValue,
        ]
        let _: APIStatusResponse = try await client.post(NetatmoEndpoint.setRoomThermpoint, form: form)
    }

    /// Modo global del hogar: programación / ausente / antihielo.
    func setThermMode(homeId: String, mode: ThermMode) async throws {
        let form: [String: String] = [
            "home_id": homeId,
            "mode": mode.rawValue,
        ]
        let _: APIStatusResponse = try await client.post(NetatmoEndpoint.setThermMode, form: form)
    }

    /// Activa uno de los horarios existentes de la casa.
    func switchSchedule(homeId: String, scheduleId: String) async throws {
        let form: [String: String] = [
            "home_id": homeId,
            "schedule_id": scheduleId,
        ]
        let _: APIStatusResponse = try await client.post(NetatmoEndpoint.switchHomeSchedule, form: form)
    }

    /// Guarda las temperaturas de un horario (mantiene las horas intactas).
    /// Reenvía el horario completo (round-trip) cambiando solo las temperaturas indicadas.
    /// - Parameters:
    ///   - zoneTemps: nueva temperatura por `zone.id` (zonas programadas, no away/frost).
    ///   - awayTemp/hgTemp: temperaturas de Ausente y Antihielo.
    func syncScheduleTemperatures(
        homeId: String,
        schedule: HomeSchedule,
        thermostatRoomId: String?,
        zoneTemps: [Int: Double],
        awayTemp: Double,
        hgTemp: Double
    ) async throws {
        let zones: [SyncZone] = (schedule.zones ?? []).map { zone in
            let newTemp: Double?
            switch zone.type {
            case 2: newTemp = awayTemp
            case 3: newTemp = hgTemp
            default: newTemp = zoneTemps[zone.id]
            }
            let rooms: [SyncRoom] = (zone.rooms ?? []).map { room in
                let base = room.thermSetpointTemperature ?? 0
                let applies = thermostatRoomId == nil || room.id == thermostatRoomId
                let temp = (newTemp != nil && applies) ? newTemp! : base
                return SyncRoom(id: room.id, thermSetpointTemperature: temp)
            }
            return SyncZone(id: zone.id, type: zone.type ?? 0, rooms: rooms)
        }

        let timetable: [SyncTimetableEntry] = (schedule.timetable ?? []).map {
            SyncTimetableEntry(zoneId: $0.zoneId, mOffset: $0.mOffset ?? 0)
        }

        var form = try Self.scheduleForm(homeId: homeId, zones: zones, timetable: timetable,
                                         awayTemp: awayTemp, hgTemp: hgTemp)
        form["schedule_id"] = schedule.id
        if let name = schedule.name { form["name"] = name }

        let _: APIStatusResponse = try await client.post(NetatmoEndpoint.syncHomeSchedule, form: form)
    }

    // MARK: - Gestión de horarios

    /// Crea un horario nuevo a partir de la plantilla estándar (confort/noche/eco).
    /// Las habitaciones de calefacción arrancan todas con las mismas temperaturas.
    /// - Returns: identificador del horario creado, si Netatmo lo devuelve.
    @discardableResult
    func createSchedule(home: Home, name: String) async throws -> String? {
        let roomIds = home.heatingRooms.map(\.id)
        return try await createSchedule(
            homeId: home.id,
            name: name,
            zones: ScheduleTemplate.zones(roomIds: roomIds),
            timetable: ScheduleTemplate.timetable(),
            awayTemp: ScheduleTemplate.awayTemp,
            hgTemp: ScheduleTemplate.frostGuardTemp
        )
    }

    /// Copia un horario existente con otro nombre, horas y temperaturas incluidas.
    @discardableResult
    func duplicateSchedule(homeId: String, schedule: HomeSchedule, name: String) async throws -> String? {
        let zones: [SyncZone] = (schedule.zones ?? []).map { zone in
            SyncZone(id: zone.id, type: zone.type ?? 0,
                     rooms: (zone.rooms ?? []).map {
                         SyncRoom(id: $0.id, thermSetpointTemperature: $0.thermSetpointTemperature ?? 0)
                     })
        }
        let timetable: [SyncTimetableEntry] = (schedule.timetable ?? []).map {
            SyncTimetableEntry(zoneId: $0.zoneId, mOffset: $0.mOffset ?? 0)
        }
        return try await createSchedule(
            homeId: homeId,
            name: name,
            zones: zones,
            timetable: timetable,
            awayTemp: schedule.awayTemp ?? ScheduleTemplate.awayTemp,
            hgTemp: schedule.hgTemp ?? ScheduleTemplate.frostGuardTemp
        )
    }

    /// Cambia el nombre de un horario sin tocar sus franjas.
    func renameSchedule(homeId: String, scheduleId: String, name: String) async throws {
        let form: [String: String] = [
            "home_id": homeId,
            "schedule_id": scheduleId,
            "name": name,
        ]
        let _: APIStatusResponse = try await client.post(NetatmoEndpoint.renameHomeSchedule, form: form)
    }

    /// Borra un horario. Netatmo rechaza borrar el que está activo.
    func deleteSchedule(homeId: String, scheduleId: String) async throws {
        let form: [String: String] = [
            "home_id": homeId,
            "schedule_id": scheduleId,
        ]
        let _: APIStatusResponse = try await client.post(NetatmoEndpoint.deleteHomeSchedule, form: form)
    }

    private func createSchedule(
        homeId: String,
        name: String,
        zones: [SyncZone],
        timetable: [SyncTimetableEntry],
        awayTemp: Double,
        hgTemp: Double
    ) async throws -> String? {
        var form = try Self.scheduleForm(homeId: homeId, zones: zones, timetable: timetable,
                                         awayTemp: awayTemp, hgTemp: hgTemp)
        form["name"] = name
        let response: CreateScheduleResponse = try await client.post(
            NetatmoEndpoint.createNewHomeSchedule, form: form)
        return response.body?.scheduleId
    }

    /// Campos comunes de `synchomeschedule` y `createnewhomeschedule`.
    private static func scheduleForm(
        homeId: String,
        zones: [SyncZone],
        timetable: [SyncTimetableEntry],
        awayTemp: Double,
        hgTemp: Double
    ) throws -> [String: String] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return [
            "home_id": homeId,
            "zones": String(data: try encoder.encode(zones), encoding: .utf8) ?? "[]",
            "timetable": String(data: try encoder.encode(timetable), encoding: .utf8) ?? "[]",
            "away_temp": String(format: "%.1f", awayTemp),
            "hg_temp": String(format: "%.1f", hgTemp),
        ]
    }

    // MARK: - Consumo / uso

    /// Histórico de una habitación (temperatura o tiempo de caldera encendida).
    func fetchRoomMeasure(
        homeId: String,
        roomId: String,
        type: MeasureType,
        scale: MeasureScale,
        dateBegin: Date,
        dateEnd: Date
    ) async throws -> [MeasurePoint] {
        let response: RoomMeasureResponse = try await client.get(
            NetatmoEndpoint.getRoomMeasure,
            query: [
                "home_id": homeId,
                "room_id": roomId,
                "scale": scale.rawValue,
                "type": type.rawValue,
                "date_begin": String(Int(dateBegin.timeIntervalSince1970)),
                "date_end": String(Int(dateEnd.timeIntervalSince1970)),
                "optimize": "false",
            ]
        )
        return Self.flatten(response.body)
    }

    /// Convierte los bloques beg_time/step_time/value en puntos (fecha, valor).
    private static func flatten(_ blocks: [MeasureBlock]) -> [MeasurePoint] {
        var points: [MeasurePoint] = []
        for block in blocks {
            let step = block.stepTime ?? 0
            for (index, row) in block.value.enumerated() {
                guard let value = row.first ?? nil else { continue }
                let date = Date(timeIntervalSince1970: block.begTime + Double(index) * step)
                points.append(MeasurePoint(date: date, value: value))
            }
        }
        return points.sorted { $0.date < $1.date }
    }
}
