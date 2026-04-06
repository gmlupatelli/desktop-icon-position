import Foundation

/// Lightweight timing logger for performance instrumentation.
/// Enabled when the `--timing-benchmark` flag is present or `TIMING_LOG=1` env var is set.
enum TimingLog {
    static let enabled: Bool = CommandLine.arguments.contains("--timing-benchmark")
        || ProcessInfo.processInfo.environment["TIMING_LOG"] == "1"

    /// Measure and print the elapsed time for a synchronous block.
    @discardableResult
    static func measure<T>(_ label: String, _ block: () throws -> T) rethrows -> T {
        guard enabled else { return try block() }
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "[Timing] %-45s %8.1f ms", (label as NSString).utf8String!, elapsed))
        return result
    }

    /// Print a summary line.
    static func summary(_ label: String, startTime: CFAbsoluteTime) {
        guard enabled else { return }
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print(String(format: "[Timing] %-45s %8.1f ms  ← TOTAL", (label as NSString).utf8String!, elapsed))
    }
}
