//
//  LocalPort.swift
//  Spectra
//
//  Tiny helper to probe local TCP ports so the port-forward dialog can suggest a
//  port that's actually free on this Mac (mirrors what Lens does), instead of
//  blindly defaulting to the cluster port — which fails when it's privileged
//  (<1024, can't bind without root) or already in use.
//

import Darwin

nonisolated enum LocalPort {
    /// True if a TCP listener can bind `127.0.0.1:port` right now. Any bind
    /// failure (in-use *or* permission-denied for privileged ports) counts as
    /// unavailable — both mean kubectl couldn't bind it either.
    static func isAvailable(_ port: Int) -> Bool {
        guard (1...65535).contains(port) else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bound == 0
    }

    /// An OS-assigned free ephemeral port (bind to port 0, read it back).
    static func freeEphemeral() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0  // let the kernel choose
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }
        var out = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &out) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: out.sin_port))
    }

    /// The preferred port if it's free, otherwise an OS-assigned free port.
    /// There's an inherent TOCTOU gap (kubectl binds later), but it's tiny and
    /// the manager now surfaces any bind error.
    static func suggest(preferred: Int) -> Int {
        if isAvailable(preferred) { return preferred }
        return freeEphemeral() ?? preferred
    }
}
