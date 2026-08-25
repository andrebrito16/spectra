//
//  WatchEvent.swift
//  Spectra
//
//  Watch stream event model and the internal informer→store update events.
//

import Foundation

nonisolated struct WatchEvent: Sendable {
    enum EventType: String, Sendable {
        case added = "ADDED"
        case modified = "MODIFIED"
        case deleted = "DELETED"
        case bookmark = "BOOKMARK"
        case error = "ERROR"
    }

    let type: EventType
    let object: KubeResource
}

/// Events the informer pushes to its store sink.
nonisolated enum InformerEvent: Sendable {
    case listed([KubeResource], resourceVersion: String?)
    case event(WatchEvent)
    case error(KubeError)
    case loading(Bool)
}
