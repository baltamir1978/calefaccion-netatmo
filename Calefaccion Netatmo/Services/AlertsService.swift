//
//  AlertsService.swift
//  Calefaccion Netatmo
//
//  Avisos locales de batería baja y termostato sin conexión. Se evalúan tanto al
//  refrescar dentro de la app como desde el refresco en segundo plano.
//
//  Cada aviso se recuerda para no repetirlo: el de batería se puede repetir pasados
//  unos días (las pilas siguen bajas), el de "sin conexión" solo se repite si el
//  termostato llegó a volver.
//

import Foundation
import UserNotifications

@MainActor
enum AlertsService {
    /// Plazo mínimo antes de volver a avisar de la misma batería baja.
    static let batteryReminder: TimeInterval = 3 * 24 * 3600

    // MARK: - Permiso

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    // MARK: - Evaluación

    /// Revisa el estado recién traído y lanza los avisos que procedan.
    static func evaluate(homes: [Home], statuses: [String: HomeStatusHome], settings: AppSettings) async {
        guard settings.alertsEnabled, await isAuthorized() else { return }
        for home in homes where !settings.hiddenHomeIds.contains(home.id) {
            guard let status = statuses[home.id] else { continue }
            await checkBatteries(home: home, status: status)
            await checkReachability(home: home, status: status)
        }
    }

    private static func checkBatteries(home: Home, status: HomeStatusHome) async {
        for battery in status.batteries(for: home) {
            let key = "battery-\(battery.id)"
            guard battery.isLow else {
                // Pilas cambiadas: olvida el aviso para poder avisar la próxima vez.
                clear(key)
                continue
            }
            guard shouldSend(key, notBefore: batteryReminder) else { continue }
            await send(key: key,
                       title: "Batería baja",
                       body: "\(battery.name) en \(home.name). Conviene cambiar las pilas.")
        }
    }

    private static func checkReachability(home: Home, status: HomeStatusHome) async {
        guard let roomId = home.heatingRooms.first?.id,
              let room = status.rooms?.first(where: { $0.id == roomId }),
              let reachable = room.reachable else { return }
        let key = "offline-\(home.id)"
        guard !reachable else {
            clear(key)
            return
        }
        // Sin plazo: mientras siga caído no se vuelve a insistir.
        guard shouldSend(key, notBefore: nil) else { return }
        await send(key: key,
                   title: "Termostato sin conexión",
                   body: "\(home.name) no responde. Revisa el termostato o la conexión.")
    }

    // MARK: - Envío

    private static func send(key: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            markSent(key)
        } catch {
            // Si no se pudo entregar, no lo damos por avisado: se reintentará.
        }
    }

    // MARK: - Registro de avisos ya enviados

    private static let sentKey = "sentAlerts"

    /// `notBefore` nil = no repetir mientras la marca siga puesta.
    private static func shouldSend(_ key: String, notBefore: TimeInterval?) -> Bool {
        guard let last = sentAlerts()[key] else { return true }
        guard let notBefore else { return false }
        return Date().timeIntervalSince(last) >= notBefore
    }

    private static func sentAlerts() -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: sentKey) as? [String: Double] ?? [:]
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private static func markSent(_ key: String) {
        var raw = UserDefaults.standard.dictionary(forKey: sentKey) as? [String: Double] ?? [:]
        raw[key] = Date().timeIntervalSince1970
        UserDefaults.standard.set(raw, forKey: sentKey)
    }

    private static func clear(_ key: String) {
        var raw = UserDefaults.standard.dictionary(forKey: sentKey) as? [String: Double] ?? [:]
        guard raw.removeValue(forKey: key) != nil else { return }
        UserDefaults.standard.set(raw, forKey: sentKey)
    }
}
