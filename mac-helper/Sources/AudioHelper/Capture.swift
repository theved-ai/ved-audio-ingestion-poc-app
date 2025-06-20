//  Capture.swift  – plain class + delegate, NO top-level code
import ScreenCaptureKit
import AVFoundation

final class Capture: NSObject {

    private let bundleId: String
    private var stream  : SCStream?
    private let stdout  = FileHandle.standardOutput

    init(bundleId: String) { self.bundleId = bundleId }

    func stop() { stream?.stopCapture() }

    @MainActor
    func start() async throws {

        let content = try await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard content.applications.contains(where: { $0.bundleIdentifier == bundleId })
        else { throw NSError(domain: "AudioHelper", code: 1,
                 userInfo: [NSLocalizedDescriptionKey: "app not running"]) }

        let win = content.windows
            .first { $0.owningApplication?.bundleIdentifier == bundleId }

        let filter = win != nil
          ? SCContentFilter(desktopIndependentWindow: win!)
          : SCContentFilter(display: content.displays.first!,
                            excludingWindows: [])

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.sampleRate    = 48_000            // 48 kHz PCM

        stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try stream?.addStreamOutput(self, type: .audio,
                                    sampleHandlerQueue: .main)
        try await stream?.startCapture()
        fputs("[helper] capture started ✅\n", stderr)
    }
}

// ----------------------------------------------------------------
//                      SCStreamOutput delegate
// ----------------------------------------------------------------
extension Capture: SCStreamOutput {

    func stream(_ s: SCStream,
                didOutputSampleBuffer sb: CMSampleBuffer,
                of outputType: SCStreamOutputType) {

        guard outputType == .audio,
              let block = CMSampleBufferGetDataBuffer(sb) else { return }

        var len = 0; var ptr: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(block, atOffset: 0,
                                    lengthAtOffsetOut: nil,
                                    totalLengthOut: &len,
                                    dataPointerOut: &ptr)
        if let p = ptr { stdout.write(Data(bytes: p, count: len)) }
    }
}
