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
                of outputType: SCStreamOutputType)
    {
        guard outputType == .audio else { return }

        // 1⃣  Ask CM to materialise an AudioBufferList for us
        var ablSizeNeeded = 0
        let abl = AudioBufferList.allocate(maximumBuffers: 2)
        var blockBuf: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb,
            bufferListSizeNeededOut: &ablSizeNeeded,
            bufferListOut: &abl.unsafeMutablePointer.pointee,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuf
        )
        guard status == noErr else { return }

        // 2⃣  Format sanity-check — we expect 32-bit float, **non-interleaved**
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc),
              asbd.pointee.mFormatID == kAudioFormatLinearPCM,
              asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.pointee.mBitsPerChannel == 32,
              asbd.pointee.mChannelsPerFrame == 2
        else { return }

        let frames = Int(CMSampleBufferGetNumSamples(sb))
        guard frames > 0 else { return }

        // 3⃣  Build an AVAudioPCMBuffer (planar / mono L+R)
        let avFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate : 48_000,
                                  channels   : 2,
                                  interleaved: false)!

        guard let pcm = AVAudioPCMBuffer(pcmFormat: avFmt,
                                         frameCapacity: AVAudioFrameCount(frames))
        else { return }
        pcm.frameLength = pcm.frameCapacity

        // 4⃣  Copy the two planes (left/right) from the ABL into the AVAudioPCMBuffer
        let left  = pcm.floatChannelData![0]
        let right = pcm.floatChannelData![1]

        // ScreenCaptureKit delivers **non-interleaved** float32 - one AudioBuffer per channel
        let audioBufL = abl[0]
        let audioBufR = abl[1]

        memcpy(left,
               audioBufL.mData!,
               Int(audioBufL.mDataByteSize))
        memcpy(right,
               audioBufR.mData!,
               Int(audioBufR.mDataByteSize))

        // 5⃣  Hand off to the merging engine
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
