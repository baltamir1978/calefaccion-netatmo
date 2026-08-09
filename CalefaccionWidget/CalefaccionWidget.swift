//
//  CalefaccionWidget.swift
//  CalefaccionWidget
//
//  Widget de estado configurable por casa: anillo con la temperatura actual y objetivo.
//  Fondo blanco si la caldera está apagada, degradado naranja si está encendida.
//

import WidgetKit
import SwiftUI

// MARK: - Entry

struct StatusEntry: TimelineEntry {
    let date: Date
    let configured: Bool
    let homeName: String
    let currentTemp: Double?
    let targetTemp: Double?
    let boilerOn: Bool
    /// Hay varias casas y el widget todavía no tiene una elegida.
    var needsChoice = false

    static let placeholder = StatusEntry(date: .now, configured: true, homeName: "Casa",
                                         currentTemp: 21, targetTemp: 20, boilerOn: false)
    static let unconfigured = StatusEntry(date: .now, configured: false, homeName: "—",
                                          currentTemp: nil, targetTemp: nil, boilerOn: false)
    static let needsHomeChoice = StatusEntry(date: .now, configured: false, homeName: "—",
                                             currentTemp: nil, targetTemp: nil, boilerOn: false,
                                             needsChoice: true)
}

// MARK: - Provider

struct StatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { .placeholder }

    func snapshot(for configuration: SelectHomeIntent, in context: Context) async -> StatusEntry {
        await entry(for: configuration, allowNetwork: !context.isPreview)
    }

    func timeline(for configuration: SelectHomeIntent, in context: Context) async -> Timeline<StatusEntry> {
        let entry = await entry(for: configuration, allowNetwork: true)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: SelectHomeIntent, allowNetwork: Bool) async -> StatusEntry {
        let home: WCachedHome
        switch ResolvedHome.resolve(configured: configuration.home) {
        case .home(let resolved): home = resolved
        case .noCache: return .unconfigured
        case .needsChoice: return .needsHomeChoice
        }
        let snapshot = WidgetCache.load().snapshots[home.id]

        if allowNetwork,
           let live = try? await WidgetNetatmoClient().fetchStatus(homeId: home.id, roomId: home.thermostatRoomId) {
            return StatusEntry(date: .now, configured: true, homeName: home.name,
                               currentTemp: live.currentTemp, targetTemp: live.targetTemp, boilerOn: live.boilerOn)
        }
        // Sin red: se pinta lo último que dejó la app en el App Group.
        return StatusEntry(date: .now, configured: true, homeName: home.name,
                           currentTemp: snapshot?.currentTemp, targetTemp: snapshot?.targetTemp,
                           boilerOn: snapshot?.boilerOn ?? false)
    }
}

// MARK: - Anillo de temperatura

private struct TempRing: View {
    let current: Double?
    let boilerOn: Bool
    var lineWidth: CGFloat = 10

    private let lo = 10.0
    private let hi = 30.0

