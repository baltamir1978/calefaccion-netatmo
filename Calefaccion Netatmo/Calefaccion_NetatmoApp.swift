//
//  Calefaccion_NetatmoApp.swift
//  Calefaccion Netatmo
//
//  Created by Bruno Altamirano on 12/07/2026.
//

import SwiftUI

@main
struct Calefaccion_NetatmoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model.settings)
                .environment(model.auth)
                .environment(model.energy)
        }
        // Refresco periódico que iOS despierta cuando le viene bien: comprueba
        // baterías y conexión, y encadena la siguiente ejecución.
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await BackgroundRefresh.run()
            BackgroundRefresh.schedule()
        }
    }
}
