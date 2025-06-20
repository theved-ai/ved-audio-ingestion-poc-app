import Foundation
import AppKit

@_cdecl("sig_handler")
func sig_handler(_ sig: Int32) -> Void {
    Runner.stopAndExit()
}


struct Runner {

    private static var capture: Capture?

    // called by the C trampoline above
    static func stopAndExit() {
        capture?.stop()
        exit(EXIT_SUCCESS)
    }

    static func main() async {
        _ = await NSApplication.shared       // `.shared` is async in Swift 6

        let bundle = CommandLine.arguments.dropFirst().first
                   ?? "com.google.Chrome"

        do {
            let cap = Capture(bundleId: bundle)
            capture = cap
            try await cap.start()

            // register the **plain C** handler
            signal(SIGTERM, sig_handler)
            signal(SIGINT , sig_handler)

            // keep helper alive forever
            let oneDay: UInt64 = 86_400 * 1_000_000_000
            while true { try await Task.sleep(nanoseconds: oneDay) }

        } catch {
            fputs("[helper] \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}


await Runner.main()
