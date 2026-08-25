//
//  LogView.swift
//  Spectra
//
//  Live pod log streaming via the native API (follow=true) consumed as an
//  AsyncBytes line stream — true follow, not Freelens's polling. Container
//  selector, search/highlight, timestamps, wrap, auto-scroll, copy, download.
//

import SwiftUI
import AppKit

@MainActor
@Observable
final class LogStreamer {
    private(set) var lines: [String] = []
    private(set) var isStreaming = false
    /// Response headers received — distinguishes "connecting" from "quiet pod".
    private(set) var connected = false
    var error: String?

    private var task: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    /// Bumped per start(); a superseded stream's late writes are dropped.
    private var generation = 0
    private let maxLines = 5000
    /// Lines fetched on (re)start; grows via `loadOlder()`.
    private(set) var tailLines = 1000
    private var pending: [String] = []
    private var flushTask: Task<Void, Never>?
    private var restart: (() -> Void)?

    func start(session: ClusterSession, namespace: String, pod: String,
               container: String?, previous: Bool) {
        stop()
        generation += 1
        let gen = generation
        lines = []
        error = nil
        connected = false
        isStreaming = true
        restart = { [weak self] in
            self?.start(session: session, namespace: namespace, pod: pod,
                        container: container, previous: previous)
        }
        task = Task { [weak self, tailLines] in
            await self?.stream(session: session, namespace: namespace, pod: pod,
                               container: container, previous: previous,
                               tailLines: tailLines, generation: gen)
        }
        // The stream request allows hour-long idle gaps (quiet pods), so a
        // never-answered request would otherwise spin forever. If headers
        // haven't arrived in 15s, fail it with a useful message.
        let streamTask = task
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.generation == gen, self.isStreaming,
                  !self.connected, self.error == nil else { return }
            streamTask?.cancel()
            self.error = "Timed out waiting for the log stream. "
                + "The API server may be unable to reach this node's kubelet."
            self.isStreaming = false
        }
    }

    /// Refetch with a larger tail, pulling older history into the buffer.
    func loadOlder(by amount: Int = 2000) {
        tailLines += amount
        restart?()
    }

    func stop() {
        task?.cancel()
        task = nil
        watchdog?.cancel()
        watchdog = nil
        flushTask?.cancel()
        flushTask = nil
        pending = []
        isStreaming = false
    }

    private func stream(session: ClusterSession, namespace: String, pod: String,
                        container: String?, previous: Bool,
                        tailLines: Int, generation gen: Int) async {
        // Always fetch WITH timestamps; the view strips them for display. This
        // way the Timestamps toggle is instant instead of re-streaming.
        var query = [
            URLQueryItem(name: "follow", value: "true"),
            URLQueryItem(name: "timestamps", value: "true"),
            URLQueryItem(name: "tailLines", value: String(tailLines)),
        ]
        if previous { query.append(.init(name: "previous", value: "true")) }
        if let container { query.append(.init(name: "container", value: container)) }
        let path = "/api/v1/namespaces/\(namespace)/pods/\(pod)/log"
        do {
            // NOT "text/plain": the apiserver's stream negotiation 406s it
            // ("only application/json, application/yaml, ... are accepted").
            // kubectl sends this; the body is still raw log text.
            var request = try await session.connection.makeRequest(
                path: path, queryItems: query, accept: "application/json, */*")
            request.timeoutInterval = 3600
            // Defeat gzip on the stream: URLSession's decompressor buffers, so a
            // compressed follow-stream looks empty until the connection closes.
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let (bytes, response) = try await session.connection.bytes(for: request)
            guard generation == gen else { return }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let message = await Self.statusMessage(from: bytes)
                guard generation == gen else { return }
                error = message ?? "HTTP \(http.statusCode)"
                isStreaming = false
                return
            }
            connected = true
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard generation == gen else { return }
                buffer(line)
            }
            flushPending()
        } catch is CancellationError {
            // expected on stop
        } catch let urlError as URLError where urlError.code == .cancelled {
            // stop() or the connect watchdog (which sets its own message)
        } catch {
            guard generation == gen else { return }
            self.error = error.localizedDescription
        }
        guard generation == gen else { return }
        isStreaming = false
    }

    /// Coalesce incoming lines into ~60ms windows: the initial 1000-line tail
    /// lands as ONE update already scrolled to the end, instead of a visible
    /// per-line crawl down the view. Steady-state streaming gets the same
    /// batching for free.
    private func buffer(_ line: String) {
        pending.append(line)
        if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(60))
                self?.flushPending()
            }
        }
    }

    private func flushPending() {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty else { return }
        lines.append(contentsOf: pending)
        pending.removeAll()
        let cap = max(maxLines, tailLines + 1000)
        if lines.count > cap { lines.removeFirst(lines.count - cap) }
    }

    /// The apiserver answers errors with a Status JSON whose `message` says what's
    /// wrong (e.g. "container ... is waiting to start: CrashLoopBackOff").
    private static func statusMessage(from bytes: URLSession.AsyncBytes) async -> String? {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > 8192 { break }
            }
        } catch { /* use whatever arrived */ }
        if let value = try? JSONDecoder().decode(JSONValue.self, from: data),
           let message = value["message"]?.stringValue {
            return message
        }
        return data.isEmpty ? nil : String(data: data, encoding: .utf8)
    }
}

