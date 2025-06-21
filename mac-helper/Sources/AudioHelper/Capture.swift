import Foundation
import ScreenCaptureKit
import AVFoundation

final class Capture: NSObject {

    init(bundleId: String,
         stdout: FileHandle = .standardOutput) {
        self.bundleId = bundleId
        self.stdout   = stdout
        self.engine   = AVEngine { pcm in stdout.write(pcm) }
        super.init()
    }

    @MainActor
    func start() async throws {

        let content = try await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard content.applications.contains(where: { $0.bundleIdentifier == bundleId })
        else { throw CaptureError.appNotRunning(bundleId) }

        let win = content.windows
            .first { $0.owningApplication?.bundleIdentifier == bundleId }

        let filter = win != nil
            ? SCContentFilter(desktopIndependentWindow: win!)
            : SCContentFilter(display: content.displays.first!,
                              excludingWindows: [])

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.sampleRate    = 48_000

        stream = SCStream(filter: filter, configuration: cfg, delegate: nil)

        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
        try await stream?.startCapture()
        try engine.start()

        fputs("[helper] capture+mic started ✅\n", stderr)
    }

    func stop() {
        stream?.stopCapture()
        engine.stop()
    }

    private let bundleId: String
    private let stdout  : FileHandle
    private var stream  : SCStream?
    private let engine  : AVEngine
}

extension Capture: SCStreamOutput {

    func stream(_ stream: SCStream,
            didOutputSampleBuffer sb: CMSampleBuffer,
            of outputType: SCStreamOutputType) {

        guard outputType == .audio,
            let block = CMSampleBufferGetDataBuffer(sb) else { return }

        /* raw pointer + size -------------------------------------------------- */
        var len = 0; var ptr: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(block,
                                    atOffset: 0,
                                    lengthAtOffsetOut: nil,
                                    totalLengthOut: &len,
                                    dataPointerOut: &ptr)

        /* we captured **Float-32 / stereo / 48 kHz / interleaved** ------------ */
        let frames = len / MemoryLayout<Float>.size / 2
        guard frames > 0,
            let p = ptr?.withMemoryRebound(to: Float.self,
                                            capacity: frames * 2,
                                            { $0 })          // Float32 *
        else { return }

        /* create a *planar* buffer that AVEngine wants (non-interleaved) ------ */
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate : 48_000,
                                channels   : 2,
                                interleaved: false)!

        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt,
                                        frameCapacity: AVAudioFrameCount(frames))
        else { return }

        pcm.frameLength = pcm.frameCapacity
        let l = pcm.floatChannelData![0]
        let r = pcm.floatChannelData![1]

        for i in 0..<frames {
            l[i] = p[i * 2]       // left
            r[i] = p[i * 2 + 1]   // right
        }

        /* hand the buffer to the mixer/merger ------------------------------- */
        engine.feed(tabPCM_F32_stereo: pcm)
    }
}

enum CaptureError: LocalizedError {
    case appNotRunning(String)
    var errorDescription: String? {
        switch self {
        case .appNotRunning(let id): return "App \(id) is not running."
        }
    }
}
