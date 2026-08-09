//
//  ScheduleWeek.swift
//  Calefaccion Netatmo
//
//  Convierte el `timetable` de Netatmo en franjas por día para poder pintarlo.
//
//  Netatmo describe la semana como una lista de cambios: cada entrada tiene un
//  `m_offset` (minutos desde el lunes a las 00:00) y la zona que empieza a regir
//  en ese instante hasta el siguiente cambio. La semana es cíclica: lo que hay
//  antes del primer cambio lo cubre la última zona de la lista.
//

import Foundation

/// Un tramo continuo dentro de un día, en minutos desde medianoche (`end` exclusivo).
struct ScheduleSlot: Identifiable, Hashable {
    let dayIndex: Int
    let start: Int
    let end: Int
    let zoneId: Int

    var id: String { "\(dayIndex)-\(start)" }
    var duration: Int { end - start }
}

/// Un día de la semana con sus tramos ya recortados a 00:00–24:00.
struct ScheduleDay: Identifiable, Hashable {
    /// 0 = lunes … 6 = domingo, igual que los offsets de Netatmo.
    let index: Int
    let slots: [ScheduleSlot]

    var id: Int { index }

    /// Nombre del día en el idioma del sistema ("lunes", "martes"…).
    var name: String {
        let symbols = DateFormatter().standaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return String(localized: "Día \(index + 1)") }
        // `standaloneWeekdaySymbols` empieza en domingo; los offsets empiezan en lunes.
        return symbols[(index + 1) % 7].capitalized
    }

    var shortName: String { String(name.prefix(3)) }
}

enum ScheduleWeek {
    static let minutesPerDay = 1440
    static let minutesPerWeek = minutesPerDay * 7

    /// Un cambio de zona ya normalizado, en minutos desde el lunes 00:00.
    private struct Change {
        let offset: Int
        let zoneId: Int
    }

    /// Tramo continuo dentro de la semana, antes de recortarlo por días.
    private struct Interval {
        let start: Int
        let end: Int
        let zoneId: Int
    }

    /// Expande el timetable en los 7 días. Devuelve vacío si no hay datos utilizables.
    static func days(from timetable: [TimetableEntry]?) -> [ScheduleDay] {
        var changes: [Change] = []
        for entry in timetable ?? [] {
            let offset = min(max(entry.mOffset ?? 0, 0), minutesPerWeek - 1)
            changes.append(Change(offset: offset, zoneId: entry.zoneId))
        }
        changes.sort { $0.offset < $1.offset }
        guard let first = changes.first, let last = changes.last else { return [] }

        var intervals: [Interval] = []
        if first.offset > 0 {
            intervals.append(Interval(start: 0, end: first.offset, zoneId: last.zoneId))
        }
        for (i, change) in changes.enumerated() {
            let end = i + 1 < changes.count ? changes[i + 1].offset : minutesPerWeek
            // Descarta entradas duplicadas en el mismo minuto, que quedarían vacías.
            if end > change.offset {
                intervals.append(Interval(start: change.offset, end: end, zoneId: change.zoneId))
            }
        }

        var result: [ScheduleDay] = []
        for day in 0..<7 {
            let dayStart = day * minutesPerDay
            let dayEnd = dayStart + minutesPerDay
            var slots: [ScheduleSlot] = []
            for interval in intervals {
                let start = max(interval.start, dayStart)
                let end = min(interval.end, dayEnd)
                guard start < end else { continue }
                slots.append(ScheduleSlot(dayIndex: day,
                                          start: start - dayStart,
                                          end: end - dayStart,
                                          zoneId: interval.zoneId))
            }
            slots.sort { $0.start < $1.start }
            result.append(ScheduleDay(index: day, slots: merged(slots)))
        }
        return result
    }

    /// Une tramos consecutivos de la misma zona para no pintar cortes invisibles.
    private static func merged(_ slots: [ScheduleSlot]) -> [ScheduleSlot] {
        var result: [ScheduleSlot] = []
        for slot in slots {
            if let previous = result.last, previous.zoneId == slot.zoneId, previous.end == slot.start {
                result[result.count - 1] = ScheduleSlot(dayIndex: previous.dayIndex,
                                                        start: previous.start,
                                                        end: slot.end,
                                                        zoneId: previous.zoneId)
            } else {
                result.append(slot)
            }
        }
        return result
    }

    /// Índice de día (0 = lunes) correspondiente a una fecha.
    static func dayIndex(for date: Date, calendar: Calendar = .current) -> Int {
        // `weekday` es 1 = domingo … 7 = sábado.
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}
