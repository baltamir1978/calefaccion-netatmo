//
//  RootView.swift
//  Calefaccion Netatmo
//
//  Muestra el login o la app principal según el estado de autenticación.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Group {
            if auth.isAuthenticated {
                HomeOverviewView()
            } else {
                LoginView()
            }
        }
        .animation(.default, value: auth.isAuthenticated)
    }
}

#Preview {
    RootView()
        .environment(AppSettings())
        .environment(AuthManager(settings: AppSettings()))
}
