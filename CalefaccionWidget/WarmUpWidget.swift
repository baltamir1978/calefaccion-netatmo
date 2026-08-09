//
//  WarmUpWidget.swift
//  CalefaccionWidget
//
//  Widget pequeño con un botón "Tengo frío" (sube 1 °C durante 2 h) para la casa elegida.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Entry

struct WarmUpEntry: TimelineEntry {
    let date: Date
    let configured: Bool
    let homeName: String
    let homeId: String
    let roomId: String?
    let targetTemp: Double?
    let boilerOn: Bool
    /// Hay varias casas y el widget todavía no tiene una elegida.
    var needsChoice = false

    static let unconfigured = WarmUpEntry(date: .now, configured: false, homeName: "—",
                                          homeId: "", roomId: nil, targetTemp: nil, boilerOn: false)
    static let needsHomeChoice = WarmUpEntry(date: .now, configured: false, homeName: "—",
                                             homeId: "", roomId: nil, targetTemp: nil,
                                             boilerOn: false, needsChoice: true)
}

// MARK: - Provider

struct WarmUpProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WarmUpEntry {
        WarmUpEntry(date: .now, configured: true, homeName: "Casa", homeId: "1", roomId: "r1",
                    targetTemp: 21, boilerOn: false)
    }

    func snapshot(for configuration: SelectHomeIntent, in context: Context) async -> WarmUpEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectHomeIntent, in context: Context) async -> Timeline<WarmUpEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: SelectHomeIntent) -> WarmUpEntry {
        let home: WCachedHome
        switch ResolvedHome.resolve(configured: configuration.home) {
        case .home(let resolved): home = resolved
        case .noCache: return .unconfigured
        case .needsChoice: return .needsHomeChoice
        }
        let snapshot = WidgetCache.load().snapshots[home.id]
        return WarmUpEntry(date: .now, configured: true, homeName: home.name, homeId: home.id,
                           roomId: home.thermostatRoomId, targetTemp: snapshot?.targetTemp,
                           boilerOn: snapshot?.boilerOn ?? false)
    }
}

// MARK: - Vista

struct WarmUpWidgetView: View {
    var entry: WarmUpEntry

    private var fg: Color { entry.boilerOn ? .white : .primary }

    var body: some View {
        Group {
            if entry.configured, let roomId = entry.roomId {
                content(roomId: roomId)
            } else if entry.configured {
                note("Esta casa no permite ajuste de temperatura.")
            } else if entry.needsChoice {
                note("Mantén pulsado el widget y elige la casa.")
            } else {
                note("Abre la app y elige una casa.")
            }
        }
        .containerBackground(for: .widget) { background }
    }

    private func content(roomId: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "house.fill").font(.caption2)
                Text(entry.homeName).font(.caption).lineLimit(1)
            }
            .foregroundStyle(entry.boilerOn ? .white.opacity(0.85) : .secondary)

            Button(intent: WarmUpIntent(homeId: entry.homeId, roomId: roomId)) {
                VStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.title2)
                    Text("Tengo frío").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityLabel(Text("Tengo frío en \(entry.homeName)"))
            .accessibilityHint(Text("Sube el objetivo un grado durante dos horas"))

            Text("+1 °C durante 2 h")
                .font(.caption2)
                .foregroundStyle(entry.boilerOn ? .white.opacity(0.85) : .secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "flame").font(.title2)
            Text(text).font(.caption).multilineTextAlignment(.center)
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

// MARK: - Widget

struct WarmUpWidget: Widget {
    let kind = "CalefaccionWarmUpWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectHomeIntent.self, provider: WarmUpProvider()) { entry in
            WarmUpWidgetView(entry: entry)
        }
        .configurationDisplayName("Tengo frío")
        .description("Un botón que sube el objetivo 1 °C durante 2 horas en la casa elegida.")
        .supportedFamilies([.systemSmall])
    }
}
