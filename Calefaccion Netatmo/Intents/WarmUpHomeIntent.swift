//
//  WarmUpHomeIntent.swift
//  Calefaccion Netatmo
//
//  "Tengo frío" para Siri y Atajos: sube el objetivo 1 °C sobre la temperatura
//  actual durante dos horas, sin abrir la app.
//
//  El widget tiene su propia versión (CalefaccionWidget/WarmUpIntent.swift) que
//  recibe los identificadores ya resueltos; esta pide la casa al usuario y vive
//  en el target de la app, que es donde Siri busca los atajos.
//

import AppIntents
import WidgetKit

// MARK: - Casa seleccionable

/// Casa que ofrece Siri/Atajos. Sale de la caché del App Group, así que el
/// selector se rellena sin llamar a la API.
struct HomeEntity: AppEntity {
    let id: String
    let name: String
    let thermostatRoomId: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Casa" }
    static var defaultQuery = HomeEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct HomeEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HomeEntity] {
        cachedHomes().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HomeEntity] {
        cachedHomes()
    }

    /// Con más de una casa no se preselecciona ninguna: que Siri pregunte es
    /// mejor que calentar la casa equivocada.
    func defaultResult() async -> HomeEntity? {
        let homes = cachedHomes()
        return homes.count == 1 ? homes.first : nil
    }

    private func cachedHomes() -> [HomeEntity] {
        SharedStore.load().homes.map {
            HomeEntity(id: $0.id, name: $0.name, thermostatRoomId: $0.thermostatRoomId)
        }
    }
}

// MARK: - Intent

struct WarmUpHomeIntent: AppIntent {
    static var title: LocalizedStringResource { "Tengo frío" }
    static var description: IntentDescription {
        IntentDescription("Sube el objetivo 1 °C por encima de la temperatura actual durante 2 horas.")
    }

    /// Se resuelve en segundo plano: no hace falta traer la app a pantalla.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Casa", requestValueDialog: "¿En qué casa tienes frío?")
    var home: HomeEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Tengo frío en \(\.$home)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings()
        let auth = AuthManager(settings: settings)
        guard auth.isAuthenticated else { throw WarmUpError.notAuthenticated }
        let energy = EnergyService(authManager: auth, settings: settings)

        let (homeId, homeName, roomId) = try await resolveTarget(using: energy, settings: settings)

        let status = try await energy.fetchHomeStatus(homeId: homeId)
        let room = status.rooms?.first { $0.id == roomId }
        let base = room?.thermMeasuredTemperature ?? room?.thermSetpointTemperature ?? 20
        let target = ((base + 1) * 2).rounded() / 2   // +1 °C ajustado al medio grado

        try await energy.setRoomTemperature(
            homeId: homeId,
            roomId: roomId,
            temperature: target,
            endTime: Date().addingTimeInterval(2 * 3600).timeIntervalSince1970
        )
        WidgetCenter.shared.reloadAllTimelines()

        return .result(dialog: "Subo \(homeName) a \(Formatters.temperature(target)) durante dos horas.")
    }

    /// Casa elegida, o la única disponible. Si la caché no tiene la habitación
    /// del termostato (widget nunca abierto), se pide la topología a la API.
    @MainActor
    private func resolveTarget(using energy: EnergyService,
                               settings: AppSettings) async throws -> (String, String, String) {
        if let home, let roomId = home.thermostatRoomId {
            return (home.id, home.name, roomId)
        }

        let cache = SharedStore.load()
        let visible = cache.homes.filter { !settings.hiddenHomeIds.contains($0.id) }
        if home == nil, visible.count == 1, let only = visible.first, let roomId = only.thermostatRoomId {
            return (only.id, only.name, roomId)
        }

        // Sin datos suficientes en caché: resolver contra la API.
        let homes = try await energy.fetchHomes()
        let candidates = homes.filter { !settings.hiddenHomeIds.contains($0.id) }
        let match = home.flatMap { selected in homes.first { $0.id == selected.id } }
            ?? (candidates.count == 1 ? candidates.first : nil)
        guard let match else {
            // Varias casas y ninguna elegida: Siri pregunta en vez de dar por hecho.
            guard candidates.isEmpty else {
                throw $home.needsValueError("¿En qué casa tienes frío?")
            }
            throw WarmUpError.noHome
        }
        guard let roomId = match.heatingRooms.first?.id else { throw WarmUpError.noThermostat }
        return (match.id, match.name, roomId)
    }
}

// MARK: - Errores

enum WarmUpError: Error, CustomLocalizedStringResourceConvertible {
    case notAuthenticated
    case noHome
    case noThermostat

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAuthenticated: "Abre Calefacción Netatmo e inicia sesión primero."
        case .noHome: "No sé en qué casa. Elige una en el atajo."
        case .noThermostat: "Esa casa no tiene termostato configurado."
        }
    }
}

// MARK: - Atajo con frase para Siri

/// Las frases con `\(\.$home)` generan una variante por casa, así que con dos
/// casas se puede decir «tengo frío en La Granja» sin pasar por el selector.
struct CalefaccionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WarmUpHomeIntent(),
            phrases: [
                "Tengo frío en \(.applicationName)",
                "Tengo frío en \(\.$home) con \(.applicationName)",
                "Sube la calefacción de \(\.$home) con \(.applicationName)",
                "Sube la calefacción en \(.applicationName)",
                "Dame calor en \(.applicationName)",
            ],
            shortTitle: "Tengo frío",
            systemImageName: "thermometer.sun.fill"
        )
    }
}
