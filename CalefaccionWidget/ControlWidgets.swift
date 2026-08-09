//
//  ControlWidgets.swift
//  CalefaccionWidget
//
//  Controles para el Centro de Control (y la pantalla de bloqueo / botón de acción):
//  un botón "Tengo frío" y un interruptor de modo ausente, ambos por casa.
//
//  A diferencia de los widgets, un control no tiene línea de tiempo: el sistema pide
//  su valor cuando lo va a pintar, así que se responde con la caché del App Group y
//  solo se sale a la red para el estado del interruptor.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuración

struct SelectHomeControlIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource { "Elegir casa" }
    static var description: IntentDescription { "Selecciona la casa que controla este botón." }

    @Parameter(title: "Casa")
    var home: HomeEntity?
}

/// Datos mínimos que necesita un control para pintarse y actuar.
struct HomeControlValue {
    let configured: Bool
    let homeId: String
    let homeName: String
    let roomId: String?
    let isAway: Bool

    static let preview = HomeControlValue(configured: true, homeId: "1", homeName: "Casa",
                                          roomId: "r1", isAway: false)
    static let empty = HomeControlValue(configured: false, homeId: "", homeName: "",
                                        roomId: nil, isAway: false)

    /// Resuelve la casa elegida en la configuración. Con dos casas y ninguna
    /// elegida el control se queda inactivo: no debe adivinar cuál calentar.
    static func resolve(_ configuration: SelectHomeControlIntent, mode: String? = nil) -> HomeControlValue {
        guard case .home(let home) = ResolvedHome.resolve(configured: configuration.home) else {
            return .empty
        }
        let resolvedMode = mode ?? WidgetCache.load().snapshots[home.id]?.mode
        return HomeControlValue(configured: true, homeId: home.id, homeName: home.name,
                                roomId: home.thermostatRoomId, isAway: resolvedMode == "away")
    }
}

// MARK: - Botón «Tengo frío»

/// Solo lee la caché: pulsar el botón es lo que hace el trabajo de red.
struct WarmUpControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectHomeControlIntent) -> HomeControlValue { .preview }

    func currentValue(configuration: SelectHomeControlIntent) async throws -> HomeControlValue {
        HomeControlValue.resolve(configuration)
    }
}

struct WarmUpControlWidget: ControlWidget {
    let kind = "CalefaccionWarmUpControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: kind, provider: WarmUpControlProvider()) { value in
            ControlWidgetButton(action: WarmUpIntent(homeId: value.homeId, roomId: value.roomId ?? "")) {
                Label("Tengo frío", systemImage: "flame.fill")
                if value.configured {
                    Text(value.homeName)
                } else {
                    Text("Elige una casa")
                }
            }
            .disabled(!value.configured || value.roomId == nil)
        }
        .displayName("Tengo frío")
        .description("Sube el objetivo 1 °C durante 2 horas en la casa elegida.")
    }
}

// MARK: - Interruptor de modo ausente

/// El interruptor sí necesita saber el modo real, así que consulta la API y
/// se queda con lo último conocido si no hay red.
struct AwayControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectHomeControlIntent) -> HomeControlValue { .preview }

    func currentValue(configuration: SelectHomeControlIntent) async throws -> HomeControlValue {
        let cached = HomeControlValue.resolve(configuration)
        guard cached.configured,
              let live = try? await WidgetNetatmoClient().fetchStatus(homeId: cached.homeId,
                                                                     roomId: cached.roomId)
        else { return cached }
        return HomeControlValue.resolve(configuration, mode: live.mode)
    }
}

struct AwayModeControlWidget: ControlWidget {
    let kind = "CalefaccionAwayControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: kind, provider: AwayControlProvider()) { value in
            ControlWidgetToggle("Modo ausente",
                                isOn: value.isAway,
                                action: SetAwayModeIntent(homeId: value.homeId)) { isAway in
                Label(isAway ? "Ausente" : "Programación",
                      systemImage: isAway ? "figure.walk.departure" : "calendar")
                if value.configured {
                    Text(value.homeName)
                } else {
                    Text("Elige una casa")
                }
            }
            .disabled(!value.configured)
            .tint(.orange)
        }
        .displayName("Modo ausente")
        .description("Pone la casa en ausente, o la devuelve a su programación.")
    }
}

/// Acción del interruptor: `value` lo rellena el sistema con el estado pedido.
struct SetAwayModeIntent: SetValueIntent {
    static var title: LocalizedStringResource { "Modo ausente" }
    static var description: IntentDescription {
        IntentDescription("Cambia entre el modo ausente y la programación de la casa.")
    }

    /// Se invoca desde el control con la casa ya resuelta; en Atajos está WarmUpHomeIntent.
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Ausente") var value: Bool
    @Parameter(title: "homeId") var homeId: String

    init() {}
    init(homeId: String) { self.homeId = homeId }

    func perform() async throws -> some IntentResult {
        let mode = value ? "away" : "schedule"
        try await WidgetNetatmoClient().setThermMode(homeId: homeId, mode: mode)
        WidgetCache.updateMode(homeId: homeId, mode: mode)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}
