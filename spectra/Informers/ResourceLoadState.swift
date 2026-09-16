import Foundation

/// Tracks each namespace independently so a fast response cannot end loading
/// while another namespace still has its first list in flight.
nonisolated struct ResourceLoadState {
    private var pending: Set<String?> = [nil]
    private var loading: Set<String?> = []

    var isLoading: Bool { !pending.isEmpty || !loading.isEmpty }

    mutating func reset(scopes: [String?]) {
        pending = Set(scopes)
        loading = []
    }

    mutating func setLoading(_ value: Bool, scope: String?) {
        if value { loading.insert(scope) } else { loading.remove(scope) }
    }

    mutating func complete(scope: String?) {
        pending.remove(scope)
        loading.remove(scope)
    }
}