struct LogView: View {
    let spec: LogSpec

    @State private var streamer = LogStreamer()
    @State private var container: String?
    @State private var search = ""
    @State private var timestamps = true
    @State private var previous = false
    @State private var wrap = false
    @State private var autoScroll = true
    @State private var olderBaseline: Int?
    @State private var scrollAnchor: LogScrollAnchor?

    private var filteredLines: [String] {
        let visible = timestamps ? streamer.lines : streamer.lines.map(Self.stripTimestamp)
        let needle = search.lowercased()
        guard !needle.isEmpty else { return visible }
        return visible.filter { $0.lowercased().contains(needle) }
    }

    /// Drop the leading RFC3339 stamp the stream always fetches (see start()).
    private static func stripTimestamp(_ line: String) -> String {
        guard let space = line.firstIndex(of: " "),
              line[..<space].count >= 20, line[..<space].contains("T") else { return line }
        return String(line[line.index(after: space)...])
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logBody
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            container = spec.initialContainer ?? spec.containers.first
            restart()
        }
        .onDisappear { streamer.stop() }
        .onChange(of: streamer.lines.count) { _, count in
            // After "load older" refills the buffer, anchor the scroll where the
            // previously-oldest line now sits, chat-history style.
            guard let baseline = olderBaseline, count > 0 else { return }
            scrollAnchor = LogScrollAnchor(line: max(count - baseline, 0))
            olderBaseline = nil
        }
    }

    private var toolbar: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            if spec.containers.count > 1 {
                Picker("", selection: $container) {
                    ForEach(spec.containers, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: container) { _, _ in restart() }
            }
            SearchField(placeholder: "Search…", text: $search).frame(width: 200)
            Toggle("Timestamps", isOn: $timestamps)
            Toggle("Previous", isOn: $previous).onChange(of: previous) { _, _ in restart() }
                .help("Logs from the previous (crashed) container instance")
            Toggle("Wrap", isOn: $wrap)
            Toggle("Auto-scroll", isOn: $autoScroll)
            Spacer()
            if streamer.isStreaming { ProgressView().controlSize(.small) }
            Button { loadOlder() } label: { Image(systemName: "clock.arrow.circlepath") }
                .help("Load older lines")
            Button { copy() } label: { Image(systemName: "doc.on.doc") }.help("Copy")
            Button { download() } label: { Image(systemName: "square.and.arrow.down") }.help("Download")
        }
        .toggleStyle(.checkbox)
        .font(.caption)
        .padding(.horizontal, Tokens.Spacing.md)
        .padding(.vertical, Tokens.Spacing.xs)
    }

    @ViewBuilder
    private var logBody: some View {
        if let error = streamer.error {
            VStack(spacing: Tokens.Spacing.sm) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                Button("Retry") { restart() }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if streamer.lines.isEmpty {
            Text(emptyStateText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LogTextView(lines: filteredLines, filterKey: "\(timestamps)|\(search)",
                        wrap: wrap, autoScroll: autoScroll, scrollAnchor: scrollAnchor)
        }
    }

    private var emptyStateText: String {
        guard streamer.isStreaming else { return "No log output" }
        return streamer.connected
            ? "No log output yet — following…"
            : "Connecting to log stream…"
    }

    private func restart() {
        streamer.start(session: spec.session, namespace: spec.namespace, pod: spec.pod,
                       container: container, previous: previous)
    }

    private func loadOlder() {
        olderBaseline = streamer.lines.count
        autoScroll = false
        streamer.loadOlder()
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(streamer.lines.joined(separator: "\n"), forType: .string)
    }

    private func download() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(spec.pod).log"
        if panel.runModal() == .OK, let url = panel.url {
            try? streamer.lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// NSTextView-backed log renderer (the SwiftUI lazy-stack-in-2-axis-ScrollView
/// approach can't size rows: lines truncate and float mid-panel). Monospaced,
/// left-aligned, selectable; horizontal scrolling when wrap is off. Streaming
/// updates APPEND to the text storage instead of rebuilding 5000 lines per tick.
/// One-shot scroll request: put `line` at the top of the viewport.
struct LogScrollAnchor: Equatable {
    let id = UUID()
    let line: Int
}

private struct LogTextView: NSViewRepresentable {
    let lines: [String]
    let filterKey: String
    let wrap: Bool
    let autoScroll: Bool
    let scrollAnchor: LogScrollAnchor?

    final class Coordinator {
        var appliedCount = 0
        var firstApplied: String?
        var filterKey = ""
        var wrap: Bool?
        var appliedAnchor: UUID?
        let parser = ANSILogParser()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isRichText = false
        textView.usesFindBar = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        let state = context.coordinator

        if state.wrap != wrap {
            state.wrap = wrap
            applyWrap(textView, scroll: scroll)
        }

        // Append-only fast path: same filter, same first line, and the buffer
        // only grew. Anything else (filter change, tail trim, restart) rebuilds.
        let canAppend = state.filterKey == filterKey
            && state.firstApplied == lines.first
            && lines.count >= state.appliedCount
        if canAppend {
            if lines.count > state.appliedCount {
                storage.append(render(lines[state.appliedCount...], with: state.parser))
            }
        } else {
            state.parser.reset()
            storage.setAttributedString(render(lines[...], with: state.parser))
        }
        state.appliedCount = lines.count
        state.firstApplied = lines.first
        state.filterKey = filterKey

        if let anchor = scrollAnchor, state.appliedAnchor != anchor.id {
            state.appliedAnchor = anchor.id
            scrollToLine(anchor.line, in: textView)
        } else if autoScroll {
            textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
        }
    }

    /// Scroll so the given line index sits at the top of the viewport — after
    /// "load older", reading continues from the previously-oldest line.
    private func scrollToLine(_ line: Int, in textView: NSTextView) {
        let ns = textView.string as NSString
        guard ns.length > 0 else { return }
        var offset = 0
        var remaining = line
        while remaining > 0 {
            let newline = ns.range(of: "\n",
                                   range: NSRange(location: offset, length: ns.length - offset))
            guard newline.location != NSNotFound else { break }
            offset = newline.location + 1
            remaining -= 1
        }
        guard let layout = textView.layoutManager, let container = textView.textContainer
        else { return }
        layout.ensureLayout(for: container)
        let glyph = layout.glyphIndexForCharacter(at: min(offset, ns.length - 1))
        let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        textView.scroll(NSPoint(x: 0, y: rect.minY))
    }

    /// Render lines through the ANSI parser (colors/bold; escapes stripped).
    private func render(_ slice: ArraySlice<String>, with parser: ANSILogParser) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for line in slice {
            result.append(parser.parse(line))
            result.append(NSAttributedString(string: "\n"))
        }
        return result
    }

    private func applyWrap(_ textView: NSTextView, scroll: NSScrollView) {
        guard let container = textView.textContainer else { return }
        if wrap {
            textView.isHorizontallyResizable = false
            container.widthTracksTextView = true
            container.size = NSSize(width: scroll.contentSize.width,
                                    height: CGFloat.greatestFiniteMagnitude)
            textView.frame.size.width = scroll.contentSize.width
            textView.autoresizingMask = [.width]
        } else {
            textView.isHorizontallyResizable = true
            container.widthTracksTextView = false
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
            textView.autoresizingMask = []
        }
    }
}
