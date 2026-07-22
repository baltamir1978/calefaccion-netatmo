//
//  HomeOverviewView.swift
//  Calefaccion Netatmo
//
//  Pantalla de inicio: estado completo y control directo de cada casa.
//  Tarjetas compactas para que ambas casas quepan a la vez, con un control
//  vertical (+ / objetivo / –) que evoca el termostato Netatmo.
//

import SwiftUI

struct HomeOverviewView: View {
    @Environment(EnergyService.self) private var energy
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    @State private var model = OverviewViewModel()
    @State private var showSettings = false

    private var visibleHomes: [Home] {
        model.homes.filter { !settings.hiddenHomeIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Calefacción")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                Task { await model.refreshStatuses(using: energy) }
                            } label: {
                                Label("Actualizar", systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) {
                                auth.logout()
                            } label: {
                                Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
                .navigationDestination(for: Home.self) { home in
                    HomeDetailView(home: home) {
                        await model.load(using: energy)
                    }
                }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(homes: model.homes)
        }
        .alert("No se pudo aplicar el cambio",
               isPresented: Binding(get: { model.actionError != nil },
                                    set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
        .task { if model.homes.isEmpty { await model.load(using: energy) } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Cargando…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("No se pudo cargar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Reintentar") { Task { await model.load(using: energy) } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            ScrollView {
                VStack(spacing: 14) {
                    if visibleHomes.isEmpty {
                        ContentUnavailableView("Todas las casas ocultas", systemImage: "eye.slash",
                                               description: Text("Actívalas en Ajustes."))
                            .padding(.top, 40)
                    }
                    ForEach(visibleHomes) { home in
                        HomeCard(home: home, model: model)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await model.refreshStatuses(using: energy) }
        }
    }
}

// MARK: - Tarjeta de casa (compacta)

private struct HomeCard: View {
    let home: Home
    @Bindable var model: OverviewViewModel
    @Environment(EnergyService.self) private var energy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .center) {
                currentBlock
                Spacer()
                if model.canControlTemperature(for: home) {
                    thermostatControl
                }
            }
            modeControl
            footer
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // Cabecera: nombre + estado de caldera.
    private var header: some View {
        HStack {
            Text(home.name).font(.title3.bold())
            Spacer()
            boilerPill
        }
    }

    private var boilerPill: some View {
        let on = model.isBoilerOn(for: home)
        return Label(on ? "Caldera on" : "Caldera off", systemImage: "flame.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(on ? .white : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(on ? Color.orange : Color(.secondarySystemBackground), in: Capsule())
    }

    // Temperatura actual grande.
    private var currentBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Formatters.temperature(model.currentTemperature(for: home)))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(model.isBoilerOn(for: home) ? .orange : .primary)
            Text("Temperatura actual")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !model.isReachable(for: home) {
                Label("Sin conexión", systemImage: "wifi.slash")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    // Control vertical (+ / objetivo / –) al estilo del termostato Netatmo.
    private var thermostatControl: some View {
        VStack(spacing: 6) {
            stepButton(systemImage: "plus", delta: model.step)
            VStack(spacing: 0) {
                Text(Formatters.temperature(model.targetTemperature(for: home)))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(model.isBusy(home) ? "aplicando…" : "objetivo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            stepButton(systemImage: "minus", delta: -model.step)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.orange.opacity(0.5), lineWidth: 1.5))
        .disabled(!model.isReachable(for: home))
    }

    private func stepButton(systemImage: String, delta: Double) -> some View {
        Button {
            model.adjustTarget(by: delta, home: home, using: energy)
        } label: {
            Image(systemName: systemImage)
                .font(.headline.bold())
                .frame(width: 40, height: 32)
                .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
    }

    // Modo del hogar.
    private var modeControl: some View {
        Picker("Modo", selection: Binding(
            get: { model.currentMode(for: home) },
            set: { newMode in Task { await model.setMode(newMode, home: home, using: energy) } }
        )) {
            ForEach(ThermMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.isBusy(home))
    }

    // Pie: horario activo + enlace a detalle en una sola línea.
    private var footer: some View {
        HStack(spacing: 8) {
            if let schedule = model.activeScheduleName(for: home) {
                Image(systemName: "calendar")
                Text(schedule).lineLimit(1)
            }
            Spacer()
            NavigationLink(value: home) {
                HStack(spacing: 4) {
                    Text("Programación y uso")
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    HomeOverviewView()
        .environment(AppSettings())
        .environment(AuthManager(settings: AppSettings()))
        .environment(EnergyService(authManager: AuthManager(settings: AppSettings()), settings: AppSettings()))
}
