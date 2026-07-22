//
//  AppModel.swift
//  Calefaccion Netatmo
//
//  Contenedor raíz de dependencias (ajustes + auth + servicio Energy).
//

import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let auth: AuthManager
    let energy: EnergyService

    init() {
        let settings = AppSettings()
        self.settings = settings
        let auth = AuthManager(settings: settings)
        self.auth = auth
        self.energy = EnergyService(authManager: auth, settings: settings)
    }
}
