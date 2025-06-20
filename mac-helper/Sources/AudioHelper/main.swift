import Foundation
import AppKit                                  


@main
struct Runner {

    static func main() async {

        _ = NSApplication.shared               // first runtime statement

        // ----- command-line arg or default  -----
        let bundleId = CommandLine.arguments.dropFirst().first
                    ?? "com.google.Chrome"

        do {
            let cap = Capture(bundleId: bundleId)
            try await cap.start()

            // register signal handlers *after* success
            signal(SIGTERM) { _ in cap.stop(); exit(EXIT_SUCCESS) }
            signal(SIGINT ) { _ in cap.stop(); exit(EXIT_SUCCESS) }

            // keep process alive forever
            let day: UInt64 = 86_400 * 1_000_000_000
            while true { try await Task.sleep(nanoseconds: day) }

        } catch {
            fputs("[helper] error: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
