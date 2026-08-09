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
    @Environment(\.scenePhase) private var scenePhase
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
                        .accessibilityLabel(Text("Ajustes"))
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
                        .accessibilityLabel(Text("Cuenta"))
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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.refreshIfStale(using: energy) }
            case .background:
                // Al salir, deja pedido el próximo refresco en segundo plano.
                if settings.alertsEnabled { BackgroundRefresh.schedule() }
            default:
                break
            }
        }
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
    @Environment(\.colorScheme) private var colorScheme

    /// La temperatura grande crece con el tamaño de texto del sistema en vez de
    /// quedarse clavada en 46 pt.
    @ScaledMetric(relativeTo: .largeTitle) private var currentTempSize: CGFloat = 46

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
            manualOverrideRow
            lowBatteryWarning
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(home.name))
        .padding(16)
        // En modo oscuro `.background` y `systemGroupedBackground` son ambos negro:
        // la tarjeta se fundía con la pantalla. El nivel «secondary» sí contrasta
        // en ambos modos, y el borde marca el límite donde la sombra no se ve.
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.06),
                              lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.06), radius: 6, y: 2)
    }

    // Cabecera: nombre + batería del termostato + estado de caldera.
    private var header: some View {
        HStack(spacing: 8) {
            Text(home.name).font(.title3.bold())
            if let battery = model.worstBattery(for: home) {
                BatteryBarsView(level: battery.level)
            }
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
            .background(on ? Color.orange : Color(.tertiarySystemGroupedBackground), in: Capsule())
            .accessibilityLabel(on ? Text("Caldera encendida") : Text("Caldera apagada"))
    }

    // Temperatura actual grande.
    private var currentBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Formatters.temperature(model.currentTemperature(for: home)))
                .font(.system(size: currentTempSize, weight: .bold, design: .rounded))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Temperatura actual"))
        .accessibilityValue(temperatureValueDescription)
    }

    private var temperatureValueDescription: Text {
        let value = Text("\(Formatters.temperatureValue(model.currentTemperature(for: home))) grados")
        guard !model.isReachable(for: home) else { return value }
        return Text("\(value). Sin conexión")
    }

    // Control vertical (+ / objetivo / –) al estilo del termostato Netatmo.
    // Para VoiceOver es un único control ajustable con gestos arriba/abajo.
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Temperatura objetivo"))
        .accessibilityValue(Text("\(Formatters.temperatureValue(model.targetTemperature(for: home))) grados"))
        .accessibilityHint(Text("Desliza arriba o abajo para cambiarla"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                model.adjustTarget(by: model.step, home: home, using: energy)
            case .decrement:
                model.adjustTarget(by: -model.step, home: home, using: energy)
            @unknown default:
                break
            }
        }
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
        .accessibilityLabel(delta > 0 ? Text("Subir temperatura") : Text("Bajar temperatura"))
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

    // Ajuste manual en curso: permite devolver la casa a su programación sin esperar.
    @ViewBuilder
    private var manualOverrideRow: some View {
        if model.hasManualOverride(for: home) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Temperatura fijada a mano")
                        .font(.caption.weight(.medium))
                    if let end = model.manualOverrideEnd(for: home) {
                        Text("hasta las \(Formatters.endOfOverride(end))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Button("Volver al horario") {
                    Task { await model.resumeSchedule(home: home, using: energy) }
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
                .tint(.orange)
                .disabled(model.isBusy(home))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // Aviso de batería baja: solo aparece si algún módulo está en el último escalón.
    @ViewBuilder
    private var lowBatteryWarning: some View {
        let lowModules = model.lowBatteryModules(for: home)
        if !lowModules.isEmpty {
            HStack(spacing: 7) {
                BatteryBarsView(level: .low)
                Text(lowModules.count == 1
                     ? "Batería baja en \(lowModules[0].name)"
                     : "Batería baja en \(lowModules.count) dispositivos")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
    }

    // Pie: horario activo + enlace a detalle en una sola línea.
    private var footer: some View {
        HStack(spacing: 8) {
            if let schedule = model.activeScheduleName(for: home) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                    Text(schedule).lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Horario activo: \(schedule)"))
            }
            Spacer()
            NavigationLink(value: home) {
                HStack(spacing: 4) {
                    Text("Programación y uso")
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(.orange)
            }
            .accessibilityLabel(Text("Programación y uso de \(home.name)"))
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
