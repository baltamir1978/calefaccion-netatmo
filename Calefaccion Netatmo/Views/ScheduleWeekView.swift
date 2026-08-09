//
//  ScheduleWeekView.swift
//  Calefaccion Netatmo
//
//  Vista de solo lectura del horario semanal: una barra de 24 h por día,
//  desplegable para ver a qué hora empieza cada franja y con qué temperatura.
//

import SwiftUI

struct ScheduleWeekView: View {
    let home: Home
    let schedule: HomeSchedule

    @State private var expandedDay: Int? = ScheduleWeek.dayIndex(for: Date())

    private var thermostatRoomId: String? { home.heatingRooms.first?.id }
    private var days: [ScheduleDay] { ScheduleWeek.days(from: schedule.timetable) }

    private var zonesById: [Int: ScheduleZone] {
        Dictionary(uniqueKeysWithValues: (schedule.zones ?? []).map { ($0.id, $0) })
    }

    /// Zonas que realmente aparecen en la semana, para la leyenda.
    private var usedZoneIds: [Int] {
        var seen: Set<Int> = []
        for day in days {
            for slot in day.slots { seen.insert(slot.zoneId) }
        }
        return seen.sorted()
    }

    var body: some View {
        List {
            if days.isEmpty {
                ContentUnavailableView("Sin franjas horarias",
                                       systemImage: "calendar.badge.exclamationmark",
                                       description: Text("Netatmo no ha devuelto la programación semanal de «\(schedule.displayName)»."))
            } else {
                Section {
                    ForEach(days) { day in
                        dayRow(day)
                    }
                } header: {
                    Text("Semana")
                } footer: {
                    Text("Cada barra son las 24 h de un día, con marcas cada 6 h. Toca un día para ver sus franjas.")
                }
                legendSection
            }
        }
        .navigationTitle(schedule.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Fila de día

    private func dayRow(_ day: ScheduleDay) -> some View {
        DisclosureGroup(isExpanded: expansion(for: day.index)) {
            ForEach(day.slots) { slot in
                slotRow(slot)
            }
        } label: {
            HStack(spacing: 10) {
                Text(day.shortName)
                    .font(.subheadline.weight(isToday(day) ? .bold : .regular))
                    .foregroundStyle(isToday(day) ? Color.orange : .primary)
                    .frame(width: 34, alignment: .leading)
                bar(for: day)
            }
        }
    }

    private func slotRow(_ slot: ScheduleSlot) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color(forZone: slot.zoneId))
                .frame(width: 9, height: 9)
            Text(Formatters.timeOfDay(minutes: slot.start))
                .monospacedDigit()
                .frame(width: 62, alignment: .leading)
            Text(zonesById[slot.zoneId]?.displayName ?? "Zona \(slot.zoneId)")
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Formatters.temperature(temperature(forZone: slot.zoneId)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    // MARK: - Barra de 24 h

    private func bar(for day: ScheduleDay) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(day.slots) { slot in
                        let width = geo.size.width * CGFloat(slot.duration) / CGFloat(ScheduleWeek.minutesPerDay)
                        ZStack {
                            color(forZone: slot.zoneId)
                            // La temperatura solo cabe en las franjas anchas.
                            if width > 36 {
                                Text(Formatters.temperature(temperature(forZone: slot.zoneId)))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: width)
                    }
                }
                // Marcas de 6, 12 y 18 h como referencia visual.
                ForEach([6, 12, 18], id: \.self) { hour in
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1)
                        .offset(x: geo.size.width * CGFloat(hour) / 24)
                }
            }
        }
        .frame(height: 26)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Leyenda

    private var legendSection: some View {
        Section("Zonas") {
            ForEach(usedZoneIds, id: \.self) { zoneId in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(forZone: zoneId))
                        .frame(width: 14, height: 14)
                    Text(zonesById[zoneId]?.displayName ?? "Zona \(zoneId)")
                    Spacer()
                    Text(Formatters.temperature(temperature(forZone: zoneId)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func expansion(for index: Int) -> Binding<Bool> {
        Binding(get: { expandedDay == index },
                set: { expandedDay = $0 ? index : nil })
    }

    private func isToday(_ day: ScheduleDay) -> Bool {
        day.index == ScheduleWeek.dayIndex(for: Date())
    }

    private func temperature(forZone zoneId: Int) -> Double? {
        zonesById[zoneId]?.temperature(forRoom: thermostatRoomId)
    }

    /// Color estable por tipo de zona, para que la barra y la leyenda coincidan.
    private func color(forZone zoneId: Int) -> Color {
        switch zonesById[zoneId]?.type {
        case 0: return .orange
        case 1: return .indigo
        case 2: return .teal
        case 3: return .cyan
        case 4: return .red
        case 5: return .green
        default: return .gray
        }
    }
}

#Preview {
    var timetable: [TimetableEntry] = []
    for day in 0..<7 {
        let base = day * 1440
        timetable.append(TimetableEntry(zoneId: 0, mOffset: base + 420))
        timetable.append(TimetableEntry(zoneId: 4, mOffset: base + 600))
        timetable.append(TimetableEntry(zoneId: 0, mOffset: base + 1080))
        timetable.append(TimetableEntry(zoneId: 1, mOffset: base + 1350))
    }
    let home = Home(
        id: "1", name: "Casa", country: "ES", timezone: "Europe/Madrid",
        rooms: [Room(id: "r1", name: "Salón", type: "livingroom", moduleIds: ["m1"])],
        modules: [Module(id: "m1", type: "NATherm1", name: "Termostato", roomId: "r1", bridge: nil)],
        schedules: [HomeSchedule(
            id: "s1", name: "Semana", selected: true, type: "therm",
            zones: [
                ScheduleZone(id: 0, name: "Confort", type: 0, rooms: [ZoneRoomTemp(id: "r1", thermSetpointTemperature: 21)]),
                ScheduleZone(id: 1, name: "Noche", type: 1, rooms: [ZoneRoomTemp(id: "r1", thermSetpointTemperature: 17)]),
                ScheduleZone(id: 4, name: "Eco", type: 5, rooms: [ZoneRoomTemp(id: "r1", thermSetpointTemperature: 19)]),
            ],
            timetable: timetable,
            awayTemp: 12, hgTemp: 7)],
        thermMode: "schedule", thermSetpointDefaultDuration: 180)
    return NavigationStack {
        ScheduleWeekView(home: home, schedule: home.schedules!.first!)
    }
}
