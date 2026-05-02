import AVFoundation
import Accelerate
import os.log

class AudioRecorder {
  // Lazily created on startRecording and torn down on stopRecording so the
  // audio HAL doesn't stay warm between recordings (big idle-energy win for
  // a menu-bar app).
  private var audioEngine: AVAudioEngine?
  private var audioBuffer: [Float] = []
  private let bufferLock = NSLock()
  private var isRecording = false

  /// Current audio level (0.0–1.0), updated in real-time from the mic input.
  var onLevelUpdate: ((Float) -> Void)?

  private let logger = Logger(subsystem: "com.audiotype", category: "AudioRecorder")

  // Whisper requires 16kHz mono audio
  private let targetSampleRate: Double = 16000

  init() {
    // Buffer is allocated on each startRecording so the recorder has zero
    // footprint when idle.
  }

  func startRecording() throws {
    guard !isRecording else {
      logger.warning("Already recording")
      return
    }

    // Drop the buffer entirely (don't preserve capacity — see issue 1.4).
    do {
      bufferLock.lock()
      defer { bufferLock.unlock() }
      audioBuffer = []
      audioBuffer.reserveCapacity(Int(targetSampleRate * 30))
    }

    // Lazily create the audio engine on each recording.
    let engine = AVAudioEngine()
    audioEngine = engine

    let inputNode = engine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)

    logger.info("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

    // Create format for Whisper (16kHz mono)
    guard
      let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
      )
    else {
      throw AudioRecorderError.formatCreationFailed
    }

    // Create converter if sample rates differ
    let converter: AVAudioConverter?
    if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
      converter = AVAudioConverter(from: inputFormat, to: targetFormat)
      if converter == nil {
        logger.error("Failed to create audio converter")
        throw AudioRecorderError.converterCreationFailed
      }
    } else {
      converter = nil
    }

    // Install tap on input node
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
      self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
    }

    // Start audio engine
    engine.prepare()
    try engine.start()

    isRecording = true
    logger.info("Recording started")
  }

  func stopRecording() -> [Float]? {
    guard isRecording else {
      logger.warning("Not recording")
      return nil
    }

    // Stop and tear down the engine so the audio HAL releases its resources.
    if let engine = audioEngine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    audioEngine = nil

    isRecording = false

    // Move the buffer out of the recorder (zero-copy via COW transfer) and
    // leave the recorder with a fresh empty array so it doesn't keep the
    // recording's high-water capacity in memory.
    let samples: [Float]
    do {
      bufferLock.lock()
      defer { bufferLock.unlock() }
      samples = audioBuffer
      audioBuffer = []
    }

    logger.info(
      "Recording stopped, captured \(samples.count) samples (\(Double(samples.count) / self.targetSampleRate, format: .fixed(precision: 2))s)"
    )

    return samples.isEmpty ? nil : samples
  }

  private func processAudioBuffer(
    _ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat
  ) {
    if let converter = converter {
      let frameCount = AVAudioFrameCount(
        Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
      )

      guard
        let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount)
      else {
        logger.error("Failed to create converted buffer")
        return
      }

      var error: NSError?
      let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
        outStatus.pointee = .haveData
        return buffer
      }

      converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

      if let error = error {
        logger.error("Conversion error: \(error.localizedDescription)")
        return
      }

      guard let channelData = convertedBuffer.floatChannelData else { return }
      let count = Int(convertedBuffer.frameLength)
      consume(samples: channelData[0], count: count)
    } else {
      guard let channelData = buffer.floatChannelData else { return }
      let count = Int(buffer.frameLength)
      consume(samples: channelData[0], count: count)
    }
  }

  /// Consume a chunk of mic samples: compute RMS for the waveform and append
  /// to the recording buffer — without ever materialising an intermediate
  /// `[Float]`. Called on the audio thread.
  private func consume(samples: UnsafePointer<Float>, count: Int) {
    guard count > 0 else { return }

    // RMS via Accelerate (vectorised). Replaces a scalar reduce loop that
    // ran on every tap callback.
    var meanSquare: Float = 0
    vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(count))
    let rms = sqrt(meanSquare)
    // Normalize: typical speech RMS is 0.01–0.15, scale aggressively to 0–1
    let level = min(rms * 25, 1.0)
    onLevelUpdate?(level)

    // Append directly from the unsafe buffer pointer; [Float] has an
    // append(contentsOf:) overload that takes any Sequence, including
    // UnsafeBufferPointer, so no intermediate Array is allocated.
    let ptr = UnsafeBufferPointer(start: samples, count: count)
    bufferLock.lock()
    defer { bufferLock.unlock() }
    audioBuffer.append(contentsOf: ptr)
  }
}

enum AudioRecorderError: Error, LocalizedError {
  case formatCreationFailed
  case converterCreationFailed
  case engineStartFailed

  var errorDescription: String? {
    switch self {
    case .formatCreationFailed:
      return "Failed to create audio format"
    case .converterCreationFailed:
      return "Failed to create audio converter"
    case .engineStartFailed:
      return "Failed to start audio engine"
    }
  }
}
