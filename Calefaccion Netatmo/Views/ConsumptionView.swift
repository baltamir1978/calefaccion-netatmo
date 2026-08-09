//
//  ConsumptionView.swift
//  Calefaccion Netatmo
//
//  Uso de calefacción de una habitación (tiempo de caldera / temperatura).
//

import SwiftUI
import Charts

struct ConsumptionView: View {
    let home: Home
    let room: Room

    @Environment(EnergyService.self) private var energy
    @State private var model = ConsumptionViewModel()

    var body: some View {
        List {
            Section {
                Picker("Dato", selection: $model.measureType) {
                    Text("Uso de caldera").tag(MeasureType.sumBoilerOn)
                    Text("Temperatura").tag(MeasureType.temperature)
                }
                .pickerStyle(.segmented)

                Picker("Escala", selection: $model.scale) {
                    ForEach(MeasureScale.allCases) { scale in
                        Text(scale.displayName).tag(scale)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                chart
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                Text(model.measureType == .sumBoilerOn ? "Tiempo de caldera encendida" : "Temperatura")
            } footer: {
                if model.measureType == .sumBoilerOn {
                    Text("Netatmo no expone el consumo eléctrico real; se muestra el tiempo que la caldera ha estado encendida como indicador de uso.")
                }
            }
        }
        .navigationTitle("Uso · \(room.name)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: taskKey) { await model.load(home: home, room: room, using: energy) }
    }

    private var taskKey: String { "\(model.measureType.rawValue)-\(model.scale.rawValue)" }

    @ViewBuilder
    private var chart: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 220)
        case .failed(let message):
            ContentUnavailableView {
                Label("Sin datos", systemImage: "chart.bar.xaxis")
            } description: {
                Text(message)
            } actions: {
                Button("Reintentar") { Task { await model.load(home: home, room: room, using: energy) } }
            }
        case .loaded:
            if model.points.isEmpty {
                ContentUnavailableView("Sin datos en este periodo", systemImage: "chart.bar.xaxis")
            } else {
                measureChart
            }
        }
    }

    @ViewBuilder
    private var measureChart: some View {
        // Cada barra o punto se anuncia por separado, con su fecha y su valor.
        Chart(model.points) { point in
            if model.measureType == .sumBoilerOn {
                BarMark(
                    x: .value("Fecha", point.date),
                    y: .value("Minutos", point.value / 60)
                )
                .foregroundStyle(.orange)
                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                .accessibilityValue(Text("\(Formatters.duration(seconds: point.value)) de caldera"))
            } else {
                LineMark(
                    x: .value("Fecha", point.date),
                    y: .value("Temperatura", point.value)
                )
                .foregroundStyle(.orange)
                .interpolationMethod(.catmullRom)
                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                .accessibilityValue(Text("\(Formatters.temperatureValue(point.value)) grados"))
            }
        }
        .chartYAxisLabel(model.measureType == .sumBoilerOn ? "min" : "°C")
    }
}
