//
//  Onboarding.swift
//  Spectra
//
//  First-run state for the onboarding flow. Lives in UserDefaults (not
//  SwiftData) so it is readable even when the store is the thing that failed,
//  and so the canary/Debug "reset first-run state" tool is a one-liner.
//

import Foundation

nonisolated enum Onboarding {
    /// Bump this if the flow ever changes enough that everyone should see it
    /// again. Anyone who completed an older version is shown the new one once.
    static let currentVersion = 1

    private static let completedVersionKey = "spectra.onboardingCompletedVersion"

    static var isCompleted: Bool {
        UserDefaults.standard.integer(forKey: completedVersionKey) >= currentVersion
    }

    static func markCompleted() {
        UserDefaults.standard.set(currentVersion, forKey: completedVersionKey)
    }

    /// Developer tool (canary/Debug): the next launch shows onboarding again.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: completedVersionKey)
    }
}

/// The pages, in order. Each is a full "scene" in `OnboardingView`.
nonisolated enum OnboardingPage: Int, CaseIterable, Identifiable, Sendable {
    case welcome, look, clusters, tools, shortcuts, ready
    var id: Int { rawValue }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }
    var isLast: Bool { next == nil }

    /// Label of the primary (Return) button.
    var continueTitle: String {
        switch self {
        case .welcome: return "Get Started"
        case .ready: return "Open Spectra"
        default: return "Continue"
        }
    }
}
