//
//  LoginView.swift
//  Calefaccion Netatmo
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "thermometer.sun.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Calefacción Netatmo")
                    .font(.largeTitle.bold())
                Text("Controla la calefacción de tus casas desde una sola app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            if !settings.hasValidCredentials {
                Label("Configura las credenciales de Netatmo Connect en Ajustes antes de conectar.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await auth.login() }
            } label: {
                HStack {
                    if auth.isAuthenticating {
                        ProgressView().tint(.white)
                    } else {
                        Text("Conectar con Netatmo")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(auth.isAuthenticating || !settings.hasValidCredentials)
            .padding(.horizontal, 32)

            Button {
                showSettings = true
            } label: {
                Label("Ajustes", systemImage: "gearshape")
            }
            .font(.subheadline)

            if let error = auth.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer(minLength: 40)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

#Preview {
    LoginView()
        .environment(AppSettings())
        .environment(AuthManager(settings: AppSettings()))
}
