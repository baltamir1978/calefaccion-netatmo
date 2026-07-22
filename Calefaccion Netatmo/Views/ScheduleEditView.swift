//
//  ScheduleEditView.swift
//  Calefaccion Netatmo
//
//  Editor de temperaturas de un horario (mantiene las horas). Con vista previa y confirmación.
//

import SwiftUI

struct ScheduleEditView: View {
    let home: Home
    let schedule: HomeSchedule
    var onSaved: () async -> Void = {}

    @Environment(EnergyService.self) private var energy
    @Environment(\.dismiss) private var dismiss
    @State private var model = ScheduleEditViewModel()
    @State private var showConfirm = false

    private var thermostatRoomId: String? { home.heatingRooms.first?.id }

    var body: some View {
        List {
            Section("Franjas del horario") {
                ForEach(model.zones) { zone in
                    tempRow(title: zone.name,
                            value: model.temperature(forZone: zone.id),
                            onMinus: { model.adjustZone(zone.id, by: -model.step) },
                            onPlus: { model.adjustZone(zone.id, by: model.step) })
                }
            }
            Section("Especiales") {
                tempRow(title: "Ausente",
                        value: model.awayTemp,
                        onMinus: { model.adjustAway(by: -model.step) },
                        onPlus: { model.adjustAway(by: model.step) })
                tempRow(title: "Antihielo",
                        value: model.hgTemp,
                        onMinus: { model.adjustHg(by: -model.step) },
                        onPlus: { model.adjustHg(by: model.step) })
            }
        }
        .navigationTitle("Editar temperaturas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Revisar") { showConfirm = true }
                    .disabled(!model.hasChanges || model.isSaving)
            }
        }
        .task { model.prime(schedule: schedule, thermostatRoomId: thermostatRoomId) }
        .sheet(isPresented: $showConfirm) { confirmSheet }
        .alert("No se pudo guardar",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Fila de temperatura

    private func tempRow(title: String, value: Double,
                         onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: onMinus) {
                Image(systemName: "minus.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)

            Text(Formatters.temperature(value))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 64)

            Button(action: onPlus) {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
        }
    }

    // MARK: - Hoja de confirmación

    private var confirmSheet: some View {
        NavigationStack {
            List {
                Section("Cambios a aplicar") {
                    ForEach(model.changes()) { change in
                        HStack {
                            Text(change.label)
                            Spacer()
                            Text("\(Formatters.temperature(change.from)) → \(Formatters.temperature(change.to))")
                                .foregroundStyle(.orange)
                                .monospacedDigit()
                        }
                    }
                }
                Section {
                    Button {
                        Task {
                            let ok = await model.save(homeId: home.id, schedule: schedule,
                                                      thermostatRoomId: thermostatRoomId, using: energy)
                            if ok {
                                showConfirm = false
                                await onSaved()
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isSaving { ProgressView().tint(.white) }
                            else { Text("Guardar en Netatmo").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(model.isSaving)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Se sobrescribe el horario «\(schedule.displayName)» en Netatmo. Las horas y las demás franjas no cambian.")
                }
            }
            .navigationTitle("Confirmar cambios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { showConfirm = false }.disabled(model.isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
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
            timetable: [TimetableEntry(zoneId: 0, mOffset: 420), TimetableEntry(zoneId: 1, mOffset: 1320)],
            awayTemp: 12, hgTemp: 7)],
        thermMode: "schedule", thermSetpointDefaultDuration: 180)
    return NavigationStack {
        ScheduleEditView(home: home, schedule: home.schedules!.first!)
    }
    .environment(EnergyService(authManager: AuthManager(settings: AppSettings()), settings: AppSettings()))
}
