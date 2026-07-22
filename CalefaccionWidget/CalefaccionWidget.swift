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

    static let placeholder = StatusEntry(date: .now, configured: true, homeName: "Casa",
                                         currentTemp: 21, targetTemp: 20, boilerOn: false)
    static let unconfigured = StatusEntry(date: .now, configured: false, homeName: "—",
                                          currentTemp: nil, targetTemp: nil, boilerOn: false)
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

    private func resolvedHome(_ configuration: SelectHomeIntent) -> WCachedHome? {
        if let home = configuration.home {
            return WCachedHome(id: home.id, name: home.name, thermostatRoomId: home.thermostatRoomId)
        }
        return WidgetCache.load().homes.first
    }

    private func entry(for configuration: SelectHomeIntent, allowNetwork: Bool) async -> StatusEntry {
        guard let home = resolvedHome(configuration) else { return .unconfigured }
        let snapshot = WidgetCache.load().snapshots[home.id]

        if allowNetwork,
           let live = try? await WidgetNetatmoClient().fetchStatus(homeId: home.id, roomId: home.thermostatRoomId) {
            return StatusEntry(date: .now, configured: true, homeName: home.name,
                               currentTemp: live.currentTemp, targetTemp: live.targetTemp, boilerOn: live.boilerOn)
        }
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
            if !entry.configured {
                unconfigured
            } else if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .containerBackground(for: .widget) { background }
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
            Image(systemName: "house.slash").font(.title2)
            Text("Abre la app y elige una casa").font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var background: some View {
        if entry.boilerOn {
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
        .supportedFamilies([.systemSmall, .systemMedium])
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
