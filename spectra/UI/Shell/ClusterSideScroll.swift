//
//  ClusterSideScroll.swift
//  Spectra
//
//  Switch clusters with a horizontal scroll while the cursor is over the sidebar.
//  Uses an AppKit local scroll-wheel monitor and distinguishes two input styles:
//
//  • Trackpad two-finger swipe — emits a continuous stream of events (.began →
//    .changed → .ended) plus a momentum tail. We accumulate the horizontal delta
//    and switch one cluster per `swipeThreshold` points of travel (remainder
//    carried), Arc-style: a short swipe moves one, a long deliberate swipe can
//    move a couple. Momentum events never switch — lifting your fingers stops it.
//  • Mouse wheel / MX Master thumb wheel — events with no phase. The thumb
//    wheel (and its free-spin mode under Logi Options+) floods events, so a
//    fixed threshold either machine-guns through clusters or misses gentle
//    nudges. Instead, travel within a "burst" (events closer together than the
//    idle gap) escalates: the FIRST switch fires after a few points — a nudge
//    always registers — but follow-up switches in the same burst need several
//    times more travel, so a hard flick (and its decaying tail) moves exactly
//    one cluster while a sustained deliberate spin still steps through at a
//    controlled pace. Idle gap or direction change resets the burst.
//
//  Vertical scrolling always passes through so the list scrolls normally. Only
//  scalar deltas + a Sendable phase enum cross into the actor-isolated handler,
//  keeping Swift 6 happy.
//
//  Direction: we read `scrollingDeltaX`, which the OS has ALREADY adjusted for the
//  user's scroll-direction preference (System Settings ▸ natural/standard), so both
//  input styles track that setting automatically. The two styles map opposite ways
//  because they FEEL opposite: a trackpad swipe drags content (negative deltaX →
//  NEXT cluster, matching swipe-to-navigate), while a thumb wheel points at a
//  destination (positive deltaX → NEXT cluster — verified on an MX Master 3 with
//  natural scrolling on).
//

import SwiftUI
import AppKit

/// Classification of a scroll-wheel event, computed on the main thread from the
/// NSEvent so the event itself never crosses into the isolated handler.
private enum ScrollKind: Sendable {
    case began      // trackpad gesture started
    case changed    // trackpad gesture continuing
    case ended      // trackpad gesture finished / cancelled
    case momentum   // post-lift inertial scrolling — never triggers a switch
    case wheel      // discrete mouse / thumb-wheel tick (no phase)
}

@MainActor
private final class SideScrollController {
    var hovering = false
    var onSwitch: ((Int) -> Void)?

    private var monitor: Any?

    // Trackpad swipe state.
    private var accumulatedX: CGFloat = 0
    private var firedThisGesture = false
    /// Points of horizontal travel per switch within a swipe (remainder carried).
    private let swipeThreshold: CGFloat = 45

    // Mouse-wheel state.
    private var wheelAccumulatedX: CGFloat = 0
    private var lastWheelEvent = Date.distantPast
    /// Switches fired in the current burst (events closer than `wheelIdleReset`).
    private var burstSwitches = 0
    /// Idle gap that ends a burst and discards leftover wheel travel.
    private let wheelIdleReset: TimeInterval = 0.25
    /// Travel for the first switch of a burst — low, so a single tick registers.
    private let firstWheelThreshold: CGFloat = 8
    /// Travel for each further switch in the same burst — high, so a flick's
    /// free-spin tail can't machine-gun through clusters.
    private let repeatWheelThreshold: CGFloat = 40

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let kind = SideScrollController.classify(event)
            guard let self else { return event }
            let consume = MainActor.assumeIsolated { self.handle(dx: dx, dy: dy, kind: kind) }
            return consume ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func classify(_ event: NSEvent) -> ScrollKind {
        if !event.momentumPhase.isEmpty { return .momentum }
        let phase = event.phase
        if phase.contains(.began) { return .began }
        if phase.contains(.ended) || phase.contains(.cancelled) { return .ended }
        if phase.isEmpty { return .wheel }
        return .changed
    }

    /// Returns true to consume the event (a horizontal scroll over the sidebar).
    private func handle(dx: CGFloat, dy: CGFloat, kind: ScrollKind) -> Bool {
        guard hovering else { return false }
        switch kind {
        case .began:
            accumulatedX = 0
            firedThisGesture = false
            return accumulate(dx: dx, dy: dy)
        case .changed:
            return accumulate(dx: dx, dy: dy)
        case .ended:
            let consumed = firedThisGesture
            accumulatedX = 0
            firedThisGesture = false
            return consumed
        case .momentum:
            // Inertial tail: swallow horizontal momentum, never switch.
            return abs(dx) > abs(dy)
        case .wheel:
            return handleWheel(dx: dx, dy: dy)
        }
    }

    /// Accumulate one trackpad delta, switching once per `swipeThreshold` points.
    private func accumulate(dx: CGFloat, dy: CGFloat) -> Bool {
        guard abs(dx) >= abs(dy) else { return false }  // vertical → let the list scroll
        accumulatedX += dx
        while abs(accumulatedX) >= swipeThreshold {
            firedThisGesture = true
            onSwitch?(accumulatedX < 0 ? 1 : -1)
            accumulatedX += accumulatedX < 0 ? swipeThreshold : -swipeThreshold
        }
        return true
    }

    /// Accumulate wheel travel with an escalating per-burst threshold: the first
    /// switch fires after `firstWheelThreshold` points, further switches in the
    /// same burst need `repeatWheelThreshold`. At most one switch per event; the
    /// accumulator and burst reset on idle and on direction change.
    private func handleWheel(dx: CGFloat, dy: CGFloat) -> Bool {
        guard abs(dx) > abs(dy), abs(dx) > 0.1 else { return false }
        let now = Date()
        if now.timeIntervalSince(lastWheelEvent) > wheelIdleReset {
            wheelAccumulatedX = 0
            burstSwitches = 0
        }
        lastWheelEvent = now
        if wheelAccumulatedX != 0, (wheelAccumulatedX < 0) != (dx < 0) {
            wheelAccumulatedX = 0
            burstSwitches = 0
        }
        wheelAccumulatedX += dx
        let threshold = burstSwitches == 0 ? firstWheelThreshold : repeatWheelThreshold
        if abs(wheelAccumulatedX) >= threshold {
            // Opposite mapping from the trackpad swipe: wheel deltas arrive
            // already adjusted for the system scroll-direction setting, and the
            // thumb wheel reads as "roll toward = go there", not as dragging
            // content. Positive (rightward) travel → next cluster, so the
            // direction follows System Settings (natural vs standard).
            onSwitch?(wheelAccumulatedX > 0 ? 1 : -1)
            wheelAccumulatedX = 0
            burstSwitches += 1
        }
        return true
    }
}

private struct ClusterSideScrollModifier: ViewModifier {
    let onSwitch: (Int) -> Void
    @State private var controller = SideScrollController()

    func body(content: Content) -> some View {
        content
            .onHover { controller.hovering = $0 }
            .onAppear {
                controller.onSwitch = onSwitch
                controller.install()
            }
            .onDisappear {
                controller.hovering = false
                controller.remove()
            }
    }
}

extension View {
    /// Switch clusters via horizontal scroll while hovering this view.
    func clusterSideScroll(onSwitch: @escaping (Int) -> Void) -> some View {
        modifier(ClusterSideScrollModifier(onSwitch: onSwitch))
    }
}
