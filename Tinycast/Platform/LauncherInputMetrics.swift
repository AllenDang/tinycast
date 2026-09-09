#if UI_TESTING
import AppKit
import SwiftUI
import os

@MainActor
@Observable
final class LauncherInputMetrics {
    @ObservationIgnored private(set) var sequence = 0
    @ObservationIgnored private var pending: (start: UInt64, state: OSSignpostIntervalState)?
    @ObservationIgnored private var samples: [Double] = []
    @ObservationIgnored private var superseded = 0
    @ObservationIgnored private var requests: DispatchSourceFileSystemObject?
    private let signposter = OSSignposter(subsystem: "com.tinycast.perf", category: "LauncherInput")

    func start() {
        guard let path = ProcessInfo.processInfo.environment["TINYCAST_UI_METRICS_PATH"] else { return }
        let url = URL(fileURLWithPath: path).appendingPathExtension("request")
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let action = try? String(contentsOf: url, encoding: .utf8),
                    action == "reset" || action == "export"
                else { return }
                if action == "reset" {
                    self?.samples = []
                    self?.superseded = 0
                }
                self?.export()
            }
        }
        source.setCancelHandler { close(descriptor) }
        requests = source
        source.resume()
    }

    isolated deinit {
        requests?.cancel()
    }

    func inputChanged() {
        if let pending {
            signposter.endInterval("Launcher.InputToLayout", pending.state, "superseded")
            superseded += 1
        }
        sequence &+= 1
        pending = (DispatchTime.now().uptimeNanoseconds,
                   signposter.beginInterval("Launcher.InputToLayout", id: signposter.makeSignpostID()))
    }

    func layoutFinished(sequence: Int) {
        guard sequence == self.sequence, let pending else { return }
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - pending.start) / 1_000_000)
        signposter.endInterval("Launcher.InputToLayout", pending.state, "layout")
        self.pending = nil
    }

    private func export() {
        guard let path = ProcessInfo.processInfo.environment["TINYCAST_UI_METRICS_PATH"] else { return }
        let report: [String: Any] = ["layoutMilliseconds": samples, "superseded": superseded]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: .sortedKeys) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

}

struct LauncherLayoutProbe: NSViewRepresentable {
    let sequence: Int
    let metrics: LauncherInputMetrics

    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.complete = { metrics.layoutFinished(sequence: sequence) }
        view.needsLayout = true
    }

    final class ProbeView: NSView {
        var complete: (() -> Void)?

        override func layout() {
            super.layout()
            complete?()
            complete = nil
        }
    }
}
#endif
