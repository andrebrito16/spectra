//
//  TerminalView.swift
//  Spectra
//
//  SwiftTerm-backed terminal hosting a PTY process (local shell, pod exec, or
//  node shell). Wrapped as NSViewRepresentable. Content surface is solid; only
//  the surrounding dock chrome is glass. Replaces xterm.js + node-pty.
//

import SwiftUI
import SwiftTerm

struct TerminalView: NSViewRepresentable {
    let spec: TerminalSpec

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        var merged = ProcessInfo.processInfo.environment
        merged["TERM"] = "xterm-256color"
        merged["LANG"] = merged["LANG"] ?? "en_US.UTF-8"
        for (key, value) in spec.environment { merged[key] = value }
        let environment = merged.map { "\($0.key)=\($0.value)" }
        view.startProcess(executable: spec.executable, args: spec.args,
                          environment: environment)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
