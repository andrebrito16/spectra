//
//  CustomizeClusterSheet.swift
//  Spectra
//
//  Customize a cluster's local identity (Arc-style): display name, icon, and
//  accent color. Sets ClusterRecord.displayName / iconSymbol / iconColorHex —
//  identification only, never touches the kubeconfig.
//

import SwiftUI
import SwiftData

struct CustomizeClusterSheet: View {
    let record: ClusterRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var env
    @State private var name: String
    @State private var symbol: String
    @State private var colorHex: String?

    init(record: ClusterRecord) {
        self.record = record
        _name = State(initialValue: record.displayName ?? record.contextName)
        _symbol = State(initialValue: record.effectiveIcon)
        _colorHex = State(initialValue: record.iconColorHex)
    }

    /// The accent previewed in the sheet: chosen color, else the theme accent.
    private var selectedColor: Color {
        Color(hex: colorHex) ?? env.theme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(selectedColor)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Customize Cluster").font(.headline)
                    Text(record.contextName)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            TextField("Display name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            Text("Icon").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34))], spacing: 4) {
                ForEach(ClusterStyle.symbols, id: \.self) { candidate in
                    Button { symbol = candidate } label: {
                        Image(systemName: candidate)
                            .font(.system(size: 14))
                            .frame(width: 32, height: 28)
                            .foregroundStyle(candidate == symbol ? selectedColor : Color.secondary)
                            .background(candidate == symbol ? selectedColor.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .help(candidate)
                }
            }

            Text("Color").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: Tokens.Spacing.sm) {
                swatch(hex: nil, color: env.theme.accent, help: "Default (theme accent)")
                ForEach(ClusterStyle.palette, id: \.hex) { entry in
                    swatch(hex: entry.hex, color: Color(hex: entry.hex) ?? .gray, help: entry.name)
                }
            }

            HStack {
                Button("Reset to default") {
                    name = record.contextName
                    symbol = ClusterStyle.defaultSymbol
                    colorHex = nil
                }
                .controlSize(.small)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Spacing.xl)
        .frame(width: 420)
    }

    private func swatch(hex: String?, color: Color, help: String) -> some View {
        Button { colorHex = hex } label: {
            ZStack {
                Circle().fill(color).frame(width: 20, height: 20)
                if colorHex == hex {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        record.displayName = (trimmed.isEmpty || trimmed == record.contextName) ? nil : trimmed
        record.iconSymbol = symbol == ClusterStyle.defaultSymbol ? nil : symbol
        record.iconColorHex = colorHex
        try? modelContext.save()
        env.clusters.reload()
        dismiss()
    }
}
