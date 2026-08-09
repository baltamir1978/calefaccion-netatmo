//
//  BackgroundRefresh.swift
//  Calefaccion Netatmo
//
//  Refresco periódico en segundo plano (BGAppRefreshTask) para poder avisar de
//  batería baja o de un termostato caído sin tener que abrir la app.
//
//  El identificador debe estar declarado en BGTaskSchedulerPermittedIdentifiers
//  (build setting INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers) y el target
//  necesita el modo de segundo plano "fetch".
//

import Foundation
import BackgroundTasks

enum BackgroundRefresh {
    static let taskIdentifier = "Altamirano.Calefaccion-Netatmo.refresh"

    /// Margen mínimo antes de la siguiente ejecución. iOS decide el momento real
    /// según el uso de la app y la batería del dispositivo.
    static let interval: TimeInterval = 2 * 3600

    /// Pide otra ejecución. Se llama al pasar a segundo plano y tras cada refresco.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Trae el estado de las casas visibles y lanza los avisos que procedan.
    /// Construye sus propias dependencias: en segundo plano no hay vistas ni entorno.
    @MainActor
    static func run() async {
        let settings = AppSettings()
        guard settings.alertsEnabled else { return }

        let auth = AuthManager(settings: settings)
        guard auth.isAuthenticated else { return }

        let energy = EnergyService(authManager: auth, settings: settings)
        guard let homes = try? await energy.fetchHomes() else { return }

        var statuses: [String: HomeStatusHome] = [:]
        for home in homes where !settings.hiddenHomeIds.contains(home.id) {
            statuses[home.id] = try? await energy.fetchHomeStatus(homeId: home.id)
        }
        await AlertsService.evaluate(homes: homes, statuses: statuses, settings: settings)
    }
}
