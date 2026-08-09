//
//  BatteryBarsView.swift
//  Calefaccion Netatmo
//
//  Icono compacto de batería: 4 barras dentro de una carcasa de pila.
//  Cuando solo queda una barra se pinta en rojo (aviso de batería baja).
//

import SwiftUI

struct BatteryBarsView: View {
    let level: BatteryLevel

    /// Alto total del icono; el resto de medidas se derivan de él.
    var height: CGFloat = 13

    private var barColor: Color {
        switch level {
        case .low: .red
        case .medium: .orange
        case .high, .full: .green
        }
    }

    private var width: CGFloat { height * 1.85 }
    private var spacing: CGFloat { height * 0.09 }
    private var padding: CGFloat { height * 0.13 }

    var body: some View {
        HStack(spacing: spacing) {
            HStack(spacing: spacing) {
                ForEach(1...4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(index <= level.bars ? barColor : Color.secondary.opacity(0.18))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(padding)
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: height * 0.22)
                    .strokeBorder(level.isLow ? Color.red : Color.secondary, lineWidth: height * 0.09)
            )

            // Borne positivo de la pila.
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 0,
                bottomTrailingRadius: height * 0.12, topTrailingRadius: height * 0.12
            )
            .fill(level.isLow ? Color.red : Color.secondary)
            .frame(width: height * 0.11, height: height * 0.38)
        }
        .accessibilityElement()
        .accessibilityLabel("\(level.displayName), \(level.bars) de 4")
    }
}

/// Etiqueta de batería con nombre de módulo opcional, para listas de dispositivos.
struct BatteryBadge: View {
    let battery: ModuleBattery
    var showsName = true

    var body: some View {
        HStack(spacing: 5) {
            BatteryBarsView(level: battery.level)
            if showsName {
                Text(battery.name)
                    .font(.caption2)
                    .foregroundStyle(battery.isLow ? .red : .secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        ForEach(BatteryLevel.allCases.reversed(), id: \.self) { level in
            HStack(spacing: 10) {
                BatteryBarsView(level: level)
                BatteryBarsView(level: level, height: 24)
                Text(level.displayName).font(.caption)
            }
        }
    }
    .padding()
}
