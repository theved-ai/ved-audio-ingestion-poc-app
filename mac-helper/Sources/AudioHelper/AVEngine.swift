//  AVEngine.swift
//  -----------------------------------------------------------------
//  One engine – three modes:
//
//      ┌─────────┬────────────────────────────┐
//      │  .tabOnly│   tab → pcmOut            │
//      │  .micOnly│   mic → pcmOut            │
//      │  .mix    │   0.5·tab + 0.5·mic → out │
//      └─────────┴────────────────────────────┘
//
//  All data is Float-32, mono, 48 kHz  (“f32le” once it hits stdout)
//  -----------------------------------------------------------------

import AVFoundation

@inline(__always)
private func dataFrom(buffer: [Float]) -> Data {
    Data(bytes: buffer, count: buffer.count * MemoryLayout<Float>.size)
}

@inline(__always)
private func dequeue<T>(_ array: inout [T]) -> T? {
    guard !array.isEmpty else { return nil }
    return array.removeFirst()
}


final class AVEngine {

    // MARK:  – mode ---------------------------------------------------------

    enum Mode { case tabOnly, micOnly, mix }

    // MARK:  – public API ---------------------------------------------------

    /// Push one **stereo / Float-32** buffer that came from ScreenCaptureKit
    /// (only *left* is kept).
    func feed(tabPCM_F32_stereo pcm: AVAudioPCMBuffer) {
        guard mode != .micOnly,                    // ignore tab in mic-only mode
              let l = pcm.floatChannelData?.pointee else { return }

        let frames = Int(pcm.frameLength)
        tabQ.async {
            self.tabBuffers.append(
                Array(UnsafeBufferPointer(start: l, count: frames))
            )
            self.maybeEmit()
        }
    }

    func start() throws { try engine.start() }
    func stop()  { engine.stop(); micBuffers.removeAll(); tabBuffers.removeAll() }

    // MARK:  – life-cycle ---------------------------------------------------

    init(mode: Mode = .mix,
         sampleRate: Double = 48_000,
         pcmOut: @escaping (Data) -> Void) {

        self.mode      = mode
        self.pcmOut    = pcmOut
        self.sampleRate = sampleRate

        // ── mic tap ────────────────────────────────────────────────────────
        let mic     = engine.inputNode
        let micFmt  = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate : sampleRate,
                                    channels   : 1,
                                    interleaved: false)!

        mic.installTap(onBus: 0,
                       bufferSize: 256,
                       format: micFmt) { [weak self] buf, _ in
            guard let self,
                  self.mode != .tabOnly,                       // ignore in tab-only
                  let ch = buf.floatChannelData?.pointee else { return }

            let frames = Int(buf.frameLength)
            self.micQ.async {
                self.micBuffers.append(
                    Array(UnsafeBufferPointer(start: ch, count: frames))
                )
                self.maybeEmit()
            }
        }
    }

    // MARK:  – private helpers ---------------------------------------------

    /// If at least one side (or both, in `.mix`) is ready – emit.
    private func maybeEmit() {
        switch mode {

        case .tabOnly:
            if let tab = dequeue(&tabBuffers) {
                pcmOut( dataFrom(buffer: tab) )
            }

        case .micOnly:
            if let mic = dequeue(&micBuffers) {
                pcmOut( dataFrom(buffer: mic) )
            }

        case .mix:
            if let tab = dequeue(&tabBuffers),
            let mic = dequeue(&micBuffers),
            tab.count == mic.count {

                var mono = [Float](repeating: 0, count: tab.count)
                for i in 0..<mono.count { mono[i] = 0.5 * (tab[i] + mic[i]) }
                pcmOut( dataFrom(buffer: mono) )

            } else if let tab = dequeue(&tabBuffers) {
                pcmOut( dataFrom(buffer: tab) )

            } else if let mic = dequeue(&micBuffers) {
                pcmOut( dataFrom(buffer: mic) )
            }

        }
    }

    // MARK:  – ivars --------------------------------------------------------

    private let mode: Mode
    private let sampleRate: Double
    private let pcmOut: (Data) -> Void

    private let engine  = AVAudioEngine()

    private let micQ    = DispatchQueue(label: "pcm.mic.q")
    private let tabQ    = DispatchQueue(label: "pcm.tab.q")

    private var micBuffers: [[Float]] = []
    private var tabBuffers: [[Float]] = []
}