    private var fraction: Double {
        guard let current else { return 0 }
        return min(1, max(0, (current - lo) / (hi - lo)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(boilerOn ? Color.white.opacity(0.25) : Color.orange.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ringStyle, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Image(systemName: boilerOn ? "flame.fill" : "thermometer.medium")
                    .font(.caption2)
                    .foregroundStyle(boilerOn ? .white : .orange)
                Text(TempFormat.short(current))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(boilerOn ? .white : .primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }

    private var ringStyle: AnyShapeStyle {
        if boilerOn {
            return AnyShapeStyle(Color.white)
        }
        return AnyShapeStyle(LinearGradient(
            colors: [Color(red: 1.0, green: 0.66, blue: 0.28), Color(red: 0.97, green: 0.40, blue: 0.09)],
            startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Vista

struct StatusWidgetView: View {
    var entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    private var onColor: Color { entry.boilerOn ? .white : .primary }
    private var subColor: Color { entry.boilerOn ? .white.opacity(0.85) : .secondary }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                accessoryCircular
            case .accessoryRectangular:
                accessoryRectangular
            case .accessoryInline:
                accessoryInline
            default:
                homeScreen
            }
        }
        .containerBackground(for: .widget) { widgetBackground }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Widgets de la pantalla de inicio (fondo propio, color).
    @ViewBuilder
    private var homeScreen: some View {
        if !entry.configured {
            unconfigured
        } else if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    /// En la pantalla de bloqueo el sistema pinta todo en monocromo: sin fondo de color.
    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    // Descripción única para VoiceOver, que si no leería el anillo trozo a trozo.
    private var accessibilitySummary: Text {
        guard entry.configured else {
            return entry.needsChoice
                ? Text("Sin casa elegida. Mantén pulsado el widget para elegirla.")
                : Text("Sin casa elegida. Abre la app y elige una.")
        }
        let current = entry.currentTemp.map { Text("\(TempFormat.spoken($0)) grados") }
            ?? Text("temperatura desconocida")
        let target = entry.targetTemp.map { Text("objetivo \(TempFormat.spoken($0)) grados") }
            ?? Text("sin objetivo")
        let boiler = entry.boilerOn ? Text("caldera encendida") : Text("caldera apagada")
        return Text("\(entry.homeName): \(current), \(target), \(boiler)")
    }

    // Pequeño: anillo protagonista.
    private var small: some View {
        VStack(spacing: 6) {
            homeLabel
            TempRing(current: entry.currentTemp, boilerOn: entry.boilerOn)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            targetLabel
        }
    }

    // Mediano: anillo + detalles.
    private var medium: some View {
        HStack(spacing: 16) {
            TempRing(current: entry.currentTemp, boilerOn: entry.boilerOn, lineWidth: 12)
                .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 8) {
                homeLabel
                VStack(alignment: .leading, spacing: 2) {
                    Text("Actual \(TempFormat.full(entry.currentTemp))")
                        .font(.headline).foregroundStyle(onColor)
                    Text("Objetivo \(TempFormat.full(entry.targetTemp))")
                        .font(.subheadline).foregroundStyle(subColor)
                }
                boilerPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var homeLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "house.fill").font(.caption2)
            Text(entry.homeName).font(.caption).fontWeight(.medium).lineLimit(1)
        }
        .foregroundStyle(subColor)
        .frame(maxWidth: .infinity, alignment: family == .systemMedium ? .leading : .center)
    }

    private var targetLabel: some View {
        Text("Objetivo \(TempFormat.full(entry.targetTemp))")
            .font(.caption).foregroundStyle(subColor)
    }

    private var boilerPill: some View {
        Label(entry.boilerOn ? "Caldera encendida" : "Caldera apagada", systemImage: "flame.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(entry.boilerOn ? .white : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(entry.boilerOn ? Color.white.opacity(0.22) : Color.orange.opacity(0.12), in: Capsule())
    }

    private var unconfigured: some View {
        VStack(spacing: 6) {
            Image(systemName: entry.needsChoice ? "house.and.flag" : "house.slash").font(.title2)
            if entry.needsChoice {
                Text("Mantén pulsado el widget y elige la casa")
                    .font(.caption).multilineTextAlignment(.center)
            } else {
                Text("Abre la app y elige una casa")
                    .font(.caption).multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pantalla de bloqueo

    /// Circular: aguja de temperatura sobre el rango habitual de una casa.
    private var accessoryCircular: some View {
        Gauge(value: gaugeFraction) {
            Image(systemName: entry.boilerOn ? "flame.fill" : "thermometer.medium")
        } currentValueLabel: {
            Text(TempFormat.short(entry.currentTemp))
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    /// Rectangular: casa, temperatura actual y objetivo, y estado de la caldera.
    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: entry.boilerOn ? "flame.fill" : "house.fill")
                Text(entry.homeName).lineLimit(1)
            }
            .font(.caption2)
            .widgetAccentable()

            Text(TempFormat.full(entry.currentTemp))
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            Text("Objetivo \(TempFormat.full(entry.targetTemp))")
                .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// En línea: cabe una sola frase junto al reloj.
    private var accessoryInline: some View {
        Label {
            Text("\(TempFormat.full(entry.currentTemp)) → \(TempFormat.full(entry.targetTemp))")
        } icon: {
            Image(systemName: entry.boilerOn ? "flame.fill" : "thermometer.medium")
        }
    }

    /// Posición dentro del rango 10–30 °C, que es donde se mueve una casa.
    private var gaugeFraction: Double {
        guard let current = entry.currentTemp else { return 0 }
        return min(1, max(0, (current - 10) / 20))
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if family == .accessoryCircular {
            AccessoryWidgetBackground()
        } else if isAccessory {
            // Rectangular e inline se dibujan directamente sobre el fondo de bloqueo.
            Color.clear
        } else if entry.boilerOn {
            LinearGradient(colors: [Color(red: 1.0, green: 0.66, blue: 0.28),
                                    Color(red: 0.97, green: 0.40, blue: 0.09)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color(.systemBackground)
        }
    }
}

enum TempFormat {
    static func short(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f°", value)
    }
    static func full(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f°", value)
    }
    /// Sin el símbolo de grado: VoiceOver lo lee mejor con la palabra completa.
    static func spoken(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

// MARK: - Widget

struct CalefaccionWidget: Widget {
    let kind = "CalefaccionStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectHomeIntent.self, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Estado calefacción")
        .description("Temperatura actual y objetivo de una casa. Se pone naranja si la caldera está encendida.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    CalefaccionWidget()
} timeline: {
    StatusEntry(date: .now, configured: true, homeName: "La Granja", currentTemp: 21.5, targetTemp: 20, boilerOn: false)
    StatusEntry(date: .now, configured: true, homeName: "Madrid", currentTemp: 19, targetTemp: 21, boilerOn: true)
}

#Preview(as: .systemMedium) {
    CalefaccionWidget()
} timeline: {
    StatusEntry(date: .now, configured: true, homeName: "La Granja", currentTemp: 21.5, targetTemp: 20, boilerOn: false)
    StatusEntry(date: .now, configured: true, homeName: "Madrid", currentTemp: 19, targetTemp: 21, boilerOn: true)
}
