//
//  HomeDetailView.swift
//  Calefaccion Netatmo
//
//  Detalle de una casa completa: horario activo + uso de calefacción.
//  (La caldera calienta toda la casa, así que no hay control por habitación.)
//

import SwiftUI
import Charts

struct HomeDetailView: View {
    let home: Home
    /// Se llama tras editar un horario para refrescar la topología (homesdata).
    var onSchedulesChanged: () async -> Void = {}

    @Environment(EnergyService.self) private var energy
    @State private var model = HomeDetailViewModel()
    @State private var usage = ConsumptionViewModel()

    private var thermostatRoom: Room? { home.heatingRooms.first }

    private var editableSchedule: HomeSchedule? {
        home.schedules?.first { $0.id == model.selectedScheduleId }
            ?? home.selectedSchedule
            ?? home.schedules?.first
    }

    var body: some View {
        List {
            if let schedules = home.schedules, !schedules.isEmpty {
                scheduleSection(schedules)
            }
            if let schedule = editableSchedule {
                Section {
                    NavigationLink {
                        ScheduleEditView(home: home, schedule: schedule, onSaved: onSchedulesChanged)
                    } label: {
                        Label("Editar temperaturas del horario", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("Cambia la temperatura de cada franja del horario «\(schedule.displayName)». Las horas no se modifican.")
                }
            }
            usageSection
        }
        .navigationTitle(home.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.prime(with: home)
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
    }

    // MARK: - Horario

    private func scheduleSection(_ schedules: [HomeSchedule]) -> some View {
        Section {
            ForEach(schedules) { schedule in
                Button {
                    guard schedule.id != model.selectedScheduleId else { return }
                    Task { await model.switchSchedule(to: schedule.id, home: home, using: energy) }
                } label: {
                    HStack {
                        Text(schedule.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if schedule.id == model.selectedScheduleId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.orange)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .disabled(model.isSwitching)
        } header: {
            Text("Horario activo")
        } footer: {
            if schedules.count <= 1 {
                Text("Solo hay un horario configurado en esta casa.")
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
            }
        }
    }
}
