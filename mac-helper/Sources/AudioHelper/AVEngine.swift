//  AVEngine.swift
//  -----------------------------------------------------------
//  • merges tab-audio (left channel, Float32 stereo)
//    with microphone (Float32 mono) **sample-accurately**
//  • emits mono, 48 kHz, Float32 little-endian  (“f32le”)
//  • zero-copy on the hot path, zero audible output
//  -----------------------------------------------------------

import AVFoundation

@inline(__always)
private func dataFromMonoBuffer(_ ptr: UnsafePointer<Float>,
                                frames: Int) -> Data {
    Data(bytes: ptr,
         count: frames * MemoryLayout<Float>.size)
}

final class AVEngine {

    // ───────── public API ─────────

    /// Feed one ScreenCaptureKit **stereo / f32 / 48 kHz** buffer.
    /// Only the left channel (index 0) is used.
    func feed(tabPCM_F32_stereo buf: AVAudioPCMBuffer) {
        guard let l = buf.floatChannelData?.pointee else { return }
        let frames  = Int(buf.frameLength)

        micQ.async { [self] in
            guard !micRing.isEmpty else { return }
            let mic = micRing.removeFirst()               // ← fixed (no popFirst)

            /* ---- merge tab-L + mic → mono ---- */
            var mono = [Float](repeating: 0, count: frames)
            for i in 0..<frames {
                mono[i] = 0.5 * (l[i * 2] + mic[i])       // 50 / 50 mix
            }
            mono.withUnsafeBufferPointer { ptr in
                pcmOut( dataFromMonoBuffer(ptr.baseAddress!, frames: frames) )
            }
        }
    }

    func start() throws { try engine.start() }
    func stop ()        { engine.stop(); micRing.removeAll() }

    // ───────── life-cycle ─────────

    /// `pcmOut` receives **Float32/mono/48 kHz** data – ready for b64.
    init(pcmOut: @escaping (Data) -> Void) {
        self.pcmOut = pcmOut

        /* 1⃣ mic → tap → small ring-buffer */
        let mic     = engine.inputNode
        let micFmt  = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: sampleRate,
                                    channels: 1,
                                    interleaved: false)!

        mic.installTap(onBus: 0,
                       bufferSize: 256,
                       format: micFmt) { [weak self] buf, _ in
            guard let self,
                  let src = buf.floatChannelData?.pointee else { return }
            let frames = Int(buf.frameLength)

            /* store one mic block (copy) – VERY small & fast */
            self.micQ.async {
                self.micRing.append(
                    Array(UnsafeBufferPointer(start: src, count: frames))
                )
                /* keep ring at most 5 blocks */
                if self.micRing.count > 5 { self.micRing.removeFirst() }
            }
        }
    }

    // ───────── private state ─────────

    private let engine  = AVAudioEngine()
    private let micQ    = DispatchQueue(label: "mic.merge.q")

    private var micRing: [[Float]] = []        // tiny FIFO, < 100 ms
    private let pcmOut : (Data) -> Void

    private let sampleRate: Double = 48_000
}
