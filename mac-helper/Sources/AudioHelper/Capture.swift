//
//  Capture.swift
//  AudioHelper  (SwiftPM target)
//

import Foundation
import ScreenCaptureKit
import AVFoundation            // CMSampleBuffer helpers

/// Captures raw PCM from a given app (or default display) and writes it to
/// `stdout` so the Electron parent can read from `proc.stdout`.
final class Capture: NSObject {

    private let bundleId : String
    private var stream   : SCStream?
    private let stdout   = FileHandle.standardOutput

    // MARK: - init / life-cycle ------------------------------------------------

    init(bundleId: String) { self.bundleId = bundleId }

    func stop() { stream?.stopCapture() }

    // MARK: - start (must run on the main actor) ------------------------------

    @MainActor
    func start() async throws {

        // 1. Enumerate shareable items
        let content = try await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // 2. Make sure the target app is running
        guard content.applications.contains(where: { $0.bundleIdentifier == bundleId }) else {
            throw NSError(domain: "AudioHelper",
                          code:   1,
                          userInfo: [NSLocalizedDescriptionKey:
                                     "App \(bundleId) not running"])
        }

        // 3. Capture the specific window if we can, else the first display
        let targetWin = content.windows
            .first { $0.owningApplication?.bundleIdentifier == bundleId }

        let filter = targetWin != nil
            ? SCContentFilter(desktopIndependentWindow: targetWin!)
            : SCContentFilter(display: content.displays.first!,
                              excludingWindows: [])

        // 4. Configure audio-only stream
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.sampleRate    = 48_000          // 48 kHz PCM

        // 5. Build + start SCStream
        stream = SCStream(filter: filter, configuration: cfg, delegate: nil)

        try stream?.addStreamOutput(self,
                                    type: .audio,
                                    sampleHandlerQueue: .main)
        try await stream?.startCapture()
        fputs("[helper] capture started ✅\n", stderr)
    }
}

/* ────────────────────────────── delegate ───────────────────────────── */

extension Capture: SCStreamOutput {

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {

        guard outputType == .audio,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var ptr    : UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &ptr)

        if let p = ptr {
            stdout.write( Data(bytes: p, count: length) )
        }
    }
}
