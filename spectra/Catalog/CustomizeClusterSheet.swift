import SwiftUI
import SwiftData

/// Local appearance preferences, previewed before saving to the cluster record.
struct CustomizeClusterSheet: View {
    let record: ClusterRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var env
    @State private var name: String
    @State private var symbol: String
    @State private var colorHex: String?
    @State private var endColorHex: String?
    @State private var angle: Double
    @State private var saveError: String?

    init(record: ClusterRecord) {
        self.record = record
        _name = State(initialValue: record.displayName ?? record.contextName)
        _symbol = State(initialValue: record.effectiveIcon)
        _colorHex = State(initialValue: record.iconColorHex)
        _endColorHex = State(initialValue: record.gradientEndColorHex)
        _angle = State(initialValue: record.gradientAngle ?? 135)
    }

    private var selectedColor: Color { Color(hex: colorHex) ?? env.theme.accent }
    private var endColor: Color { Color(hex: endColorHex) ?? selectedColor }
    private var identityStyle: AnyShapeStyle {
        endColorHex == nil ? AnyShapeStyle(selectedColor)
            : AnyShapeStyle(ClusterGradient(start: selectedColor, end: endColor, angle: angle))
    }

    var body: some View {
        ScrollView {
            editor
        }
        .frame(width: 520, height: 700)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Make this cluster yours").font(.title2.weight(.semibold))
                Text("Give each workspace its own look.").foregroundStyle(.secondary)
            }
            preview
            TextField("Display name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                sectionTitle("Gradient themes")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(ClusterStyle.gradients) { preset in gradientSwatch(preset) }
                }
            }

            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                sectionTitle("Solid colors")
                HStack(spacing: Tokens.Spacing.sm) {
                    swatch(hex: nil, color: env.theme.accent, title: "Default")
                    ForEach(ClusterStyle.palette, id: \.hex) { entry in
                        swatch(hex: entry.hex, color: Color(hex: entry.hex) ?? .gray, title: entry.name)
                    }
                }
            }

            HStack(spacing: Tokens.Spacing.md) {
                ColorPicker("Color", selection: colorBinding(end: false), supportsOpacity: false)
                Toggle("Gradient", isOn: Binding(get: { endColorHex != nil }, set: { enabled in
                    endColorHex = enabled ? (endColorHex ?? "#28C6B7") : nil
                    if enabled && colorHex == nil { colorHex = selectedColor.rgbHex ?? "#5B4FE9" }
                }))
                if endColorHex != nil {
                    ColorPicker("End", selection: colorBinding(end: true), supportsOpacity: false)
                }
            }
            if endColorHex != nil {
                HStack {
                    Text("Direction").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $angle, in: 0...360, step: 1).accessibilityLabel("Gradient direction")
                    Text("\(Int(angle))°").font(.caption.monospacedDigit()).frame(width: 36)
                }
            }

            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                sectionTitle("Icon")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 12), spacing: 4) {
                    ForEach(ClusterStyle.symbols, id: \.self) { candidate in
                        Button { symbol = candidate } label: {
                            Image(systemName: candidate)
                                .font(.system(size: 14))
                                .frame(width: 32, height: 28)
                                .foregroundStyle(candidate == symbol ? identityStyle : AnyShapeStyle(.secondary))
                                .background(candidate == symbol ? selectedColor.opacity(0.18) : .clear,
                                            in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(candidate)
                        .help(candidate)
                    }
                }
            }

            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Reset to default") {
                    name = record.contextName
                    symbol = ClusterStyle.defaultSymbol
                    colorHex = nil
                    endColorHex = nil
                    angle = 135
                }
                .controlSize(.small)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Spacing.xl)
    }

    private var preview: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: symbol).foregroundStyle(identityStyle)
                    Text(name.isEmpty ? record.contextName : name).font(.callout.weight(.semibold)).lineLimit(1)
                }
                Label("Overview", systemImage: "gauge.with.dots.needle.50percent").font(.caption)
                Label("Workloads", systemImage: "square.stack.3d.up").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 225, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background {
                if colorHex != nil {
                    ClusterThemeBackground(start: selectedColor, end: endColor, angle: angle)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Workspace preview").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach([0.85, 0.6, 0.72], id: \.self) { width in
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 170 * width, height: 6)
                }
            }
            .padding(16)
            Spacer(minLength: 0)
        }
        .frame(height: 126)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(name) with the selected cluster colors")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func gradientSwatch(_ preset: ClusterGradientPreset) -> some View {
        let selected = colorHex == preset.start && endColorHex == preset.end && angle == preset.angle
        return Button {
            colorHex = preset.start
            endColorHex = preset.end
            angle = preset.angle
        } label: {
            HStack {
                Text(preset.name).font(.caption.weight(.semibold))
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill") }
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(height: 45)
            .background(ClusterGradient(start: Color(hex: preset.start)!, end: Color(hex: preset.end)!, angle: preset.angle),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.primary.opacity(0.7) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name) gradient")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatch(hex: String?, color: Color, title: String) -> some View {
        Button { colorHex = hex; endColorHex = nil } label: {
            Circle().fill(color).frame(width: 24, height: 24)
                .overlay {
                    if colorHex == hex && endColorHex == nil {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    private func colorBinding(end: Bool) -> Binding<Color> {
        Binding(get: { end ? endColor : selectedColor }, set: { color in
            guard let hex = color.rgbHex else { return }
            if end { endColorHex = hex } else { colorHex = hex }
        })
    }

    private func save() {
        let previous = (record.displayName, record.iconSymbol, record.iconColorHex,
                        record.gradientEndColorHex, record.gradientAngle)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        record.displayName = (trimmed.isEmpty || trimmed == record.contextName) ? nil : trimmed
        record.iconSymbol = symbol == ClusterStyle.defaultSymbol ? nil : symbol
        record.iconColorHex = colorHex
        record.gradientEndColorHex = endColorHex
        record.gradientAngle = endColorHex == nil ? nil : angle
        do {
            try modelContext.save()
            env.clusters.reload()
            dismiss()
        } catch {
            (record.displayName, record.iconSymbol, record.iconColorHex,
             record.gradientEndColorHex, record.gradientAngle) = previous
            saveError = "Couldn’t save the cluster appearance. \(error.localizedDescription)"
        }
    }
}
