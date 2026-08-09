//
//  SettingsView.swift
//  Calefaccion Netatmo
//
//  Ajustes: credenciales de Netatmo Connect, cuenta y preferencias.
//

import SwiftUI

struct SettingsView: View {
    /// Casas conocidas (para mostrar/ocultar). Vacío si aún no hay sesión.
    var homes: [Home] = []

    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var draft = NetatmoCredentials(clientID: "", clientSecret: "", redirectURI: "")
    @State private var savedNotice = false
    @State private var alertsDenied = false

    private let durationOptions: [(minutes: Int, label: LocalizedStringKey)] = [
        (0, "Usar la de Netatmo"),
        (60, "1 hora"),
        (120, "2 horas"),
        (180, "3 horas"),
        (240, "4 horas"),
    ]

    private var credentialsChanged: Bool { draft != settings.credentials }

    var body: some View {
        NavigationStack {
            Form {
                credentialsSection
                accountSection
                preferencesSection
                alertsSection
                if !homes.isEmpty { homesSection }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
            .onAppear { draft = settings.credentials }
            .alert("Credenciales guardadas", isPresented: $savedNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Si cambiaste la app de Netatmo, vuelve a conectar la cuenta.")
            }
        }
    }

    // MARK: - Credenciales

    @ViewBuilder
    private var credentialsSection: some View {
        Section {
            LabeledContent("client_id") {
                TextField("client_id", text: $draft.clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("client_secret") {
                SecureField("client_secret", text: $draft.clientSecret)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Redirect URI") {
                TextField("miapp://callback", text: $draft.redirectURI)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            Button {
                settings.updateCredentials(draft)
                if credentialsChanged, auth.isAuthenticated { auth.logout() }
                savedNotice = true
            } label: {
                Text("Guardar credenciales")
            }
            .disabled(!draft.isComplete || !credentialsChanged)
        } header: {
            Text("Netatmo Connect")
        } footer: {
            Text("Obtén estos datos en dev.netatmo.com › My apps. La Redirect URI debe estar registrada allí exactamente igual. Se guardan de forma segura en el Llavero.")
        }
    }

    // MARK: - Cuenta

    private var accountSection: some View {
        Section("Cuenta") {
            HStack {
                Label("Estado", systemImage: auth.isAuthenticated ? "checkmark.seal.fill" : "xmark.seal")
                    .foregroundStyle(auth.isAuthenticated ? .green : .secondary)
                Spacer()
                Text(auth.isAuthenticated ? "Conectado" : "No conectado")
                    .foregroundStyle(.secondary)
            }
            if auth.isAuthenticated {
                Button(role: .destructive) {
                    auth.logout()
                } label: {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    // MARK: - Preferencias

    private var preferencesSection: some View {
        @Bindable var settingsBindable = settings
        return Section {
            Picker("Duración de ajuste manual", selection: $settingsBindable.defaultManualDurationMinutes) {
                ForEach(durationOptions, id: \.minutes) { option in
                    Text(option.label).tag(option.minutes)
                }
            }
        } header: {
            Text("Preferencias")
        } footer: {
            Text("Cuánto se mantiene una temperatura fijada a mano antes de volver a la programación.")
        }
    }

    // MARK: - Avisos

    private var alertsSection: some View {
        Section {
            Toggle("Batería baja y desconexión", isOn: Binding(
                get: { settings.alertsEnabled },
                set: { enable in Task { await setAlerts(enabled: enable) } }
            ))
        } header: {
            Text("Avisos")
        } footer: {
            if alertsDenied {
                Text("Las notificaciones están desactivadas para esta app. Actívalas en Ajustes de iOS › Calefacción Netatmo › Notificaciones.")
                    .foregroundStyle(.red)
            } else {
                Text("La app comprueba las casas de vez en cuando en segundo plano y avisa si un termostato se queda sin pilas o sin conexión. iOS decide cada cuánto según el uso.")
            }
        }
    }

    /// Activar los avisos exige permiso del sistema: si se deniega, el interruptor vuelve atrás.
    private func setAlerts(enabled: Bool) async {
        guard enabled else {
            settings.alertsEnabled = false
            alertsDenied = false
            return
        }
        let granted = await AlertsService.requestAuthorization()
        settings.alertsEnabled = granted
        alertsDenied = !granted
        if granted { BackgroundRefresh.schedule() }
    }

    // MARK: - Casas

    private var homesSection: some View {
        @Bindable var settingsBindable = settings
        return Section {
            ForEach(homes) { home in
                Toggle(home.name, isOn: Binding(
                    get: { !settings.hiddenHomeIds.contains(home.id) },
                    set: { settings.setHome(home.id, hidden: !$0) }
                ))
            }
        } header: {
            Text("Casas visibles")
        } footer: {
            Text("Desactiva una casa para ocultarla de la pantalla de inicio.")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
        .environment(AuthManager(settings: AppSettings()))
}
