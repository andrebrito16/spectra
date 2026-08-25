//
//  MiddleClick.swift
//  Spectra
//
//  Browser-style middle-click (scroll-wheel click) support, which SwiftUI has
//  no gesture for. An overlay NSView intercepts ONLY middle-button events —
//  hitTest checks the current event's button so left/right clicks pass through
//  to the SwiftUI content underneath. Used to close tabs like a browser.
//

import SwiftUI
import AppKit

private final class MiddleClickNSView: NSView {
    var action: () -> Void = {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Claim only middle-button events; everything else falls through.
        if let event = NSApp.currentEvent,
           event.type == .otherMouseDown || event.type == .otherMouseUp || event.type == .otherMouseDragged,
           event.buttonNumber == 2 {
            return super.hitTest(point)
        }
        return nil
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)) {
            action()
        } else {
            super.otherMouseUp(with: event)
        }
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MiddleClickNSView {
        let view = MiddleClickNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MiddleClickNSView, context: Context) {
        nsView.action = action
    }
}

extension View {
    /// Runs `action` on a middle-button (scroll-wheel) click, browser-style.
    /// Left/right clicks are unaffected.
    func onMiddleClick(perform action: @escaping () -> Void) -> some View {
        overlay(MiddleClickCatcher(action: action))
    }
}
