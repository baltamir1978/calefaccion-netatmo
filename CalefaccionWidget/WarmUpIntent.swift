//
//  WarmUpIntent.swift
//  CalefaccionWidget
//
//  Acción "Tengo frío": pone el objetivo a +1 °C sobre la temperatura actual durante 2 horas.
//

import AppIntents
import WidgetKit

struct WarmUpIntent: AppIntent {
    static var title: LocalizedStringResource { "Tengo frío" }
    static var description: IntentDescription {
        IntentDescription("Sube el objetivo 1 °C por encima de la temperatura actual durante 2 horas.")
    }

    @Parameter(title: "homeId") var homeId: String
    @Parameter(title: "roomId") var roomId: String

    init() {}
    init(homeId: String, roomId: String) {
        self.homeId = homeId
        self.roomId = roomId
    }

    func perform() async throws -> some IntentResult {
        let client = WidgetNetatmoClient()
        let status = try await client.fetchStatus(homeId: homeId, roomId: roomId)
        let base = status.currentTemp ?? status.targetTemp ?? 20
        let target = ((base + 1) * 2).rounded() / 2   // +1 °C redondeado a 0.5
        let endtime = Date().addingTimeInterval(2 * 3600).timeIntervalSince1970
        try await client.setRoomTemperature(homeId: homeId, roomId: roomId, temp: target, endtime: endtime)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
