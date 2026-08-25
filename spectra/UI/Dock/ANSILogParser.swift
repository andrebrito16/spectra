//
//  ANSILogParser.swift
//  Spectra
//
//  Renders ANSI SGR escape sequences (colors, bold, underline) in pod log
//  output as NSAttributedString runs — and strips the escapes apps emit that
//  we don't render (cursor moves, OSC titles) so they never show as garbage.
//  SGR state carries across lines and batches because apps set a color once
//  and reset it much later.
//

import AppKit

final class ANSILogParser {
    private struct State {
        var foreground: NSColor?
        var background: NSColor?
        var bold = false
        var underline = false
    }

    private var state = State()

    func reset() { state = State() }

    /// Parse one log line, returning styled text with all escapes removed.
    func parse(_ line: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            result.append(NSAttributedString(string: run, attributes: attributes()))
            run = ""
        }

        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            guard ch == "\u{1B}" else {
                run.append(ch)
                i = line.index(after: i)
                continue
            }
            let next = line.index(after: i)
            guard next < line.endIndex else { break }
            switch line[next] {
            case "[":  // CSI … final-byte
                var j = line.index(after: next)
                var params = ""
                while j < line.endIndex, let ascii = line[j].asciiValue,
                      !(0x40...0x7E).contains(ascii) {
                    params.append(line[j])
                    j = line.index(after: j)
                }
                if j < line.endIndex {
                    if line[j] == "m" {
                        flush()
                        apply(params)
                    }
                    i = line.index(after: j)
                } else {
                    i = j
                }
            case "]":  // OSC … (BEL or ESC\)
                var j = line.index(after: next)
                while j < line.endIndex, line[j] != "\u{07}", line[j] != "\u{1B}" {
                    j = line.index(after: j)
                }
                if j < line.endIndex, line[j] == "\u{1B}" {
                    j = line.index(after: j)  // skip the ST's backslash too
                }
                i = j < line.endIndex ? line.index(after: j) : j
            default:   // lone ESC + one char (e.g. ESC( charset selection)
                i = line.index(after: next)
            }
        }
        flush()
        return result
    }

    // MARK: - SGR

    private func apply(_ params: String) {
        var codes = params.split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        if codes.isEmpty { codes = [0] }
        var i = 0
        while i < codes.count {
            switch codes[i] {
            case 0: state = State()
            case 1: state.bold = true
            case 4: state.underline = true
            case 22: state.bold = false
            case 24: state.underline = false
            case 30...37: state.foreground = Self.palette[codes[i] - 30]
            case 90...97: state.foreground = Self.palette[codes[i] - 90]
            case 39: state.foreground = nil
            case 40...47: state.background = Self.palette[codes[i] - 40]
            case 100...107: state.background = Self.palette[codes[i] - 100]
            case 49: state.background = nil
            case 38, 48:
                let (color, consumed) = Self.extendedColor(codes, at: i)
                if codes[i] == 38 { state.foreground = color } else { state.background = color }
                i += consumed
            default: break
            }
            i += 1
        }
    }

    private func attributes() -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: state.bold ? .semibold : .regular),
            .foregroundColor: state.foreground ?? NSColor.textColor,
        ]
        if let background = state.background { attrs[.backgroundColor] = background }
        if state.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }

    /// Black and white map to the adaptive text color so they stay legible in
    /// both light and dark themes; the rest use system colors for the same reason.
    private static let palette: [NSColor] = [
        .textColor, .systemRed, .systemGreen, .systemYellow,
        .systemBlue, .systemPurple, .systemTeal, .textColor,
    ]

    /// 38;5;n (xterm-256) and 38;2;r;g;b (truecolor) forms. Returns the color
    /// and how many extra params were consumed.
    private static func extendedColor(_ codes: [Int], at i: Int) -> (NSColor?, Int) {
        if i + 2 < codes.count, codes[i + 1] == 5 {
            return (xterm256(codes[i + 2]), 2)
        }
        if i + 4 < codes.count, codes[i + 1] == 2 {
            return (NSColor(srgbRed: CGFloat(codes[i + 2]) / 255,
                            green: CGFloat(codes[i + 3]) / 255,
                            blue: CGFloat(codes[i + 4]) / 255, alpha: 1), 4)
        }
        return (nil, 0)
    }

    private static func xterm256(_ n: Int) -> NSColor? {
        switch n {
        case 0...7: return palette[n]
        case 8...15: return palette[n - 8]
        case 16...231:
            let v = n - 16
            let levels: [CGFloat] = [0, 95, 135, 175, 215, 255]
            return NSColor(srgbRed: levels[v / 36] / 255,
                           green: levels[(v / 6) % 6] / 255,
                           blue: levels[v % 6] / 255, alpha: 1)
        case 232...255:
            let gray = CGFloat(8 + 10 * (n - 232)) / 255
            return NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1)
        default: return nil
        }
    }
}
