//
//  HomeDetailView.swift
//  Calefaccion Netatmo
//
//  Detalle de una casa completa: horarios + uso de calefacción.
//  (La caldera calienta toda la casa, así que no hay control por habitación.)
//

import SwiftUI
import Charts

struct HomeDetailView: View {
    /// Se llama tras cambiar los horarios para refrescar la pantalla de inicio.
    var onSchedulesChanged: () async -> Void = {}

    @Environment(EnergyService.self) private var energy
    @State private var model: HomeDetailViewModel
    @State private var usage = ConsumptionViewModel()

    /// Diálogo de nombre en curso (crear, renombrar o duplicar).
    @State private var nameAction: NameAction?
    @State private var nameDraft = ""
    @State private var scheduleToDelete: HomeSchedule?

    init(home: Home, onSchedulesChanged: @escaping () async -> Void = {}) {
        _model = State(initialValue: HomeDetailViewModel(home: home))
        self.onSchedulesChanged = onSchedulesChanged
    }

    private var home: Home { model.home }
    private var thermostatRoom: Room? { home.heatingRooms.first }

    var body: some View {
        List {
            scheduleSection
            if let schedule = model.editableSchedule {
                scheduleToolsSection(schedule)
            }
            batterySection
            usageSection
        }
        .navigationTitle(home.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.prime()
            await model.loadBatteries(using: energy)
            if let room = thermostatRoom, usage.points.isEmpty {
                await usage.load(home: home, room: room, using: energy)
            }
        }
        .alert("No se pudo cambiar el horario",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert(nameAction?.title ?? "", isPresented: nameActionPresented) {
            TextField("Nombre del horario", text: $nameDraft)
                .textInputAutocapitalization(.sentences)
            Button("Cancelar", role: .cancel) { nameAction = nil }
            Button(nameAction?.confirmLabel ?? "") { performNameAction() }
                .disabled(trimmedName.isEmpty)
        }
        .confirmationDialog("¿Borrar este horario?",
                            isPresented: Binding(get: { scheduleToDelete != nil },
                                                 set: { if !$0 { scheduleToDelete = nil } }),
                            presenting: scheduleToDelete) { schedule in
            Button("Borrar «\(schedule.displayName)»", role: .destructive) {
                Task {
                    await model.deleteSchedule(schedule, using: energy)
                    await onSchedulesChanged()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Se borrará en Netatmo y no se puede deshacer.")
        }
    }

    // MARK: - Horarios

    private var scheduleSection: some View {
        Section {
            ForEach(model.schedules) { schedule in
                scheduleRow(schedule)
            }
            Button {
                start(.create)
            } label: {
                Label("Nuevo horario", systemImage: "plus")
            }
            .disabled(model.isWorking)
        } header: {
            HStack {
                Text("Horarios")
                if model.isWorking {
                    Spacer()
                    ProgressView().controlSize(.mini)
                }
            }
        } footer: {
            Text("Toca un horario para activarlo. Desliza una fila para renombrarlo, duplicarlo o borrarlo. El horario nuevo arranca con una semana tipo (confort de día, noche a partir de las 23:00).")
        }
        .disabled(model.isSwitching)
    }

    private func scheduleRow(_ schedule: HomeSchedule) -> some View {
        let isActive = schedule.id == model.selectedScheduleId
        return Button {
            guard !isActive else { return }
            Task {
                await model.switchSchedule(to: schedule.id, using: energy)
                await onSchedulesChanged()
            }
        } label: {
            HStack {
                Text(schedule.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityLabel(schedule.displayName)
        .accessibilityValue(isActive ? Text("Activo") : Text("Inactivo"))
        .accessibilityHint(isActive ? Text("") : Text("Toca dos veces para activarlo"))
        .swipeActions(edge: .trailing) {
            if model.canDelete(schedule) {
                Button(role: .destructive) {
                    scheduleToDelete = schedule
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            }
            Button {
                start(.rename(schedule))
            } label: {
                Label("Renombrar", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button {
                start(.duplicate(schedule))
            } label: {
                Label("Duplicar", systemImage: "plus.square.on.square")
            }
            .tint(.indigo)
        }
    }

    private func scheduleToolsSection(_ schedule: HomeSchedule) -> some View {
        Section {
            NavigationLink {
                ScheduleWeekView(home: home, schedule: schedule)
            } label: {
                Label("Ver horario semanal", systemImage: "calendar")
            }
            NavigationLink {
                ScheduleEditView(home: home, schedule: schedule) {
                    await model.reload(using: energy)
                    await onSchedulesChanged()
                }
            } label: {
                Label("Editar temperaturas del horario", systemImage: "slider.horizontal.3")
            }
        } footer: {
            Text("Cambia la temperatura de cada franja del horario «\(schedule.displayName)». Las horas no se modifican.")
        }
    }

    // MARK: - Diálogo de nombre

    /// Acciones que piden un nombre antes de tocar Netatmo.
    private enum NameAction {
        case create
        case rename(HomeSchedule)
        case duplicate(HomeSchedule)

        var title: LocalizedStringKey {
            switch self {
            case .create: "Nuevo horario"
            case .rename: "Renombrar horario"
            case .duplicate: "Duplicar horario"
            }
        }

        var confirmLabel: LocalizedStringKey {
            switch self {
            case .create: "Crear"
            case .rename: "Renombrar"
            case .duplicate: "Duplicar"
            }
        }
    }

    private var nameActionPresented: Binding<Bool> {
        Binding(get: { nameAction != nil }, set: { if !$0 { nameAction = nil } })
    }

    private var trimmedName: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func start(_ action: NameAction) {
        switch action {
        case .create:
            nameDraft = String(localized: "Horario nuevo")
        case .rename(let schedule):
            nameDraft = schedule.displayName
        case .duplicate(let schedule):
            nameDraft = model.copyName(for: schedule)
        }
        nameAction = action
    }

    private func performNameAction() {
        guard let action = nameAction, !trimmedName.isEmpty else { return }
        let name = trimmedName
        nameAction = nil
        Task {
            switch action {
            case .create:
                await model.createSchedule(named: name, using: energy)
            case .rename(let schedule):
                await model.renameSchedule(schedule, to: name, using: energy)
            case .duplicate(let schedule):
                await model.duplicateSchedule(schedule, named: name, using: energy)
            }
            await onSchedulesChanged()
        }
    }

    // MARK: - Batería

    @ViewBuilder
    private var batterySection: some View {
        if !model.batteries.isEmpty {
            Section {
                ForEach(model.batteries) { battery in
                    HStack {
                        Text(battery.name)
                        Spacer()
                        Text(battery.level.displayName)
                            .font(.caption)
                            .foregroundStyle(battery.isLow ? .red : .secondary)
                        BatteryBarsView(level: battery.level, height: 15)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Batería")
            } footer: {
                if model.batteries.contains(where: \.isLow) {
                    Text("Sustituye las pilas de los dispositivos marcados en rojo.")
                }
            }
        }
    }

    // MARK: - Uso

    @ViewBuilder
    private var usageSection: some View {
        Section {
            if thermostatRoom == nil {
                Text("Esta casa no reporta datos de uso.")
                    .foregroundStyle(.secondary)
            } else {
                usageChart
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                if let room = thermostatRoom {
                    NavigationLink {
                        ConsumptionView(home: home, room: room)
                    } label: {
                        Label("Ver uso detallado", systemImage: "chart.xyaxis.line")
                    }
                }
            }
        } header: {
            Text("Uso de calefacción (caldera encendida)")
        } footer: {
            Text("Tiempo que la caldera ha estado encendida por periodo. Netatmo no expone el consumo eléctrico real.")
        }
    }

    @ViewBuilder
    private var usageChart: some View {
        switch usage.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        case .failed(let message):
            ContentUnavailableView {
                Label("Sin datos de uso", systemImage: "chart.bar.xaxis")
            } description: {
                Text(message)
            }
        case .loaded:
            if usage.points.isEmpty {
                ContentUnavailableView("Sin datos en este periodo", systemImage: "chart.bar.xaxis")
            } else {
                Chart(usage.points) { point in
                    BarMark(
                        x: .value("Fecha", point.date),
                        y: .value("Minutos", point.value / 60)
                    )
                    .foregroundStyle(.orange)
                }
                .chartYAxisLabel("min")
                .accessibilityLabel(Text("Uso de calefacción de los últimos días"))
            }
        }
    }
}
